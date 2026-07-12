import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../snapshots/presentation/providers/snapshot_providers.dart';
import '../../data/habit_completion_supabase_data_source.dart';
import '../../domain/habit_v1.dart';

class HabitCompletionPage extends ConsumerStatefulWidget {
  const HabitCompletionPage({super.key});

  @override
  ConsumerState<HabitCompletionPage> createState() =>
      _HabitCompletionPageState();
}

class _HabitCompletionPageState extends ConsumerState<HabitCompletionPage> {
  List<HabitV1> _habits = const [];
  final Set<String> _savingHabitIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadHabits);
  }

  @override
  Widget build(BuildContext context) {
    final today = habitDateOnly(DateTime.now());
    return AppPage(
      title: 'Today habits',
      subtitle: 'Complete, intentionally skip, or undo today\'s opportunities',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _isLoading ? null : _loadHabits,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Manage habits',
          onPressed: () => context.go(AppRoutes.habitManagement),
          icon: const Icon(Icons.tune),
        ),
      ],
      children: [
        if (_isLoading)
          const AppCard(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: CircularProgressIndicator(),
              ),
            ),
          )
        else if (_habits.isEmpty)
          const AppCard(
            child: Row(
              children: [
                Icon(Icons.check_circle_outline),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text('No active habit is scheduled for today.'),
                ),
              ],
            ),
          )
        else
          ..._habits.map(
            (habit) => HabitOutcomeTile(
              habit: habit,
              today: today,
              isSaving: _savingHabitIds.contains(habit.id),
              onComplete: () => _setOutcome(
                habit,
                HabitOutcome.completed,
              ),
              onSkip: () => _setOutcome(habit, HabitOutcome.skipped),
              onUndo: () => _undoOutcome(habit),
            ),
          ),
      ],
    );
  }

  Future<void> _loadHabits() async {
    final config = ref.read(appConfigProvider);
    final client = ref.read(supabaseClientProvider);
    if (config.useMockData || client == null) {
      if (mounted) {
        setState(() {
          _habits = const [];
          _isLoading = false;
        });
        if (!config.useMockData) {
          _showMessage('Supabase is not configured.');
        }
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final habits = await HabitCompletionSupabaseDataSource(
        client,
      ).fetchActiveHabits();
      if (mounted) {
        setState(() {
          _habits = habits;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('Could not load today\'s habits.');
      }
    }
  }

  Future<void> _setOutcome(HabitV1 habit, HabitOutcome outcome) async {
    final targetDate = habitDateOnly(DateTime.now());
    final config = ref.read(appConfigProvider);
    final client = ref.read(supabaseClientProvider);
    if (config.useMockData || client == null) {
      _showMessage('Supabase is not configured.');
      return;
    }
    if (_savingHabitIds.contains(habit.id)) {
      return;
    }

    setState(() => _savingHabitIds.add(habit.id));
    try {
      await HabitCompletionSupabaseDataSource(client).setTodayOutcome(
        habitId: habit.id,
        outcome: outcome,
        targetDate: targetDate,
      );
      await ref
          .read(snapshotRefreshServiceProvider)
          .refreshDailyAfterHabitChange(
            targetDate: habitDateKey(targetDate),
          );
      ref.invalidate(dashboardSnapshotProvider);
      await _loadHabits();
      if (mounted) {
        _showMessage(
          outcome == HabitOutcome.completed
              ? 'Habit completed.'
              : 'Habit intentionally skipped.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not save the habit outcome.');
      }
    } finally {
      if (mounted) {
        setState(() => _savingHabitIds.remove(habit.id));
      }
    }
  }

  Future<void> _undoOutcome(HabitV1 habit) async {
    final targetDate = habitDateOnly(DateTime.now());
    final config = ref.read(appConfigProvider);
    final client = ref.read(supabaseClientProvider);
    if (config.useMockData || client == null) {
      _showMessage('Supabase is not configured.');
      return;
    }
    if (_savingHabitIds.contains(habit.id)) {
      return;
    }

    setState(() => _savingHabitIds.add(habit.id));
    try {
      await HabitCompletionSupabaseDataSource(client).undoTodayOutcome(
        habitId: habit.id,
        targetDate: targetDate,
      );
      await ref
          .read(snapshotRefreshServiceProvider)
          .refreshDailyAfterHabitChange(
            targetDate: habitDateKey(targetDate),
          );
      ref.invalidate(dashboardSnapshotProvider);
      await _loadHabits();
      if (mounted) {
        _showMessage('Habit outcome undone.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not undo the habit outcome.');
      }
    } finally {
      if (mounted) {
        setState(() => _savingHabitIds.remove(habit.id));
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class HabitOutcomeTile extends StatelessWidget {
  const HabitOutcomeTile({
    super.key,
    required this.habit,
    required this.today,
    required this.isSaving,
    required this.onComplete,
    required this.onSkip,
    required this.onUndo,
  });

  final HabitV1 habit;
  final DateTime today;
  final bool isSaving;
  final VoidCallback onComplete;
  final VoidCallback onSkip;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final outcome = habit.outcomeOn(today);
    final progress = habit.progressAt(today);
    final completed = outcome == HabitOutcome.completed;
    final skipped = outcome == HabitOutcome.skipped;
    return AppCard(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  completed
                      ? Icons.check_circle
                      : skipped
                          ? Icons.fast_forward_outlined
                          : Icons.radio_button_unchecked,
                  color: outcome == null
                      ? null
                      : Theme.of(context).colorScheme.primary,
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
                      if (habit.description != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          habit.description!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        [
                          habit.cadence.label,
                          if (habit.isSetupManaged) 'Managed in Setup',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ExcludeSemantics(
              child: LinearProgressIndicator(
                value: progress.ratio,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                Text(
                  '${progress.label} completed opportunities',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                if (progress.skipped > 0)
                  Text(
                    '${progress.skipped} skipped',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (progress.missed > 0)
                  Text(
                    '${progress.missed} missed',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                Text(
                  '${progress.streak} streak',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (isSaving)
              const Align(
                alignment: Alignment.centerRight,
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (outcome != null)
              Align(
                alignment: Alignment.centerRight,
                child: Semantics(
                  label: 'Undo habit ${habit.title}',
                  button: true,
                  child: ExcludeSemantics(
                    child: OutlinedButton.icon(
                      onPressed: onUndo,
                      icon: const Icon(Icons.undo),
                      label: Text(
                        skipped ? 'Undo skip' : 'Undo completion',
                      ),
                    ),
                  ),
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Semantics(
                    label: 'Skip habit ${habit.title}',
                    button: true,
                    child: ExcludeSemantics(
                      child: TextButton(
                        onPressed: onSkip,
                        child: const Text('Skip today'),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Semantics(
                    label: 'Complete habit ${habit.title}',
                    button: true,
                    child: ExcludeSemantics(
                      child: FilledButton.icon(
                        onPressed: onComplete,
                        icon: const Icon(Icons.check),
                        label: const Text('Complete today'),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
