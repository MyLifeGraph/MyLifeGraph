import 'package:flutter/material.dart';

import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../composition/projection_refresh_providers.dart';
import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
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

class PlannerPage extends ConsumerStatefulWidget {
  const PlannerPage({super.key});

  @override
  ConsumerState<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends ConsumerState<PlannerPage> {
  PlannerTaskDraft? _retainedTaskDraft;
  PlannerHabitDraft? _retainedHabitDraft;
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
                      onPressed: state.isBusy ? null : controller.load,
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
                  final retryingProposal = state.pendingMutation?.kind ==
                      PlannerPendingKind.proposal;
                  final saved = await controller.retryExact();
                  if (mounted && saved) {
                    final preview = ref.read(plannerControllerProvider).preview;
                    if (retryingProposal && preview != null) {
                      await _showPreview(preview);
                    } else {
                      await _afterPlannerMutation();
                      _showMessage('Planner change confirmed.');
                    }
                  }
                }
              : null,
          onReload: controller.discardPendingAndReload,
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
                onPressed: state.isBusy ? null : controller.load,
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
        onOpen: (item) => _openAttention(item, overview),
      ),
    );
    children.add(
      PlannerSevenDaySection(
        days: overview.days,
        onItemTap: (item) => _openDayItem(item, overview),
      ),
    );
    children.add(
      PlannerPreparationSection(
        plans: overview.ongoingPreparation,
        onOpen: (plan) => context.push(
          '${AppRoutes.preparationPlans}?plan_id=${plan.planId}',
        ),
      ),
    );
    children.add(
      PlannerUnscheduledSection(
        items: overview.unscheduled,
        onOpen: (item) => _openUnscheduled(item, overview),
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
              onPressed: state.isBusy
                  ? null
                  : () {
                      ref.invalidate(examWeekOutlookProvider);
                      controller.load();
                    },
              icon: const Icon(AppIcons.refresh),
            ),
          ],
        ),
      ],
      children: children,
    );
  }

  Future<void> _createTask({PlannerTaskDraft? initial}) async {
    final draft = await showDialog<PlannerTaskDraft>(
      context: context,
      builder: (_) => PlannerTaskDialog(initial: initial ?? _retainedTaskDraft),
    );
    if (!mounted || draft == null) return;
    _retainedTaskDraft = draft;
    if (_taskUsesAutomaticPlanning(draft) &&
        !await _confirmAvailabilityForAutomaticPlanning()) {
      return;
    }
    final plan =
        await ref.read(plannerControllerProvider.notifier).proposeTask(draft);
    if (!mounted || plan == null) {
      if (mounted) _showFailure();
      return;
    }
    final confirmed = await _showPreview(plan);
    if (confirmed) _retainedTaskDraft = null;
  }

  Future<void> _createHabit({PlannerHabitDraft? initial}) async {
    final draft = await showDialog<PlannerHabitDraft>(
      context: context,
      builder: (_) =>
          PlannerHabitDialog(initial: initial ?? _retainedHabitDraft),
    );
    if (!mounted || draft == null) return;
    _retainedHabitDraft = draft;
    if (!await _confirmAvailabilityForAutomaticPlanning()) return;
    final plan =
        await ref.read(plannerControllerProvider.notifier).proposeHabit(draft);
    if (!mounted || plan == null) {
      if (mounted) _showFailure();
      return;
    }
    final confirmed = await _showPreview(plan);
    if (confirmed) _retainedHabitDraft = null;
  }

  Future<void> _openPreparationCreation(String kind) async {
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

  Future<bool> _showPreview(PlannerActionPlan plan) async {
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
        await _afterPlannerMutation();
        if (!mounted) return saved;
        _showMessage(
          plan.pendingRevision?.plannedMinutes == 0
              ? 'Saved under Unscheduled.'
              : 'Plan confirmed. Times are now reserved.',
        );
      } else {
        _showFailure();
      }
    }
    return saved;
  }

  Future<void> _createCommitment(PlannerOverview? overview) async {
    if (overview == null) return;
    final draft = await showDialog<PlannerCommitmentDraft>(
      context: context,
      builder: (_) =>
          PlannerCommitmentDialog(initial: _retainedCommitmentDraft),
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
        _showMessage('Fixed commitment saved.');
      } else {
        _showFailure();
      }
    }
  }

  Future<void> _openDayItem(
    PlannerDayItem item,
    PlannerOverview overview,
  ) async {
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
      _showMessage(
        saved ? 'Commitment archived.' : 'Could not archive commitment.',
      );
    }
  }

  Future<void> _openAttention(
    PlannerAttention item,
    PlannerOverview overview,
  ) async {
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

  Future<void> _openUnscheduled(
    PlannerUnscheduled item,
    PlannerOverview overview,
  ) async {
    final plan = overview.actionPlans
        .where(
          (value) => value.targetKind == item.kind && value.targetId == item.id,
        )
        .firstOrNull;
    if (plan?.pendingRevision != null) {
      await _showPreview(plan!);
      return;
    }
    if (item.kind == 'task') {
      await _createTask(
        initial: PlannerTaskDraft(
          title: item.title,
          description: item.description,
          priority: item.priority!,
          estimatedMinutes: item.estimatedMinutes,
          deadlineAt: item.deadlineAt?.toLocal(),
          preferredSessionMinutes: item.preferredSessionMinutes,
          useStudyRhythm: item.useStudyRhythm,
          targetId: item.id,
          expectedUpdatedAt: item.expectedUpdatedAt,
        ),
      );
      return;
    }
    await _createHabit(
      initial: PlannerHabitDraft(
        title: item.title,
        description: item.description,
        cadenceKind: item.cadenceKind!,
        scheduledWeekdays: item.scheduledWeekdays,
        weeklyTarget: item.weeklyTarget!,
        durationMinutes: item.durationMinutes,
        targetId: item.id,
        expectedUpdatedAt: item.expectedUpdatedAt,
      ),
    );
  }

  Future<void> _openActionReservation(
    PlannerDayItem item,
    PlannerOverview overview,
  ) async {
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
    if (!mounted || execute != false) return execute == true;
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
      _showMessage(
        saved
            ? 'Future reservations released.'
            : 'Could not cancel reservations.',
      );
    }
    return false;
  }

  Future<void> _editCommitment(PlannerCommitment commitment) async {
    final draft = await showDialog<PlannerCommitmentDraft>(
      context: context,
      builder: (_) => PlannerCommitmentDialog(
        initial: PlannerCommitmentDraft(
          title: commitment.title,
          location: commitment.location,
          recurrence: commitment.recurrence,
          startsAt: commitment.startsAt?.toLocal(),
          endsAt: commitment.endsAt?.toLocal(),
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
      _showMessage(
        saved
            ? 'Fixed commitment updated.'
            : 'Could not update commitment. Your values are retained.',
      );
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
      final overlaps = draft.recurrence == 'one_off'
          ? draft.startsAt!.isBefore(item.endsAt!.toLocal()) &&
              draft.endsAt!.isAfter(item.startsAt!.toLocal())
          : item.startsAt!.toLocal().weekday == draft.weekday &&
              _minuteOfDate(item.startsAt!.toLocal()) <
                  _minuteOfString(draft.localEndsAt!) &&
              _minuteOfDate(item.endsAt!.toLocal()) >
                  _minuteOfString(draft.localStartsAt!);
      if (overlaps) titles.add(item.title);
    }
  }
  return titles.toList()..sort();
}

int _minuteOfDate(DateTime value) => value.hour * 60 + value.minute;

int _minuteOfString(String value) {
  final parts = value.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}
