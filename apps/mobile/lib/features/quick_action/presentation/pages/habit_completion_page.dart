import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../snapshots/presentation/providers/snapshot_providers.dart';
import '../../data/habit_completion_supabase_data_source.dart';

class HabitCompletionPage extends ConsumerStatefulWidget {
  const HabitCompletionPage({super.key});

  @override
  ConsumerState<HabitCompletionPage> createState() =>
      _HabitCompletionPageState();
}

class _HabitCompletionPageState extends ConsumerState<HabitCompletionPage> {
  List<HabitCompletionOption> _habits = const [];
  final Set<String> _savingHabitIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadHabits);
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Habit completion',
      subtitle: 'Track today\'s consistency signals',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _isLoading ? null : _loadHabits,
          icon: const Icon(Icons.refresh),
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
                  child: Text('No active habits found.'),
                ),
              ],
            ),
          )
        else
          ..._habits.map(
            (habit) => _HabitTile(
              habit: habit,
              isSaving: _savingHabitIds.contains(habit.id),
              onComplete:
                  habit.completedToday ? null : () => _completeHabit(habit.id),
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
        _showMessage('Could not load habits.');
      }
    }
  }

  Future<void> _completeHabit(String habitId) async {
    final config = ref.read(appConfigProvider);
    final client = ref.read(supabaseClientProvider);
    if (config.useMockData || client == null) {
      _showMessage('Supabase is not configured.');
      return;
    }

    setState(() => _savingHabitIds.add(habitId));
    try {
      await HabitCompletionSupabaseDataSource(
        client,
      ).completeHabit(habitId: habitId);
      await ref
          .read(snapshotRefreshServiceProvider)
          .refreshDailyAfterHabitChange();
      ref.invalidate(dashboardSnapshotProvider);

      if (mounted) {
        setState(() {
          _habits = _habits
              .map(
                (habit) => habit.id == habitId
                    ? HabitCompletionOption(
                        id: habit.id,
                        title: habit.title,
                        frequency: habit.frequency,
                        target: habit.target,
                        completedToday: true,
                        description: habit.description,
                      )
                    : habit,
              )
              .toList();
        });
        _showMessage('Habit completed.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not save habit completion.');
      }
    } finally {
      if (mounted) {
        setState(() => _savingHabitIds.remove(habitId));
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _HabitTile extends StatelessWidget {
  const _HabitTile({
    required this.habit,
    required this.isSaving,
    required this.onComplete,
  });

  final HabitCompletionOption habit;
  final bool isSaving;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final completed = habit.completedToday;
    return AppCard(
      child: Row(
        children: [
          Icon(
            completed ? Icons.check_circle : Icons.radio_button_unchecked,
            color: completed ? Theme.of(context).colorScheme.primary : null,
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
                if (habit.description != null &&
                    habit.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    habit.description!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${habit.frequency} target: ${habit.target}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          FilledButton.icon(
            onPressed: isSaving ? null : onComplete,
            icon: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(completed ? Icons.done : Icons.add_task),
            label: Text(completed ? 'Done' : 'Log'),
          ),
        ],
      ),
    );
  }
}
