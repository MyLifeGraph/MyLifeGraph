import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/utils/client_uuid.dart';
import '../../../../core/utils/local_date.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../briefings/presentation/providers/briefing_providers.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../snapshots/presentation/providers/snapshot_providers.dart';
import '../../application/deadline_plan_controller.dart';
import '../../domain/deadline_calendar_prefill.dart';
import '../../domain/deadline_plan.dart';
import '../providers/deadline_plan_providers.dart';
import '../widgets/preparation_workload_card.dart';

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
    this.currentTime,
  });

  final String? sourceCalendarEventId;
  final String? initialTitle;
  final DateTime? initialDeadlineAt;
  final String? initialDeadlineOn;
  final DeadlinePlanKind? initialKind;
  final String? initialPlanId;
  final bool openInitialReplan;
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
  Object? _targetPlanError;
  DeadlinePlanProposalDraft? _retainedDraft;

  @override
  void didUpdateWidget(covariant DeadlinePlansPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPlanId != widget.initialPlanId) {
      _targetPlanRequested = false;
      _targetPlanLoading = false;
      _targetPlanError = null;
      _initialReplanOpened = false;
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
        children: [
          _MessageCard(
            icon: Icons.cloud_off_outlined,
            title: 'Synced preparation plans unavailable',
            message:
                'Preparation plans require a signed-in account with synced data. Local demo stays on this device and does not create a pretend plan.',
          ),
        ],
      );
    }
    final state = ref.watch(deadlinePlanControllerProvider);
    final workload = ref.watch(preparationWorkloadProvider);
    final controller = ref.read(deadlinePlanControllerProvider.notifier);
    final sourcePrefill = widget.sourceCalendarEventId == null
        ? null
        : ref.watch(
            deadlineCalendarPrefillProvider(widget.sourceCalendarEventId!),
          );
    _openSourceEditorAfterBuild(state, sourcePrefill);
    _loadTargetPlanAfterBuild(state);
    _openInitialReplanAfterBuild(state);
    _openInitialKindEditorAfterBuild(state);

    return AppPage(
      title: 'Preparation plans',
      subtitle: 'Reserve realistic focus time before an exam or assignment',
      actions: [
        IconButton(
          tooltip: 'Reload preparation plans',
          onPressed: state.isBusy
              ? null
              : () {
                  ref.invalidate(preparationWorkloadProvider);
                  controller.load();
                },
          icon: const Icon(Icons.refresh),
        ),
      ],
      children: _children(state, controller, sourcePrefill, workload),
    );
  }

  List<Widget> _children(
    DeadlinePlanState state,
    DeadlinePlanController controller,
    AsyncValue<DeadlineCalendarPrefill>? sourcePrefill,
    AsyncValue<PreparationWorkload> workload,
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
          icon: Icons.cloud_off_outlined,
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
    return [
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
          icon: Icons.search_off_outlined,
          title: 'Requested preparation plan unavailable',
          message:
              'The plan could not be loaded for this account. It may have been removed, or the link may not belong to the signed-in user.',
          actionLabel: 'Retry requested plan',
          onAction: _retryTargetPlan,
        ),
      if (sourcePrefill != null) _sourcePrefillCard(sourcePrefill),
      PreparationWorkloadCard(
        value: workload,
        onRetry: () => ref.invalidate(preparationWorkloadProvider),
        onOpenSettings: () => context.go(AppRoutes.settings),
        onLoadDayDetail: (localDate) => ref
            .read(deadlinePlanRepositoryProvider)
            .getWorkloadDetail(localDate),
        onReviewPlan: _reviewPlanFromWorkload,
        onReplanPlan: _replanFromWorkload,
      ),
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
              icon: const Icon(Icons.event_available_outlined),
              label: const Text('Plan preparation'),
            ),
          ],
        ),
      ),
      if (visiblePlans.isEmpty)
        const _MessageCard(
          icon: Icons.calendar_view_week_outlined,
          title: 'No preparation plan yet',
          message:
              'Create a staged preview first. Nothing is reserved until you confirm it.',
        )
      else
        for (final plan in visiblePlans)
          _DeadlinePlanCard(
            key: ValueKey('deadline-plan-${plan.id}'),
            plan: plan,
            isBusy: state.isBusy,
            exactRetryLocked: state.requiresExactRetry,
            onAdjust: () => _openEditor(plan: plan),
            onReplanMissed: () => _openEditor(
              plan: plan,
              replanContext: _DeadlineReplanContext.missed,
            ),
            onConfirm: () => _confirmPlan(plan),
            onComplete: () => _completePlan(plan),
            onCancel: () => _cancelPlan(plan),
            onStartBlock: (block) => _startBlock(plan, block),
          ),
      if (_retainedDraft != null &&
          state.operationError == null &&
          !state.isBusy)
        _CalendarPrefillCard(
          icon: Icons.edit_note_outlined,
          title: 'Entered plan values kept',
          message:
              'The latest saved plan was loaded without discarding your inputs. Review both before trying again.',
          primaryLabel: 'Review entered values',
          onPrimary: () => _openEditor(retainedDraft: _retainedDraft),
          secondaryLabel: 'Discard entered values',
          onSecondary: () => setState(() => _retainedDraft = null),
        ),
      if (state.operationError != null)
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
      if (plan.isTerminal) {
        _showMessage(
          'This preparation plan is already closed and cannot be replanned.',
        );
        return;
      }
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

  void _reviewPlanFromWorkload(String planId) {
    final query = Uri(
      path: AppRoutes.preparationPlans,
      queryParameters: {'plan_id': planId},
    );
    if (widget.initialPlanId == planId) {
      _showMessage(
        'This plan is listed first below. No reservations were changed.',
      );
      return;
    }
    context.go(query.toString());
  }

  void _replanFromWorkload(String planId) {
    final state = ref.read(deadlinePlanControllerProvider);
    final plan = _planById(state.plans, planId);
    if (plan != null && !plan.isTerminal) {
      _openEditor(
        plan: plan,
        replanContext: _DeadlineReplanContext.workload,
      );
      return;
    }
    context.go(
      Uri(
        path: AppRoutes.preparationPlans,
        queryParameters: {'plan_id': planId, 'action': 'replan'},
      ).toString(),
    );
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
        icon: Icons.cloud_off_outlined,
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
            icon: Icons.event_busy_outlined,
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
            icon: Icons.event_busy_outlined,
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
            icon: Icons.sync_problem_outlined,
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
          icon: Icons.event_available_outlined,
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
      setState(() => _retainedDraft = null);
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
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Reserve these focus blocks?'),
            content: Text(
              '${_duration(revision.plannedMinutes)} will be reserved in MyLifeGraph only. Your imported or external calendar will not be changed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep as preview'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Confirm reservations'),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !confirmed) return;
    final saved =
        await ref.read(deadlinePlanControllerProvider.notifier).confirm(plan);
    if (mounted && saved) {
      await _afterManagedTaskMutation();
      _showMessage('Preparation blocks reserved.');
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
    final saved =
        await ref.read(deadlinePlanControllerProvider.notifier).complete(plan);
    if (mounted && saved) {
      await _afterManagedTaskMutation();
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
    final saved =
        await ref.read(deadlinePlanControllerProvider.notifier).cancel(plan);
    if (mounted && saved) {
      if (plan.taskId != null) {
        await _afterManagedTaskMutation();
      } else {
        ref.invalidate(dashboardSnapshotProvider);
      }
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
    final taskId = plan.taskId;
    final remainingMinutes =
        block.plannedMinutes - block.creditedTrackedMinutes;
    if (!plan.isActive || taskId == null || remainingMinutes < 5) return;
    final query = Uri(
      path: AppRoutes.deepWork,
      queryParameters: {
        'target_kind': 'task',
        'target_id': taskId,
        'planned_minutes': '$remainingMinutes',
      },
    );
    context.go(query.toString());
  }

  Future<void> _afterManagedTaskMutation() async {
    try {
      await ref
          .read(snapshotRefreshServiceProvider)
          .refreshDailyAfterTaskChange(
            targetDate: localDateKey(DateTime.now()),
          );
    } catch (_) {
      // The plan mutation is already durable; snapshot refresh is best effort.
    }
    ref.invalidate(dashboardSnapshotProvider);
    ref.invalidate(todayBriefingProvider);
    ref.invalidate(preparationWorkloadProvider);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}

class _DeadlinePlanCard extends StatefulWidget {
  const _DeadlinePlanCard({
    super.key,
    required this.plan,
    required this.isBusy,
    required this.exactRetryLocked,
    required this.onAdjust,
    required this.onReplanMissed,
    required this.onConfirm,
    required this.onComplete,
    required this.onCancel,
    required this.onStartBlock,
  });

  final DeadlinePlan plan;
  final bool isBusy;
  final bool exactRetryLocked;
  final VoidCallback onAdjust;
  final VoidCallback onReplanMissed;
  final VoidCallback onConfirm;
  final VoidCallback onComplete;
  final VoidCallback onCancel;
  final ValueChanged<DeadlinePlanBlock> onStartBlock;

  @override
  State<_DeadlinePlanCard> createState() => _DeadlinePlanCardState();
}

class _DeadlinePlanCardState extends State<_DeadlinePlanCard> {
  static const _collapsedBlockLimit = 6;

  bool _showTerminalDetails = false;
  bool _showAllDisplayedBlocks = false;
  bool _showAllActiveBlocks = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final isBusy = widget.isBusy;
    final exactRetryLocked = widget.exactRetryLocked;
    final onAdjust = widget.onAdjust;
    final onReplanMissed = widget.onReplanMissed;
    final onConfirm = widget.onConfirm;
    final onComplete = widget.onComplete;
    final onCancel = widget.onCancel;
    final onStartBlock = widget.onStartBlock;
    final revision = plan.displayedRevision;
    if (revision == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusPill(label: _statusLabel(plan.status)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              plan.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'This unconfirmed preview was discarded. It created no task or reserved preparation blocks.',
            ),
          ],
        ),
      );
    }
    final pending = plan.pendingRevision != null;
    final active = plan.activeRevision;
    final sourceNeedsReview =
        revision.sourceStatus == DeadlinePlanSourceStatus.stale ||
            revision.sourceStatus == DeadlinePlanSourceStatus.unavailable;
    final canMutate = !isBusy && !exactRetryLocked && !plan.isTerminal;
    final missedSourceRevision = pending && active != null ? active : revision;
    final missedBlocks = plan.isActive
        ? missedSourceRevision.blocks
            .where((block) => block.state == DeadlinePlanBlockState.missed)
            .toList(growable: false)
        : const <DeadlinePlanBlock>[];
    final missedMinutes = missedBlocks.fold<int>(
      0,
      (sum, block) =>
          sum + (block.plannedMinutes - block.creditedTrackedMinutes),
    );
    final estimate = revision.estimatedTotalMinutes;
    final prior = revision.creditedPriorMinutes;
    final tracked = pending
        ? revision.trackedFocusMinutesAtProposal
        : plan.progress.trackedFocusMinutes;
    final accounted = (prior + tracked).clamp(0, estimate).toInt();
    final remaining = pending
        ? revision.remainingMinutesAtProposal
        : plan.progress.remainingMinutes;
    if (plan.isTerminal && !_showTerminalDetails) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                _StatusPill(label: _statusLabel(plan.status)),
                _StatusPill(
                  label: revision.kind == DeadlinePlanKind.exam
                      ? 'Exam'
                      : 'Assignment',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              revision.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Finished by ${DateFormat.yMMMd().add_Hm().format(revision.deadlineAt.toLocal())} · device time',
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${_duration(estimate)} estimated · ${_duration(tracked)} tracked Focus · ${revision.blocks.length} preparation blocks',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextButton.icon(
              key: ValueKey('deadline-show-history-${plan.id}'),
              onPressed: () => setState(() => _showTerminalDetails = true),
              icon: const Icon(Icons.expand_more),
              label: const Text('Show history details'),
            ),
          ],
        ),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusPill(
                label: pending ? 'Preview' : _statusLabel(plan.status),
              ),
              _StatusPill(
                label: revision.kind == DeadlinePlanKind.exam
                    ? 'Exam'
                    : 'Assignment',
              ),
              if (sourceNeedsReview) const _StatusPill(label: 'Source changed'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(revision.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Finish by ${DateFormat.yMMMd().add_Hm().format(revision.deadlineAt.toLocal())} · device time',
          ),
          Text(
            'Preparation blocks use your profile timezone: ${revision.timezone}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            _planningWindowDescription(revision.bestEnergyWindow),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _ProgressValue(
                label: pending ? 'Proposed estimate' : 'Estimate',
                value: _duration(estimate),
              ),
              _ProgressValue(
                label: 'Entered prior credit',
                value: _duration(prior),
              ),
              _ProgressValue(
                label: 'Tracked focus',
                value: _duration(tracked),
              ),
              _ProgressValue(
                label: 'Remaining',
                value: _duration(remaining),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: (accounted / estimate).clamp(0, 1).toDouble(),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${_duration(revision.plannedMinutes)} scheduled · ${_duration(revision.unscheduledMinutes)} unscheduled',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (revision.unscheduledMinutes > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Not all remaining preparation fits before the buffer. Increase the daily cap, start earlier, shorten the buffer, or revise your estimate.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ],
          if (sourceNeedsReview) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'The imported calendar event may be out of date or unavailable. Check the deadline before confirming another version of this plan.',
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            pending
                ? plan.isActive
                    ? 'Proposed reservations only. Your currently active plan remains in place until you confirm.'
                    : 'Proposed reservations only. Nothing is reserved until you confirm.'
                : 'Reserved in MyLifeGraph only',
          ),
          if (plan.isActive) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Linked Focus completed after this plan was first activated counts toward the plan as a whole and fills reserved blocks in chronological order. Starting from a row only prefills its remaining duration.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (missedMinutes >= 5) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Plan needs attention',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${missedBlocks.length} reserved ${missedBlocks.length == 1 ? 'block has' : 'blocks have'} passed with ${_duration(missedMinutes)} still uncredited. Replan from today; completed focus remains counted.',
                  ),
                  if (pending) ...[
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'The active reservations still need attention while the replacement remains an unconfirmed preview.',
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton.icon(
                    key: ValueKey('deadline-replan-missed-${plan.id}'),
                    onPressed: canMutate ? onReplanMissed : null,
                    icon: const Icon(Icons.autorenew),
                    label: const Text('Replan remaining time'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          for (final block in _visibleBlocks(
            revision.blocks,
            showAll: _showAllDisplayedBlocks,
          ))
            _DeadlineBlockTile(
              block: block,
              canStart: plan.isActive &&
                  !pending &&
                  block.plannedMinutes - block.creditedTrackedMinutes >= 5 &&
                  (block.state == DeadlinePlanBlockState.upcoming ||
                      block.state == DeadlinePlanBlockState.partial),
              onStart: () => onStartBlock(block),
            ),
          if (revision.blocks.length > _collapsedBlockLimit)
            TextButton.icon(
              key: ValueKey('deadline-toggle-blocks-${plan.id}'),
              onPressed: () => setState(
                () => _showAllDisplayedBlocks = !_showAllDisplayedBlocks,
              ),
              icon: Icon(
                _showAllDisplayedBlocks ? Icons.expand_less : Icons.expand_more,
              ),
              label: Text(
                _showAllDisplayedBlocks
                    ? 'Show fewer blocks'
                    : 'Show all ${revision.blocks.length} blocks',
              ),
            ),
          if (pending && active != null) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Currently reserved until you confirm',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(active.title),
            Text(
              '${_duration(active.plannedMinutes)} remains on the weekly plan while this replacement is only a preview.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final block in _visibleBlocks(
              active.blocks,
              showAll: _showAllActiveBlocks,
            ))
              _DeadlineBlockTile(
                block: block,
                canStart:
                    block.plannedMinutes - block.creditedTrackedMinutes >= 5 &&
                        (block.state == DeadlinePlanBlockState.upcoming ||
                            block.state == DeadlinePlanBlockState.partial),
                onStart: () => onStartBlock(block),
              ),
            if (active.blocks.length > _collapsedBlockLimit)
              TextButton.icon(
                key: ValueKey('deadline-toggle-active-blocks-${plan.id}'),
                onPressed: () => setState(
                  () => _showAllActiveBlocks = !_showAllActiveBlocks,
                ),
                icon: Icon(
                  _showAllActiveBlocks ? Icons.expand_less : Icons.expand_more,
                ),
                label: Text(
                  _showAllActiveBlocks
                      ? 'Show fewer active blocks'
                      : 'Show all ${active.blocks.length} active blocks',
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (pending)
                FilledButton.icon(
                  onPressed: canMutate && !sourceNeedsReview ? onConfirm : null,
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('Confirm reservations'),
                ),
              if (!plan.isTerminal)
                OutlinedButton.icon(
                  onPressed: canMutate ? onAdjust : null,
                  icon: const Icon(Icons.tune),
                  label: const Text('Adjust estimate or plan'),
                ),
              if (plan.isActive)
                OutlinedButton.icon(
                  onPressed: canMutate ? onComplete : null,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Mark preparation complete'),
                ),
              if (plan.isActive || plan.isDraft)
                TextButton(
                  onPressed: canMutate ? onCancel : null,
                  child: Text(plan.isDraft ? 'Discard preview' : 'Cancel plan'),
                ),
              if (plan.isTerminal)
                TextButton.icon(
                  key: ValueKey('deadline-hide-history-${plan.id}'),
                  onPressed: () => setState(() => _showTerminalDetails = false),
                  icon: const Icon(Icons.expand_less),
                  label: const Text('Hide history details'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Iterable<DeadlinePlanBlock> _visibleBlocks(
    List<DeadlinePlanBlock> blocks, {
    required bool showAll,
  }) =>
      showAll ? blocks : blocks.take(_collapsedBlockLimit);
}

class _DeadlineBlockTile extends StatelessWidget {
  const _DeadlineBlockTile({
    required this.block,
    required this.canStart,
    required this.onStart,
  });

  final DeadlinePlanBlock block;
  final bool canStart;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('deadline-block-${block.id}'),
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Text('${block.sequence}')),
      title: Text(
        '${block.localDate} · ${block.localStartTime.substring(0, 5)}–${block.localEndTime.substring(0, 5)}',
      ),
      subtitle: Text(
        '${_duration(block.plannedMinutes)} · ${_blockLabel(block.state)}'
        '${block.creditedTrackedMinutes > 0 ? ' · ${_duration(block.creditedTrackedMinutes)} tracked' : ''}',
      ),
      trailing: canStart
          ? IconButton(
              tooltip: 'Start plan focus with this remaining duration',
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
            )
          : null,
    );
  }
}

enum _DeadlineReplanContext { general, workload, missed }

class _DeadlinePlanEditorSheet extends StatefulWidget {
  const _DeadlinePlanEditorSheet({
    required this.planId,
    required this.baseRevision,
    required this.existing,
    required this.trackedFocusMinutes,
    required this.accountDailyPreparationBudgetKnown,
    required this.accountDailyPreparationBudgetMinutes,
    required this.retainedDraft,
    required this.initialKind,
    required this.initialTitle,
    required this.initialDeadlineAt,
    required this.initialDeadlineOn,
    required this.sourceKind,
    required this.sourceCalendarEventId,
    required this.sourceCalendarEventFingerprint,
    required this.initialSourceStatus,
    required this.startWithExistingSummary,
    required this.replanContext,
    required this.currentTime,
  });

  final String planId;
  final int baseRevision;
  final DeadlinePlanRevision? existing;
  final int trackedFocusMinutes;
  final bool accountDailyPreparationBudgetKnown;
  final int? accountDailyPreparationBudgetMinutes;
  final DeadlinePlanProposalDraft? retainedDraft;
  final DeadlinePlanKind? initialKind;
  final String? initialTitle;
  final DateTime? initialDeadlineAt;
  final String? initialDeadlineOn;
  final DeadlinePlanSourceKind sourceKind;
  final String? sourceCalendarEventId;
  final String? sourceCalendarEventFingerprint;
  final DeadlinePlanSourceStatus initialSourceStatus;
  final bool startWithExistingSummary;
  final _DeadlineReplanContext replanContext;
  final DateTime? currentTime;

  @override
  State<_DeadlinePlanEditorSheet> createState() =>
      _DeadlinePlanEditorSheetState();
}

class _DeadlinePlanEditorSheetState extends State<_DeadlinePlanEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _totalHoursController;
  late final TextEditingController _totalMinutesController;
  late final TextEditingController _priorHoursController;
  late final TextEditingController _priorMinutesController;
  late final TextEditingController _dailyCapController;
  DeadlinePlanKind? _kind;
  DateTime? _deadline;
  DateTime? _deadlineDateHint;
  bool? _alreadyStarted;
  int _step = 0;
  int _sessionMinutes = 50;
  int _bufferDays = 1;
  late DateTime _planningStart;
  late DeadlinePlanSourceKind _sourceKind;
  late bool _showExistingSummary;
  bool _useCalendarAvailability = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final retained = widget.retainedDraft;
    _titleController = TextEditingController(
      text: retained?.title ?? existing?.title ?? widget.initialTitle ?? '',
    );
    final total =
        retained?.estimatedTotalMinutes ?? existing?.estimatedTotalMinutes;
    _totalHoursController = TextEditingController(
      text: total == null ? '' : '${total ~/ 60}',
    );
    _totalMinutesController = TextEditingController(
      text: total == null ? '' : '${total % 60}',
    );
    final prior =
        retained?.creditedPriorMinutes ?? existing?.creditedPriorMinutes;
    _priorHoursController = TextEditingController(
      text: prior == null || prior == 0 ? '' : '${prior ~/ 60}',
    );
    _priorMinutesController = TextEditingController(
      text: prior == null || prior == 0 ? '' : '${prior % 60}',
    );
    _dailyCapController = TextEditingController(
      text: '${retained?.maxDailyMinutes ?? existing?.maxDailyMinutes ?? 120}',
    );
    _kind = retained?.kind ?? existing?.kind ?? widget.initialKind;
    _deadline = retained?.deadlineAt ??
        existing?.deadlineAt ??
        widget.initialDeadlineAt;
    _deadlineDateHint = _deadline == null
        ? DateTime.tryParse(widget.initialDeadlineOn ?? '')
        : null;
    _alreadyStarted = prior == null ? null : prior > 0;
    _sessionMinutes = retained?.preferredSessionMinutes ??
        existing?.preferredSessionMinutes ??
        50;
    _bufferDays = retained?.bufferDays ?? existing?.bufferDays ?? 1;
    final now = _now;
    final localDeadline = _deadline?.toLocal();
    if (retained == null &&
        existing == null &&
        localDeadline != null &&
        localDeadline.year == now.year &&
        localDeadline.month == now.month &&
        localDeadline.day == now.day) {
      _bufferDays = 0;
    }
    _sourceKind = widget.sourceKind;
    _showExistingSummary = widget.startWithExistingSummary;
    final today = DateTime(now.year, now.month, now.day);
    final savedPlanningStart = DateTime.tryParse(
      retained?.planningStartOn ?? existing?.planningStartOn ?? '',
    );
    final requestedPlanningStart = savedPlanningStart == null
        ? today
        : DateTime(
            savedPlanningStart.year,
            savedPlanningStart.month,
            savedPlanningStart.day,
          );
    _planningStart =
        requestedPlanningStart.isBefore(today) ? today : requestedPlanningStart;
    _useCalendarAvailability = retained?.useCalendarAvailability ??
        existing?.useCalendarAvailability ??
        false;
  }

  DateTime get _now => widget.currentTime ?? DateTime.now();

  @override
  void dispose() {
    _titleController.dispose();
    _totalHoursController.dispose();
    _totalMinutesController.dispose();
    _priorHoursController.dispose();
    _priorMinutesController.dispose();
    _dailyCapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showExistingSummary) {
      return _buildExistingSummary(context);
    }
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing == null
                ? 'Plan preparation'
                : 'Adjust preparation plan',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Step ${_step + 1} of 3'),
          const SizedBox(height: AppSpacing.lg),
          if (_step == 0) _buildIdentityStep(context),
          if (_step == 1) _buildEstimateStep(context),
          if (_step == 2) _buildPreferencesStep(context),
          const SizedBox(height: AppSpacing.lg),
          _buildNavigation(context),
        ],
      ),
    );
  }

  Widget _buildExistingSummary(BuildContext context) {
    final revision = widget.existing!;
    final total = revision.estimatedTotalMinutes;
    final prior = revision.creditedPriorMinutes;
    final tracked = widget.trackedFocusMinutes;
    final remaining = (total - prior - tracked).clamp(0, total).toInt();
    final sourceCurrent =
        revision.sourceKind == DeadlinePlanSourceKind.manual ||
            revision.sourceStatus == DeadlinePlanSourceStatus.current;
    final deadlineFuture = revision.deadlineAt.isAfter(_now);
    final canCreatePreview = sourceCurrent && deadlineFuture;
    final contextCopy = switch (widget.replanContext) {
      _DeadlineReplanContext.workload =>
        'You opened this from a daily workload that needs review. A fresh preview applies the current account budget again.',
      _DeadlineReplanContext.missed =>
        'This plan has missed, uncredited preparation. A fresh preview starts no earlier than today, while completed linked Focus remains counted.',
      _DeadlineReplanContext.general => null,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Replan remaining preparation',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Review the saved values below. You only need the full editor when one of them should change.',
          ),
          if (contextCopy != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(contextCopy),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(revision.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${revision.kind == DeadlinePlanKind.exam ? 'Exam' : 'Assignment'} · '
            'finish by ${DateFormat.yMMMd().add_Hm().format(revision.deadlineAt.toLocal())} · device time',
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _ProgressValue(label: 'Estimate', value: _duration(total)),
              _ProgressValue(
                label: 'Entered prior credit',
                value: _duration(prior),
              ),
              _ProgressValue(
                label: 'Tracked focus',
                value: _duration(tracked),
              ),
              _ProgressValue(
                label: 'Remaining',
                value: _duration(remaining),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${_duration(revision.preferredSessionMinutes)} preferred blocks · '
            '${_duration(revision.maxDailyMinutes)} maximum per day · '
            '${revision.bufferDays} ${revision.bufferDays == 1 ? 'clear day' : 'clear days'}',
          ),
          Text(
            'Plan from ${DateFormat.yMMMd().format(_planningStart)} · '
            '${revision.useCalendarAvailability ? 'use latest imported busy times' : 'do not use imported busy times'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            !widget.accountDailyPreparationBudgetKnown
                ? 'The account-wide budget could not be read here. The backend will still apply any saved total budget.'
                : widget.accountDailyPreparationBudgetMinutes == null
                    ? 'No account-wide daily preparation budget is set.'
                    : 'Current account-wide budget: ${_duration(widget.accountDailyPreparationBudgetMinutes!)} per day.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!sourceCurrent) ...[
            const SizedBox(height: AppSpacing.md),
            const Text(
              'The imported source changed or became unavailable. Change values and review the source before creating another preview.',
            ),
          ] else if (!deadlineFuture) ...[
            const SizedBox(height: AppSpacing.md),
            const Text(
              'The saved finish-by time has passed. Change values before creating another preview.',
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'Creating a preview stores a staged replacement. Your current reservations stay active until you confirm it. Nothing changes automatically, and the calculation is rule-based rather than AI-generated.',
          ),
          const SizedBox(height: AppSpacing.md),
          _buildExistingSummaryActions(context, canCreatePreview),
        ],
      ),
    );
  }

  Widget _buildExistingSummaryActions(
    BuildContext context,
    bool canCreatePreview,
  ) {
    final create = FilledButton.icon(
      key: const ValueKey('deadline-create-preview-existing'),
      onPressed: canCreatePreview ? _submit : null,
      icon: const Icon(Icons.event_repeat_outlined),
      label: const Text('Create preview with these values'),
    );
    final change = OutlinedButton(
      key: const ValueKey('deadline-change-existing-values'),
      onPressed: () => setState(() => _showExistingSummary = false),
      child: const Text('Change values'),
    );
    final cancel = TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Cancel'),
    );
    if (_choiceDirection(context) == Axis.vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          create,
          const SizedBox(height: AppSpacing.sm),
          change,
          const SizedBox(height: AppSpacing.xs),
          cancel,
        ],
      );
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [create, change, cancel],
    );
  }

  Widget _buildNavigation(BuildContext context) {
    final secondary = TextButton(
      onPressed: _step == 0
          ? () => Navigator.of(context).pop()
          : () => setState(() => _step -= 1),
      child: Text(_step == 0 ? 'Cancel' : 'Back'),
    );
    final primary = FilledButton(
      onPressed: _step == 2 ? _submit : _next,
      child: Text(_step == 2 ? 'Create preview' : 'Continue'),
    );

    if (_choiceDirection(context) == Axis.vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          const SizedBox(height: AppSpacing.sm),
          secondary,
        ],
      );
    }

    return Row(
      children: [
        secondary,
        const Spacer(),
        primary,
      ],
    );
  }

  Widget _buildIdentityStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What are you preparing for?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Choose this yourself. MyLifeGraph never infers an exam or assignment from a calendar title.',
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'You enter the finish time in this device\'s timezone. The preview places blocks in the profile timezone saved in Settings.',
        ),
        const SizedBox(height: AppSpacing.md),
        SegmentedButton<DeadlinePlanKind>(
          direction: _choiceDirection(context),
          emptySelectionAllowed: true,
          segments: const [
            ButtonSegment(value: DeadlinePlanKind.exam, label: Text('Exam')),
            ButtonSegment(
              value: DeadlinePlanKind.assignment,
              label: Text('Assignment'),
            ),
          ],
          selected: _kind == null ? const {} : {_kind!},
          onSelectionChanged: (values) {
            setState(() => _kind = values.isEmpty ? null : values.single);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const ValueKey('deadline-plan-title'),
          controller: _titleController,
          maxLength: 160,
          decoration:
              const InputDecoration(labelText: 'Exam or assignment title'),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _pickDeadline,
            icon: const Icon(Icons.event_outlined),
            label: Text(
              _deadline == null
                  ? _deadlineDateHint == null
                      ? 'Choose finish-by date and device time'
                      : 'Choose finish-by device time for ${DateFormat.yMMMd().format(_deadlineDateHint!)}'
                  : 'Finish by ${DateFormat.yMMMd().add_Hm().format(_deadline!.toLocal())} · device time',
            ),
          ),
        ),
        if (widget.sourceKind == DeadlinePlanSourceKind.calendarEvent) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Imported event details are prefilled for review only. The source stays read-only.',
          ),
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            key: const ValueKey('deadline-keep-calendar-source'),
            contentPadding: EdgeInsets.zero,
            value: _sourceKind == DeadlinePlanSourceKind.calendarEvent,
            onChanged: (value) {
              setState(() {
                _sourceKind = value
                    ? DeadlinePlanSourceKind.calendarEvent
                    : DeadlinePlanSourceKind.manual;
                if (!value &&
                    widget.initialSourceStatus ==
                        DeadlinePlanSourceStatus.unavailable) {
                  _useCalendarAvailability = false;
                }
              });
            },
            title: const Text('Keep this imported event linked'),
            subtitle: Text(
              widget.initialSourceStatus == DeadlinePlanSourceStatus.stale ||
                      widget.initialSourceStatus ==
                          DeadlinePlanSourceStatus.unavailable
                  ? 'The imported source changed. Turn this off to keep your reviewed title and deadline as a manual plan.'
                  : 'Turn this off if you want the reviewed title and deadline to become a manual plan.',
            ),
          ),
          if (_sourceKind == DeadlinePlanSourceKind.manual)
            const Text(
              'The next preview will no longer depend on the imported event. The event itself is never changed.',
            ),
        ],
      ],
    );
  }

  Widget _buildEstimateStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your preparation estimate',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'How much active preparation time do you think you will need in total? Count focused work, not breaks or classes.',
        ),
        const SizedBox(height: AppSpacing.md),
        _DurationFields(
          prefix: 'deadline-total',
          hours: _totalHoursController,
          minutes: _totalMinutesController,
          label: 'Total active preparation',
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final hours in const [2, 5, 10])
              ActionChip(
                key: ValueKey('deadline-estimate-${hours}h'),
                label: Text('$hours h'),
                onPressed: () {
                  setState(() {
                    _totalHoursController.text = '$hours';
                    _totalMinutesController.text = '0';
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'MyLifeGraph cannot estimate this for you. One transparent approach is topics × sessions per topic × minutes per session; these chips are only optional shortcuts.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text(
          'Do you have preparation this plan will not credit automatically?',
        ),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<bool>(
          direction: _choiceDirection(context),
          emptySelectionAllowed: true,
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('No additional prior work'),
            ),
            ButtonSegment(value: true, label: Text('Yes, add prior work')),
          ],
          selected: _alreadyStarted == null ? const {} : {_alreadyStarted!},
          onSelectionChanged: (values) {
            setState(
              () => _alreadyStarted = values.isEmpty ? null : values.single,
            );
          },
        ),
        if (_alreadyStarted == true) ...[
          const SizedBox(height: AppSpacing.md),
          _DurationFields(
            prefix: 'deadline-prior',
            hours: _priorHoursController,
            minutes: _priorMinutesController,
            label: 'Prior preparation to credit',
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Enter earlier preparation, including Focus completed before this plan was first activated or Focus linked to another task. Do not re-enter the linked Focus shown below; after activation it is credited automatically.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (_totalMinutes != null && _creditedPriorMinutes != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            '${_duration(_totalMinutes!)} total · ${_duration(_creditedPriorMinutes!)} entered prior credit · ${_duration(widget.trackedFocusMinutes)} linked Focus · ${_duration((_totalMinutes! - _creditedPriorMinutes! - widget.trackedFocusMinutes).clamp(0, _totalMinutes!).toInt())} to schedule',
            key: const ValueKey('deadline-estimate-summary'),
          ),
        ],
      ],
    );
  }

  Widget _buildPreferencesStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How should we split it?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'These controls are optional. You can adjust them before confirming any reservations.',
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('Preferred focus block'),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<int>(
          direction: _choiceDirection(context),
          segments: const [
            ButtonSegment(value: 25, label: Text('25 min')),
            ButtonSegment(value: 50, label: Text('50 min')),
            ButtonSegment(value: 90, label: Text('90 min')),
          ],
          selected: {_sessionMinutes},
          onSelectionChanged: (values) =>
              setState(() => _sessionMinutes = values.single),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const ValueKey('deadline-daily-cap'),
          controller: _dailyCapController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Maximum preparation minutes per day for this plan',
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          !widget.accountDailyPreparationBudgetKnown
              ? 'The account-wide budget could not be read here. The backend will still apply any saved total budget.'
              : widget.accountDailyPreparationBudgetMinutes == null
                  ? 'No account-wide budget is set. Only this plan cap applies; you can add a total daily limit in Settings.'
                  : 'Account-wide budget: ${_duration(widget.accountDailyPreparationBudgetMinutes!)} per day. Confirmed blocks from other plans are deducted before this plan is placed.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<int>(
          initialValue: _bufferDays,
          decoration: const InputDecoration(
            labelText: 'Clear days before finish-by date',
          ),
          items: List.generate(
            8,
            (days) => DropdownMenuItem(
              value: days,
              child: Text(
                '$days ${days == 1 ? 'clear day' : 'clear days'}',
              ),
            ),
          ),
          onChanged: (value) {
            if (value != null) setState(() => _bufferDays = value);
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'A clear day receives no preparation blocks. With 0 clear days, the finish-by day may still be used.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: _pickPlanningStart,
          icon: const Icon(Icons.today_outlined),
          label: Text(
            'Start planning ${DateFormat.yMMMd().format(_planningStart)}',
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'When replanning, a saved start in the past moves to today.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_busy_outlined),
          title: const Text('Imported busy times follow Planner'),
          subtitle: const Text(
            'The one read-only Planner calendar setting applies here too. Change it in Planner before creating this preview. Re-import after changes; there is no background sync, and no event text is sent to AI.',
          ),
          trailing: const Icon(Icons.open_in_new_outlined),
          onTap: () {
            final router = GoRouter.of(context);
            Navigator.of(context).pop();
            router.go(AppRoutes.planner);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'Next, MyLifeGraph creates a staged preview. Nothing is reserved until you confirm it.',
        ),
      ],
    );
  }

  void _next() {
    if (_step == 0) {
      if (_kind == null ||
          _titleController.text.trim().isEmpty ||
          _deadline == null) {
        _showValidation('Choose a type, title, and future finish-by time.');
        return;
      }
      if (!_deadline!.isAfter(_now)) {
        _showValidation('The finish-by time must be in the future.');
        return;
      }
      if (_deadline!.difference(_now).inDays > 366) {
        _showValidation('Choose a finish-by time within the next 366 days.');
        return;
      }
    }
    if (_step == 1) {
      final total = _totalMinutes;
      final prior = _creditedPriorMinutes;
      if (total == null || total < 30 || total > 30000) {
        _showValidation('Enter 30 minutes to 500 hours of total preparation.');
        return;
      }
      if (_alreadyStarted == null) {
        _showValidation('Choose whether you have already started.');
        return;
      }
      if (prior == null || prior < 0 || prior >= total) {
        _showValidation(
          'Already invested time must be below the total estimate.',
        );
        return;
      }
    }
    setState(() => _step += 1);
  }

  Future<void> _pickDeadline() async {
    final now = _now;
    final lastDate = now.add(const Duration(days: 366));
    final dateHint = _deadlineDateHint;
    final requestedInitial = _deadline?.toLocal() ??
        (dateHint == null
            ? now.add(const Duration(days: 7))
            : DateTime(
                dateHint.year,
                dateHint.month,
                dateHint.day,
                now.hour,
                now.minute,
              ));
    final initial = requestedInitial.isAfter(lastDate)
        ? lastDate
        : requestedInitial.isBefore(now)
            ? now
            : requestedInitial;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: lastDate,
      helpText: 'Preparation finish-by date',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Preparation finish-by time',
    );
    if (time == null || !mounted) return;
    setState(() {
      _deadline =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _deadlineDateHint = null;
      if (widget.existing == null &&
          widget.retainedDraft == null &&
          date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        _bufferDays = 0;
      }
    });
  }

  Future<void> _pickPlanningStart() async {
    final now = _now;
    final today = DateTime(now.year, now.month, now.day);
    final deadlineDate = _deadline?.toLocal();
    final lastDate = deadlineDate == null
        ? now.add(const Duration(days: 365))
        : DateTime(deadlineDate.year, deadlineDate.month, deadlineDate.day);
    final firstDate = today;
    final initialDate = _planningStart.isAfter(lastDate)
        ? lastDate
        : _planningStart.isBefore(firstDate)
            ? firstDate
            : _planningStart;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Preparation planning start',
    );
    if (selected != null && mounted) setState(() => _planningStart = selected);
  }

  void _submit() {
    final total = _totalMinutes;
    final prior = _creditedPriorMinutes;
    final dailyCap = int.tryParse(_dailyCapController.text.trim());
    if (total == null ||
        prior == null ||
        dailyCap == null ||
        _kind == null ||
        _deadline == null) {
      _showValidation('Review all required plan values.');
      return;
    }
    if (!_deadline!.isAfter(_now)) {
      _showValidation('The finish-by time must be in the future.');
      return;
    }
    if (_deadline!.difference(_now).inDays > 366) {
      _showValidation('Choose a finish-by time within the next 366 days.');
      return;
    }
    final deadlineDate = DateTime(
      _deadline!.year,
      _deadline!.month,
      _deadline!.day,
    );
    final startDate = DateTime(
      _planningStart.year,
      _planningStart.month,
      _planningStart.day,
    );
    final horizonDays = deadlineDate.difference(startDate).inDays;
    if (horizonDays < 0 || horizonDays > 366) {
      _showValidation(
        'Planning must start no later than the deadline date and span at most 366 days.',
      );
      return;
    }
    try {
      Navigator.of(context).pop(
        DeadlinePlanProposalDraft(
          planId: widget.planId,
          baseRevision: widget.baseRevision,
          kind: _kind!,
          title: _titleController.text,
          deadlineAt: _deadline!,
          estimatedTotalMinutes: total,
          creditedPriorMinutes: prior,
          preferredSessionMinutes: _sessionMinutes,
          maxDailyMinutes: dailyCap,
          planningStartOn: localDateKey(_planningStart),
          bufferDays: _bufferDays,
          sourceKind: _sourceKind,
          sourceCalendarEventId:
              _sourceKind == DeadlinePlanSourceKind.calendarEvent
                  ? widget.sourceCalendarEventId
                  : null,
          sourceCalendarEventFingerprint:
              _sourceKind == DeadlinePlanSourceKind.calendarEvent
                  ? widget.sourceCalendarEventFingerprint
                  : null,
          useCalendarAvailability: _useCalendarAvailability,
        ),
      );
    } on DeadlinePlanAccessException catch (error) {
      _showValidation(error.message);
    }
  }

  int? get _totalMinutes => _durationInput(
        _totalHoursController.text,
        _totalMinutesController.text,
      );

  int? get _creditedPriorMinutes {
    if (_alreadyStarted == false) return 0;
    if (_alreadyStarted != true) return null;
    return _durationInput(
      _priorHoursController.text,
      _priorMinutesController.text,
    );
  }

  void _showValidation(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _DurationFields extends StatelessWidget {
  const _DurationFields({
    required this.prefix,
    required this.hours,
    required this.minutes,
    required this.label,
  });

  final String prefix;
  final TextEditingController hours;
  final TextEditingController minutes;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: ValueKey('$prefix-hours'),
              controller: hours,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Hours'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              key: ValueKey('$prefix-minutes'),
              controller: minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Minutes'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressValue extends StatelessWidget {
  const _ProgressValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _OperationErrorCard extends StatelessWidget {
  const _OperationErrorCard({
    required this.state,
    required this.onRetry,
    required this.onReload,
    required this.onDismiss,
    required this.onReview,
  });

  final DeadlinePlanState state;
  final Future<bool> Function() onRetry;
  final Future<void> Function() onReload;
  final VoidCallback onDismiss;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final exact = state.requiresExactRetry;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exact
                ? 'Could not confirm the plan save'
                : 'Could not update the plan',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            exact
                ? 'Your submitted values are still here and locked for a safe retry. Retry unchanged or load the latest saved plan.'
                : deadlinePlanConflictGuidance(state.operationError!) ??
                    _errorMessage(state.operationError!),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (exact)
                FilledButton(
                  onPressed: state.isBusy ? null : onRetry,
                  child: const Text('Retry unchanged'),
                ),
              OutlinedButton(
                onPressed: state.isBusy ? null : onReload,
                child: const Text('Load latest plan'),
              ),
              if (onReview != null)
                OutlinedButton(
                  onPressed: state.isBusy ? null : onReview,
                  child: const Text('Review entered values'),
                ),
              if (!exact && !state.reloadSuggested)
                TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(message),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _CalendarPrefillCard extends StatelessWidget {
  const _CalendarPrefillCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(message),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton(
                onPressed: onPrimary,
                child: Text(primaryLabel),
              ),
              if (secondaryLabel != null && onSecondary != null)
                TextButton(
                  onPressed: onSecondary,
                  child: Text(secondaryLabel!),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

int? _durationInput(String hoursText, String minutesText) {
  final cleanHours = hoursText.trim();
  final cleanMinutes = minutesText.trim();
  if (cleanHours.isEmpty && cleanMinutes.isEmpty) return null;
  final hours = cleanHours.isEmpty ? 0 : int.tryParse(cleanHours);
  final minutes = cleanMinutes.isEmpty ? 0 : int.tryParse(cleanMinutes);
  if (hours == null ||
      minutes == null ||
      hours < 0 ||
      minutes < 0 ||
      minutes > 59) {
    return null;
  }
  return hours * 60 + minutes;
}

String _duration(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest min';
  if (rest == 0) return '$hours h';
  return '$hours h $rest min';
}

Axis _choiceDirection(BuildContext context) {
  final scaledBody = MediaQuery.textScalerOf(context).scale(14);
  return MediaQuery.sizeOf(context).width < 420 || scaledBody > 20
      ? Axis.vertical
      : Axis.horizontal;
}

String _statusLabel(DeadlinePlanStatus status) => switch (status) {
      DeadlinePlanStatus.draft => 'Draft',
      DeadlinePlanStatus.active => 'Active',
      DeadlinePlanStatus.completed => 'Completed',
      DeadlinePlanStatus.cancelled => 'Cancelled',
    };

String _blockLabel(DeadlinePlanBlockState state) => switch (state) {
      DeadlinePlanBlockState.proposed => 'proposed',
      DeadlinePlanBlockState.upcoming => 'upcoming',
      DeadlinePlanBlockState.partial => 'partly credited',
      DeadlinePlanBlockState.completed => 'fully credited',
      DeadlinePlanBlockState.missed => 'missed',
    };

String _planningWindowDescription(String energyWindow) =>
    switch (energyWindow) {
      'early_morning' =>
        'Rule-based windows: prefers 06:00–11:00, then tries 13:00–17:00 and 18:00–21:00 if needed.',
      'morning' =>
        'Rule-based windows: prefers 08:00–13:00, then tries 14:00–18:00 and 18:00–21:00 if needed.',
      'afternoon' =>
        'Rule-based windows: prefers 13:00–18:00, then tries 09:00–12:00 and 18:00–21:00 if needed.',
      'evening' =>
        'Rule-based windows: prefers 18:00–23:00, then tries 14:00–17:00 and 09:00–12:00 if needed.',
      _ =>
        'Rule-based windows: tries 09:00–12:00, 14:00–18:00, then 18:00–21:00.',
    };

String _errorMessage(Object error) => switch (error) {
      DeadlinePlanAccessException(:final message) => message,
      DeadlinePlanContractException(:final message) => message,
      _ => 'The preparation plan operation could not be completed.',
    };
