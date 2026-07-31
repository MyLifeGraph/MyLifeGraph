import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/supabase/supabase_providers.dart';
import '../core/utils/local_date.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import '../features/dashboard/application/today_command_controller.dart';
import 'package:my_life_graph/composition/dashboard_providers.dart';
import '../features/quick_action/data/habit_completion_supabase_data_source.dart';
import '../features/quick_action/domain/habit_v1.dart';
import '../features/tasks/data/task_supabase_data_source.dart';
import '../features/tasks/domain/executable_task.dart';
import 'projection_refresh_providers.dart';

export '../features/dashboard/application/today_command_controller.dart';

final todayCommandControllerProvider = StateNotifierProvider.autoDispose<
    TodayCommandController, TodayCommandState>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    final taskCommands = client == null
        ? null
        : _SupabaseTodayTaskCommands(TaskSupabaseDataSource(client));
    final habitCommands = client == null
        ? null
        : _SupabaseTodayHabitCommands(
            HabitCompletionSupabaseDataSource(
              client,
              todayProvider: ref.watch(profileLocalDateSourceProvider).today,
            ),
          );
    final projectionRefreshCoordinator =
        ref.watch(projectionRefreshCoordinatorProvider);
    return TodayCommandController(
      taskCommands: taskCommands,
      habitCommands: habitCommands,
      dashboardRepository: ref.watch(dashboardRepositoryProvider),
      refreshAfterTask: (targetDate) => projectionRefreshCoordinator
          .todayTaskChanged(targetDate: localDateKey(targetDate)),
      refreshAfterHabit: (targetDate) => projectionRefreshCoordinator
          .todayHabitOutcomeChanged(targetDate: habitDateKey(targetDate)),
      onTodayReloaded: () {
        ref.invalidate(dashboardSupportingSnapshotProvider);
      },
    );
  },
);

class _SupabaseTodayTaskCommands implements TodayTaskCommandPort {
  const _SupabaseTodayTaskCommands(this._source);

  final TaskSupabaseDataSource _source;

  @override
  Future<ExecutableTask> createTask({
    required String taskId,
    required ExecutableTaskDraft draft,
  }) =>
      _source.createTask(taskId: taskId, draft: draft);

  @override
  Future<ExecutableTask> editTask({
    required String taskId,
    required ExecutableTaskDraft draft,
  }) =>
      _source.editTask(taskId: taskId, draft: draft);

  @override
  Future<TaskUndoToken> completeTask(String taskId) =>
      _source.completeTask(taskId);

  @override
  Future<TaskUndoToken> cancelTask(String taskId) => _source.cancelTask(taskId);

  @override
  Future<TaskUndoToken> postponeTask({
    required String taskId,
    required DateTime newDeadline,
  }) =>
      _source.postponeTask(taskId: taskId, newDeadline: newDeadline);

  @override
  Future<ExecutableTask> restoreTask(String taskId) =>
      _source.restoreTask(taskId);

  @override
  Future<ExecutableTask> undo(TaskUndoToken token) => _source.undo(token);
}

class _SupabaseTodayHabitCommands implements TodayHabitCommandPort {
  const _SupabaseTodayHabitCommands(this._source);

  final HabitCompletionSupabaseDataSource _source;

  @override
  Future<void> setOutcome({
    required String habitId,
    required HabitOutcome outcome,
    required DateTime targetDate,
  }) async {
    try {
      await _source.setTodayOutcome(
        habitId: habitId,
        outcome: outcome,
        targetDate: targetDate,
      );
    } on HabitCommandException catch (error) {
      throw TodayHabitCommandFailure(error.message);
    }
  }

  @override
  Future<void> undoOutcome({
    required String habitId,
    required DateTime targetDate,
  }) async {
    try {
      await _source.undoTodayOutcome(
        habitId: habitId,
        targetDate: targetDate,
      );
    } on HabitCommandException catch (error) {
      throw TodayHabitCommandFailure(error.message);
    }
  }
}
