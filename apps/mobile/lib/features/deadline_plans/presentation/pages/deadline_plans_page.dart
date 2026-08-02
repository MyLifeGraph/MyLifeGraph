import 'package:flutter/material.dart';

import 'package:my_life_graph/core/constants/app_radii.dart';

import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../composition/projection_refresh_providers.dart';
import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/utils/client_uuid.dart';
import '../../../../core/utils/local_date.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_surface.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import '../../application/deadline_plan_controller.dart';
import '../../domain/deadline_calendar_prefill.dart';
import '../../domain/deadline_plan.dart';
import 'package:my_life_graph/composition/deadline_plan_providers.dart';

part '../widgets/deadline_plan_card.dart';
part '../widgets/deadline_plan_editor_sheet.dart';
part '../widgets/deadline_plan_support_widgets.dart';

class DeadlinePlansPage extends ConsumerStatefulWidget {
  const DeadlinePlansPage({
    super.key,
    this.sourceCalendarEventId,
    this.initialTitle,
    this.initialDeadlineAt,
    this.initialDeadlineOn,
    this.initialKind,
    this.initialPlanId,
    this.openInitialReplan = false,
    this.focusedReplan = false,
    this.currentTime,
  });

  final String? sourceCalendarEventId;
  final String? initialTitle;
  final DateTime? initialDeadlineAt;
  final String? initialDeadlineOn;
  final DeadlinePlanKind? initialKind;
  final String? initialPlanId;
  final bool openInitialReplan;
  final bool focusedReplan;
  final DateTime? currentTime;

  @override
  ConsumerState<DeadlinePlansPage> createState() => _DeadlinePlansPageState();
}

class _DeadlinePlansPageState extends ConsumerState<DeadlinePlansPage> {
  bool _sourceEditorOpened = false;
  bool _editorOpen = false;
  bool _targetPlanRequested = false;
  bool _targetPlanLoading = false;
  bool _initialReplanOpened = false;
  bool _initialKindEditorOpened = false;
  bool _expansionInitialized = false;
  Object? _targetPlanError;
  DeadlinePlanProposalDraft? _retainedDraft;
  String? _expandedPlanId;
  String? _operationPlanId;
  final Map<String, GlobalKey> _planKeys = {};

  @override
  void initState() {
    super.initState();
    _expandedPlanId = widget.initialPlanId;
  }

  @override
  void didUpdateWidget(covariant DeadlinePlansPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPlanId != widget.initialPlanId) {
      _targetPlanRequested = false;
      _targetPlanLoading = false;
      _targetPlanError = null;
      _initialReplanOpened = false;
      _expandedPlanId = widget.initialPlanId;
      _expansionInitialized = false;
    } else if (oldWidget.openInitialReplan != widget.openInitialReplan) {
      _initialReplanOpened = false;
    }
    if (oldWidget.initialKind != widget.initialKind) {
      _initialKindEditorOpened = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    if (!capabilities.canUseDeadlinePlanner) {
      return const AppPage(
        title: 'Preparation plans',
        subtitle: 'Reserve realistic focus time before an exam or assignment',
        backFallback: AppRoutes.planner,
        children: [
          _MessageCard(
            icon: AppIcons.cloudOffOutlined,
            title: 'Synced preparation plans unavailable',
            message:
                'Preparation plans require a signed-in account with synced data. Local demo stays on this device and does not create a pretend plan.',
          ),
        ],
      );
    }
    final state = ref.watch(deadlinePlanControllerProvider);
    ref.watch(preparationWorkloadProvider);
    final controller = ref.read(deadlinePlanControllerProvider.notifier);
    final sourcePrefill = widget.sourceCalendarEventId == null
        ? null
        : ref.watch(
            deadlineCalendarPrefillProvider(widget.sourceCalendarEventId!),
          );
    _openSourceEditorAfterBuild(state, sourcePrefill);
    _loadTargetPlanAfterBuild(state);
    _initializeExpansionAfterBuild(state);
    _openInitialReplanAfterBuild(state);
    _openInitialKindEditorAfterBuild(state);

    return AppPage(
      title: widget.focusedReplan ? 'Replan preparation' : 'Preparation plans',
      subtitle: widget.focusedReplan
          ? 'Review one plan, stage a preview, then confirm explicitly'
          : 'Reserve realistic focus time before an exam or assignment',
      backFallback: AppRoutes.planner,
      actions: [
        IconButton(
          tooltip: 'Reload preparation plans',
          onPressed: state.isBusy
              ? null
              : () {
                  ref.invalidate(preparationWorkloadProvider);
                  controller.load();
                },
          icon: const Icon(AppIcons.refresh),
        ),
      ],
      children: _children(state, controller, sourcePrefill),
    );
  }

  List<Widget> _children(
    DeadlinePlanState state,
    DeadlinePlanController controller,
    AsyncValue<DeadlineCalendarPrefill>? sourcePrefill,
  ) {
    if (state.isLoading) {
      return const [
        AppCard(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      ];
    }
    if (state.loadError != null) {
      return [
        _MessageCard(
          icon: AppIcons.cloudOffOutlined,
          title: 'Preparation plans unavailable',
          message:
              'Synced plan state could not be read. It was not replaced with an empty or demo plan.',
          actionLabel: 'Retry',
          onAction: controller.load,
        ),
      ];
    }

    final visiblePlans = [...state.plans]..sort((left, right) {
        final selectedId = widget.initialPlanId;
        if (selectedId != null && left.id != right.id) {
          if (left.id == selectedId) return -1;
          if (right.id == selectedId) return 1;
        }
        if (left.isTerminal != right.isTerminal) {
          return left.isTerminal ? 1 : -1;
        }
        final leftDeadline = left.displayedRevision?.deadlineAt;
        final rightDeadline = right.displayedRevision?.deadlineAt;
        if (leftDeadline == null || rightDeadline == null) return 0;
        return leftDeadline.compareTo(rightDeadline);
      });
    final targetPlan = _planById(visiblePlans, widget.initialPlanId);

    Widget planCard(DeadlinePlan plan) {
      final key = _planKeys.putIfAbsent(plan.id, GlobalKey.new);
      final hasInlineError =
          state.operationError != null && _operationPlanId == plan.id;
      return KeyedSubtree(
        key: key,
        child: _DeadlinePlanCard(
          key: ValueKey('deadline-plan-${plan.id}'),
          plan: plan,
          expanded: _expandedPlanId == plan.id,
          isBusy: state.isBusy,
          exactRetryLocked: state.requiresExactRetry,
          confirmLabel: widget.focusedReplan
              ? 'Confirm reservations and return to Planner'
              : 'Confirm reservations',
          operationError: hasInlineError ? state.operationError : null,
          onToggle: () => setState(
            () => _expandedPlanId = _expandedPlanId == plan.id ? null : plan.id,
          ),
          onAdjust: () => _openEditor(plan: plan),
          onReplanMissed: () => _openEditor(
            plan: plan,
            replanContext: _DeadlineReplanContext.missed,
          ),
          onConfirm: () => _confirmPlan(plan),
          onComplete: () => _completePlan(plan),
          onCancel: () => _cancelPlan(plan),
          onStartBlock: (block) => _startBlock(plan, block),
          onRetry: controller.retryExact,
          onReload: controller.load,
          onDismissError: () {
            controller.clearOperationError();
            setState(() => _operationPlanId = null);
          },
        ),
      );
    }

    final openPlans =
        visiblePlans.where((plan) => !plan.isTerminal).toList(growable: false);
    final historyPlans =
        visiblePlans.where((plan) => plan.isTerminal).toList(growable: false);

    final leading = <Widget>[
      if (_targetPlanLoading)
        const AppCard(
          child: Row(
            children: [
              SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(child: Text('Loading requested preparation plan…')),
            ],
          ),
        ),
      if (_targetPlanError != null)
        _MessageCard(
          icon: AppIcons.searchOffOutlined,
          title: 'Requested preparation plan unavailable',
          message:
              'The plan could not be loaded for this account. It may have been removed, or the link may not belong to the signed-in user.',
          actionLabel: 'Retry requested plan',
          onAction: _retryTargetPlan,
        ),
      if (sourcePrefill != null) _sourcePrefillCard(sourcePrefill),
    ];

    if (widget.focusedReplan) {
      if (targetPlan == null &&
          !_targetPlanLoading &&
          _targetPlanError == null) {
        leading.add(
          _MessageCard(
            icon: AppIcons.searchOffOutlined,
            title: 'Preparation plan unavailable',
            message:
                'This focused replan needs an available, open Exam or Assignment plan.',
            actionLabel: 'Return to Planner',
            onAction: () => context.go(AppRoutes.planner),
          ),
        );
      } else if (targetPlan?.isTerminal == true) {
        leading.add(
          _MessageCard(
            icon: AppIcons.infoOutline,
            title: 'This plan can no longer be replanned',
            message:
                'Completed and cancelled preparation plans keep their history, but cannot create another preview.',
            actionLabel: 'Return to Planner',
            onAction: () => context.go(AppRoutes.planner),
          ),
        );
      } else if (targetPlan != null) {
        leading.add(planCard(targetPlan));
      }
      if (state.operationError != null && _operationPlanId == null) {
        leading.add(
          _OperationErrorCard(
            state: state,
            onRetry: controller.retryExact,
            onReload: controller.load,
            onDismiss: controller.clearOperationError,
            onReview: _retainedDraft == null
                ? null
                : () => _openEditor(retainedDraft: _retainedDraft),
          ),
        );
      }
      return leading;
    }

    return [
      ...leading,
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your estimate leads the plan',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Tell MyLifeGraph how much active preparation you expect. It will split that time into reviewable blocks without changing an external calendar.',
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: state.isBusy ||
                      state.requiresExactRetry ||
                      sourcePrefill?.isLoading == true
                  ? null
                  : () => _openEditor(),
              icon: const Icon(AppIcons.eventAvailableOutlined),
              label: const Text('Plan preparation'),
            ),
          ],
        ),
      ),
      if (visiblePlans.isEmpty)
        const _MessageCard(
          icon: AppIcons.calendarViewWeekOutlined,
          title: 'No preparation plan yet',
          message:
              'Create a staged preview first. Nothing is reserved until you confirm it.',
        )
      else ...[
        Text('Open plans', style: Theme.of(context).textTheme.titleLarge),
        if (openPlans.isEmpty)
          const Text('No open preparation plans.')
        else
          for (final plan in openPlans) planCard(plan),
        if (historyPlans.isNotEmpty) ...[
          Text('History', style: Theme.of(context).textTheme.titleLarge),
          for (final plan in historyPlans) planCard(plan),
        ],
      ],
      if (_retainedDraft != null &&
          state.operationError == null &&
          !state.isBusy)
        _CalendarPrefillCard(
          icon: AppIcons.editNoteOutlined,
          title: 'Entered plan values kept',
          message:
              'The latest saved plan was loaded without discarding your inputs. Review both before trying again.',
          primaryLabel: 'Review entered values',
          onPrimary: () => _openEditor(retainedDraft: _retainedDraft),
          secondaryLabel: 'Discard entered values',
          onSecondary: () => setState(() => _retainedDraft = null),
        ),
      if (state.operationError != null && _operationPlanId == null)
        _OperationErrorCard(
          state: state,
          onRetry: controller.retryExact,
          onReload: controller.load,
          onDismiss: controller.clearOperationError,
          onReview: !state.requiresExactRetry &&
                  !state.reloadSuggested &&
                  _retainedDraft != null
              ? () => _openEditor(retainedDraft: _retainedDraft)
              : null,
        ),
    ];
  }

  void _loadTargetPlanAfterBuild(DeadlinePlanState state) {
    final planId = widget.initialPlanId;
    if (planId == null ||
        _targetPlanRequested ||
        state.isLoading ||
        state.loadError != null ||
        state.plans.any((plan) => plan.id == planId)) {
      return;
    }
    _targetPlanRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadTargetPlan(planId);
    });
  }

  void _initializeExpansionAfterBuild(DeadlinePlanState state) {
    if (_expansionInitialized || state.isLoading || state.loadError != null) {
      return;
    }
    _expansionInitialized = true;
    if (_expandedPlanId != null) return;
    for (final plan in state.plans) {
      if (plan.pendingRevision != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _expandedPlanId == null) {
            setState(() => _expandedPlanId = plan.id);
          }
        });
        return;
      }
    }
  }

  void _openInitialReplanAfterBuild(DeadlinePlanState state) {
    final planId = widget.initialPlanId;
    if (!widget.openInitialReplan ||
        _initialReplanOpened ||
        planId == null ||
        state.isLoading ||
        state.loadError != null ||
        state.isBusy ||
        state.requiresExactRetry) {
      return;
    }
    final plan = _planById(state.plans, planId);
    if (plan == null) return;
    _initialReplanOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (plan.isTerminal) return;
      _openEditor(
        plan: plan,
        replanContext: _DeadlineReplanContext.workload,
      );
    });
  }

  void _openInitialKindEditorAfterBuild(DeadlinePlanState state) {
    if (widget.initialKind == null ||
        _initialKindEditorOpened ||
        widget.initialPlanId != null ||
        widget.sourceCalendarEventId != null ||
        state.isLoading ||
        state.loadError != null ||
        state.isBusy ||
        state.requiresExactRetry) {
      return;
    }
    _initialKindEditorOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openEditor();
    });
  }

  Future<void> _loadTargetPlan(String planId) async {
    setState(() {
      _targetPlanLoading = true;
      _targetPlanError = null;
    });
    try {
      final plan =
          await ref.read(deadlinePlanRepositoryProvider).getPlan(planId);
      if (!mounted) return;
      ref.read(deadlinePlanControllerProvider.notifier).includeReadPlan(plan);
      setState(() => _targetPlanLoading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _targetPlanLoading = false;
        _targetPlanError = error;
      });
    }
  }

  void _retryTargetPlan() {
    final planId = widget.initialPlanId;
    if (planId == null || _targetPlanLoading) return;
    setState(() {
      _targetPlanRequested = true;
      _targetPlanError = null;
    });
    _loadTargetPlan(planId);
  }

  Widget _sourcePrefillCard(AsyncValue<DeadlineCalendarPrefill> source) {
    final eventId = widget.sourceCalendarEventId!;
    return source.when(
      loading: () => const AppCard(
        child: Row(
          children: [
            SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(child: Text('Loading imported event securely…')),
          ],
        ),
      ),
      error: (_, __) => _CalendarPrefillCard(
        icon: AppIcons.cloudOffOutlined,
        title: 'Imported event unavailable',
        message:
            'The owner-scoped imported event could not be loaded. No event details were taken from the URL or replaced with demo data.',
        primaryLabel: 'Retry event',
        onPrimary: () => ref.invalidate(
          deadlineCalendarPrefillProvider(eventId),
        ),
      ),
      data: (prefill) {
        final future = prefill.hasFutureDeadline(_pageNow);
        if (prefill.status == DeadlineCalendarPrefillStatus.unavailable) {
          return _CalendarPrefillCard(
            icon: AppIcons.eventBusyOutlined,
            title: 'Imported event no longer available',
            message:
                'The event is not available in your current imported data. Create a manual plan or retry after updating the calendar import.',
            primaryLabel: 'Retry event',
            onPrimary: () => ref.invalidate(
              deadlineCalendarPrefillProvider(eventId),
            ),
          );
        }
        if (!future) {
          return _CalendarPrefillCard(
            icon: AppIcons.eventBusyOutlined,
            title: 'Imported event deadline has passed',
            message:
                'The event was loaded from your account, but its date is no longer a future finish-by time.',
            primaryLabel: 'Retry event',
            onPrimary: () => ref.invalidate(
              deadlineCalendarPrefillProvider(eventId),
            ),
          );
        }
        if (prefill.status == DeadlineCalendarPrefillStatus.stale) {
          return _CalendarPrefillCard(
            icon: AppIcons.syncProblemOutlined,
            title: 'Imported event changed or disconnected',
            message:
                'Its saved basics can be reviewed, but this event is not a current source. Continue only as a manual plan, or retry after a new import.',
            primaryLabel: 'Review as manual plan',
            onPrimary: () => _openEditor(
              sourcePrefill: prefill,
              forceManualSource: true,
            ),
            secondaryLabel: 'Retry event',
            onSecondary: () => ref.invalidate(
              deadlineCalendarPrefillProvider(eventId),
            ),
          );
        }
        return _CalendarPrefillCard(
          icon: AppIcons.eventAvailableOutlined,
          title: 'Imported event ready for review',
          message:
              'The event was loaded directly from your owner-scoped calendar data. Its title and time are not carried in the URL.',
          primaryLabel: 'Review event',
          onPrimary: () => _openEditor(sourcePrefill: prefill),
          secondaryLabel: 'Reload event',
          onSecondary: () => ref.invalidate(
            deadlineCalendarPrefillProvider(eventId),
          ),
        );
      },
    );
  }

  void _openSourceEditorAfterBuild(
    DeadlinePlanState state,
    AsyncValue<DeadlineCalendarPrefill>? source,
  ) {
    final prefill = source?.asData?.value;
    if (_sourceEditorOpened ||
        state.isLoading ||
        state.loadError != null ||
        prefill == null ||
        prefill.status != DeadlineCalendarPrefillStatus.current ||
        !prefill.hasFutureDeadline(_pageNow)) {
      return;
    }
    _sourceEditorOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openEditor(sourcePrefill: prefill);
    });
  }

  Future<void> _openEditor({
    DeadlinePlan? plan,
    DeadlinePlanProposalDraft? retainedDraft,
    DeadlineCalendarPrefill? sourcePrefill,
    bool forceManualSource = false,
    _DeadlineReplanContext replanContext = _DeadlineReplanContext.general,
  }) async {
    final state = ref.read(deadlinePlanControllerProvider);
    if (state.isBusy || state.requiresExactRetry || _editorOpen) return;
    _editorOpen = true;
    final sourcePlan = plan ?? _planById(state.plans, retainedDraft?.planId);
    final existing = sourcePlan?.displayedRevision;
    final loadedPrefill = sourcePrefill ??
        (widget.sourceCalendarEventId == null
            ? null
            : ref
                .read(
                  deadlineCalendarPrefillProvider(
                    widget.sourceCalendarEventId!,
                  ),
                )
                .asData
                ?.value);
    final calendarSource = sourcePlan == null &&
        loadedPrefill?.canPrefill == true &&
        !forceManualSource;
    final prefillDeadline =
        loadedPrefill?.kind == DeadlineCalendarEventKind.timed
            ? loadedPrefill?.startsAt
            : null;
    final prefillDeadlineOn =
        loadedPrefill?.kind == DeadlineCalendarEventKind.allDay
            ? loadedPrefill?.startsOn
            : null;
    DeadlinePlanProposalDraft? draft;
    final preparationWorkload = ref.read(preparationWorkloadProvider);
    final profileToday = widget.currentTime == null
        ? ref.read(profileLocalDateSourceProvider).today()
        : DateTime(
            widget.currentTime!.year,
            widget.currentTime!.month,
            widget.currentTime!.day,
          );
    try {
      draft = await showModalBottomSheet<DeadlinePlanProposalDraft>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        useSafeArea: true,
        builder: (_) => _DeadlinePlanEditorSheet(
          planId: sourcePlan?.id ?? retainedDraft?.planId ?? newClientUuid(),
          baseRevision:
              sourcePlan?.latestRevision ?? retainedDraft?.baseRevision ?? 0,
          existing: existing,
          trackedFocusMinutes: sourcePlan?.progress.trackedFocusMinutes ?? 0,
          accountDailyPreparationBudgetKnown: preparationWorkload.hasValue,
          accountDailyPreparationBudgetMinutes:
              preparationWorkload.valueOrNull?.dailyPreparationBudgetMinutes,
          retainedDraft: retainedDraft,
          initialKind: widget.initialKind,
          initialTitle:
              existing?.title ?? loadedPrefill?.title ?? widget.initialTitle,
          initialDeadlineAt: existing?.deadlineAt ??
              prefillDeadline ??
              widget.initialDeadlineAt,
          initialDeadlineOn: retainedDraft == null && existing == null
              ? prefillDeadlineOn ?? widget.initialDeadlineOn
              : null,
          sourceKind: retainedDraft?.sourceKind ??
              existing?.sourceKind ??
              (calendarSource
                  ? DeadlinePlanSourceKind.calendarEvent
                  : DeadlinePlanSourceKind.manual),
          sourceCalendarEventId: retainedDraft?.sourceCalendarEventId ??
              existing?.sourceCalendarEventId ??
              (calendarSource ? loadedPrefill?.eventId : null),
          sourceCalendarEventFingerprint:
              retainedDraft?.sourceCalendarEventFingerprint ??
                  existing?.sourceCalendarEventFingerprint ??
                  (calendarSource ? loadedPrefill?.sourceFingerprint : null),
          initialSourceStatus: existing?.sourceStatus ??
              (calendarSource
                  ? switch (loadedPrefill?.status) {
                      DeadlineCalendarPrefillStatus.current =>
                        DeadlinePlanSourceStatus.current,
                      DeadlineCalendarPrefillStatus.stale =>
                        DeadlinePlanSourceStatus.stale,
                      _ => DeadlinePlanSourceStatus.unavailable,
                    }
                  : DeadlinePlanSourceStatus.notApplicable),
          startWithExistingSummary: sourcePlan?.isActive == true &&
              sourcePlan?.pendingRevision == null &&
              retainedDraft == null,
          replanContext: replanContext,
          currentTime: widget.currentTime,
          profileToday: profileToday,
          onOpenPlanner: () => context.go(AppRoutes.planner),
        ),
      );
    } finally {
      _editorOpen = false;
    }
    if (!mounted || draft == null) return;
    setState(() => _retainedDraft = draft);
    final saved =
        await ref.read(deadlinePlanControllerProvider.notifier).propose(draft);
    if (mounted && saved) {
      final changedPlanId =
          ref.read(deadlinePlanControllerProvider).lastChangedPlanId;
      setState(() {
        _retainedDraft = null;
        _expandedPlanId = changedPlanId ?? draft!.planId;
      });
      _showMessage('Preparation preview created. Review and confirm it.');
    }
  }

  DeadlinePlan? _planById(List<DeadlinePlan> plans, String? planId) {
    if (planId == null) return null;
    for (final candidate in plans) {
      if (candidate.id == planId) return candidate;
    }
    return null;
  }

  DateTime get _pageNow => widget.currentTime ?? DateTime.now();

  Future<void> _confirmPlan(DeadlinePlan plan) async {
    final revision = plan.pendingRevision;
    if (revision == null) return;
    final recoveryMinutes = revision.blocks.fold<int>(
      0,
      (sum, block) => sum + block.recoveryMinutes,
    );
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Reserve these focus blocks?'),
            content: Text(
              '${_duration(revision.plannedMinutes)} of preparation'
              '${recoveryMinutes > 0 ? ' plus ${_duration(recoveryMinutes)} of recovery buffers' : ''} '
              'will be reserved in MyLifeGraph only. Recovery does not count as preparation or against the preparation budget. Your imported or external calendar will not be changed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep as preview'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  widget.focusedReplan
                      ? 'Confirm reservations and return to Planner'
                      : 'Confirm reservations',
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !confirmed) return;
    setState(() => _operationPlanId = plan.id);
    final saved =
        await ref.read(deadlinePlanControllerProvider.notifier).confirm(plan);
    if (mounted && saved) {
      await _afterManagedTaskMutation();
      if (!mounted) return;
      setState(() => _operationPlanId = null);
      if (widget.focusedReplan) {
        context.go(AppRoutes.planner);
      } else {
        _showMessage('Preparation blocks reserved.');
      }
    }
  }

  Future<void> _completePlan(DeadlinePlan plan) async {
    final confirmed = await _confirm(
      title: 'Mark preparation complete?',
      message:
          'This closes the plan. It does not record an exam result or complete anything in an external calendar.',
      action: 'Mark complete',
    );
    if (!mounted || !confirmed) return;
    setState(() => _operationPlanId = plan.id);
    final saved =
        await ref.read(deadlinePlanControllerProvider.notifier).complete(plan);
    if (mounted && saved) {
      await _afterManagedTaskMutation();
      if (!mounted) return;
      setState(() {
        _operationPlanId = null;
        _expandedPlanId = null;
      });
      _keepPlanVisible(plan.id);
      _showMessage('Preparation plan completed.');
    }
  }

  Future<void> _cancelPlan(DeadlinePlan plan) async {
    final confirmed = await _confirm(
      title: plan.isDraft
          ? 'Discard preparation preview?'
          : 'Cancel preparation plan?',
      message: plan.isDraft
          ? 'This removes the unconfirmed preview. No task or reservation was created, and no external calendar is changed.'
          : 'Future MyLifeGraph reservations will close. Tracked focus history remains, and no external calendar is changed.',
      action: plan.isDraft ? 'Discard preview' : 'Cancel plan',
    );
    if (!mounted || !confirmed) return;
    setState(() => _operationPlanId = plan.id);
    final saved =
        await ref.read(deadlinePlanControllerProvider.notifier).cancel(plan);
    if (mounted && saved) {
      if (plan.taskId != null) {
        await _afterManagedTaskMutation();
      } else {
        await ref
            .read(projectionRefreshCoordinatorProvider)
            .deadlinePlanChanged();
      }
      if (!mounted) return;
      setState(() {
        _operationPlanId = null;
        _expandedPlanId = null;
      });
      _keepPlanVisible(plan.id);
      _showMessage(
        plan.isDraft
            ? 'Preparation preview discarded.'
            : 'Preparation plan cancelled.',
      );
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep plan'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _startBlock(DeadlinePlan plan, DeadlinePlanBlock block) {
    final remainingMinutes =
        block.plannedMinutes - block.creditedTrackedMinutes;
    if (!plan.isActive || remainingMinutes < 5) return;
    final query = Uri(
      path: AppRoutes.deepWork,
      queryParameters: {
        'source_kind': 'deadline_plan_block',
        'source_block_id': block.id,
      },
    );
    context.push(query.toString());
  }

  Future<void> _afterManagedTaskMutation() async {
    try {
      await ref.read(projectionRefreshCoordinatorProvider).deadlinePlanChanged(
            targetDate: ref.read(profileLocalDateSourceProvider).todayKey(),
          );
    } catch (_) {
      // The plan mutation is already durable; snapshot refresh is best effort.
    }
  }

  void _keepPlanVisible(String planId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _planKeys[planId]?.currentContext;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.2,
        duration: const Duration(milliseconds: 220),
      );
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}
