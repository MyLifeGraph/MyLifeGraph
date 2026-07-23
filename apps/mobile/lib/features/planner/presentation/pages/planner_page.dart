import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../application/planner_controller.dart';
import '../../domain/planner.dart';
import '../providers/planner_providers.dart';

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
        children: const [
          _PlannerLockedCard(),
        ],
      );
    }

    final state = ref.watch(plannerControllerProvider);
    final controller = ref.read(plannerControllerProvider.notifier);
    final overview = state.overview;
    final availabilityIncomplete =
        overview != null && _availabilityIsIncomplete(overview);
    final children = <Widget>[
      _AddNewSection(
        busy: state.isBusy || state.requiresExactRetry,
        calendarPreference: overview?.preferences,
        availabilityIncomplete: availabilityIncomplete,
        onTask: _createTask,
        onHabit: _createHabit,
        onExam: () => _openPreparationCreation('exam'),
        onAssignment: () => _openPreparationCreation('assignment'),
        onCommitment: () => _createCommitment(overview),
        onReviewSetup: () => context.go('${AppRoutes.onboarding}?edit=1'),
        onCalendarPreference: overview == null
            ? null
            : (value) async {
                final saved = await controller.updateCalendarPreference(value);
                if (mounted && !saved) _showFailure();
              },
      ),
    ];

    if (state.requiresExactRetry || state.operationError != null) {
      children.add(
        _PlannerMutationError(
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
            : _PlannerLoadError(onRetry: controller.load),
      );
      return AppPage(
        title: 'Planner',
        subtitle: 'Turn explicit estimates into reviewable time blocks',
        children: children,
      );
    }

    children.add(
      _NeedsAttentionSection(
        items: overview.needsAttention,
        onOpen: (item) => _openAttention(item, overview),
      ),
    );
    children.add(
      _SevenDaySection(
        days: overview.days,
        onItemTap: (item) => _openDayItem(item, overview),
      ),
    );
    children.add(
      _PreparationSection(
        plans: overview.ongoingPreparation,
        onOpen: (plan) => context.go(
          '${AppRoutes.preparationPlans}?plan_id=${plan.planId}',
        ),
      ),
    );
    children.add(
      _UnscheduledSection(
        items: overview.unscheduled,
        onOpen: (item) => _openUnscheduled(item, overview),
      ),
    );
    children.add(_HistorySection(items: overview.history));
    return AppPage(
      title: 'Planner',
      subtitle: 'Preview first. Times are reserved only after confirmation.',
      actions: [
        IconButton(
          tooltip: 'Reload Planner',
          onPressed: state.isBusy ? null : controller.load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      children: children,
    );
  }

  Future<void> _createTask({PlannerTaskDraft? initial}) async {
    final draft = await showDialog<PlannerTaskDraft>(
      context: context,
      builder: (_) => _TaskDialog(initial: initial ?? _retainedTaskDraft),
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
      builder: (_) => _HabitDialog(initial: initial ?? _retainedHabitDraft),
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
    context.go('${AppRoutes.preparationPlans}?kind=$kind');
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
          builder: (_) => _PlanPreviewDialog(plan: plan),
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
      builder: (_) => _CommitmentDialog(initial: _retainedCommitmentDraft),
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
      context.go('${AppRoutes.preparationPlans}?plan_id=${item.sourceId}');
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
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit commitment'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'archive'),
                icon: const Icon(Icons.archive_outlined),
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
      context.go('${AppRoutes.onboarding}?edit=1&section=study');
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
        context.go(
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
      context.go(
        '${AppRoutes.deepWork}?target_kind=task&target_id=${item.sourceId}'
        '&planned_minutes=${item.endsAt!.difference(item.startsAt!).inMinutes}'
        '&recovery_minutes=${item.recoveryMinutes}',
      );
    } else {
      context.go(AppRoutes.habitCompletion);
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
                        ? Icons.play_arrow
                        : Icons.check_circle_outline,
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
                icon: const Icon(Icons.event_busy_outlined),
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
      builder: (_) => _CommitmentDialog(
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
      if (saved) _retainedCommitmentDraft = null;
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PlannerLockedCard extends StatelessWidget {
  const _PlannerLockedCard();

  @override
  Widget build(BuildContext context) => const AppCard(
        key: ValueKey('planner-locked'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Synced Planner unavailable'),
                  SizedBox(height: AppSpacing.xs),
                  Text(
                    'Guest and demo sessions stay local. They do not create or invent synced plans.',
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _AddNewSection extends StatelessWidget {
  const _AddNewSection({
    required this.busy,
    required this.calendarPreference,
    required this.availabilityIncomplete,
    required this.onTask,
    required this.onHabit,
    required this.onExam,
    required this.onAssignment,
    required this.onCommitment,
    required this.onReviewSetup,
    required this.onCalendarPreference,
  });

  final bool busy;
  final PlannerPreferences? calendarPreference;
  final bool availabilityIncomplete;
  final VoidCallback onTask;
  final VoidCallback onHabit;
  final VoidCallback onExam;
  final VoidCallback onAssignment;
  final VoidCallback onCommitment;
  final VoidCallback onReviewSetup;
  final ValueChanged<bool>? onCalendarPreference;

  @override
  Widget build(BuildContext context) => AppCard(
        key: const ValueKey('planner-add-new'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add new', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Only explicit values are planned. Nothing is scheduled in the background.',
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _CreateButton(
                  key: const ValueKey('planner-add-task'),
                  icon: Icons.task_alt_outlined,
                  label: 'Task',
                  onPressed: busy ? null : onTask,
                ),
                _CreateButton(
                  key: const ValueKey('planner-add-habit'),
                  icon: Icons.repeat_outlined,
                  label: 'Habit',
                  onPressed: busy ? null : onHabit,
                ),
                _CreateButton(
                  key: const ValueKey('planner-add-exam'),
                  icon: Icons.school_outlined,
                  label: 'Exam',
                  onPressed: busy ? null : onExam,
                ),
                _CreateButton(
                  key: const ValueKey('planner-add-assignment'),
                  icon: Icons.assignment_outlined,
                  label: 'Assignment',
                  onPressed: busy ? null : onAssignment,
                ),
                _CreateButton(
                  key: const ValueKey('planner-add-commitment'),
                  icon: Icons.event_busy_outlined,
                  label: 'Fixed commitment',
                  onPressed: busy ? null : onCommitment,
                ),
              ],
            ),
            if (availabilityIncomplete) ...[
              const Divider(height: AppSpacing.xl),
              Container(
                key: const ValueKey('planner-availability-warning'),
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.event_note_outlined),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Availability may be incomplete',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              const Text(
                                'Add recurring classes or work times before the first automatic plan. Calendar import stays optional.',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton.tonalIcon(
                      key: const ValueKey('planner-review-setup-schedule'),
                      onPressed: busy ? null : onReviewSetup,
                      icon: const Icon(Icons.calendar_view_week_outlined),
                      label: const Text('Add weekly schedule'),
                    ),
                  ],
                ),
              ),
            ],
            if (calendarPreference != null) ...[
              const Divider(height: AppSpacing.xl),
              SwitchListTile(
                key: const ValueKey('planner-calendar-consent'),
                contentPadding: EdgeInsets.zero,
                value: calendarPreference!.useCalendarBusyTime,
                onChanged: busy ? null : onCalendarPreference,
                secondary: const Icon(Icons.calendar_month_outlined),
                title: const Text('Use current calendar import as busy time'),
                subtitle: Text(
                  calendarPreference!.calendarAvailable
                      ? 'Read-only. A changed import makes open previews stale.'
                      : 'No current .ics import is available. Import one in Settings first.',
                ),
              ),
            ],
          ],
        ),
      );
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
}

class _NeedsAttentionSection extends StatelessWidget {
  const _NeedsAttentionSection({required this.items, required this.onOpen});

  final List<PlannerAttention> items;
  final ValueChanged<PlannerAttention> onOpen;

  @override
  Widget build(BuildContext context) => AppCard(
        key: const ValueKey('planner-needs-attention'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Needs attention',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (items.isEmpty)
              const Row(
                children: [
                  Icon(Icons.check_circle_outline),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('No conflicts or stale previews.')),
                ],
              )
            else
              for (final item in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item.kind == 'stale_preview'
                        ? Icons.update_outlined
                        : item.kind == 'unscheduled'
                            ? Icons.timer_off_outlined
                            : Icons.warning_amber_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(item.title),
                  subtitle: Text(item.detail),
                  trailing: item.planId == null
                      ? (item.target == 'study_setup'
                          ? const Icon(Icons.chevron_right)
                          : item.unplacedMinutes > 0
                              ? Text('${item.unplacedMinutes} min')
                              : null)
                      : const Icon(Icons.chevron_right),
                  onTap: item.planId == null && item.target != 'study_setup'
                      ? null
                      : () => onOpen(item),
                ),
          ],
        ),
      );
}

class _SevenDaySection extends StatelessWidget {
  const _SevenDaySection({required this.days, required this.onItemTap});

  final List<PlannerDay> days;
  final ValueChanged<PlannerDayItem> onItemTap;

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey('planner-seven-days'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Next seven days',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final day in days) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('EEEE, MMM d').format(day.localDate),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (day.items.isEmpty)
                    const Text('No planned or fixed items.')
                  else
                    for (final item in day.items)
                      _PlannerDayItemTile(
                        item: item,
                        onTap: () => onItemTap(item),
                      ),
                ],
              ),
            ),
            if (day != days.last) const SizedBox(height: AppSpacing.sm),
          ],
        ],
      );
}

class _PlannerDayItemTile extends StatelessWidget {
  const _PlannerDayItemTile({required this.item, required this.onTap});

  final PlannerDayItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = _visual(item.kind);
    final time = item.allDay
        ? 'All day'
        : item.recoveryMinutes > 0
            ? '${DateFormat.Hm().format(item.startsAt!.toLocal())}–'
                '${DateFormat.Hm().format(item.endsAt!.toLocal())} focus + '
                '${item.recoveryMinutes} min recovery · reserved until '
                '${DateFormat.Hm().format(item.reservedEndsAt!.toLocal())}'
            : '${DateFormat.Hm().format(item.startsAt!.toLocal())}–'
                '${DateFormat.Hm().format(item.endsAt!.toLocal())}';
    final actionable = {
      'manual_commitment',
      'task_block',
      'habit_slot',
      'preparation',
    }.contains(item.kind);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor:
            visual.color(Theme.of(context)).withValues(alpha: 0.14),
        foregroundColor: visual.color(Theme.of(context)),
        child: Icon(visual.icon, size: 20),
      ),
      title: Text(item.title),
      subtitle: Text('$time · ${visual.label}'),
      trailing: actionable ? const Icon(Icons.chevron_right) : null,
      onTap: actionable ? onTap : null,
    );
  }
}

class _PreparationSection extends StatelessWidget {
  const _PreparationSection({required this.plans, required this.onOpen});

  final List<PlannerPreparation> plans;
  final ValueChanged<PlannerPreparation> onOpen;

  @override
  Widget build(BuildContext context) => AppCard(
        key: const ValueKey('planner-ongoing-preparation'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ongoing preparation',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (plans.isEmpty)
              const Text('No active exam or assignment preparation.')
            else
              for (final plan in plans)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.school_outlined),
                  title: Text(plan.title),
                  subtitle: Text(
                    '${_minutes(plan.remainingMinutes)} remaining · '
                    '${plan.nextBlockStartsAt == null ? 'no next block' : 'next ${DateFormat.MMMd().add_Hm().format(plan.nextBlockStartsAt!.toLocal())}'}',
                  ),
                  trailing: plan.hasPendingPreview
                      ? const Chip(label: Text('Preview'))
                      : const Icon(Icons.chevron_right),
                  onTap: () => onOpen(plan),
                ),
          ],
        ),
      );
}

class _UnscheduledSection extends StatelessWidget {
  const _UnscheduledSection({required this.items, required this.onOpen});

  final List<PlannerUnscheduled> items;
  final ValueChanged<PlannerUnscheduled> onOpen;

  @override
  Widget build(BuildContext context) => AppCard(
        key: const ValueKey('planner-unscheduled'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Unscheduled', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            if (items.isEmpty)
              const Text('No open Tasks or Habits are waiting for a plan.')
            else
              for (final item in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item.kind == 'task'
                        ? Icons.task_outlined
                        : Icons.repeat_outlined,
                  ),
                  title: Text(item.title),
                  subtitle: Text(_reason(item.reason)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onOpen(item),
                ),
          ],
        ),
      );
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.items});

  final List<PlannerUnscheduled> items;

  @override
  Widget build(BuildContext context) => AppCard(
        key: const ValueKey('planner-history'),
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          title: const Text('Completed and archived'),
          subtitle: Text('${items.length} historical items'),
          children: [
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No history yet.'),
                ),
              )
            else
              for (final item in items)
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(item.title),
                  subtitle: Text(item.kind == 'task' ? 'Task' : 'Habit'),
                ),
          ],
        ),
      );
}

class _PlannerMutationError extends StatelessWidget {
  const _PlannerMutationError({
    required this.exactRetryRequired,
    required this.conflict,
    required this.onRetryExact,
    required this.onReload,
  });

  final bool exactRetryRequired;
  final bool conflict;
  final VoidCallback? onRetryExact;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              exactRetryRequired
                  ? 'Result not confirmed'
                  : conflict
                      ? 'Planner changed'
                      : 'Could not save change',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              exactRetryRequired
                  ? 'Retry the exact submitted values, or reload before starting another change.'
                  : conflict
                      ? 'Reload current data and create a new preview. Active reservations were not changed.'
                      : 'Your entered values are retained on this page.',
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (onRetryExact != null)
                  FilledButton(
                    onPressed: onRetryExact,
                    child: const Text('Retry same change'),
                  ),
                OutlinedButton(
                  onPressed: onReload,
                  child: const Text('Reload Planner'),
                ),
              ],
            ),
          ],
        ),
      );
}

class _PlannerLoadError extends StatelessWidget {
  const _PlannerLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          children: [
            const Text(
              'Planner could not be loaded. No demo plan was substituted.',
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
}

class _PlanPreviewDialog extends StatelessWidget {
  const _PlanPreviewDialog({required this.plan});

  final PlannerActionPlan plan;

  @override
  Widget build(BuildContext context) {
    final revision = plan.pendingRevision!;
    return AlertDialog(
      title: const Text('Review plan preview'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                revision.targetTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${revision.plannedMinutes} min placed · '
                '${revision.unscheduledMinutes} min unplaced',
              ),
              const SizedBox(height: AppSpacing.md),
              if (revision.taskBlocks.isEmpty && revision.habitSlots.isEmpty)
                const Text(
                  'No time is reserved in this preview. Confirming saves the target under Unscheduled.',
                ),
              for (final block in revision.taskBlocks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.view_timeline_outlined),
                  title: Text('${block.plannedMinutes} min'),
                  subtitle: Text(
                    block.recoveryMinutes > 0
                        ? '${DateFormat.yMMMd().add_Hm().format(block.startsAt.toLocal())} · '
                            '${block.plannedMinutes} min focus + ${block.recoveryMinutes} min recovery · '
                            'reserved until ${DateFormat.Hm().format(block.reservedEndsAt.toLocal())}'
                        : DateFormat.yMMMd()
                            .add_Hm()
                            .format(block.startsAt.toLocal()),
                  ),
                ),
              for (final slot in revision.habitSlots)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.repeat_outlined),
                  title: Text(
                    '${_weekdayLabel(slot.weekday)} · ${slot.durationMinutes} min',
                  ),
                  subtitle: Text(
                    '${slot.startsAt.substring(0, 5)}–${slot.endsAt.substring(0, 5)} every week',
                  ),
                ),
              if (revision.unscheduledMinutes > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Unplaced minutes stay explicit. Planner will not extend the deadline or overlap another reservation.',
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep as draft'),
        ),
        FilledButton(
          key: const ValueKey('planner-confirm-plan'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirm plan'),
        ),
      ],
    );
  }
}

class _TaskDialog extends StatefulWidget {
  const _TaskDialog({required this.initial});

  final PlannerTaskDraft? initial;

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _duration;
  late final TextEditingController _session;
  late String _priority;
  late bool _schedule;
  late bool _useStudyRhythm;
  DateTime? _deadline;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title);
    _description = TextEditingController(text: initial?.description);
    _duration =
        TextEditingController(text: initial?.estimatedMinutes?.toString());
    _session = TextEditingController(
      text: initial?.preferredSessionMinutes?.toString(),
    );
    _priority = initial?.priority ?? 'medium';
    _deadline = initial?.deadlineAt;
    _schedule = initial?.estimatedMinutes != null ||
        initial?.deadlineAt != null ||
        initial?.preferredSessionMinutes != null;
    _useStudyRhythm = initial?.useStudyRhythm ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _duration.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add Task'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('planner-task-title'),
                  controller: _title,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Title *'),
                ),
                TextField(
                  controller: _description,
                  maxLength: 2000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(
                      value: 'critical',
                      child: Text('Critical'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _priority = value!),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _schedule,
                  onChanged: (value) => setState(() {
                    _schedule = value;
                    if (!value) _useStudyRhythm = false;
                  }),
                  title: const Text('Create a time-block preview'),
                  subtitle: const Text(
                    'Requires your duration, exact deadline, and preferred session length.',
                  ),
                ),
                if (_schedule) ...[
                  SwitchListTile.adaptive(
                    key: const ValueKey('planner-task-study-rhythm'),
                    contentPadding: EdgeInsets.zero,
                    value: _useStudyRhythm,
                    onChanged: (value) {
                      setState(() => _useStudyRhythm = value);
                    },
                    title: const Text('Use study rhythm'),
                    subtitle: const Text(
                      'Uses the exact Focus length and reserves the full recovery buffer from Settings. Habits never use this rule.',
                    ),
                  ),
                  TextField(
                    key: const ValueKey('planner-task-duration'),
                    controller: _duration,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Total duration in minutes *',
                    ),
                  ),
                  TextField(
                    key: const ValueKey('planner-task-session'),
                    controller: _session,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Preferred session in minutes *',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Exact deadline *'),
                    subtitle: Text(
                      _deadline == null
                          ? 'Not selected'
                          : DateFormat.yMMMd().add_Hm().format(_deadline!),
                    ),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: _pickDeadline,
                  ),
                ],
                if (_error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('planner-task-preview'),
            onPressed: _submit,
            child: Text(_schedule ? 'Preview plan' : 'Save as unscheduled'),
          ),
        ],
      );

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      initialDate: _deadline ?? now.add(const Duration(days: 1)),
    );
    if (!mounted || day == null) return;
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: _deadline == null
          ? const TimeOfDay(hour: 17, minute: 0)
          : TimeOfDay.fromDateTime(_deadline!),
    );
    if (!mounted || selectedTime == null) return;
    setState(() {
      _deadline = DateTime(
        day.year,
        day.month,
        day.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  void _submit() {
    final title = _title.text.trim();
    final duration = _schedule ? int.tryParse(_duration.text.trim()) : null;
    final session = _schedule ? int.tryParse(_session.text.trim()) : null;
    if (title.isEmpty) {
      setState(() => _error = 'Enter a Task title.');
      return;
    }
    if (_schedule &&
        (duration == null ||
            duration < 5 ||
            duration > 480 ||
            session == null ||
            session < 5 ||
            session > 240 ||
            session % 5 != 0 ||
            _deadline == null ||
            !_deadline!.isAfter(DateTime.now()))) {
      setState(() {
        _error =
            'Use 5–480 total minutes, a 5–240 minute session in five-minute steps, and a future deadline.';
      });
      return;
    }
    Navigator.pop(
      context,
      PlannerTaskDraft(
        title: title,
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        priority: _priority,
        estimatedMinutes: duration,
        deadlineAt: _schedule ? _deadline : null,
        preferredSessionMinutes: session,
        useStudyRhythm: _schedule && _useStudyRhythm,
        targetId: widget.initial?.targetId,
        expectedUpdatedAt: widget.initial?.expectedUpdatedAt,
      ),
    );
  }
}

class _HabitDialog extends StatefulWidget {
  const _HabitDialog({required this.initial});

  final PlannerHabitDraft? initial;

  @override
  State<_HabitDialog> createState() => _HabitDialogState();
}

class _HabitDialogState extends State<_HabitDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _duration;
  String? _cadence;
  Set<int> _weekdays = {};
  int _weeklyTarget = 3;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title);
    _description = TextEditingController(text: initial?.description);
    _duration = TextEditingController(
      text: initial?.durationMinutes?.toString(),
    );
    _cadence = initial?.cadenceKind;
    _weekdays = initial?.scheduledWeekdays.toSet() ?? {};
    _weeklyTarget = initial?.weeklyTarget ?? 3;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add Habit'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const ValueKey('planner-habit-title'),
                  controller: _title,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Title *'),
                ),
                TextField(
                  controller: _description,
                  maxLength: 2000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _cadence,
                  decoration: const InputDecoration(labelText: 'Cadence *'),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(
                      value: 'weekdays',
                      child: Text('Selected weekdays'),
                    ),
                    DropdownMenuItem(
                      value: 'weekly_target',
                      child: Text('Times per week'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _cadence = value),
                ),
                if (_cadence == 'weekdays') ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (var day = 1; day <= 7; day++)
                        FilterChip(
                          label: Text(_weekdayLabel(day)),
                          selected: _weekdays.contains(day),
                          onSelected: (selected) => setState(() {
                            selected
                                ? _weekdays.add(day)
                                : _weekdays.remove(day);
                          }),
                        ),
                    ],
                  ),
                ],
                if (_cadence == 'weekly_target')
                  DropdownButtonFormField<int>(
                    initialValue: _weeklyTarget,
                    decoration:
                        const InputDecoration(labelText: 'Times per week'),
                    items: [
                      for (var value = 1; value <= 7; value++)
                        DropdownMenuItem(value: value, child: Text('$value')),
                    ],
                    onChanged: (value) =>
                        setState(() => _weeklyTarget = value!),
                  ),
                TextField(
                  key: const ValueKey('planner-habit-duration'),
                  controller: _duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Minutes per occurrence *',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'The same weekly time is checked across the next four weeks. Later conflicts appear under Needs attention.',
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('planner-habit-preview'),
            onPressed: _submit,
            child: const Text('Preview plan'),
          ),
        ],
      );

  void _submit() {
    final title = _title.text.trim();
    final duration = int.tryParse(_duration.text.trim());
    if (title.isEmpty || _cadence == null) {
      setState(() => _error = 'Enter a title and choose a cadence.');
      return;
    }
    if (_cadence == 'weekdays' && _weekdays.isEmpty) {
      setState(() => _error = 'Choose at least one weekday.');
      return;
    }
    if (duration == null ||
        duration < 5 ||
        duration > 240 ||
        duration % 5 != 0) {
      setState(() => _error = 'Choose 5–240 minutes in five-minute steps.');
      return;
    }
    Navigator.pop(
      context,
      PlannerHabitDraft(
        title: title,
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        cadenceKind: _cadence!,
        scheduledWeekdays:
            _cadence == 'weekdays' ? (_weekdays.toList()..sort()) : const [],
        weeklyTarget: _cadence == 'weekly_target' ? _weeklyTarget : 1,
        durationMinutes: duration,
        targetId: widget.initial?.targetId,
        expectedUpdatedAt: widget.initial?.expectedUpdatedAt,
      ),
    );
  }
}

class _CommitmentDialog extends StatefulWidget {
  const _CommitmentDialog({required this.initial});

  final PlannerCommitmentDraft? initial;

  @override
  State<_CommitmentDialog> createState() => _CommitmentDialogState();
}

class _CommitmentDialogState extends State<_CommitmentDialog> {
  late final TextEditingController _title;
  late final TextEditingController _location;
  String? _recurrence;
  DateTime? _startsAt;
  DateTime? _endsAt;
  int? _weekday;
  TimeOfDay? _weeklyStart;
  TimeOfDay? _weeklyEnd;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title);
    _location = TextEditingController(text: initial?.location);
    _recurrence = initial?.recurrence;
    _startsAt = initial?.startsAt;
    _endsAt = initial?.endsAt;
    _weekday = initial?.weekday;
    _weeklyStart = _parseTime(initial?.localStartsAt);
    _weeklyEnd = _parseTime(initial?.localEndsAt);
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add fixed commitment'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('planner-commitment-title'),
                  controller: _title,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Title *'),
                ),
                TextField(
                  controller: _location,
                  maxLength: 300,
                  decoration:
                      const InputDecoration(labelText: 'Location (optional)'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _recurrence,
                  decoration: const InputDecoration(labelText: 'Repeats *'),
                  items: const [
                    DropdownMenuItem(value: 'one_off', child: Text('One time')),
                    DropdownMenuItem(
                      value: 'weekly',
                      child: Text('Every week'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _recurrence = value),
                ),
                if (_recurrence == 'one_off') ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Starts *'),
                    subtitle: Text(
                      _startsAt == null
                          ? 'Not selected'
                          : DateFormat.yMMMd().add_Hm().format(_startsAt!),
                    ),
                    onTap: () => _pickOneOff(start: true),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ends *'),
                    subtitle: Text(
                      _endsAt == null
                          ? 'Not selected'
                          : DateFormat.yMMMd().add_Hm().format(_endsAt!),
                    ),
                    onTap: () => _pickOneOff(start: false),
                  ),
                ],
                if (_recurrence == 'weekly') ...[
                  DropdownButtonFormField<int>(
                    initialValue: _weekday,
                    decoration: const InputDecoration(labelText: 'Weekday *'),
                    items: [
                      for (var day = 1; day <= 7; day++)
                        DropdownMenuItem(
                          value: day,
                          child: Text(_weekdayLabel(day)),
                        ),
                    ],
                    onChanged: (value) => setState(() => _weekday = value),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Starts *'),
                    subtitle:
                        Text(_weeklyStart?.format(context) ?? 'Not selected'),
                    onTap: () => _pickWeekly(start: true),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ends *'),
                    subtitle:
                        Text(_weeklyEnd?.format(context) ?? 'Not selected'),
                    onTap: () => _pickWeekly(start: false),
                  ),
                ],
                if (_error != null)
                  Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('planner-commitment-review'),
            onPressed: _submit,
            child: const Text('Review commitment'),
          ),
        ],
      );

  Future<void> _pickOneOff({required bool start}) async {
    final current = start ? _startsAt : _endsAt;
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      initialDate: current ?? now,
    );
    if (!mounted || day == null) return;
    final value = await showTimePicker(
      context: context,
      initialTime: current == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay.fromDateTime(current),
    );
    if (!mounted || value == null) return;
    final instant =
        DateTime(day.year, day.month, day.day, value.hour, value.minute);
    setState(() => start ? _startsAt = instant : _endsAt = instant);
  }

  Future<void> _pickWeekly({required bool start}) async {
    final value = await showTimePicker(
      context: context,
      initialTime: (start ? _weeklyStart : _weeklyEnd) ??
          (start
              ? const TimeOfDay(hour: 9, minute: 0)
              : const TimeOfDay(hour: 10, minute: 0)),
    );
    if (!mounted || value == null) return;
    setState(() => start ? _weeklyStart = value : _weeklyEnd = value);
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty || _recurrence == null) {
      setState(() => _error = 'Enter a title and choose one time or weekly.');
      return;
    }
    if (_recurrence == 'one_off' &&
        (_startsAt == null ||
            _endsAt == null ||
            !_endsAt!.isAfter(_startsAt!))) {
      setState(() => _error = 'Choose an end after the start.');
      return;
    }
    if (_recurrence == 'weekly' &&
        (_weekday == null ||
            _weeklyStart == null ||
            _weeklyEnd == null ||
            _minuteOfDay(_weeklyEnd!) <= _minuteOfDay(_weeklyStart!))) {
      setState(() => _error = 'Choose a weekday and an end after the start.');
      return;
    }
    Navigator.pop(
      context,
      PlannerCommitmentDraft(
        title: title,
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        recurrence: _recurrence!,
        startsAt: _recurrence == 'one_off' ? _startsAt : null,
        endsAt: _recurrence == 'one_off' ? _endsAt : null,
        weekday: _recurrence == 'weekly' ? _weekday : null,
        localStartsAt:
            _recurrence == 'weekly' ? _timeString(_weeklyStart!) : null,
        localEndsAt: _recurrence == 'weekly' ? _timeString(_weeklyEnd!) : null,
      ),
    );
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

_BlockVisual _visual(String kind) => switch (kind) {
      'setup_commitment' => const _BlockVisual(
          Icons.settings_suggest_outlined,
          'Setup commitment',
          _tertiary,
        ),
      'manual_commitment' => const _BlockVisual(
          Icons.event_busy_outlined,
          'Fixed commitment',
          _error,
        ),
      'task_block' => const _BlockVisual(Icons.task_outlined, 'Task', _primary),
      'habit_slot' =>
        const _BlockVisual(Icons.repeat_outlined, 'Habit', _secondary),
      'preparation' =>
        const _BlockVisual(Icons.school_outlined, 'Preparation', _tertiary),
      _ =>
        const _BlockVisual(Icons.calendar_month_outlined, 'Calendar', _outline),
    };

class _BlockVisual {
  const _BlockVisual(this.icon, this.label, this.color);

  final IconData icon;
  final String label;
  final Color Function(ThemeData) color;
}

Color _primary(ThemeData theme) => theme.colorScheme.primary;
Color _secondary(ThemeData theme) => theme.colorScheme.secondary;
Color _tertiary(ThemeData theme) => theme.colorScheme.tertiary;
Color _error(ThemeData theme) => theme.colorScheme.error;
Color _outline(ThemeData theme) => theme.colorScheme.outline;

String _reason(String value) => switch (value) {
      'released' => 'Future reservations were released. Create a new preview.',
      'missing_scheduling_inputs' =>
        'Duration, exact deadline, or session length is missing.',
      _ => 'No confirmed reservation.',
    };

String _minutes(int value) {
  final hours = value ~/ 60;
  final minutes = value % 60;
  if (hours == 0) return '$minutes min';
  if (minutes == 0) return '$hours h';
  return '$hours h $minutes min';
}

String _weekdayLabel(int value) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][value - 1];

int _minuteOfDay(TimeOfDay value) => value.hour * 60 + value.minute;
int _minuteOfDate(DateTime value) => value.hour * 60 + value.minute;

int _minuteOfString(String value) {
  final parts = value.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String _timeString(TimeOfDay value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:00';

TimeOfDay? _parseTime(String? value) {
  if (value == null) return null;
  final parts = value.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}
