import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../quick_action/domain/habit_v1.dart';
import '../../tasks/domain/executable_task.dart';
import '../domain/entities/dashboard_snapshot.dart';
import '../domain/repositories/dashboard_repository.dart';

typedef TodayProjectionRefresh = Future<void> Function(DateTime targetDate);

abstract interface class TodayTaskCommandPort {
  Future<ExecutableTask> createTask({
    required String taskId,
    required ExecutableTaskDraft draft,
  });

  Future<ExecutableTask> editTask({
    required String taskId,
    required ExecutableTaskDraft draft,
  });

  Future<TaskUndoToken> completeTask(String taskId);

  Future<TaskUndoToken> cancelTask(String taskId);

  Future<TaskUndoToken> postponeTask({
    required String taskId,
    required DateTime newDeadline,
  });

  Future<ExecutableTask> restoreTask(String taskId);

  Future<ExecutableTask> undo(TaskUndoToken token);
}

abstract interface class TodayHabitCommandPort {
  Future<void> setOutcome({
    required String habitId,
    required HabitOutcome outcome,
    required DateTime targetDate,
  });

  Future<void> undoOutcome({
    required String habitId,
    required DateTime targetDate,
  });
}

class TodayHabitCommandFailure implements Exception {
  const TodayHabitCommandFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

enum TodayProjectionStatus {
  current,
  refreshingAfterMutation,
  staleAfterMutation,
}

class TodayCommandState {
  TodayCommandState({
    required this.projectionStatus,
    required this.displayedSnapshot,
    required Set<String> completedTaskIds,
    required Set<String> restoredTaskIds,
    required Set<String> deletedTaskIds,
    required Set<String> updatingTaskIds,
    required Set<String> updatingHabitIds,
    required Map<String, String?> habitOutcomeOverrides,
  })  : completedTaskIds = Set.unmodifiable(completedTaskIds),
        restoredTaskIds = Set.unmodifiable(restoredTaskIds),
        deletedTaskIds = Set.unmodifiable(deletedTaskIds),
        updatingTaskIds = Set.unmodifiable(updatingTaskIds),
        updatingHabitIds = Set.unmodifiable(updatingHabitIds),
        habitOutcomeOverrides = Map.unmodifiable(habitOutcomeOverrides);

  factory TodayCommandState.initial() => TodayCommandState(
        projectionStatus: TodayProjectionStatus.current,
        displayedSnapshot: null,
        completedTaskIds: const {},
        restoredTaskIds: const {},
        deletedTaskIds: const {},
        updatingTaskIds: const {},
        updatingHabitIds: const {},
        habitOutcomeOverrides: const {},
      );

  final TodayProjectionStatus projectionStatus;
  final DashboardSnapshot? displayedSnapshot;
  final Set<String> completedTaskIds;
  final Set<String> restoredTaskIds;
  final Set<String> deletedTaskIds;
  final Set<String> updatingTaskIds;
  final Set<String> updatingHabitIds;
  final Map<String, String?> habitOutcomeOverrides;

  bool get canMutate => projectionStatus == TodayProjectionStatus.current;

  TodayCommandState copyWith({
    TodayProjectionStatus? projectionStatus,
    Object? displayedSnapshot = _unset,
    Set<String>? completedTaskIds,
    Set<String>? restoredTaskIds,
    Set<String>? deletedTaskIds,
    Set<String>? updatingTaskIds,
    Set<String>? updatingHabitIds,
    Map<String, String?>? habitOutcomeOverrides,
  }) {
    return TodayCommandState(
      projectionStatus: projectionStatus ?? this.projectionStatus,
      displayedSnapshot: identical(displayedSnapshot, _unset)
          ? this.displayedSnapshot
          : displayedSnapshot as DashboardSnapshot?,
      completedTaskIds: completedTaskIds ?? this.completedTaskIds,
      restoredTaskIds: restoredTaskIds ?? this.restoredTaskIds,
      deletedTaskIds: deletedTaskIds ?? this.deletedTaskIds,
      updatingTaskIds: updatingTaskIds ?? this.updatingTaskIds,
      updatingHabitIds: updatingHabitIds ?? this.updatingHabitIds,
      habitOutcomeOverrides:
          habitOutcomeOverrides ?? this.habitOutcomeOverrides,
    );
  }
}

class TodayCommandResult<T> {
  const TodayCommandResult._({
    required this.accepted,
    required this.committed,
    required this.projectionCurrent,
    this.value,
    this.error,
  });

  const TodayCommandResult.ignored()
      : this._(
          accepted: false,
          committed: false,
          projectionCurrent: false,
        );

  TodayCommandResult.failed(Object error)
      : this._(
          accepted: true,
          committed: false,
          projectionCurrent: false,
          error: error,
        );

  TodayCommandResult.saved({
    required bool projectionCurrent,
    T? value,
  }) : this._(
          accepted: true,
          committed: true,
          projectionCurrent: projectionCurrent,
          value: value,
        );

  final bool accepted;
  final bool committed;
  final bool projectionCurrent;
  final T? value;
  final Object? error;
}

class TodayCommandController extends StateNotifier<TodayCommandState> {
  TodayCommandController({
    required TodayTaskCommandPort? taskCommands,
    required TodayHabitCommandPort? habitCommands,
    required DashboardRepository dashboardRepository,
    required TodayProjectionRefresh refreshAfterTask,
    required TodayProjectionRefresh refreshAfterHabit,
    required void Function() onTodayReloaded,
  })  : _taskCommands = taskCommands,
        _habitCommands = habitCommands,
        _dashboardRepository = dashboardRepository,
        _refreshAfterTask = refreshAfterTask,
        _refreshAfterHabit = refreshAfterHabit,
        _onTodayReloaded = onTodayReloaded,
        super(TodayCommandState.initial());

  final TodayTaskCommandPort? _taskCommands;
  final TodayHabitCommandPort? _habitCommands;
  final DashboardRepository _dashboardRepository;
  final TodayProjectionRefresh _refreshAfterTask;
  final TodayProjectionRefresh _refreshAfterHabit;
  final void Function() _onTodayReloaded;

  Future<TodayCommandResult<void>> setHabitOutcome({
    required String habitId,
    required HabitOutcome outcome,
    required DateTime targetDate,
  }) {
    return _runHabit(
      habitId: habitId,
      targetDate: targetDate,
      optimisticOutcome: outcome.code,
      mutation: (commands) => commands.setOutcome(
        habitId: habitId,
        outcome: outcome,
        targetDate: targetDate,
      ),
    );
  }

  Future<TodayCommandResult<void>> undoHabitOutcome({
    required String habitId,
    required DateTime targetDate,
  }) {
    return _runHabit(
      habitId: habitId,
      targetDate: targetDate,
      optimisticOutcome: null,
      mutation: (commands) => commands.undoOutcome(
        habitId: habitId,
        targetDate: targetDate,
      ),
    );
  }

  Future<TodayCommandResult<ExecutableTask>> createTask({
    required String taskId,
    required ExecutableTaskDraft draft,
    required DateTime targetDate,
  }) {
    return _runTask(
      taskId: taskId,
      targetDate: targetDate,
      mutation: (commands) => commands.createTask(
        taskId: taskId,
        draft: draft,
      ),
    );
  }

  Future<TodayCommandResult<ExecutableTask>> editTask({
    required String taskId,
    required ExecutableTaskDraft draft,
    required DateTime targetDate,
  }) {
    return _runTask(
      taskId: taskId,
      targetDate: targetDate,
      mutation: (commands) => commands.editTask(
        taskId: taskId,
        draft: draft,
      ),
    );
  }

  Future<TodayCommandResult<TaskUndoToken>> completeTask({
    required String taskId,
    required DateTime targetDate,
  }) {
    return _runTask(
      taskId: taskId,
      targetDate: targetDate,
      optimisticStatus: ExecutableTaskStatus.done.code,
      mutation: (commands) => commands.completeTask(taskId),
    );
  }

  Future<TodayCommandResult<TaskUndoToken>> cancelTask({
    required String taskId,
    required DateTime targetDate,
  }) {
    return _runTask(
      taskId: taskId,
      targetDate: targetDate,
      optimisticStatus: ExecutableTaskStatus.cancelled.code,
      mutation: (commands) => commands.cancelTask(taskId),
    );
  }

  Future<TodayCommandResult<TaskUndoToken>> postponeTask({
    required String taskId,
    required DateTime newDeadline,
    required DateTime targetDate,
  }) {
    return _runTask(
      taskId: taskId,
      targetDate: targetDate,
      optimisticStatus: ExecutableTaskStatus.todo.code,
      mutation: (commands) => commands.postponeTask(
        taskId: taskId,
        newDeadline: newDeadline,
      ),
    );
  }

  Future<TodayCommandResult<ExecutableTask>> restoreTask({
    required String taskId,
    required DateTime targetDate,
  }) {
    return _runTask(
      taskId: taskId,
      targetDate: targetDate,
      optimisticStatus: ExecutableTaskStatus.todo.code,
      mutation: (commands) => commands.restoreTask(taskId),
    );
  }

  Future<TodayCommandResult<ExecutableTask>> undoTask({
    required TaskUndoToken token,
    required DateTime targetDate,
  }) {
    return _runTask(
      taskId: token.taskId,
      targetDate: targetDate,
      optimisticStatus: token.status.code,
      mutation: (commands) => commands.undo(token),
    );
  }

  Future<bool> reloadToday() async {
    if (!mounted ||
        state.projectionStatus ==
            TodayProjectionStatus.refreshingAfterMutation) {
      return false;
    }
    state = state.copyWith(
      projectionStatus: TodayProjectionStatus.refreshingAfterMutation,
    );
    return _loadFreshProjection();
  }

  Future<TodayCommandResult<void>> _runHabit({
    required String habitId,
    required DateTime targetDate,
    required String? optimisticOutcome,
    required Future<void> Function(TodayHabitCommandPort commands) mutation,
  }) async {
    if (!mounted ||
        !state.canMutate ||
        state.updatingHabitIds.contains(habitId)) {
      return const TodayCommandResult.ignored();
    }
    _setHabitUpdating(habitId, true);
    try {
      final commands = _habitCommands;
      if (commands == null) {
        throw const TodayHabitCommandFailure(
          'Synced habits are unavailable.',
        );
      }
      await mutation(commands);
      if (mounted) {
        final overrides = Map<String, String?>.from(
          state.habitOutcomeOverrides,
        )..[habitId] = optimisticOutcome;
        state = state.copyWith(
          projectionStatus: TodayProjectionStatus.refreshingAfterMutation,
          habitOutcomeOverrides: overrides,
        );
      }
      final projectionCurrent = await _refreshAfterMutation(
        targetDate: targetDate,
        refreshProjection: _refreshAfterHabit,
      );
      return TodayCommandResult.saved(
        projectionCurrent: projectionCurrent,
      );
    } catch (error) {
      return TodayCommandResult.failed(error);
    } finally {
      if (mounted) _setHabitUpdating(habitId, false);
    }
  }

  Future<TodayCommandResult<T>> _runTask<T>({
    required String taskId,
    required DateTime targetDate,
    required Future<T> Function(TodayTaskCommandPort commands) mutation,
    String? optimisticStatus,
  }) async {
    if (!mounted ||
        !state.canMutate ||
        state.updatingTaskIds.contains(taskId)) {
      return const TodayCommandResult.ignored();
    }
    _setTaskUpdating(taskId, true);
    try {
      final commands = _taskCommands;
      if (commands == null) {
        throw const TaskCommandException('Synced tasks are unavailable.');
      }
      final value = await mutation(commands);
      if (mounted) {
        if (optimisticStatus != null) {
          _applyLocalTaskStatus(taskId, optimisticStatus);
        } else {
          state = state.copyWith(
            projectionStatus: TodayProjectionStatus.refreshingAfterMutation,
          );
        }
      }
      final projectionCurrent = await _refreshAfterMutation(
        targetDate: targetDate,
        refreshProjection: _refreshAfterTask,
      );
      return TodayCommandResult.saved(
        value: value,
        projectionCurrent: projectionCurrent,
      );
    } catch (error) {
      return TodayCommandResult.failed(error);
    } finally {
      if (mounted) _setTaskUpdating(taskId, false);
    }
  }

  Future<bool> _refreshAfterMutation({
    required DateTime targetDate,
    required TodayProjectionRefresh refreshProjection,
  }) async {
    try {
      await refreshProjection(targetDate);
      if (!mounted) return false;
      return _loadFreshProjection();
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          projectionStatus: TodayProjectionStatus.staleAfterMutation,
        );
      }
      return false;
    }
  }

  Future<bool> _loadFreshProjection() async {
    try {
      final fresh = await _dashboardRepository.getSnapshot();
      if (fresh.origin != DashboardOrigin.account || fresh.localDate == null) {
        throw const DashboardUnavailableException(
          'Authenticated Today projection is incomplete.',
        );
      }
      if (!mounted) return false;
      state = state.copyWith(
        projectionStatus: TodayProjectionStatus.current,
        displayedSnapshot: fresh,
        completedTaskIds: const {},
        restoredTaskIds: const {},
        deletedTaskIds: const {},
        habitOutcomeOverrides: const {},
      );
      _onTodayReloaded();
      return true;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          projectionStatus: TodayProjectionStatus.staleAfterMutation,
        );
      }
      return false;
    }
  }

  void _setTaskUpdating(String taskId, bool updating) {
    final values = Set<String>.from(state.updatingTaskIds);
    if (updating) {
      values.add(taskId);
    } else {
      values.remove(taskId);
    }
    state = state.copyWith(updatingTaskIds: values);
  }

  void _setHabitUpdating(String habitId, bool updating) {
    final values = Set<String>.from(state.updatingHabitIds);
    if (updating) {
      values.add(habitId);
    } else {
      values.remove(habitId);
    }
    state = state.copyWith(updatingHabitIds: values);
  }

  void _applyLocalTaskStatus(String taskId, String status) {
    final completed = Set<String>.from(state.completedTaskIds)..remove(taskId);
    final restored = Set<String>.from(state.restoredTaskIds)..remove(taskId);
    final deleted = Set<String>.from(state.deletedTaskIds)..remove(taskId);
    switch (status) {
      case 'done':
        completed.add(taskId);
      case 'todo':
        restored.add(taskId);
      case 'cancelled':
        deleted.add(taskId);
    }
    state = state.copyWith(
      projectionStatus: TodayProjectionStatus.refreshingAfterMutation,
      completedTaskIds: completed,
      restoredTaskIds: restored,
      deletedTaskIds: deleted,
    );
  }
}

const _unset = Object();
