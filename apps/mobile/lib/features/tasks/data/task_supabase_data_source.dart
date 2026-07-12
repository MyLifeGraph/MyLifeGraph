import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/app_user_resolver.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../core/utils/client_uuid.dart';
import '../domain/executable_task.dart';

typedef TaskNowProvider = DateTime Function();

class TaskSupabaseDataSource {
  TaskSupabaseDataSource(
    this._client, {
    TaskNowProvider? nowProvider,
  }) : _nowProvider = nowProvider ?? DateTime.now;

  static const _columns =
      'id,title,description,status,priority,deadline,estimated_minutes,'
      'completed_at,cancelled_at,updated_at';

  final SupabaseClient _client;
  final TaskNowProvider _nowProvider;

  Future<List<ExecutableTask>> fetchTasks({int limit = 100}) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final rows = await _client
        .from(SupabaseTables.tasks)
        .select(_columns)
        .eq('user_id', userId)
        .order('deadline', ascending: true)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List)
        .map(ExecutableTask.fromRow)
        .toList();
  }

  Future<ExecutableTask> createTask({
    required String taskId,
    required ExecutableTaskDraft draft,
  }) async {
    draft.validate();
    if (!isClientUuid(taskId)) {
      throw const TaskCommandException('Task request identity is invalid.');
    }
    final userId = await AppUserResolver(_client).resolveUserId();
    final now = _timestamp(_nowProvider());
    final row = await _client
        .from(SupabaseTables.tasks)
        .upsert(
          {
            'id': taskId,
            'user_id': userId,
            'title': draft.title,
            'description': draft.description,
            'status': ExecutableTaskStatus.todo.code,
            'priority': draft.priority.code,
            'deadline': _optionalTimestamp(draft.deadline),
            'estimated_minutes': draft.estimatedMinutes,
            'source': 'flutter-task-v1',
            'metadata': const {
              'source': 'flutter-task-v1',
              'contract_version': 'executable-task-v1',
            },
            'updated_at': now,
          },
          onConflict: 'id',
        )
        .select(_columns)
        .single();
    return ExecutableTask.fromRow(Map<String, dynamic>.from(row));
  }

  Future<ExecutableTask> editTask({
    required String taskId,
    required ExecutableTaskDraft draft,
  }) async {
    draft.validate();
    final task = await _requireOwnedTask(taskId);
    if (task.status == ExecutableTaskStatus.archived ||
        task.status == ExecutableTaskStatus.cancelled) {
      throw const TaskCommandException('This task cannot be edited.');
    }
    return _updateOwnedTask(
      taskId,
      {
        'title': draft.title,
        'description': draft.description,
        'priority': draft.priority.code,
        'deadline': _optionalTimestamp(draft.deadline),
        'estimated_minutes': draft.estimatedMinutes,
      },
      expectedUpdatedAt: task.updatedAt,
      mutationAt: _nextMutationAt(task.updatedAt),
    );
  }

  Future<TaskUndoToken> completeTask(String taskId) async {
    final task = await _requireOwnedTask(taskId);
    if (task.status == ExecutableTaskStatus.done) {
      throw const TaskCommandException('This task is already completed.');
    }
    if (!task.isOpen) {
      throw const TaskCommandException('This task cannot be completed.');
    }
    final mutationAt = _nextMutationAt(task.updatedAt);
    late final ExecutableTask updated;
    try {
      updated = await _updateOwnedTask(
        taskId,
        {
          'status': ExecutableTaskStatus.done.code,
          'completed_at': _timestamp(mutationAt),
          'cancelled_at': null,
        },
        expectedUpdatedAt: task.updatedAt,
        mutationAt: mutationAt,
      );
    } catch (_) {
      final reconciled = await _readMatchingAmbiguousWrite(
        taskId: taskId,
        mutationAt: mutationAt,
        matches: (current) =>
            current.status == ExecutableTaskStatus.done &&
            _sameInstant(current.completedAt, mutationAt) &&
            current.cancelledAt == null,
      );
      if (reconciled == null) {
        rethrow;
      }
      updated = reconciled;
    }
    return TaskUndoToken.forTransition(previous: task, current: updated);
  }

  Future<TaskUndoToken> cancelTask(String taskId) async {
    final task = await _requireOwnedTask(taskId);
    if (task.status == ExecutableTaskStatus.cancelled) {
      throw const TaskCommandException('This task is already cancelled.');
    }
    if (!task.isOpen) {
      throw const TaskCommandException('This task cannot be cancelled.');
    }
    final mutationAt = _nextMutationAt(task.updatedAt);
    late final ExecutableTask updated;
    try {
      updated = await _updateOwnedTask(
        taskId,
        {
          'status': ExecutableTaskStatus.cancelled.code,
          'cancelled_at': _timestamp(mutationAt),
          'completed_at': null,
        },
        expectedUpdatedAt: task.updatedAt,
        mutationAt: mutationAt,
      );
    } catch (_) {
      final reconciled = await _readMatchingAmbiguousWrite(
        taskId: taskId,
        mutationAt: mutationAt,
        matches: (current) =>
            current.status == ExecutableTaskStatus.cancelled &&
            _sameInstant(current.cancelledAt, mutationAt) &&
            current.completedAt == null,
      );
      if (reconciled == null) {
        rethrow;
      }
      updated = reconciled;
    }
    return TaskUndoToken.forTransition(previous: task, current: updated);
  }

  Future<TaskUndoToken> postponeTask({
    required String taskId,
    required DateTime newDeadline,
  }) async {
    final task = await _requireOwnedTask(taskId);
    if (!task.isOpen) {
      throw const TaskCommandException('This task cannot be postponed.');
    }
    if (task.deadline == newDeadline) {
      throw const TaskCommandException(
        'This task already has that deadline.',
      );
    }
    validateTaskPostpone(
      currentDeadline: task.deadline,
      newDeadline: newDeadline,
      now: _nowProvider(),
    );
    final mutationAt = _nextMutationAt(task.updatedAt);
    late final ExecutableTask updated;
    try {
      updated = await _updateOwnedTask(
        taskId,
        {'deadline': _timestamp(newDeadline)},
        expectedUpdatedAt: task.updatedAt,
        mutationAt: mutationAt,
      );
    } catch (_) {
      final reconciled = await _readMatchingAmbiguousWrite(
        taskId: taskId,
        mutationAt: mutationAt,
        matches: (current) => _sameInstant(current.deadline, newDeadline),
      );
      if (reconciled == null) {
        rethrow;
      }
      updated = reconciled;
    }
    return TaskUndoToken.forTransition(previous: task, current: updated);
  }

  Future<ExecutableTask> restoreTask(String taskId) async {
    final task = await _requireOwnedTask(taskId);
    if (task.status == ExecutableTaskStatus.todo) {
      return task;
    }
    if (task.status != ExecutableTaskStatus.done &&
        task.status != ExecutableTaskStatus.cancelled) {
      throw const TaskCommandException('This task cannot be restored.');
    }
    return _updateOwnedTask(
      taskId,
      {
        'status': ExecutableTaskStatus.todo.code,
        'completed_at': null,
        'cancelled_at': null,
      },
      expectedUpdatedAt: task.updatedAt,
      mutationAt: _nextMutationAt(task.updatedAt),
    );
  }

  Future<ExecutableTask> undo(TaskUndoToken token) {
    return _updateOwnedTask(
      token.taskId,
      {
        'status': token.status.code,
        'deadline': _optionalTimestamp(token.deadline),
        'completed_at': _optionalTimestamp(token.completedAt),
        'cancelled_at': _optionalTimestamp(token.cancelledAt),
      },
      expectedUpdatedAt: token.expectedUpdatedAt,
      mutationAt: _nextMutationAt(token.expectedUpdatedAt),
    );
  }

  Future<ExecutableTask> _requireOwnedTask(String taskId) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final row = await _client
        .from(SupabaseTables.tasks)
        .select(_columns)
        .eq('id', taskId)
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) {
      throw const TaskCommandException('Task is unavailable.');
    }
    return ExecutableTask.fromRow(Map<String, dynamic>.from(row));
  }

  Future<ExecutableTask> _updateOwnedTask(
    String taskId,
    Map<String, dynamic> values, {
    required DateTime expectedUpdatedAt,
    required DateTime mutationAt,
  }) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    List<Map<String, dynamic>> typedRows;
    try {
      final rows = await _client
          .from(SupabaseTables.tasks)
          .update({
            ...values,
            'updated_at': _timestamp(mutationAt),
          })
          .eq('id', taskId)
          .eq('user_id', userId)
          .eq('updated_at', _timestamp(expectedUpdatedAt))
          .select(_columns);
      typedRows = List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      final reconciled = await _readMatchingTaskMutation(
        userId: userId,
        taskId: taskId,
        values: values,
        mutationAt: mutationAt,
      );
      if (reconciled == null) {
        rethrow;
      }
      return ExecutableTask.fromRow(reconciled);
    }
    if (typedRows.length != 1) {
      final reconciled = await _readMatchingTaskMutation(
        userId: userId,
        taskId: taskId,
        values: values,
        mutationAt: mutationAt,
      );
      if (reconciled != null) {
        return ExecutableTask.fromRow(reconciled);
      }
      throw const TaskCommandException(
        'Task changed elsewhere. Reload before retrying.',
      );
    }
    return ExecutableTask.fromRow(typedRows.single);
  }

  Future<Map<String, dynamic>?> _readMatchingTaskMutation({
    required String userId,
    required String taskId,
    required Map<String, dynamic> values,
    required DateTime mutationAt,
  }) async {
    try {
      final row = await _client
          .from(SupabaseTables.tasks)
          .select(_columns)
          .eq('id', taskId)
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) {
        return null;
      }
      final typedRow = Map<String, dynamic>.from(row);
      final updatedAt = DateTime.tryParse(
        typedRow['updated_at']?.toString() ?? '',
      );
      if (updatedAt == null || !updatedAt.isAtSameMomentAs(mutationAt)) {
        return null;
      }
      for (final entry in values.entries) {
        if (!_taskValueMatches(
          key: entry.key,
          actual: typedRow[entry.key],
          expected: entry.value,
        )) {
          return null;
        }
      }
      return typedRow;
    } catch (_) {
      return null;
    }
  }

  Future<ExecutableTask?> _readMatchingAmbiguousWrite({
    required String taskId,
    required DateTime mutationAt,
    required bool Function(ExecutableTask task) matches,
  }) async {
    try {
      final current = await _requireOwnedTask(taskId);
      if (current.updatedAt.isAtSameMomentAs(mutationAt) && matches(current)) {
        return current;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  DateTime _nextMutationAt(DateTime expectedUpdatedAt) {
    final now = _nowProvider();
    return now.isAfter(expectedUpdatedAt)
        ? now
        : expectedUpdatedAt.add(const Duration(microseconds: 1));
  }

  static bool _sameInstant(DateTime? left, DateTime right) =>
      left?.isAtSameMomentAs(right) ?? false;

  static bool _taskValueMatches({
    required String key,
    required Object? actual,
    required Object? expected,
  }) {
    if (const {'deadline', 'completed_at', 'cancelled_at'}.contains(key)) {
      if (actual == null || expected == null) {
        return actual == null && expected == null;
      }
      final actualTimestamp = DateTime.tryParse(actual.toString());
      final expectedTimestamp = DateTime.tryParse(expected.toString());
      return actualTimestamp != null &&
          expectedTimestamp != null &&
          actualTimestamp.isAtSameMomentAs(expectedTimestamp);
    }
    return actual == expected;
  }

  static String _timestamp(DateTime value) => value.toUtc().toIso8601String();

  static String? _optionalTimestamp(DateTime? value) =>
      value == null ? null : _timestamp(value);
}
