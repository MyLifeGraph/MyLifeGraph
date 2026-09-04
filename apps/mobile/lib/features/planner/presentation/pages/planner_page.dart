import 'package:flutter/material.dart';

import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../composition/projection_refresh_providers.dart';
import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/time/profile_timezone.dart';
import '../../../../core/utils/local_date.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import 'package:my_life_graph/composition/deadline_plan_providers.dart';
import 'package:my_life_graph/composition/widgets/app_header_actions.dart';
import '../../application/planner_controller.dart';
import '../../domain/planner.dart';
import '../providers/planner_providers.dart';
import '../widgets/planner_dialogs.dart';
import '../widgets/planner_sections.dart';

class _RetainedTaskReplacementDraft {
  const _RetainedTaskReplacementDraft({
    required this.sourceTargetId,
    required this.draft,
  });

  final String sourceTargetId;
  final PlannerTaskDraft draft;
}

class _RetainedHabitReplacementDraft {
  const _RetainedHabitReplacementDraft({
    required this.sourceTargetId,
    required this.draft,
  });

  final String sourceTargetId;
  final PlannerHabitDraft draft;
}

enum _RetainedDraftOwner {
  newTask,
  taskTarget,
  newHabit,
  habitTarget,
  setupTarget,
}

class _ProposalAttemptBinding {
  const _ProposalAttemptBinding({
    required this.pending,
    required this.retainedOwner,
    this.retainedKey,
    this.sourceReplacementKey,
    this.taskDraft,
    this.habitDraft,
  });

  final PlannerPendingMutation pending;
  final _RetainedDraftOwner? retainedOwner;
  final String? retainedKey;
  final String? sourceReplacementKey;
  final PlannerTaskDraft? taskDraft;
  final PlannerHabitDraft? habitDraft;
}

class _ProposalPreviewBinding {
  const _ProposalPreviewBinding({
    required this.sourceReplacementKey,
    required this.setupTargetId,
    this.taskDraft,
    this.habitDraft,
  });

  final String? sourceReplacementKey;
  final String? setupTargetId;
  final PlannerTaskDraft? taskDraft;
  final PlannerHabitDraft? habitDraft;
}

class PlannerPage extends ConsumerStatefulWidget {
  const PlannerPage({super.key});

  @override
  ConsumerState<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends ConsumerState<PlannerPage> {
  PlannerTaskDraft? _retainedNewTaskDraft;
  final Map<String, PlannerTaskDraft> _retainedTaskDraftsByTarget = {};
  PlannerHabitDraft? _retainedNewHabitDraft;
  final Map<String, PlannerHabitDraft> _retainedHabitDraftsByTarget = {};
  final Map<String, PlannerHabitDraft> _retainedSetupHabitDrafts = {};
  final Map<String, _RetainedTaskReplacementDraft>
      _retainedTaskReplacementDrafts = {};
  final Map<String, _RetainedHabitReplacementDraft>
      _retainedHabitReplacementDrafts = {};
  final Map<String, _ProposalAttemptBinding> _proposalAttemptsByRequest = {};
  final Map<String, _ProposalPreviewBinding> _proposalBindingsByPreview = {};
  PlannerCommitmentDraft? _retainedCommitmentDraft;
  bool _continuedWithoutAvailability = false;

  @override
  Widget build(BuildContext context) {
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    if (!capabilities.canUseSyncedExecution) {
      return AppPage(
        title: 'Planner',
        subtitle: 'Turn explicit estimates into reviewable time blocks',
        backFallback: AppRoutes.dashboard,
        showBackForFallback: false,
        actions: const [AppHeaderActions()],
        children: const [
          PlannerLockedCard(),
        ],
      );
    }

    final state = ref.watch(plannerControllerProvider);
    final examWeekOutlook = ref.watch(examWeekOutlookProvider);
    final examPlanHealth = ref.watch(examPlanHealthProvider);
    final controller = ref.read(plannerControllerProvider.notifier);
    final overview = state.overview;
    final availabilityIncomplete =
        overview != null && _availabilityIsIncomplete(overview);
    final children = <Widget>[
      PlannerAddNewSection(
        busy: !state.canMutate,
        calendarPreference: overview?.preferences,
        availabilityIncomplete: availabilityIncomplete,
        onTask: _createTask,
        onHabit: _createHabit,
        onExam: () => _openPreparationCreation('exam'),
        onAssignment: () => _openPreparationCreation('assignment'),
        onCommitment: () => _createCommitment(overview),
        onReviewSetup: () => context.push('${AppRoutes.onboarding}?edit=1'),
        onCalendarPreference: overview == null
            ? null
            : (value) async {
                final saved = await controller.updateCalendarPreference(value);
                if (!mounted) return;
                if (saved) {
                  await _afterPlannerMutation();
                } else {
                  _showFailure();
                }
              },
      ),
    ];
    if (state.projectionStatus == PlannerProjectionStatus.staleAfterMutation) {
      children.add(
        AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                AppIcons.warningAmberOutlined,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Change saved. Planner could not reload.',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'The overview is out of date. Reload it before making another change.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: state.isBusy ? null : _discardPendingAndReload,
                      icon: const Icon(AppIcons.refresh),
                      label: const Text('Reload Planner'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final outlookValue = examWeekOutlook.valueOrNull;
    if (examWeekOutlook.isLoading ||
        examWeekOutlook.hasError ||
        (outlookValue != null && outlookValue.mode != 'inactive')) {
      children.add(
        PlannerExamWeekOutlookSection(
          value: examWeekOutlook,
          onRetry: () => ref.invalidate(examWeekOutlookProvider),
          onEveningCheckIn: () => context.push(AppRoutes.quickMoodCheckIn),
          onReviewPlan: (planId) => context.push(
            Uri(
              path: AppRoutes.preparationPlans,
              queryParameters: {'plan_id': planId},
            ).toString(),
          ),
          onReplan: (planId) => context.push(
            Uri(
              path: AppRoutes.plannerReplan,
              queryParameters: {'plan_id': planId},
            ).toString(),
          ),
          enabled: state.canMutate,
        ),
      );
    }

    if (state.requiresExactRetry || state.operationError != null) {
      children.add(
        PlannerMutationError(
          exactRetryRequired: state.requiresExactRetry,
          conflict: state.reloadSuggested,
          onRetryExact: state.requiresExactRetry
              ? () async {
                  final result = await controller.retryExact();
                  if (!mounted || result == null) return;
                  final pending = result.pending;
                  final retryingProposal =
                      pending.kind == PlannerPendingKind.proposal;
                  if (!result.succeeded) {
                    if (retryingProposal) {
                      _handleProposalExactRetryFailure(result);
                    }
                    return;
                  }
                  if (mounted) {
                    if (pending.kind == PlannerPendingKind.confirm &&
                        pending.planId != null &&
                        pending.expectedRevision != null) {
                      _completePreviewConfirmation(
                        planId: pending.planId!,
                        revision: pending.expectedRevision!,
                      );
                    }
                    final preview = ref.read(plannerControllerProvider).preview;
                    if (retryingProposal && preview != null) {
                      _bindProposalAttemptToPreview(
                        requestId: pending.requestId,
                        plan: preview,
                      );
                      final current = _freshPendingPlanAfterMutation(preview);
                      if (current != null) await _showPreview(current);
                    } else {
                      await _afterPlannerMutation();
                      if (_mutationProjectionIsCurrent()) {
                        _showMessage('Planner change confirmed.');
                      }
                    }
                  }
                }
              : null,
          onReload: _discardPendingAndReload,
        ),
      );
    }
    if (overview == null) {
      children.add(
        state.operation == PlannerOperation.loading
            ? const AppCard(
                child: Center(child: CircularProgressIndicator()),
              )
            : PlannerLoadError(onRetry: controller.load),
      );
      return AppPage(
        title: 'Planner',
        subtitle: 'Turn explicit estimates into reviewable time blocks',
        backFallback: AppRoutes.dashboard,
        showBackForFallback: false,
        actions: [
          AppHeaderActions(
            pageActions: [
              IconButton(
                tooltip: 'Reload Planner',
                onPressed:
                    state.isBusy ? null : () => _reloadPlannerFromHeader(state),
                icon: const Icon(AppIcons.refresh),
              ),
            ],
          ),
        ],
        children: children,
      );
    }

    children.add(
      PlannerNeedsAttentionSection(
        items: overview.needsAttention,
        examPlanHealth: examPlanHealth,
        onOpen: (item) => _openAttention(item, overview),
        onOpenExamHealth: (planId) => context.push(
          '${AppRoutes.preparationPlans}?plan_id=$planId',
        ),
        onRetryExamHealth: () => ref.invalidate(examPlanHealthProvider),
        enabled: state.canMutate,
      ),
    );
    children.add(
      PlannerSevenDaySection(
        days: overview.days,
        timezone: overview.timezone,
        onItemTap: (item) => _openDayItem(item, overview),
        enabled: state.canMutate,
      ),
    );
    children.add(
      PlannerPreparationSection(
        plans: overview.ongoingPreparation,
        timezone: overview.timezone,
        onOpen: (plan) => context.push(
          '${AppRoutes.preparationPlans}?plan_id=${plan.planId}',
        ),
        enabled: state.canMutate,
      ),
    );
    final pendingPlans = overview.actionPlans
        .where((plan) => plan.pendingRevision != null)
        .toList(growable: false);
    if (pendingPlans.isNotEmpty) {
      children.add(
        PlannerPendingPreviewsSection(
          plans: pendingPlans,
          onOpen: _showPreview,
          enabled: state.canMutate,
        ),
      );
    }
    children.add(
      PlannerHabitsSection(
        items: overview.habits,
        onOpen: (item) => _openHabit(item, overview),
        enabled: state.canMutate,
      ),
    );
    children.add(
      PlannerUnscheduledTasksSection(
        items: overview.unscheduledTasks,
        onOpen: (item) => _openUnscheduledTask(item, overview),
        enabled: state.canMutate,
      ),
    );
    children.add(PlannerHistorySection(items: overview.history));
    return AppPage(
      title: 'Planner',
      subtitle: 'Preview first. Times are reserved only after confirmation.',
      backFallback: AppRoutes.dashboard,
      showBackForFallback: false,
      actions: [
        AppHeaderActions(
          pageActions: [
            IconButton(
              tooltip: 'Reload Planner',
              onPressed:
                  state.isBusy ? null : () => _reloadPlannerFromHeader(state),
              icon: const Icon(AppIcons.refresh),
            ),
          ],
        ),
      ],
      children: children,
    );
  }

  Future<void> _reloadPlannerFromHeader(PlannerState state) async {
    ref.invalidate(examWeekOutlookProvider);
    ref.invalidate(examPlanHealthProvider);
    final controller = ref.read(plannerControllerProvider.notifier);
    if (state.reloadSuggested ||
        state.requiresExactRetry ||
        state.operationError != null ||
        state.projectionStatus != PlannerProjectionStatus.current) {
      await _discardPendingAndReload();
      return;
    }
    await controller.load();
  }

  Future<void> _discardPendingAndReload() async {
    final controller = ref.read(plannerControllerProvider.notifier);
    final pending = ref.read(plannerControllerProvider).pendingMutation;
    final attempt = pending?.kind == PlannerPendingKind.proposal
        ? _proposalAttemptsByRequest[pending!.requestId]
        : null;
    final reloaded = await controller.reloadBeforeDiscardingPending();
    if (!mounted || !reloaded) return;
    if (attempt != null) {
      final matching = _matchingPendingPlanAfterReload(
        attempt,
        ref.read(plannerControllerProvider).overview,
      );
      if (matching != null) {
        _bindProposalAttemptToPreview(
          requestId: attempt.pending.requestId,
          plan: matching,
        );
      } else {
        _proposalAttemptsByRequest.remove(attempt.pending.requestId);
      }
    }
    controller.clearPendingFailureAfterSuccessfulReload();
  }

  Future<void> _createTask({PlannerTaskDraft? initial}) async {
    if (!ref.read(plannerControllerProvider).canMutate) return;
    final retained = initial?.targetId == null
        ? _retainedNewTaskDraft
        : _currentTaskDraftFor(initial!);
    final draft = await showDialog<PlannerTaskDraft>(
      context: context,
      builder: (_) => PlannerTaskDialog(
        initial: retained ?? initial,
        timezone: ref.read(plannerControllerProvider).overview!.timezone,
      ),
    );
    if (!mounted || draft == null) return;
    _retainTaskDraft(draft);
    if (_taskUsesAutomaticPlanning(draft) &&
        !await _confirmAvailabilityForAutomaticPlanning()) {
      return;
    }
    final plan = await _submitTaskProposal(
      draft,
      retainedOwner: draft.targetId == null
          ? _RetainedDraftOwner.newTask
          : _RetainedDraftOwner.taskTarget,
      retainedKey: draft.targetId,
    );
    if (!mounted || plan == null) {
      if (mounted) _showFailure();
      return;
    }
    final current = _freshPendingPlanAfterMutation(plan);
    if (current != null) await _showPreview(current);
  }

  Future<void> _createHabit({
    PlannerHabitDraft? initial,
    bool definitionReadOnly = false,
  }) async {
    if (!ref.read(plannerControllerProvider).canMutate) return;
    final retained = initial?.targetId == null
        ? _retainedNewHabitDraft
        : _currentHabitDraftFor(initial!);
    final dialogInitial = definitionReadOnly
        ? _retainedSetupHabitInitial(initial)
        : retained ?? initial;
    final draft = await showDialog<PlannerHabitDraft>(
      context: context,
      builder: (_) => PlannerHabitDialog(
        initial: dialogInitial,
        definitionReadOnly: definitionReadOnly,
      ),
    );
    if (!mounted || draft == null) return;
    final setupTargetId = definitionReadOnly ? draft.targetId : null;
    if (setupTargetId != null) {
      _retainedSetupHabitDrafts[setupTargetId] = draft;
    } else if (!definitionReadOnly) {
      _retainHabitDraft(draft);
    }
    if (!await _confirmAvailabilityForAutomaticPlanning()) return;
    final plan = await _submitHabitProposal(
      draft,
      retainedOwner: definitionReadOnly
          ? _RetainedDraftOwner.setupTarget
          : draft.targetId == null
              ? _RetainedDraftOwner.newHabit
              : _RetainedDraftOwner.habitTarget,
      retainedKey: draft.targetId,
    );
    if (!mounted || plan == null) {
      if (mounted) _showFailure();
      return;
    }
    final current = _freshPendingPlanAfterMutation(plan);
    if (current != null) await _showPreview(current);
  }

  PlannerHabitDraft? _retainedSetupHabitInitial(PlannerHabitDraft? initial) {
    final targetId = initial?.targetId;
    if (initial == null || targetId == null) return initial;
    final retained = _retainedSetupHabitDrafts[targetId];
    if (retained == null) return initial;
    // Setup remains authoritative for the immutable definition and revision.
    // Only the target-bound duration draft survives a Back or failed proposal.
    return PlannerHabitDraft(
      title: initial.title,
      description: initial.description,
      cadenceKind: initial.cadenceKind,
      scheduledWeekdays: initial.scheduledWeekdays,
      weeklyTarget: initial.weeklyTarget,
      durationMinutes: retained.durationMinutes,
      targetId: initial.targetId,
      expectedUpdatedAt: initial.expectedUpdatedAt,
    );
  }

  PlannerTaskDraft? _currentTaskDraftFor(PlannerTaskDraft current) {
    final targetId = current.targetId;
    if (targetId == null) return _retainedNewTaskDraft;
    final retained = _retainedTaskDraftsByTarget[targetId];
    if (retained == null) return null;
    if (!_sameVersion(retained.expectedUpdatedAt, current.expectedUpdatedAt)) {
      _retainedTaskDraftsByTarget.remove(targetId);
      return null;
    }
    return retained;
  }

  PlannerHabitDraft? _currentHabitDraftFor(PlannerHabitDraft current) {
    final targetId = current.targetId;
    if (targetId == null) return _retainedNewHabitDraft;
    final retained = _retainedHabitDraftsByTarget[targetId];
    if (retained == null) return null;
    if (!_sameVersion(retained.expectedUpdatedAt, current.expectedUpdatedAt)) {
      _retainedHabitDraftsByTarget.remove(targetId);
      return null;
    }
    return retained;
  }

  void _retainTaskDraft(PlannerTaskDraft draft) {
    final targetId = draft.targetId;
    if (targetId == null) {
      _retainedNewTaskDraft = draft;
    } else {
      _retainedTaskDraftsByTarget[targetId] = draft;
    }
  }

  void _retainHabitDraft(PlannerHabitDraft draft) {
    final targetId = draft.targetId;
    if (targetId == null) {
      _retainedNewHabitDraft = draft;
    } else {
      _retainedHabitDraftsByTarget[targetId] = draft;
    }
  }

  String _previewDraftKey(PlannerActionPlan plan) {
    final revision = plan.pendingRevision?.revision;
    if (revision == null) {
      throw StateError('A retained Planner draft requires a pending revision.');
    }
    return '${plan.id}:$revision';
  }

  Future<PlannerActionPlan?> _submitTaskProposal(
    PlannerTaskDraft draft, {
    required _RetainedDraftOwner? retainedOwner,
    String? retainedKey,
    String? sourceReplacementKey,
  }) async {
    final controller = ref.read(plannerControllerProvider.notifier);
    final pending = controller.prepareTaskProposal(draft);
    if (pending == null) return null;
    _proposalAttemptsByRequest[pending.requestId] = _ProposalAttemptBinding(
      pending: pending,
      retainedOwner: retainedOwner,
      retainedKey: retainedKey,
      sourceReplacementKey: sourceReplacementKey,
      taskDraft: draft,
    );
    final plan = await controller.submitProposal(pending);
    if (!mounted) return plan;
    if (plan != null) {
      _bindProposalAttemptToPreview(requestId: pending.requestId, plan: plan);
    } else if (ref.read(plannerControllerProvider).pendingMutation?.requestId !=
        pending.requestId) {
      _proposalAttemptsByRequest.remove(pending.requestId);
    }
    return plan;
  }

  Future<PlannerActionPlan?> _submitHabitProposal(
    PlannerHabitDraft draft, {
    required _RetainedDraftOwner? retainedOwner,
    String? retainedKey,
    String? sourceReplacementKey,
  }) async {
    final controller = ref.read(plannerControllerProvider.notifier);
    final pending = controller.prepareHabitProposal(draft);
    if (pending == null) return null;
    _proposalAttemptsByRequest[pending.requestId] = _ProposalAttemptBinding(
      pending: pending,
      retainedOwner: retainedOwner,
      retainedKey: retainedKey,
      sourceReplacementKey: sourceReplacementKey,
      habitDraft: draft,
    );
    final plan = await controller.submitProposal(pending);
    if (!mounted) return plan;
    if (plan != null) {
      _bindProposalAttemptToPreview(requestId: pending.requestId, plan: plan);
    } else if (ref.read(plannerControllerProvider).pendingMutation?.requestId !=
        pending.requestId) {
      _proposalAttemptsByRequest.remove(pending.requestId);
    }
    return plan;
  }

  bool _bindProposalAttemptToPreview({
    required String requestId,
    required PlannerActionPlan plan,
  }) {
    final attempt = _proposalAttemptsByRequest[requestId];
    if (attempt == null || !_proposalAttemptMatchesPlan(attempt, plan)) {
      return false;
    }
    final setupTargetId =
        attempt.retainedOwner == _RetainedDraftOwner.setupTarget
            ? attempt.retainedKey
            : null;
    _proposalBindingsByPreview[_previewDraftKey(plan)] =
        _ProposalPreviewBinding(
      sourceReplacementKey: attempt.sourceReplacementKey,
      setupTargetId: setupTargetId,
      taskDraft: attempt.taskDraft,
      habitDraft: attempt.habitDraft,
    );
    _clearProposalAttemptRetention(attempt);
    _proposalAttemptsByRequest.remove(requestId);
    return true;
  }

  void _clearProposalAttemptRetention(_ProposalAttemptBinding attempt) {
    switch (attempt.retainedOwner) {
      case _RetainedDraftOwner.newTask:
        if (identical(_retainedNewTaskDraft, attempt.taskDraft)) {
          _retainedNewTaskDraft = null;
        }
        break;
      case _RetainedDraftOwner.taskTarget:
        final key = attempt.retainedKey;
        if (key != null &&
            identical(_retainedTaskDraftsByTarget[key], attempt.taskDraft)) {
          _retainedTaskDraftsByTarget.remove(key);
        }
        break;
      case _RetainedDraftOwner.newHabit:
        if (identical(_retainedNewHabitDraft, attempt.habitDraft)) {
          _retainedNewHabitDraft = null;
        }
        break;
      case _RetainedDraftOwner.habitTarget:
        final key = attempt.retainedKey;
        if (key != null &&
            identical(_retainedHabitDraftsByTarget[key], attempt.habitDraft)) {
          _retainedHabitDraftsByTarget.remove(key);
        }
        break;
      case _RetainedDraftOwner.setupTarget:
      case null:
        break;
    }
    final sourceKey = attempt.sourceReplacementKey;
    if (sourceKey == null) return;
    final taskReplacement = _retainedTaskReplacementDrafts[sourceKey];
    if (identical(taskReplacement?.draft, attempt.taskDraft)) {
      _retainedTaskReplacementDrafts.remove(sourceKey);
    }
    final habitReplacement = _retainedHabitReplacementDrafts[sourceKey];
    if (identical(habitReplacement?.draft, attempt.habitDraft)) {
      _retainedHabitReplacementDrafts.remove(sourceKey);
    }
  }

  void _handleProposalExactRetryFailure(PlannerExactRetryResult result) {
    if (result.disposition == PlannerExactRetryDisposition.ambiguous) return;
    final attempt = _proposalAttemptsByRequest.remove(
      result.pending.requestId,
    );
    if (attempt == null ||
        result.disposition != PlannerExactRetryDisposition.conflict) {
      return;
    }
    final sourceKey = attempt.sourceReplacementKey;
    if (sourceKey == null) return;
    final taskReplacement = _retainedTaskReplacementDrafts[sourceKey];
    if (identical(taskReplacement?.draft, attempt.taskDraft)) {
      _retainedTaskReplacementDrafts.remove(sourceKey);
    }
    final habitReplacement = _retainedHabitReplacementDrafts[sourceKey];
    if (identical(habitReplacement?.draft, attempt.habitDraft)) {
      _retainedHabitReplacementDrafts.remove(sourceKey);
    }
  }

  PlannerActionPlan? _matchingPendingPlanAfterReload(
    _ProposalAttemptBinding attempt,
    PlannerOverview? overview,
  ) {
    if (overview == null) return null;
    final matches = overview.actionPlans
        .where((plan) => _proposalAttemptMatchesPlan(attempt, plan))
        .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }

  bool _proposalAttemptMatchesPlan(
    _ProposalAttemptBinding attempt,
    PlannerActionPlan plan,
  ) {
    final body = attempt.pending.body;
    final planId = body?['plan_id'];
    final baseRevision = body?['base_revision'];
    final requestId = body?['request_id'];
    final target = body?['target'];
    if (planId is! String ||
        baseRevision is! int ||
        requestId != attempt.pending.requestId ||
        target is! Map ||
        target['kind'] is! String ||
        target['target_id'] is! String ||
        target['operation'] is! String) {
      return false;
    }
    final revision = plan.pendingRevision;
    final expectedRevision = baseRevision + 1;
    if (plan.id != planId ||
        plan.targetKind != target['kind'] ||
        plan.targetId != target['target_id'] ||
        plan.latestRevision != expectedRevision ||
        revision?.revision != expectedRevision ||
        revision?.targetOperation != target['operation']) {
      return false;
    }
    final taskDraft = attempt.taskDraft;
    if (taskDraft != null) {
      return _taskDraftMatchesProposalBody(taskDraft, body!) &&
          _sameTaskDraft(taskDraft, revision?.targetTaskDraft);
    }
    final habitDraft = attempt.habitDraft;
    return habitDraft != null &&
        _habitDraftMatchesProposalBody(habitDraft, body!) &&
        _sameHabitDraft(habitDraft, revision?.targetHabitDraft);
  }

  bool _taskDraftMatchesProposalBody(
    PlannerTaskDraft draft,
    Map<String, dynamic> body,
  ) {
    final requestId = body['request_id'];
    final planId = body['plan_id'];
    final baseRevision = body['base_revision'];
    final planningStartOn = body['planning_start_on'];
    final target = body['target'];
    if (requestId is! String ||
        planId is! String ||
        baseRevision is! int ||
        planningStartOn is! String ||
        target is! Map ||
        target['target_id'] is! String) {
      return false;
    }
    return _deepJsonEquals(
      draft.proposalJson(
        requestId: requestId,
        planId: planId,
        newTargetId: target['target_id'] as String,
        baseRevision: baseRevision,
        planningStartOn: planningStartOn,
      ),
      body,
    );
  }

  bool _habitDraftMatchesProposalBody(
    PlannerHabitDraft draft,
    Map<String, dynamic> body,
  ) {
    final requestId = body['request_id'];
    final planId = body['plan_id'];
    final baseRevision = body['base_revision'];
    final planningStartOn = body['planning_start_on'];
    final target = body['target'];
    if (requestId is! String ||
        planId is! String ||
        baseRevision is! int ||
        planningStartOn is! String ||
        target is! Map ||
        target['target_id'] is! String) {
      return false;
    }
    return _deepJsonEquals(
      draft.proposalJson(
        requestId: requestId,
        planId: planId,
        newTargetId: target['target_id'] as String,
        baseRevision: baseRevision,
        planningStartOn: planningStartOn,
      ),
      body,
    );
  }

  PlannerActionPlan? _freshPendingPlanAfterMutation(PlannerActionPlan plan) {
    final state = ref.read(plannerControllerProvider);
    final revision = plan.pendingRevision?.revision;
    if (revision == null ||
        state.projectionStatus != PlannerProjectionStatus.current ||
        state.mutationOutcome?.projectionCurrent != true) {
      return null;
    }
    final current = state.overview?.actionPlans
        .where(
          (candidate) =>
              candidate.id == plan.id &&
              candidate.pendingRevision?.revision == revision,
        )
        .firstOrNull;
    if (current == null) {
      ref
          .read(plannerControllerProvider.notifier)
          .requireFreshProjectionAfterCommittedMutation();
    }
    return current;
  }

  bool _mutationProjectionIsCurrent() {
    final state = ref.read(plannerControllerProvider);
    return state.projectionStatus == PlannerProjectionStatus.current &&
        state.mutationOutcome?.projectionCurrent == true;
  }

  Future<void> _openPreparationCreation(String kind) async {
    if (!ref.read(plannerControllerProvider).canMutate) return;
    if (!await _confirmAvailabilityForAutomaticPlanning() || !mounted) return;
    context.push('${AppRoutes.preparationPlans}?kind=$kind');
  }

  Future<bool> _confirmAvailabilityForAutomaticPlanning() async {
    final overview = ref.read(plannerControllerProvider).overview;
    if (overview == null ||
        !_availabilityIsIncomplete(overview) ||
        _continuedWithoutAvailability) {
      return true;
    }
    final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            key: const ValueKey('planner-availability-review-dialog'),
            title: const Text('Review your availability'),
            content: const Text(
              'No current weekly schedule, future fixed commitment, or consented calendar busy time is available. A preview may overlap classes or work. Add your schedule first, or continue if these times are genuinely free.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Back'),
              ),
              FilledButton(
                key: const ValueKey('planner-continue-without-availability'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue anyway'),
              ),
            ],
          ),
        ) ??
        false;
    if (accepted && mounted) {
      setState(() => _continuedWithoutAvailability = true);
    }
    return accepted;
  }

  Future<bool> _showPreview(
    PlannerActionPlan plan, {
    bool checkReplacement = true,
  }) async {
    if (!ref.read(plannerControllerProvider).canMutate) return false;
    final overview = ref.read(plannerControllerProvider).overview;
    if (checkReplacement &&
        overview != null &&
        _pendingPreviewNeedsReplacement(plan, overview)) {
      return _replacePendingPreview(plan, overview);
    }
    final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => PlannerPlanPreviewDialog(plan: plan),
        ) ??
        false;
    if (!mounted) return false;
    if (!accepted) {
      ref.read(plannerControllerProvider.notifier).clearPreview();
      return false;
    }
    final saved =
        await ref.read(plannerControllerProvider.notifier).confirm(plan);
    if (mounted) {
      if (saved) {
        _completePreviewConfirmation(
          planId: plan.id,
          revision: plan.pendingRevision!.revision,
        );
        await _afterPlannerMutation();
        if (!mounted) return saved;
        if (_mutationProjectionIsCurrent()) {
          _showMessage(
            plan.pendingRevision?.plannedMinutes == 0
                ? 'Saved under Unscheduled.'
                : 'Plan confirmed. Times are now reserved.',
          );
        }
      } else {
        _showFailure();
      }
    }
    return saved && _mutationProjectionIsCurrent();
  }

  bool _pendingPreviewNeedsReplacement(
    PlannerActionPlan plan,
    PlannerOverview overview,
  ) {
    final revision = plan.pendingRevision?.revision;
    if (revision == null) return false;
    final exactReadTimeItems = {
      '${plan.id}:calendar-stale:$revision': 'stale_preview',
      '${plan.id}:target-stale:$revision': 'stale_preview',
      '${plan.id}:study-stale:$revision': 'stale_preview',
      '${plan.id}:timezone-stale:$revision': 'stale_preview',
    };
    return overview.needsAttention.any(
      (item) =>
          item.planId == plan.id && exactReadTimeItems[item.id] == item.kind,
    );
  }

  Future<bool> _replacePendingPreview(
    PlannerActionPlan stalePlan,
    PlannerOverview overview,
  ) async {
    final pending = stalePlan.pendingRevision;
    if (pending == null) return false;
    final isCreate = pending.targetOperation == 'create';
    final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Create a new preview?'),
            content: Text(
              isCreate
                  ? 'This preview is stale and no saved Task or Habit exists yet. Review its details as a deliberate new item before creating another preview. The old preview will not be confirmed or cancelled.'
                  : 'This preview no longer matches the saved Task or Habit. Review the latest saved details before creating a replacement. The old preview will not be confirmed or cancelled.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep old preview'),
              ),
              FilledButton(
                key: const ValueKey('planner-replace-preview'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Create new preview'),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !replace) return false;

    PlannerActionPlan? replacement;
    if (stalePlan.targetKind == 'task') {
      final savedTask = overview.taskTargets
          .where((value) => value.id == stalePlan.targetId)
          .firstOrNull;
      final current = isCreate
          ? _localTaskDraft(pending.targetTaskDraft)
          : savedTask == null
              ? null
              : _taskDraftFromSummary(savedTask);
      if (current == null) {
        _showMessage(
          'Current Task details are unavailable. Reload Planner before creating a new preview.',
        );
        return false;
      }
      final initial = _retainedTaskReplacementInitial(
        stalePlan: stalePlan,
        current: current,
      );
      final draft = await showDialog<PlannerTaskDraft>(
        context: context,
        builder: (_) => PlannerTaskDialog(
          initial: initial,
          timezone: overview.timezone,
        ),
      );
      if (!mounted || draft == null) return false;
      _retainedTaskReplacementDrafts[_previewDraftKey(stalePlan)] =
          _RetainedTaskReplacementDraft(
        sourceTargetId: stalePlan.targetId,
        draft: draft,
      );
      if (_taskUsesAutomaticPlanning(draft) &&
          !await _confirmAvailabilityForAutomaticPlanning()) {
        return false;
      }
      final sourceKey = _previewDraftKey(stalePlan);
      replacement = await _submitTaskProposal(
        draft,
        retainedOwner: null,
        sourceReplacementKey: sourceKey,
      );
      if (replacement == null &&
          ref.read(plannerControllerProvider).reloadSuggested) {
        _retainedTaskReplacementDrafts.remove(sourceKey);
      }
    } else {
      final item = isCreate
          ? null
          : overview.habits
              .where((value) => value.id == stalePlan.targetId)
              .firstOrNull;
      final current = isCreate
          ? pending.targetHabitDraft
          : item == null
              ? null
              : _habitDraftFromSummary(item);
      if (current == null) {
        _showMessage(
          'Current Habit details are unavailable. Reload Planner before creating a new preview.',
        );
        return false;
      }
      final definitionReadOnly = item?.ownership == 'setup';
      final baseInitial = definitionReadOnly
          ? _setupReplacementInitial(
              current: current,
              pending: pending.targetHabitDraft,
            )
          : current;
      final initial = _retainedHabitReplacementInitial(
        stalePlan: stalePlan,
        current: baseInitial,
        definitionReadOnly: definitionReadOnly,
      );
      final draft = await showDialog<PlannerHabitDraft>(
        context: context,
        builder: (_) => PlannerHabitDialog(
          initial: initial,
          definitionReadOnly: definitionReadOnly,
        ),
      );
      if (!mounted || draft == null) return false;
      _retainedHabitReplacementDrafts[_previewDraftKey(stalePlan)] =
          _RetainedHabitReplacementDraft(
        sourceTargetId: stalePlan.targetId,
        draft: draft,
      );
      if (!await _confirmAvailabilityForAutomaticPlanning()) return false;
      final sourceKey = _previewDraftKey(stalePlan);
      replacement = await _submitHabitProposal(
        draft,
        retainedOwner:
            definitionReadOnly ? _RetainedDraftOwner.setupTarget : null,
        retainedKey: definitionReadOnly ? draft.targetId : null,
        sourceReplacementKey: sourceKey,
      );
      if (replacement == null &&
          ref.read(plannerControllerProvider).reloadSuggested) {
        _retainedHabitReplacementDrafts.remove(sourceKey);
      }
    }
    if (!mounted || replacement == null) {
      if (mounted) _showFailure();
      return false;
    }
    final current = _freshPendingPlanAfterMutation(replacement);
    if (current == null) return false;
    return _showPreview(current, checkReplacement: false);
  }

  PlannerTaskDraft _retainedTaskReplacementInitial({
    required PlannerActionPlan stalePlan,
    required PlannerTaskDraft current,
  }) {
    final key = _previewDraftKey(stalePlan);
    final retained = _retainedTaskReplacementDrafts[key];
    if (retained == null) return current;
    final isCreate = stalePlan.pendingRevision?.targetOperation == 'create';
    final valid = retained.sourceTargetId == stalePlan.targetId &&
        (isCreate
            ? retained.draft.targetId == null &&
                retained.draft.expectedUpdatedAt == null
            : retained.draft.targetId == current.targetId &&
                _sameVersion(
                  retained.draft.expectedUpdatedAt,
                  current.expectedUpdatedAt,
                ));
    if (!valid) {
      _retainedTaskReplacementDrafts.remove(key);
      return current;
    }
    return retained.draft;
  }

  PlannerHabitDraft _retainedHabitReplacementInitial({
    required PlannerActionPlan stalePlan,
    required PlannerHabitDraft current,
    required bool definitionReadOnly,
  }) {
    final key = _previewDraftKey(stalePlan);
    final retained = _retainedHabitReplacementDrafts[key];
    if (retained == null) return current;
    final isCreate = stalePlan.pendingRevision?.targetOperation == 'create';
    final valid = retained.sourceTargetId == stalePlan.targetId &&
        (isCreate
            ? retained.draft.targetId == null &&
                retained.draft.expectedUpdatedAt == null
            : retained.draft.targetId == current.targetId &&
                _sameVersion(
                  retained.draft.expectedUpdatedAt,
                  current.expectedUpdatedAt,
                ));
    if (!valid) {
      _retainedHabitReplacementDrafts.remove(key);
      return current;
    }
    if (!definitionReadOnly) return retained.draft;
    return PlannerHabitDraft(
      title: current.title,
      description: current.description,
      cadenceKind: current.cadenceKind,
      scheduledWeekdays: current.scheduledWeekdays,
      weeklyTarget: current.weeklyTarget,
      durationMinutes: retained.draft.durationMinutes,
      targetId: current.targetId,
      expectedUpdatedAt: current.expectedUpdatedAt,
    );
  }

  PlannerHabitDraft _setupReplacementInitial({
    required PlannerHabitDraft current,
    required PlannerHabitDraft? pending,
  }) {
    final targetId = current.targetId;
    final retained = targetId == null
        ? null
        : _retainedSetupHabitDrafts[targetId] ??
            (pending?.targetId == targetId ? pending : null);
    if (retained == null) return current;
    return PlannerHabitDraft(
      title: current.title,
      description: current.description,
      cadenceKind: current.cadenceKind,
      scheduledWeekdays: current.scheduledWeekdays,
      weeklyTarget: current.weeklyTarget,
      durationMinutes: retained.durationMinutes,
      targetId: current.targetId,
      expectedUpdatedAt: current.expectedUpdatedAt,
    );
  }

  PlannerTaskDraft _taskDraftFromSummary(PlannerTaskSummary item) =>
      PlannerTaskDraft(
        title: item.title,
        description: item.description,
        priority: item.priority,
        estimatedMinutes: item.estimatedMinutes,
        deadlineAt: item.deadlineAt,
        preferredSessionMinutes: item.preferredSessionMinutes,
        useStudyRhythm: item.useStudyRhythm,
        targetId: item.id,
        expectedUpdatedAt: item.expectedUpdatedAt,
      );

  PlannerTaskDraft? _localTaskDraft(PlannerTaskDraft? item) => item == null
      ? null
      : PlannerTaskDraft(
          title: item.title,
          description: item.description,
          priority: item.priority,
          estimatedMinutes: item.estimatedMinutes,
          deadlineAt: item.deadlineAt,
          preferredSessionMinutes: item.preferredSessionMinutes,
          useStudyRhythm: item.useStudyRhythm,
          targetId: item.targetId,
          expectedUpdatedAt: item.expectedUpdatedAt,
        );

  PlannerHabitDraft _habitDraftFromSummary(PlannerHabitSummary item) =>
      PlannerHabitDraft(
        title: item.title,
        description: item.description,
        cadenceKind: item.cadenceKind,
        scheduledWeekdays: item.scheduledWeekdays,
        weeklyTarget: item.weeklyTarget,
        durationMinutes: item.durationMinutes,
        targetId: item.id,
        expectedUpdatedAt: item.expectedUpdatedAt,
      );

  void _completePreviewConfirmation({
    required String planId,
    required int revision,
  }) {
    final key = '$planId:$revision';
    final binding = _proposalBindingsByPreview.remove(key);
    final sourceKey = binding?.sourceReplacementKey;
    if (sourceKey != null) {
      final taskReplacement = _retainedTaskReplacementDrafts[sourceKey];
      if (identical(taskReplacement?.draft, binding?.taskDraft)) {
        _retainedTaskReplacementDrafts.remove(sourceKey);
      }
      final habitReplacement = _retainedHabitReplacementDrafts[sourceKey];
      if (identical(habitReplacement?.draft, binding?.habitDraft)) {
        _retainedHabitReplacementDrafts.remove(sourceKey);
      }
    }
    final unsentHabitReplacement = _retainedHabitReplacementDrafts.remove(key);
    _retainedTaskReplacementDrafts.remove(key);
    final setupTargetId = binding?.setupTargetId;
    if (setupTargetId != null) {
      _retainedSetupHabitDrafts.remove(setupTargetId);
    }
    final unsentSetupTargetId = unsentHabitReplacement?.sourceTargetId;
    if (unsentSetupTargetId != null &&
        _retainedSetupHabitDrafts.containsKey(unsentSetupTargetId)) {
      _retainedSetupHabitDrafts.remove(unsentSetupTargetId);
    }
  }

  Future<void> _createCommitment(PlannerOverview? overview) async {
    if (overview == null || !ref.read(plannerControllerProvider).canMutate) {
      return;
    }
    final draft = await showDialog<PlannerCommitmentDraft>(
      context: context,
      builder: (_) => PlannerCommitmentDialog(
        initial: _retainedCommitmentDraft,
        timezone: overview.timezone,
      ),
    );
    if (!mounted || draft == null) return;
    _retainedCommitmentDraft = draft;
    final conflicts = _overlappingTitles(draft, overview);
    final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Save fixed commitment?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This time is authoritative. Existing plans will never move automatically.',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (conflicts.isEmpty)
                    const Text('No visible confirmed plan overlaps this time.')
                  else ...[
                    const Text('Visible plans that need attention:'),
                    const SizedBox(height: AppSpacing.xs),
                    for (final title in conflicts) Text('• $title'),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Back'),
              ),
              FilledButton(
                key: const ValueKey('planner-confirm-commitment'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save commitment'),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !accepted) return;
    final saved = await ref
        .read(plannerControllerProvider.notifier)
        .createCommitment(draft);
    if (mounted) {
      if (saved) {
        await _afterPlannerMutation();
        if (!mounted) return;
        _retainedCommitmentDraft = null;
        if (_mutationProjectionIsCurrent()) {
          _showMessage('Fixed commitment saved.');
        }
      } else {
        _showFailure();
      }
    }
  }

  Future<void> _openDayItem(
    PlannerDayItem item,
    PlannerOverview overview,
  ) async {
    if (!ref.read(plannerControllerProvider).canMutate) return;
    if (item.kind == 'preparation') {
      context.push('${AppRoutes.preparationPlans}?plan_id=${item.sourceId}');
      return;
    }
    if (item.kind == 'habit_slot') {
      await _openActionReservation(item, overview);
      return;
    }
    if (item.kind == 'task_block') {
      await _openActionReservation(item, overview);
      return;
    }
    if (item.kind != 'manual_commitment') return;
    final commitment = overview.commitments
        .where((value) => value.id == item.sourceId)
        .firstOrNull;
    if (commitment == null || commitment.status != 'active') return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                commitment.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Archiving frees this busy time. Released action slots are not restored automatically.',
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.pop(context, 'edit'),
                icon: const Icon(AppIcons.editOutlined),
                label: const Text('Edit commitment'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'archive'),
                icon: const Icon(AppIcons.archiveOutlined),
                label: const Text('Archive commitment'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      await _editCommitment(commitment);
      return;
    }
    final saved = await ref
        .read(plannerControllerProvider.notifier)
        .archiveCommitment(commitment);
    if (mounted) {
      if (saved) {
        await _afterPlannerMutation();
        if (!mounted) return;
      }
      if (!saved || _mutationProjectionIsCurrent()) {
        _showMessage(
          saved ? 'Commitment archived.' : 'Could not archive commitment.',
        );
      }
    }
  }

  Future<void> _openAttention(
    PlannerAttention item,
    PlannerOverview overview,
  ) async {
    if (!ref.read(plannerControllerProvider).canMutate) return;
    if (item.target == 'study_setup') {
      context.push('${AppRoutes.onboarding}?edit=1&section=study');
      return;
    }
    final plan = overview.actionPlans
        .where((value) => value.id == item.planId)
        .firstOrNull;
    if (plan?.pendingRevision != null) {
      await _showPreview(plan!);
    } else if (plan?.activeRevision != null) {
      await _openActionPlan(plan!);
    } else {
      final preparation = overview.ongoingPreparation
          .where((value) => value.planId == item.planId)
          .firstOrNull;
      if (preparation != null && mounted) {
        context.push(
          '${AppRoutes.preparationPlans}?plan_id=${preparation.planId}',
        );
      }
    }
  }

  Future<void> _openUnscheduledTask(
    PlannerUnscheduledTask item,
    PlannerOverview overview,
  ) async {
    if (!ref.read(plannerControllerProvider).canMutate) return;
    final plan = overview.actionPlans
        .where(
          (value) => value.targetKind == 'task' && value.targetId == item.id,
        )
        .firstOrNull;
    if (plan?.pendingRevision != null) {
      await _showPreview(plan!);
      return;
    }
    await _createTask(
      initial: PlannerTaskDraft(
        title: item.title,
        description: item.description,
        priority: item.priority,
        estimatedMinutes: item.estimatedMinutes,
        deadlineAt: item.deadlineAt,
        preferredSessionMinutes: item.preferredSessionMinutes,
        useStudyRhythm: item.useStudyRhythm,
        targetId: item.id,
        expectedUpdatedAt: item.expectedUpdatedAt,
      ),
    );
  }

  Future<void> _openHabit(
    PlannerHabitSummary item,
    PlannerOverview overview,
  ) async {
    if (!ref.read(plannerControllerProvider).canMutate) return;
    final plan = overview.actionPlans
        .where(
          (value) => value.targetKind == 'habit' && value.targetId == item.id,
        )
        .firstOrNull;
    if (plan?.pendingRevision != null) {
      await _showPreview(plan!);
      return;
    }
    await _createHabit(
      initial: PlannerHabitDraft(
        title: item.title,
        description: item.description,
        cadenceKind: item.cadenceKind,
        scheduledWeekdays: item.scheduledWeekdays,
        weeklyTarget: item.weeklyTarget,
        durationMinutes: item.durationMinutes,
        targetId: item.id,
        expectedUpdatedAt: item.expectedUpdatedAt,
      ),
      definitionReadOnly: item.ownership == 'setup',
    );
  }

  Future<void> _openActionReservation(
    PlannerDayItem item,
    PlannerOverview overview,
  ) async {
    if (!ref.read(plannerControllerProvider).canMutate) return;
    final kind = item.kind == 'task_block' ? 'task' : 'habit';
    final plan = overview.actionPlans
        .where(
          (value) =>
              value.targetKind == kind && value.targetId == item.sourceId,
        )
        .firstOrNull;
    if (plan == null) return;
    final execute = await _openActionPlan(plan);
    if (!mounted || !execute) return;
    if (kind == 'task') {
      context.push(
        Uri(
          path: AppRoutes.deepWork,
          queryParameters: {
            'source_kind': 'planner_task_block',
            'source_block_id': item.id,
          },
        ).toString(),
      );
    } else {
      context.push(AppRoutes.habitCompletion);
    }
  }

  Future<bool> _openActionPlan(PlannerActionPlan plan) async {
    if (!ref.read(plannerControllerProvider).canMutate) return false;
    final execute = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                plan.activeRevision?.targetTitle ??
                    plan.pendingRevision?.targetTitle ??
                    'Action plan',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'The target remains authoritative. Cancelling releases future reservations only.',
              ),
              const SizedBox(height: AppSpacing.md),
              if (plan.activeRevision != null)
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: Icon(
                    plan.targetKind == 'task'
                        ? AppIcons.playArrow
                        : AppIcons.checkCircleOutline,
                  ),
                  label: Text(
                    plan.targetKind == 'task'
                        ? 'Start focus'
                        : 'Log habit outcome',
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                key: const ValueKey('planner-cancel-reservations'),
                onPressed: () => Navigator.pop(context, false),
                icon: const Icon(AppIcons.eventBusyOutlined),
                label: const Text('Cancel reservations'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted ||
        !ref.read(plannerControllerProvider).canMutate ||
        execute != false) {
      return execute == true && ref.read(plannerControllerProvider).canMutate;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cancel future reservations?'),
            content: const Text(
              'The Task or Habit stays available under Unscheduled. Restoring a target never restores old slots.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep plan'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Cancel reservations'),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !confirmed) return false;
    final saved =
        await ref.read(plannerControllerProvider.notifier).cancelPlan(plan);
    if (mounted) {
      if (saved) {
        await _afterPlannerMutation();
        if (!mounted) return false;
      }
      if (!saved || _mutationProjectionIsCurrent()) {
        _showMessage(
          saved
              ? 'Future reservations released.'
              : 'Could not cancel reservations.',
        );
      }
    }
    return false;
  }

  Future<void> _editCommitment(PlannerCommitment commitment) async {
    if (!ref.read(plannerControllerProvider).canMutate) return;
    final draft = await showDialog<PlannerCommitmentDraft>(
      context: context,
      builder: (_) => PlannerCommitmentDialog(
        timezone: ref.read(plannerControllerProvider).overview!.timezone,
        initial: PlannerCommitmentDraft(
          title: commitment.title,
          location: commitment.location,
          recurrence: commitment.recurrence,
          startsAt: commitment.startsAt,
          endsAt: commitment.endsAt,
          weekday: commitment.weekday,
          localStartsAt: commitment.localStartsAt,
          localEndsAt: commitment.localEndsAt,
        ),
      ),
    );
    if (!mounted || draft == null) return;
    _retainedCommitmentDraft = draft;
    final saved = await ref
        .read(plannerControllerProvider.notifier)
        .updateCommitment(commitment, draft);
    if (mounted) {
      if (saved) {
        await _afterPlannerMutation();
        if (!mounted) return;
        _retainedCommitmentDraft = null;
      }
      if (!saved || _mutationProjectionIsCurrent()) {
        _showMessage(
          saved
              ? 'Fixed commitment updated.'
              : 'Could not update commitment. Your values are retained.',
        );
      }
    }
  }

  void _showFailure() {
    final state = ref.read(plannerControllerProvider);
    _showMessage(
      state.requiresExactRetry
          ? 'The result is unknown. Retry the exact change or reload before doing anything else.'
          : state.reloadSuggested
              ? 'Planner changed. Reload and create a new preview.'
              : 'Planner could not save that change. Your entered values are retained.',
    );
  }

  Future<void> _afterPlannerMutation() {
    final localDate = ref.read(plannerControllerProvider).overview?.localDate;
    return ref.read(projectionRefreshCoordinatorProvider).plannerChanged(
          targetDate: localDate == null ? null : localDateKey(localDate),
        );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

bool _taskUsesAutomaticPlanning(PlannerTaskDraft draft) =>
    draft.estimatedMinutes != null &&
    draft.deadlineAt != null &&
    draft.preferredSessionMinutes != null;

bool _sameVersion(DateTime? left, DateTime? right) =>
    left == null && right == null ||
    left != null && right != null && left.isAtSameMomentAs(right);

bool _sameTaskDraft(PlannerTaskDraft? left, PlannerTaskDraft? right) =>
    left != null &&
    right != null &&
    left.title == right.title &&
    left.description == right.description &&
    left.priority == right.priority &&
    left.estimatedMinutes == right.estimatedMinutes &&
    _sameVersion(left.deadlineAt, right.deadlineAt) &&
    left.preferredSessionMinutes == right.preferredSessionMinutes &&
    left.useStudyRhythm == right.useStudyRhythm &&
    left.targetId == right.targetId &&
    _sameVersion(left.expectedUpdatedAt, right.expectedUpdatedAt);

bool _sameHabitDraft(PlannerHabitDraft? left, PlannerHabitDraft? right) =>
    left != null &&
    right != null &&
    left.title == right.title &&
    left.description == right.description &&
    left.cadenceKind == right.cadenceKind &&
    _deepJsonEquals(left.scheduledWeekdays, right.scheduledWeekdays) &&
    left.weeklyTarget == right.weeklyTarget &&
    left.durationMinutes == right.durationMinutes &&
    left.targetId == right.targetId &&
    _sameVersion(left.expectedUpdatedAt, right.expectedUpdatedAt);

bool _deepJsonEquals(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length ||
        left.keys.any((key) => !right.containsKey(key))) {
      return false;
    }
    return left.keys.every((key) => _deepJsonEquals(left[key], right[key]));
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (!_deepJsonEquals(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}

bool _availabilityIsIncomplete(PlannerOverview overview) {
  final hasVisibleSetupCommitment = overview.days.any(
    (day) => day.items.any((item) => item.kind == 'setup_commitment'),
  );
  final hasCurrentManualCommitment = overview.commitments.any((commitment) {
    if (commitment.status != 'active') return false;
    if (commitment.recurrence == 'weekly') return true;
    return commitment.endsAt?.isAfter(overview.generatedAt) ?? false;
  });
  final hasConsentedCalendarBusyTime =
      overview.preferences.useCalendarBusyTime &&
          overview.preferences.calendarAvailable;
  return !hasVisibleSetupCommitment &&
      !hasCurrentManualCommitment &&
      !hasConsentedCalendarBusyTime;
}

List<String> _overlappingTitles(
  PlannerCommitmentDraft draft,
  PlannerOverview overview,
) {
  final titles = <String>{};
  for (final day in overview.days) {
    for (final item in day.items) {
      if (!{'task_block', 'habit_slot', 'preparation'}.contains(item.kind) ||
          item.startsAt == null ||
          item.endsAt == null) {
        continue;
      }
      final starts = profileDateTimeAt(
        instant: item.startsAt!,
        timezoneName: overview.timezone,
      );
      final ends = profileDateTimeAt(
        instant: item.reservedEndsAt ?? item.endsAt!,
        timezoneName: overview.timezone,
      );
      final overlaps = draft.recurrence == 'one_off'
          ? draft.startsAt!.isBefore(ends) && draft.endsAt!.isAfter(starts)
          : _weeklyCommitmentOverlaps(draft, starts, ends, overview.timezone);
      if (overlaps) titles.add(item.title);
    }
  }
  return titles.toList()..sort();
}

bool _weeklyCommitmentOverlaps(
  PlannerCommitmentDraft draft,
  DateTime starts,
  DateTime ends,
  String timezone,
) {
  final startClock = draft.localStartsAt!.split(':');
  final endClock = draft.localEndsAt!.split(':');
  final lastDay = DateTime(ends.year, ends.month, ends.day);
  for (var day = DateTime(starts.year, starts.month, starts.day);
      !day.isAfter(lastDay);
      day = DateTime(day.year, day.month, day.day + 1)) {
    if (day.weekday != draft.weekday) continue;
    try {
      DateTime boundary(List<String> clock) => profileDateTimeFromComponents(
            year: day.year,
            month: day.month,
            day: day.day,
            hour: int.parse(clock[0]),
            minute: int.parse(clock[1]),
            timezoneName: timezone,
          );
      if (boundary(startClock).isBefore(ends) &&
          boundary(endClock).isAfter(starts)) {
        return true;
      }
    } on ProfileTimezoneException {
      // Unresolved recurring occurrences are omitted from availability.
      continue;
    }
  }
  return false;
}
