import 'package:flutter/material.dart';

import 'package:my_life_graph/core/constants/app_radii.dart';

import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../core/time/profile_timezone.dart';
import '../../../../core/utils/client_uuid.dart';
import '../../../../core/utils/local_date.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_info_disclosure.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_surface.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import '../../application/deadline_plan_controller.dart';
import '../../application/assignment_series_controller.dart';
import '../../application/multi_exam_plan_controller.dart';
import '../../domain/assignment_series.dart';
import '../../domain/deadline_calendar_prefill.dart';
import '../../domain/deadline_plan.dart';
import '../../domain/exam_plan_health.dart';
import '../../domain/multi_exam_plan.dart';
import 'package:my_life_graph/composition/deadline_plan_providers.dart';

part '../widgets/deadline_plan_card.dart';
part '../widgets/deadline_plan_editor_sheet.dart';
part '../widgets/deadline_plan_support_widgets.dart';
part '../widgets/assignment_series_widgets.dart';
part '../widgets/multi_exam_plan_widgets.dart';

class DeadlinePlansPage extends ConsumerStatefulWidget {
  const DeadlinePlansPage({
    super.key,
    this.sourceCalendarEventId,
    this.initialTitle,
    this.initialDeadlineAt,
    this.initialDeadlineOn,
    this.initialKind,
    this.initialPlanId,
    this.initialBalanceId,
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
  final String? initialBalanceId;
  final bool openInitialReplan;
  final bool focusedReplan;
  final DateTime? currentTime;

  @override
  ConsumerState<DeadlinePlansPage> createState() => _DeadlinePlansPageState();
}

class _DeadlinePlansPageState extends ConsumerState<DeadlinePlansPage> {
  bool _sourceEditorOpened = false;
  bool _editorOpen = false;
  bool _seriesEditorOpen = false;
  bool _targetPlanRequested = false;
  bool _targetPlanLoading = false;
  bool _initialReplanOpened = false;
  bool _initialKindEditorOpened = false;
  bool _expansionInitialized = false;
  String? _targetPlanId;
  DeadlinePlan? _targetPlanResult;
  Object? _targetPlanError;
  DeadlinePlanProposalDraft? _retainedDraft;
  AssignmentSeriesProposalDraft? _retainedSeriesDraft;
  String? _expandedPlanId;
  String? _expandedSeriesId;
  String? _operationPlanId;
  String? _operationSeriesId;
  String? _selectedBalanceTargetPlanId;
  bool _initialBalanceRequested = false;
  final Map<String, GlobalKey> _planKeys = {};

  @override
  void initState() {
    super.initState();
    _targetPlanId = widget.initialPlanId;
    _expandedPlanId = widget.initialPlanId;
  }

  @override
  void didUpdateWidget(covariant DeadlinePlansPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPlanId != widget.initialPlanId) {
      _targetPlanRequested = false;
      _targetPlanLoading = false;
      _targetPlanId = widget.initialPlanId;
      _targetPlanResult = null;
      _targetPlanError = null;
      _initialReplanOpened = false;
      _expandedPlanId = widget.initialPlanId;
      _expansionInitialized = false;
    } else if (oldWidget.openInitialReplan != widget.openInitialReplan) {
      _initialReplanOpened = false;
    }
    if (oldWidget.initialBalanceId != widget.initialBalanceId) {
      _initialBalanceRequested = false;
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
    final seriesState = ref.watch(assignmentSeriesControllerProvider);
    final multiExamState = ref.watch(multiExamPlanControllerProvider);
    final profileTimezone =
        ref.watch(profileLocalDateSourceProvider).timezoneName;
    final examPlanHealth = ref.watch(examPlanHealthProvider);
    ref.watch(preparationWorkloadProvider);
    final controller = ref.read(deadlinePlanControllerProvider.notifier);
    final seriesController =
        ref.read(assignmentSeriesControllerProvider.notifier);
    final multiExamController =
        ref.read(multiExamPlanControllerProvider.notifier);
    final sourcePrefill = widget.sourceCalendarEventId == null
        ? null
        : ref.watch(
            deadlineCalendarPrefillProvider(widget.sourceCalendarEventId!),
          );
    _openSourceEditorAfterBuild(state, sourcePrefill);
    _loadTargetPlanAfterBuild(state);
    _initializeExpansionAfterBuild(state);
    _openInitialReplanAfterBuild(state);
    _openInitialKindEditorAfterBuild(state, seriesState);
    _loadInitialBalanceAfterBuild(multiExamController);

    final anyMutationBusy =
        state.isBusy || seriesState.isBusy || multiExamState.isBusy;

    return AppPage(
      title: widget.focusedReplan ? 'Replan preparation' : 'Preparation plans',
      subtitle: widget.focusedReplan
          ? 'Review one plan, stage a preview, then confirm explicitly'
          : 'Reserve realistic focus time before an exam or assignment',
      backFallback: AppRoutes.planner,
      actions: [
        IconButton(
          tooltip: 'Reload preparation plans',
          onPressed: anyMutationBusy
              ? null
              : () {
                  ref.invalidate(preparationWorkloadProvider);
                  ref.invalidate(examPlanHealthProvider);
                  controller.load();
                  seriesController.load();
                  multiExamController.load();
                },
          icon: const Icon(AppIcons.refresh),
        ),
      ],
      children: _children(
        state,
        controller,
        seriesState,
        seriesController,
        multiExamState,
        multiExamController,
        profileTimezone,
        sourcePrefill,
        examPlanHealth,
      ),
    );
  }

  List<Widget> _children(
    DeadlinePlanState state,
    DeadlinePlanController controller,
    AssignmentSeriesState seriesState,
    AssignmentSeriesController seriesController,
    MultiExamPlanState multiExamState,
    MultiExamPlanController multiExamController,
    String? profileTimezone,
    AsyncValue<DeadlineCalendarPrefill>? sourcePrefill,
    AsyncValue<ExamPlanHealth?> examPlanHealth,
  ) {
    final healthValue = examPlanHealth.asData?.value;
    final anyMutationBusy =
        state.isBusy || seriesState.isBusy || multiExamState.isBusy;
    final operationSeriesId =
        seriesState.pendingMutation?.seriesId ?? _operationSeriesId;
    final hasInlineSeriesError = !state.isLoading && state.loadError == null &&
        !widget.focusedReplan && !seriesState.isLoading &&
        seriesState.loadError == null && seriesState.series.any((series) =>
            series.id == operationSeriesId && _expandedSeriesId == series.id &&
            series.displayedRevision != null);
    final seriesError = seriesState.operationError != null && !hasInlineSeriesError
        ? AppCard(
            child: _AssignmentSeriesOperationError(
              error: seriesState.operationError!,
              exactRetry: seriesState.requiresExactRetry,
              isBusy: anyMutationBusy,
              onRetry: _retryAssignmentSeries,
              onReload: seriesController.load,
              onDismiss: seriesController.clearOperationError,
              onReview: _retainedSeriesDraft == null ? null : () {
                seriesController.clearOperationError();
                _openAssignmentSeriesEditor(retainedDraft: _retainedSeriesDraft);
              },
            ),
          )
        : null;
    final healthSection = _ExamPlanHealthSection(
      value: examPlanHealth,
      onRetry: () => ref.invalidate(examPlanHealthProvider),
      onOpenPlan: _openHealthPlan,
    );
    if (state.isLoading) {
      return [
        if (seriesError != null) seriesError,
        healthSection,
        const AppCard(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      ];
    }
    final seriesPlanIds =
        seriesState.series.expand((series) => series.occurrencePlanIds).toSet();
    final projectedPlans = [...state.plans];
    final targeted = _targetPlanResult;
    if (targeted != null &&
        !projectedPlans.any((plan) => plan.id == targeted.id)) {
      projectedPlans.add(targeted);
    }
    final visiblePlans = projectedPlans
        .where(
          (plan) =>
              widget.focusedReplan ||
              plan.id == _targetPlanId ||
              !seriesPlanIds.contains(plan.id),
        )
        .toList()
      ..sort((left, right) {
        final selectedId = _targetPlanId;
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
    final targetPlan = _planById(visiblePlans, _targetPlanId);

    Widget planCard(DeadlinePlan plan) {
      final key = _planKeys.putIfAbsent(plan.id, GlobalKey.new);
      final hasInlineError =
          state.operationError != null && _operationPlanId == plan.id;
      final pendingRevision = plan.pendingRevision?.revision;
      final childLink = pendingRevision == null
          ? null
          : multiExamState.proposedChildLinks['${plan.id}:$pendingRevision'];
      final childMetadataUnavailable = pendingRevision != null &&
          plan.kind == DeadlinePlanKind.exam &&
          multiExamState.metadataStatus != MultiExamPlanMetadataStatus.current;
      return KeyedSubtree(
        key: key,
        child: _DeadlinePlanCard(
          key: ValueKey('deadline-plan-${plan.id}'),
          plan: plan,
          expanded: _expandedPlanId == plan.id,
          isBusy: anyMutationBusy,
          exactRetryLocked: state.requiresExactRetry ||
              seriesState.requiresExactRetry || multiExamState.requiresExactRetry,
          examHealth: _healthForPlan(healthValue, plan.id),
          childBalanceId: childLink?.balanceId,
          childMetadataUnavailable: childMetadataUnavailable,
          profileTimezone: profileTimezone,
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
          onReviewBalance: childLink == null
              ? null
              : () => _openExamBalance(childLink.balanceId),
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

    Widget seriesCard(AssignmentSeries series) {
      final hasInlineError = seriesState.operationError != null &&
          hasInlineSeriesError && operationSeriesId == series.id;
      return _AssignmentSeriesCard(
        key: ValueKey('assignment-series-${series.id}'),
        series: series,
        plans: {
          for (final plan in state.plans)
            if (series.occurrencePlanIds.contains(plan.id)) plan.id: plan,
        },
        expanded: _expandedSeriesId == series.id,
        isBusy: anyMutationBusy,
        exactRetryLocked: state.requiresExactRetry ||
            seriesState.requiresExactRetry ||
            multiExamState.requiresExactRetry,
        operationError: hasInlineError ? seriesState.operationError : null,
        onToggle: () => setState(
          () => _expandedSeriesId =
              _expandedSeriesId == series.id ? null : series.id,
        ),
        onEditSeries: () => _openAssignmentSeriesEditor(series: series),
        onEditOccurrence: (plan) => _openEditor(plan: plan),
        onConfirm: () => _confirmAssignmentSeries(series),
        onCancelFuture: () => _cancelAssignmentSeriesFuture(series),
        onRetry: _retryAssignmentSeries,
        onReload: () async {
          await Future.wait([controller.load(), seriesController.load()]);
        },
        onDismissError: seriesController.clearOperationError,
      );
    }

    final openPlans =
        visiblePlans.where((plan) => !plan.isTerminal).toList(growable: false);
    final historyPlans =
        visiblePlans.where((plan) => plan.isTerminal).toList(growable: false);

    final leading = <Widget>[
      if (seriesError != null) seriesError,
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
      healthSection,
    ];

    if (state.loadError != null) {
      return [
        ...leading,
        _MessageCard(
          icon: AppIcons.cloudOffOutlined,
          title: 'Preparation plans unavailable',
          message:
              'Your saved plans could not be read. Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: controller.load,
        ),
        if (targetPlan != null) planCard(targetPlan),
        _MultiExamPlanSection(
          state: multiExamState,
          plans: projectedPlans,
          health: healthValue,
          profileTimezone: profileTimezone,
          selectedTargetPlanId: _selectedBalanceTargetPlanId,
          mutationsBlocked: anyMutationBusy ||
              state.requiresExactRetry ||
              seriesState.requiresExactRetry,
          onSelectTarget: (planId) => setState(
            () => _selectedBalanceTargetPlanId = planId,
          ),
          onPropose: _proposeExamBalance,
          onOpenBalance: _openExamBalance,
          onLoadBalance: multiExamController.loadBalance,
          onConfirm: _confirmExamBalance,
          onCancel: _cancelExamBalance,
          onRetryExact: multiExamController.retryExact,
          onReload: multiExamController.load,
          onRefreshSaved: multiExamController.refreshSavedProjection,
          onDismissError: multiExamController.clearOperationError,
        ),
      ];
    }

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
            icon: AppIcons.cancelOutlined,
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
              onPressed: anyMutationBusy ||
                      state.requiresExactRetry ||
                      seriesState.requiresExactRetry ||
                      multiExamState.requiresExactRetry ||
                      sourcePrefill?.isLoading == true
                  ? null
                  : _choosePreparationKind,
              icon: const Icon(AppIcons.eventAvailableOutlined),
              label: const Text('Plan preparation'),
            ),
          ],
        ),
      ),
      if (seriesState.isLoading)
        const AppCard(
          child: Row(
            children: [
              SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(child: Text('Loading weekly assignment series…')),
            ],
          ),
        )
      else if (seriesState.loadError != null)
        _MessageCard(
          icon: AppIcons.cloudOffOutlined,
          title: 'Weekly assignment series unavailable',
          message:
              'Weekly series could not be read. Individual preparation plans remain visible.',
          actionLabel: 'Retry series',
          onAction: seriesController.load,
        )
      else if (seriesState.series.isNotEmpty) ...[
        Text(
          'Weekly assignment series',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        for (final series in seriesState.series) seriesCard(series),
      ],
      if (visiblePlans.isEmpty && seriesState.series.isEmpty)
        const _MessageCard(
          icon: AppIcons.calendarViewWeekOutlined,
          title: 'No preparation plan yet',
          message:
              'Create a staged preview first. Nothing is reserved until you confirm it.',
        )
      else if (visiblePlans.isNotEmpty) ...[
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
      _MultiExamPlanSection(
        state: multiExamState,
        plans: projectedPlans,
        health: healthValue,
        profileTimezone: profileTimezone,
        selectedTargetPlanId: _selectedBalanceTargetPlanId,
        mutationsBlocked: anyMutationBusy ||
            state.requiresExactRetry ||
            seriesState.requiresExactRetry,
        onSelectTarget: (planId) => setState(
          () => _selectedBalanceTargetPlanId = planId,
        ),
        onPropose: _proposeExamBalance,
        onOpenBalance: _openExamBalance,
        onLoadBalance: multiExamController.loadBalance,
        onConfirm: _confirmExamBalance,
        onCancel: _cancelExamBalance,
        onRetryExact: multiExamController.retryExact,
        onReload: multiExamController.load,
        onRefreshSaved: multiExamController.refreshSavedProjection,
        onDismissError: multiExamController.clearOperationError,
      ),
      if (_retainedSeriesDraft != null &&
          seriesState.operationError == null &&
          !seriesState.isBusy)
        _CalendarPrefillCard(
          icon: AppIcons.editNoteOutlined,
          title: 'Entered series values kept',
          message: 'Review the weekly assignment values before trying again.',
          primaryLabel: 'Review series values',
          onPrimary: () => _openAssignmentSeriesEditor(
            retainedDraft: _retainedSeriesDraft,
          ),
          secondaryLabel: 'Discard entered values',
          onSecondary: () => setState(() => _retainedSeriesDraft = null),
        ),
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
    final planId = _targetPlanId;
    if (planId == null ||
        _targetPlanRequested ||
        state.isLoading ||
        _targetPlanResult?.id == planId ||
        state.plans.any((plan) => plan.id == planId)) {
      return;
    }
    _targetPlanRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadTargetPlan(planId);
    });
  }

  void _loadInitialBalanceAfterBuild(MultiExamPlanController controller) {
    final balanceId = widget.initialBalanceId;
    if (_initialBalanceRequested || balanceId == null) return;
    _initialBalanceRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.loadBalance(balanceId);
    });
  }

  Future<void> _proposeExamBalance() async {
    final planId = _selectedBalanceTargetPlanId;
    if (planId == null) return;
    final plan = _planById(
      ref.read(deadlinePlanControllerProvider).plans,
      planId,
    );
    if (plan == null ||
        !plan.isActive ||
        plan.kind != DeadlinePlanKind.exam ||
        plan.pendingRevision != null) {
      _showMessage('Load a current active Exam before balancing.');
      return;
    }
    final saved =
        await ref.read(multiExamPlanControllerProvider.notifier).propose(
              MultiExamPlanProposalDraft(
                targetPlanId: plan.id,
                expectedPlanRevision: plan.latestRevision,
              ),
            );
    if (!mounted || !saved) return;
    final resultState = ref.read(multiExamPlanControllerProvider);
    final balance = resultState.selectedBalance;
    if (resultState.lastOutcome == 'multi_exam_batch' && balance != null) {
      context.go('${AppRoutes.preparationPlans}?balance_id=${balance.id}');
    }
  }

  void _openExamBalance(String balanceId) {
    final state = ref.read(multiExamPlanControllerProvider);
    if (state.isBusy || state.requiresExactRetry) return;
    context.go('${AppRoutes.preparationPlans}?balance_id=$balanceId');
  }

  Future<void> _confirmExamBalance(MultiExamPlanBatch balance) async {
    final confirmed = await _confirm(
      title: 'Confirm all Exam changes?',
      message:
          '${balance.items.length} changed Exam plans will be confirmed atomically. Existing valid reservations are retained where possible. Nothing changes in an external calendar and no notification is sent.',
      action: 'Confirm all',
    );
    if (!mounted || !confirmed) return;
    final saved = await ref
        .read(multiExamPlanControllerProvider.notifier)
        .confirm(balance);
    if (mounted && saved) {
      _showMessage('All listed Exam changes confirmed.');
    }
  }

  Future<void> _cancelExamBalance(MultiExamPlanBatch balance) async {
    final confirmed = await _confirm(
      title: 'Discard this Exam balance preview?',
      message:
          'Only the shared preview will be discarded. Active Exam plans and their current reservations stay in place.',
      action: 'Discard',
    );
    if (!mounted || !confirmed) return;
    final saved = await ref
        .read(multiExamPlanControllerProvider.notifier)
        .cancel(balance);
    if (mounted && saved) {
      _showMessage('Exam balance preview discarded; active plans kept.');
    }
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

  void _openInitialKindEditorAfterBuild(
    DeadlinePlanState state,
    AssignmentSeriesState seriesState,
  ) {
    if (widget.initialKind == null ||
        _initialKindEditorOpened ||
        widget.initialPlanId != null ||
        widget.sourceCalendarEventId != null ||
        state.isLoading ||
        state.loadError != null ||
        state.isBusy ||
        state.requiresExactRetry ||
        seriesState.requiresExactRetry ||
        widget.initialKind == DeadlinePlanKind.assignment &&
            (seriesState.isLoading ||
                seriesState.isBusy ||
                seriesState.requiresExactRetry)) {
      return;
    }
    _initialKindEditorOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.initialKind == DeadlinePlanKind.assignment) {
        _openAssignmentSeriesEditor();
      } else {
        _openEditor(
          presetKind: widget.initialKind,
          lockPresetKind: true,
        );
      }
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
      if (!mounted || _targetPlanId != planId) return;
      ref.read(deadlinePlanControllerProvider.notifier).includeReadPlan(plan);
      setState(() {
        _targetPlanLoading = false;
        _targetPlanResult = plan;
        _expandedPlanId = plan.id;
      });
    } catch (error) {
      if (!mounted || _targetPlanId != planId) return;
      setState(() {
        _targetPlanLoading = false;
        _targetPlanError = error;
      });
    }
  }

  void _retryTargetPlan() {
    final planId = _targetPlanId;
    if (planId == null || _targetPlanLoading) return;
    setState(() {
      _targetPlanRequested = true;
      _targetPlanError = null;
    });
    _loadTargetPlan(planId);
  }

  void _openHealthPlan(String planId) {
    final state = ref.read(deadlinePlanControllerProvider);
    final alreadyLoaded = state.plans.any((plan) => plan.id == planId) ||
        _targetPlanResult?.id == planId;
    setState(() {
      if (_targetPlanId != planId) {
        _targetPlanResult = null;
      }
      _targetPlanId = planId;
      _expandedPlanId = planId;
      _targetPlanRequested = true;
      _targetPlanError = null;
    });
    if (!alreadyLoaded) _loadTargetPlan(planId);
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
            'The imported event could not be loaded from your account. Its details were not taken from the link.',
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
              'The event was loaded from your saved calendar import. The link contains only its identity.',
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

  Future<void> _choosePreparationKind() async {
    final state = ref.read(deadlinePlanControllerProvider);
    if (state.isBusy ||
        state.requiresExactRetry ||
        ref.read(assignmentSeriesControllerProvider).requiresExactRetry ||
        _editorOpen ||
        _seriesEditorOpen) {
      return;
    }
    final kind = await showDialog<DeadlinePlanKind>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('preparation-kind-dialog'),
        scrollable: true,
        title: const Text('What are you preparing for?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('preparation-kind-exam'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(AppIcons.schoolOutlined),
              title: const Text('Exam'),
              subtitle: const Text('One preparation plan with one deadline.'),
              trailing: const Icon(AppIcons.arrowForward),
              onTap: () => Navigator.of(dialogContext).pop(
                DeadlinePlanKind.exam,
              ),
            ),
            ListTile(
              key: const ValueKey('preparation-kind-assignment'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(AppIcons.assignmentOutlined),
              title: const Text('Assignment'),
              subtitle: const Text(
                'A finite weekly series with a plan for every assignment.',
              ),
              trailing: const Icon(AppIcons.arrowForward),
              onTap: () => Navigator.of(dialogContext).pop(
                DeadlinePlanKind.assignment,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!mounted || kind == null) return;
    if (kind == DeadlinePlanKind.assignment) {
      await _openAssignmentSeriesEditor();
      return;
    }
    await _openEditor(presetKind: kind, lockPresetKind: true);
  }

  Future<void> _openEditor({
    DeadlinePlan? plan,
    DeadlinePlanProposalDraft? retainedDraft,
    DeadlineCalendarPrefill? sourcePrefill,
    DeadlinePlanKind? presetKind,
    bool lockPresetKind = false,
    bool forceManualSource = false,
    _DeadlineReplanContext replanContext = _DeadlineReplanContext.general,
  }) async {
    final state = ref.read(deadlinePlanControllerProvider);
    if (state.isBusy || state.requiresExactRetry ||
        ref.read(assignmentSeriesControllerProvider).requiresExactRetry ||
        _editorOpen) {
      return;
    }
    final profileDateSource = ref.read(profileLocalDateSourceProvider);
    final profileTimezone = profileDateSource.timezoneName;
    if (profileTimezone == null) {
      _showMessage(
        'Your current profile timezone is unavailable. Reload your account before editing preparation times.',
      );
      return;
    }
    _editorOpen = true;
    final sourcePlan = plan ?? _planById(state.plans, retainedDraft?.planId);
    final existing = sourcePlan?.displayedRevision;
    final healthSnapshot = ref.read(examPlanHealthProvider).valueOrNull;
    final savedExamHealth = sourcePlan?.pendingRevision == null &&
            sourcePlan?.kind == DeadlinePlanKind.exam
        ? _healthForPlan(healthSnapshot, sourcePlan!.id)
        : null;
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
    final profileToday = profileDateSource.dateAt(_pageNow);
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
          healthPlanId: sourcePlan?.isActive == true ? sourcePlan?.id : null,
          healthBaseRevision:
              sourcePlan?.isActive == true ? sourcePlan?.latestRevision : null,
          existing: existing,
          trackedFocusMinutes: sourcePlan?.progress.trackedFocusMinutes ?? 0,
          accountDailyPreparationBudgetKnown: preparationWorkload.hasValue,
          accountDailyPreparationBudgetMinutes:
              preparationWorkload.valueOrNull?.dailyPreparationBudgetMinutes,
          retainedDraft: retainedDraft,
          initialKind: sourcePlan?.kind ?? presetKind,
          lockKind: sourcePlan != null ||
              lockPresetKind && presetKind != null && loadedPrefill == null,
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
          profileTimezone: profileTimezone,
          savedExamHealth: savedExamHealth,
          onOpenPlanner: () => context.go(AppRoutes.planner),
          onPreviewHealth: (draft) =>
              ref.read(examPlanHealthRepositoryProvider).preview(draft),
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

  Future<void> _openAssignmentSeriesEditor({
    AssignmentSeries? series,
    AssignmentSeriesProposalDraft? retainedDraft,
  }) async {
    final seriesState = ref.read(assignmentSeriesControllerProvider);
    final planState = ref.read(deadlinePlanControllerProvider);
    if (seriesState.isBusy ||
        seriesState.requiresExactRetry ||
        planState.isBusy ||
        planState.requiresExactRetry ||
        _seriesEditorOpen) {
      return;
    }
    _seriesEditorOpen = true;
    final workload = ref.read(preparationWorkloadProvider);
    AssignmentSeriesProposalDraft? draft;
    try {
      draft = await showModalBottomSheet<AssignmentSeriesProposalDraft>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        useSafeArea: true,
        builder: (_) => _AssignmentSeriesEditorSheet(
          seriesId: series?.id ?? retainedDraft?.seriesId ?? newClientUuid(),
          baseRevision:
              series?.latestRevision ?? retainedDraft?.baseRevision ?? 0,
          existing: series?.displayedRevision,
          retainedDraft: retainedDraft,
          accountDailyPreparationBudgetKnown: workload.hasValue,
          accountDailyPreparationBudgetMinutes:
              workload.valueOrNull?.dailyPreparationBudgetMinutes,
          currentTime: widget.currentTime,
          onOpenPlanner: () => context.go(AppRoutes.planner),
        ),
      );
    } finally {
      _seriesEditorOpen = false;
    }
    if (!mounted || draft == null) return;
    setState(() {
      _retainedSeriesDraft = draft;
      _expandedSeriesId = series?.id ?? draft!.seriesId;
      _operationSeriesId = _expandedSeriesId;
    });
    final saved = await ref
        .read(assignmentSeriesControllerProvider.notifier)
        .propose(draft);
    if (!mounted) return;
    if (saved) {
      setState(() => _retainedSeriesDraft = null);
      await ref.read(deadlinePlanControllerProvider.notifier).load();
      ref.invalidate(preparationWorkloadProvider);
      if (mounted) {
        _showMessage(
          'Weekly assignment preview created. Review the series and confirm it once.',
        );
      }
    }
  }

  Future<void> _confirmAssignmentSeries(AssignmentSeries series) async {
    final revision = series.pendingRevision;
    if (revision == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Reserve this assignment series?'),
            content: Text(
              '${revision.remainingOccurrences} weekly assignments will each keep an independent preparation plan. '
              '${_duration(revision.plannedMinutes)} of preparation is staged across the series. '
              'This is one atomic confirmation: either every future occurrence is updated, or none is.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep as preview'),
              ),
              FilledButton(
                key: const ValueKey('assignment-series-confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Confirm whole series'),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !confirmed) return;
    setState(() {
      _expandedSeriesId = series.id;
      _operationSeriesId = series.id;
    });
    final saved = await ref
        .read(assignmentSeriesControllerProvider.notifier)
        .confirm(series);
    if (mounted && saved) {
      await ref.read(deadlinePlanControllerProvider.notifier).load();
      if (mounted) _showMessage('Whole assignment series reserved.');
    }
  }

  Future<void> _cancelAssignmentSeriesFuture(AssignmentSeries series) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Cancel future assignments?'),
            content: const Text(
              'All open future occurrences in this series will be cancelled together. Past and completed assignments keep their history.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep series'),
              ),
              FilledButton(
                key: const ValueKey('assignment-series-cancel-future-confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Cancel future assignments'),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !confirmed) return;
    setState(() {
      _expandedSeriesId = series.id;
      _operationSeriesId = series.id;
    });
    final saved = await ref
        .read(assignmentSeriesControllerProvider.notifier)
        .cancelFuture(series);
    if (mounted && saved) {
      await ref.read(deadlinePlanControllerProvider.notifier).load();
      if (mounted) {
        _showMessage('Future assignments cancelled; earlier history was kept.');
      }
    }
  }

  Future<void> _retryAssignmentSeries() async {
    final controller = ref.read(assignmentSeriesControllerProvider.notifier);
    final pending = ref.read(assignmentSeriesControllerProvider).pendingMutation;
    final saved = await controller.retryExact();
    if (!mounted || !saved) return;
    if (pending?.kind == AssignmentSeriesMutationKind.proposal &&
        _retainedSeriesDraft?.seriesId == pending?.seriesId) {
      setState(() => _retainedSeriesDraft = null);
    }
    await ref.read(deadlinePlanControllerProvider.notifier).load();
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
    final multiExam = ref.read(multiExamPlanControllerProvider);
    if (plan.kind == DeadlinePlanKind.exam &&
        (multiExam.metadataStatus != MultiExamPlanMetadataStatus.current ||
            multiExam.proposedChildLinks
                .containsKey('${plan.id}:${revision.revision}'))) {
      final link =
          multiExam.proposedChildLinks['${plan.id}:${revision.revision}'];
      if (link != null) {
        _openExamBalance(link.balanceId);
      } else {
        _showMessage(
          'Exam balance metadata is unavailable. Reload before confirming this Exam preview.',
        );
      }
      return;
    }
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

ExamPlanHealthItem? _healthForPlan(ExamPlanHealth? health, String planId) {
  if (health == null) return null;
  for (final exam in health.exams) {
    if (exam.planId == planId) return exam;
  }
  return null;
}
