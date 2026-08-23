import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/dashboard/application/today_command_controller.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:my_life_graph/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:my_life_graph/features/quick_action/domain/habit_v1.dart';
import 'package:my_life_graph/features/tasks/domain/executable_task.dart';

void main() {
  const taskId = '10000000-0000-4000-8000-000000000001';
  final targetDate = DateTime(2026, 7, 21);

  test('durable task write becomes stale and reload never repeats the command',
      () async {
    final tasks = _FakeTaskCommands();
    final repository = _SequenceDashboardRepository([
      StateError('first Today reload failed'),
      _snapshot(targetDate),
    ]);
    final refreshedDates = <DateTime>[];
    var supportingReloads = 0;
    final controller = TodayCommandController(
      taskCommands: tasks,
      habitCommands: _FakeHabitCommands(),
      dashboardRepository: repository,
      refreshAfterTask: (date) async => refreshedDates.add(date),
      refreshAfterHabit: (_) async {},
      onTodayReloaded: () => supportingReloads += 1,
    );
    addTearDown(controller.dispose);

    final result = await controller.completeTask(
      taskId: taskId,
      targetDate: targetDate,
    );

    expect(result.committed, isTrue);
    expect(result.projectionCurrent, isFalse);
    expect(tasks.completeCalls, 1);
    expect(refreshedDates, [targetDate]);
    expect(
      controller.state.projectionStatus,
      TodayProjectionStatus.staleAfterMutation,
    );
    expect(controller.state.completedTaskIds, {taskId});
    expect(controller.state.updatingTaskIds, isEmpty);

    expect(await controller.reloadToday(), isTrue);
    expect(tasks.completeCalls, 1);
    expect(repository.calls, 2);
    expect(supportingReloads, 1);
    expect(
      controller.state.projectionStatus,
      TodayProjectionStatus.current,
    );
    expect(controller.state.completedTaskIds, isEmpty);
    expect(controller.state.displayedSnapshot?.localDate, targetDate);
  });

  test(
      'unconfirmed task failure stays uncommitted and leaves projection usable',
      () async {
    final tasks = _FakeTaskCommands(
      completeError: const TaskCommandException(
        'Task result could not be confirmed.',
      ),
    );
    final repository = _SequenceDashboardRepository([_snapshot(targetDate)]);
    var refreshCalls = 0;
    final controller = TodayCommandController(
      taskCommands: tasks,
      habitCommands: _FakeHabitCommands(),
      dashboardRepository: repository,
      refreshAfterTask: (_) async => refreshCalls += 1,
      refreshAfterHabit: (_) async {},
      onTodayReloaded: () {},
    );
    addTearDown(controller.dispose);

    final result = await controller.completeTask(
      taskId: taskId,
      targetDate: targetDate,
    );

    expect(result.accepted, isTrue);
    expect(result.committed, isFalse);
    expect(result.error, isA<TaskCommandException>());
    expect(tasks.completeCalls, 1);
    expect(refreshCalls, 0);
    expect(repository.calls, 0);
    expect(controller.state.projectionStatus, TodayProjectionStatus.current);
    expect(controller.state.completedTaskIds, isEmpty);
    expect(controller.state.updatingTaskIds, isEmpty);
  });

  test('duplicate task command is ignored while the first write is in flight',
      () async {
    final release = Completer<TaskUndoToken>();
    final tasks = _FakeTaskCommands(completeResult: release.future);
    final controller = TodayCommandController(
      taskCommands: tasks,
      habitCommands: _FakeHabitCommands(),
      dashboardRepository:
          _SequenceDashboardRepository([_snapshot(targetDate)]),
      refreshAfterTask: (_) async {},
      refreshAfterHabit: (_) async {},
      onTodayReloaded: () {},
    );
    addTearDown(controller.dispose);

    final first = controller.completeTask(
      taskId: taskId,
      targetDate: targetDate,
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.updatingTaskIds, {taskId});

    final duplicate = await controller.completeTask(
      taskId: taskId,
      targetDate: targetDate,
    );
    expect(duplicate.accepted, isFalse);
    expect(tasks.completeCalls, 1);

    release.complete(_undoToken(taskId));
    expect((await first).projectionCurrent, isTrue);
    expect(controller.state.updatingTaskIds, isEmpty);
  });

  test('committed task refreshes shared projections after Today is disposed',
      () async {
    final release = Completer<TaskUndoToken>();
    final tasks = _FakeTaskCommands(completeResult: release.future);
    final repository = _SequenceDashboardRepository([_snapshot(targetDate)]);
    final refreshedDates = <DateTime>[];
    var supportingReloads = 0;
    final controller = TodayCommandController(
      taskCommands: tasks,
      habitCommands: _FakeHabitCommands(),
      dashboardRepository: repository,
      refreshAfterTask: (date) async => refreshedDates.add(date),
      refreshAfterHabit: (_) async {},
      onTodayReloaded: () => supportingReloads += 1,
    );

    final command = controller.completeTask(
      taskId: taskId,
      targetDate: targetDate,
    );
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    release.complete(_undoToken(taskId));

    final result = await command;
    expect(result.committed, isTrue);
    expect(result.projectionCurrent, isFalse);
    expect(refreshedDates, [targetDate]);
    expect(repository.calls, 0);
    expect(supportingReloads, 0);
  });

  test('every Today task command delegates through the narrow task port',
      () async {
    final tasks = _FakeTaskCommands();
    final repository = _SequenceDashboardRepository(
      List<Object>.filled(6, _snapshot(targetDate)),
    );
    final refreshedDates = <DateTime>[];
    final controller = TodayCommandController(
      taskCommands: tasks,
      habitCommands: _FakeHabitCommands(),
      dashboardRepository: repository,
      refreshAfterTask: (date) async => refreshedDates.add(date),
      refreshAfterHabit: (_) async {},
      onTodayReloaded: () {},
    );
    addTearDown(controller.dispose);
    final draft = ExecutableTaskDraft(title: 'Typed task');
    final deadline = DateTime(2026, 7, 23, 17);

    await controller.createTask(
      taskId: taskId,
      draft: draft,
      targetDate: targetDate,
    );
    await controller.editTask(
      taskId: taskId,
      draft: draft,
      targetDate: targetDate,
    );
    await controller.cancelTask(taskId: taskId, targetDate: targetDate);
    await controller.postponeTask(
      taskId: taskId,
      newDeadline: deadline,
      targetDate: targetDate,
    );
    await controller.restoreTask(taskId: taskId, targetDate: targetDate);
    await controller.undoTask(
      token: _undoToken(taskId),
      targetDate: targetDate,
    );

    expect(tasks.calls, [
      'create:$taskId',
      'edit:$taskId',
      'cancel:$taskId',
      'postpone:$taskId:${deadline.toIso8601String()}',
      'restore:$taskId',
      'undo:$taskId',
    ]);
    expect(refreshedDates, List<DateTime>.filled(6, targetDate));
    expect(repository.calls, 6);
    expect(controller.state.projectionStatus, TodayProjectionStatus.current);
  });

  test('habit write retains its optimistic outcome when Today reload fails',
      () async {
    final habits = _FakeHabitCommands();
    final repository = _SequenceDashboardRepository([
      StateError('Today failed'),
    ]);
    final refreshedDates = <DateTime>[];
    final controller = TodayCommandController(
      taskCommands: _FakeTaskCommands(),
      habitCommands: habits,
      dashboardRepository: repository,
      refreshAfterTask: (_) async {},
      refreshAfterHabit: (date) async => refreshedDates.add(date),
      onTodayReloaded: () {},
    );
    addTearDown(controller.dispose);

    final result = await controller.setHabitOutcome(
      habitId: 'habit-1',
      outcome: HabitOutcome.skipped,
      targetDate: targetDate,
    );

    expect(result.committed, isTrue);
    expect(result.projectionCurrent, isFalse);
    expect(habits.outcomeCalls, 1);
    expect(habits.targetDates, [targetDate]);
    expect(refreshedDates, [targetDate]);
    expect(controller.state.habitOutcomeOverrides, {
      'habit-1': HabitOutcome.skipped.code,
    });
    expect(
      controller.state.projectionStatus,
      TodayProjectionStatus.staleAfterMutation,
    );
  });

  test('committed habit refreshes shared projections after Today is disposed',
      () async {
    final release = Completer<void>();
    final habits = _FakeHabitCommands(outcomeResult: release.future);
    final repository = _SequenceDashboardRepository([_snapshot(targetDate)]);
    final refreshedDates = <DateTime>[];
    var supportingReloads = 0;
    final controller = TodayCommandController(
      taskCommands: _FakeTaskCommands(),
      habitCommands: habits,
      dashboardRepository: repository,
      refreshAfterTask: (_) async {},
      refreshAfterHabit: (date) async => refreshedDates.add(date),
      onTodayReloaded: () => supportingReloads += 1,
    );

    final command = controller.setHabitOutcome(
      habitId: 'habit-1',
      outcome: HabitOutcome.completed,
      targetDate: targetDate,
    );
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    release.complete();

    final result = await command;
    expect(result.committed, isTrue);
    expect(result.projectionCurrent, isFalse);
    expect(refreshedDates, [targetDate]);
    expect(repository.calls, 0);
    expect(supportingReloads, 0);
  });

  test('missing command ports fail explicitly without touching read state',
      () async {
    final controller = TodayCommandController(
      taskCommands: null,
      habitCommands: null,
      dashboardRepository:
          _SequenceDashboardRepository([_snapshot(targetDate)]),
      refreshAfterTask: (_) async {},
      refreshAfterHabit: (_) async {},
      onTodayReloaded: () {},
    );
    addTearDown(controller.dispose);

    final taskResult = await controller.restoreTask(
      taskId: taskId,
      targetDate: targetDate,
    );
    final habitResult = await controller.undoHabitOutcome(
      habitId: 'habit-1',
      targetDate: targetDate,
    );

    expect(taskResult.error, isA<TaskCommandException>());
    expect(habitResult.error, isA<TodayHabitCommandFailure>());
    expect(controller.state.projectionStatus, TodayProjectionStatus.current);
    expect(controller.state.updatingTaskIds, isEmpty);
    expect(controller.state.updatingHabitIds, isEmpty);
  });

  test('reload rejects a non-account projection and remains stale', () async {
    final controller = TodayCommandController(
      taskCommands: _FakeTaskCommands(),
      habitCommands: _FakeHabitCommands(),
      dashboardRepository: _SequenceDashboardRepository([
        DashboardSnapshot.empty(
          origin: DashboardOrigin.localDemo,
          loadedAt: DateTime(2026, 7, 21, 10),
        ),
      ]),
      refreshAfterTask: (_) async {},
      refreshAfterHabit: (_) async {},
      onTodayReloaded: () {},
    );
    addTearDown(controller.dispose);

    expect(await controller.reloadToday(), isFalse);
    expect(
      controller.state.projectionStatus,
      TodayProjectionStatus.staleAfterMutation,
    );
    expect(controller.state.displayedSnapshot, isNull);
  });

  test('Dashboard presentation has no concrete Task or Habit data dependency',
      () {
    final source = File(
      'lib/features/dashboard/presentation/pages/dashboard_page.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('/data/')));
    expect(source, isNot(contains('TaskSupabaseDataSource')));
    expect(source, isNot(contains('HabitCompletionSupabaseDataSource')));
    expect(source, isNot(contains('dashboardTaskDataSourceProvider')));
    expect(source, isNot(contains('dashboardHabitDataSourceProvider')));
    expect(source, contains('todayCommandControllerProvider'));
  });
}

DashboardSnapshot _snapshot(DateTime localDate) {
  return DashboardSnapshot(
    origin: DashboardOrigin.account,
    loadedAt: DateTime(2026, 7, 21, 10),
    latestCheckIn: null,
    checkInStreakDays: 0,
    todayPlan: const [],
    scheduleDays: const [],
    localDate: localDate,
    isTodayOverview: true,
  );
}

TaskUndoToken _undoToken(String taskId) {
  return TaskUndoToken(
    taskId: taskId,
    status: ExecutableTaskStatus.todo,
    deadline: null,
    completedAt: null,
    cancelledAt: null,
    expectedUpdatedAt: DateTime.utc(2026, 7, 21, 10),
  );
}

ExecutableTask _task(String taskId) {
  return ExecutableTask(
    id: taskId,
    title: 'Task',
    status: ExecutableTaskStatus.todo,
    priority: ExecutableTaskPriority.medium,
    updatedAt: DateTime.utc(2026, 7, 21, 10),
  );
}

class _FakeTaskCommands implements TodayTaskCommandPort {
  _FakeTaskCommands({
    this.completeError,
    this.completeResult,
  });

  final Object? completeError;
  final Future<TaskUndoToken>? completeResult;
  int completeCalls = 0;
  final List<String> calls = [];

  @override
  Future<TaskUndoToken> completeTask(String taskId) {
    completeCalls += 1;
    final error = completeError;
    if (error != null) return Future.error(error);
    return completeResult ?? Future.value(_undoToken(taskId));
  }

  @override
  Future<TaskUndoToken> cancelTask(String taskId) async {
    calls.add('cancel:$taskId');
    return _undoToken(taskId);
  }

  @override
  Future<ExecutableTask> createTask({
    required String taskId,
    required ExecutableTaskDraft draft,
  }) async {
    calls.add('create:$taskId');
    return _task(taskId);
  }

  @override
  Future<ExecutableTask> editTask({
    required String taskId,
    required ExecutableTaskDraft draft,
  }) async {
    calls.add('edit:$taskId');
    return _task(taskId);
  }

  @override
  Future<TaskUndoToken> postponeTask({
    required String taskId,
    required DateTime newDeadline,
  }) async {
    calls.add('postpone:$taskId:${newDeadline.toIso8601String()}');
    return _undoToken(taskId);
  }

  @override
  Future<ExecutableTask> restoreTask(String taskId) async {
    calls.add('restore:$taskId');
    return _task(taskId);
  }

  @override
  Future<ExecutableTask> undo(TaskUndoToken token) async {
    calls.add('undo:${token.taskId}');
    return _task(token.taskId);
  }
}

class _FakeHabitCommands implements TodayHabitCommandPort {
  _FakeHabitCommands({this.outcomeResult});

  final Future<void>? outcomeResult;
  int outcomeCalls = 0;
  final List<DateTime> targetDates = [];

  @override
  Future<void> setOutcome({
    required String habitId,
    required HabitOutcome outcome,
    required DateTime targetDate,
  }) async {
    outcomeCalls += 1;
    targetDates.add(targetDate);
    await outcomeResult;
  }

  @override
  Future<void> undoOutcome({
    required String habitId,
    required DateTime targetDate,
  }) async {
    targetDates.add(targetDate);
  }
}

class _SequenceDashboardRepository implements DashboardRepository {
  _SequenceDashboardRepository(this._results);

  final List<Object> _results;
  int calls = 0;

  @override
  Future<DashboardSnapshot> getSnapshot() async {
    final result = _results[calls++];
    if (result is DashboardSnapshot) return result;
    throw result;
  }
}
