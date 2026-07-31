import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_visual_tokens.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../quick_action/domain/habit_v1.dart';
import '../../application/today_command_controller.dart';
import '../../domain/entities/dashboard_snapshot.dart';
import 'dashboard_section_widgets.dart';

class TodayTaskVisibility {
  const TodayTaskVisibility({
    required this.showAll,
    required this.showCompleted,
    required this.showCancelled,
  });

  final bool showAll;
  final bool showCompleted;
  final bool showCancelled;
}

class TodayTaskActions {
  const TodayTaskActions({
    required this.onOpenPlanner,
    required this.onComplete,
    required this.onRestore,
    required this.onStartFocus,
    required this.onToggleAll,
    required this.onToggleCompleted,
    required this.onToggleCancelled,
  });

  final VoidCallback onOpenPlanner;
  final ValueChanged<PlanItem> onComplete;
  final ValueChanged<PlanItem> onRestore;
  final ValueChanged<PlanItem> onStartFocus;
  final VoidCallback onToggleAll;
  final VoidCallback onToggleCompleted;
  final VoidCallback onToggleCancelled;
}

class TodayHabitActions {
  const TodayHabitActions({
    required this.onSetOutcome,
    required this.onUndo,
  });

  final void Function(TodayHabit habit, HabitOutcome outcome) onSetOutcome;
  final ValueChanged<TodayHabit> onUndo;
}

/// Owns the complete Today Task projection, including the optional history
/// expansion. The immutable state and action objects keep its parent boundary
/// small without hiding command execution in the widget.
class TodayTaskSections extends StatelessWidget {
  const TodayTaskSections({
    super.key,
    required this.snapshot,
    required this.commands,
    required this.canExecute,
    required this.visibility,
    required this.actions,
  });

  final DashboardSnapshot snapshot;
  final TodayCommandState commands;
  final bool canExecute;
  final TodayTaskVisibility visibility;
  final TodayTaskActions actions;

  @override
  Widget build(BuildContext context) {
    final allTasks = snapshot.allTasks;
    final activeTasks = allTasks.where((item) {
      final completed = commands.completedTaskIds.contains(item.id) ||
          (item.isCompleted && !commands.restoredTaskIds.contains(item.id));
      final cancelled = commands.deletedTaskIds.contains(item.id) ||
          (item.status == 'cancelled' &&
              !commands.restoredTaskIds.contains(item.id));
      return !completed && !cancelled;
    }).toList();
    final cancelledTasks = allTasks.where((item) {
      return commands.deletedTaskIds.contains(item.id) ||
          (item.status == 'cancelled' &&
              !commands.restoredTaskIds.contains(item.id));
    }).toList();
    final completedTasks = allTasks.where((item) {
      final completed = commands.completedTaskIds.contains(item.id) ||
          (item.isCompleted && !commands.restoredTaskIds.contains(item.id));
      return completed && !commands.deletedTaskIds.contains(item.id);
    }).toList();
    final selectedTasks =
        snapshot.isTodayOverview ? snapshot.todayTasks : activeTasks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TodayTasksSection(
          tasks: selectedTasks,
          sourceState: snapshot.sourceStates?.tasks,
          canExecute: canExecute,
          updatingTaskIds: commands.updatingTaskIds,
          onAdd: actions.onOpenPlanner,
          onComplete: actions.onComplete,
          onRestore: actions.onRestore,
          onStartFocus: actions.onStartFocus,
        ),
        const SizedBox(height: AppSpacing.md),
        DashboardInlineExpansionCard(
          key: const ValueKey('today-all-tasks'),
          title: 'Show all tasks',
          subtitle: 'Future, undated, completed, and cancelled tasks',
          expanded: visibility.showAll,
          onToggle: actions.onToggleAll,
          child: _TasksSection(
            activeTasks: activeTasks,
            completedTasks: completedTasks,
            cancelledTasks: cancelledTasks,
            canExecute: canExecute,
            updatingTaskIds: commands.updatingTaskIds,
            showCompletedTasks: visibility.showCompleted,
            showCancelledTasks: visibility.showCancelled,
            onAdd: actions.onOpenPlanner,
            onComplete: actions.onComplete,
            onRestore: actions.onRestore,
            onStartFocus: actions.onStartFocus,
            onToggleCompleted: actions.onToggleCompleted,
            onToggleCancelled: actions.onToggleCancelled,
          ),
        ),
      ],
    );
  }
}

class TodayHabitSection extends StatelessWidget {
  const TodayHabitSection({
    super.key,
    required this.snapshot,
    required this.commands,
    required this.canExecute,
    required this.actions,
  });

  final DashboardSnapshot snapshot;
  final TodayCommandState commands;
  final bool canExecute;
  final TodayHabitActions actions;

  @override
  Widget build(BuildContext context) {
    final habits = snapshot.todayHabits;
    final sourceState = snapshot.sourceStates?.habits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DashboardSectionTitle(
          title: 'Today\'s habits',
          subtitle: 'Scheduled habits and still-open weekly targets.',
        ),
        const SizedBox(height: AppSpacing.md),
        if (sourceState?.status == TodaySourceStatus.unavailable)
          DashboardSectionErrorCard(
            title: 'Habits unavailable',
            message: sourceState?.message ?? 'Habits could not be loaded.',
          )
        else if (habits.isEmpty)
          const DashboardEmptySectionCard(
            icon: AppIcons.checkCircleOutline,
            message: 'No habits need an outcome today.',
          )
        else
          ...habits.map(
            (habit) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _HabitCard(
                habit: habit,
                updating: commands.updatingHabitIds.contains(habit.id),
                outcomeOverride:
                    commands.habitOutcomeOverrides.containsKey(habit.id)
                        ? commands.habitOutcomeOverrides[habit.id]
                        : habit.outcome,
                canExecute: canExecute,
                onSetOutcome: actions.onSetOutcome,
                onUndo: actions.onUndo,
              ),
            ),
          ),
      ],
    );
  }
}

class _TodayTasksSection extends StatelessWidget {
  const _TodayTasksSection({
    required this.tasks,
    required this.sourceState,
    required this.canExecute,
    required this.updatingTaskIds,
    required this.onAdd,
    required this.onComplete,
    required this.onRestore,
    required this.onStartFocus,
  });

  final List<PlanItem> tasks;
  final TodaySourceState? sourceState;
  final bool canExecute;
  final Set<String> updatingTaskIds;
  final VoidCallback onAdd;
  final ValueChanged<PlanItem> onComplete;
  final ValueChanged<PlanItem> onRestore;
  final ValueChanged<PlanItem> onStartFocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashboardSectionTitle(
          title: 'Today\'s tasks',
          subtitle: 'Due, overdue, in-progress, and completed-today tasks.',
          trailing: canExecute
              ? FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(AppIcons.calendarMonthOutlined, size: 18),
                  label: const Text('Open Planner'),
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        if (sourceState?.status == TodaySourceStatus.unavailable)
          DashboardSectionErrorCard(
            title: 'Tasks unavailable',
            message: sourceState?.message ?? 'Tasks could not be loaded.',
          )
        else if (tasks.isEmpty)
          const DashboardEmptySectionCard(
            icon: AppIcons.taskAltOutlined,
            message: 'No due, overdue, or in-progress tasks today.',
          )
        else
          ...tasks.map(
            (task) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _TaskCard(
                task: task,
                isUpdating: updatingTaskIds.contains(task.id),
                isCompleted: task.status == 'done',
                onComplete: canExecute && task.status != 'done'
                    ? () => onComplete(task)
                    : null,
                onRestore: canExecute && task.status == 'done'
                    ? () => onRestore(task)
                    : null,
                onStartFocus: canExecute && task.status != 'done'
                    ? () => onStartFocus(task)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class _TasksSection extends StatelessWidget {
  const _TasksSection({
    required this.activeTasks,
    required this.completedTasks,
    required this.cancelledTasks,
    required this.canExecute,
    required this.updatingTaskIds,
    required this.showCompletedTasks,
    required this.showCancelledTasks,
    required this.onAdd,
    required this.onComplete,
    required this.onRestore,
    required this.onStartFocus,
    required this.onToggleCompleted,
    required this.onToggleCancelled,
  });

  final List<PlanItem> activeTasks;
  final List<PlanItem> completedTasks;
  final List<PlanItem> cancelledTasks;
  final bool canExecute;
  final Set<String> updatingTaskIds;
  final bool showCompletedTasks;
  final bool showCancelledTasks;
  final VoidCallback onAdd;
  final ValueChanged<PlanItem> onComplete;
  final ValueChanged<PlanItem> onRestore;
  final ValueChanged<PlanItem> onStartFocus;
  final VoidCallback onToggleCompleted;
  final VoidCallback onToggleCancelled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashboardSectionTitle(
          title: 'Tasks',
          subtitle: 'Finite actions with durable estimates and deadlines.',
          trailing: canExecute
              ? FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(AppIcons.calendarMonthOutlined, size: 18),
                  label: const Text('Open Planner'),
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        if (activeTasks.isEmpty)
          const DashboardEmptySectionCard(
            icon: AppIcons.taskAltOutlined,
            message: 'No open tasks.',
          )
        else
          ...activeTasks.map(
            (task) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _TaskCard(
                task: task,
                isUpdating: updatingTaskIds.contains(task.id),
                onComplete: canExecute ? () => onComplete(task) : null,
                onStartFocus: canExecute ? () => onStartFocus(task) : null,
              ),
            ),
          ),
        if (completedTasks.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: onToggleCompleted,
            icon: Icon(
              showCompletedTasks ? AppIcons.expandLess : AppIcons.expandMore,
            ),
            label: Text('Completed (${completedTasks.length})'),
          ),
          if (showCompletedTasks)
            ...completedTasks.map(
              (task) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _TaskCard(
                  task: task,
                  isUpdating: updatingTaskIds.contains(task.id),
                  isCompleted: true,
                  onRestore: canExecute ? () => onRestore(task) : null,
                ),
              ),
            ),
        ],
        if (cancelledTasks.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: onToggleCancelled,
            icon: Icon(
              showCancelledTasks ? AppIcons.expandLess : AppIcons.expandMore,
            ),
            label: Text('Cancelled (${cancelledTasks.length})'),
          ),
          if (showCancelledTasks)
            ...cancelledTasks.map(
              (task) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _TaskCard(
                  task: task,
                  isUpdating: updatingTaskIds.contains(task.id),
                  isCancelled: true,
                  onRestore: canExecute ? () => onRestore(task) : null,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _HabitCard extends StatelessWidget {
  const _HabitCard({
    required this.habit,
    required this.updating,
    required this.outcomeOverride,
    required this.canExecute,
    required this.onSetOutcome,
    required this.onUndo,
  });

  final TodayHabit habit;
  final bool updating;
  final String? outcomeOverride;
  final bool canExecute;
  final void Function(TodayHabit habit, HabitOutcome outcome) onSetOutcome;
  final ValueChanged<TodayHabit> onUndo;

  @override
  Widget build(BuildContext context) {
    final completed = outcomeOverride == 'completed';
    final skipped = outcomeOverride == 'skipped';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                completed
                    ? AppIcons.checkCircle
                    : skipped
                        ? AppIcons.skipNextOutlined
                        : AppIcons.radioButtonUnchecked,
                color: completed
                    ? context.visualTokens.success
                    : skipped
                        ? Theme.of(context).colorScheme.tertiary
                        : null,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      [
                        habit.cadenceLabel,
                        if (habit.cadence == 'weekly_target')
                          '${habit.weeklyCompleted}/${habit.weeklyTarget} this week',
                        if (habit.setupManaged) 'Managed in Setup',
                      ].join(' · '),
                    ),
                  ],
                ),
              ),
              if (updating)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (canExecute && !updating) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (outcomeOverride == null) ...[
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        onSetOutcome(habit, HabitOutcome.completed),
                    icon: const Icon(AppIcons.check),
                    label: const Text('Complete'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => onSetOutcome(habit, HabitOutcome.skipped),
                    icon: const Icon(AppIcons.skipNextOutlined),
                    label: const Text('Skip'),
                  ),
                ] else
                  OutlinedButton.icon(
                    onPressed: () => onUndo(habit),
                    icon: const Icon(AppIcons.undo),
                    label: const Text('Undo outcome'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.isUpdating,
    this.isCompleted = false,
    this.isCancelled = false,
    this.onComplete,
    this.onRestore,
    this.onStartFocus,
  });

  final PlanItem task;
  final bool isUpdating;
  final bool isCompleted;
  final bool isCancelled;
  final VoidCallback? onComplete;
  final VoidCallback? onRestore;
  final VoidCallback? onStartFocus;

  @override
  Widget build(BuildContext context) {
    final due = task.deadline == null
        ? null
        : 'Due ${DateFormat.yMMMd().format(task.deadline!)}';
    final estimate =
        task.estimatedMinutes == null ? null : '${task.estimatedMinutes} min';
    return AppCard(
      child: Row(
        children: [
          Icon(
            isCompleted
                ? AppIcons.checkCircle
                : isCancelled
                    ? AppIcons.cancelOutlined
                    : AppIcons.radioButtonUnchecked,
            color: isCompleted || isCancelled
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        decoration: isCompleted || isCancelled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                ),
                if (task.isDeadlinePlanManaged) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Managed by a preparation plan',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  [
                    task.priority,
                    if (estimate != null) estimate,
                    if (due != null) due,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (task.description != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    task.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (isUpdating)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            if (task.isDeadlinePlanManaged) ...[
              if (onStartFocus != null)
                IconButton(
                  tooltip: 'Focus on ${task.title}',
                  onPressed: onStartFocus,
                  icon: const Icon(AppIcons.timerOutlined),
                ),
              if (onRestore != null || onComplete != null)
                IconButton(
                  tooltip: 'Open preparation plan',
                  onPressed: onRestore ?? onComplete,
                  icon: const Icon(AppIcons.arrowForward),
                ),
            ] else ...[
              if (onComplete != null)
                IconButton(
                  tooltip: 'Complete task ${task.title}',
                  onPressed: onComplete,
                  icon: const Icon(AppIcons.check),
                ),
              if (onStartFocus != null)
                IconButton(
                  tooltip: 'Focus on ${task.title}',
                  onPressed: onStartFocus,
                  icon: const Icon(AppIcons.timerOutlined),
                ),
              if (onRestore != null)
                IconButton(
                  tooltip: 'Restore task ${task.title}',
                  onPressed: onRestore,
                  icon: const Icon(AppIcons.undo),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
