import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/tasks/domain/executable_task.dart';

void main() {
  group('ExecutableTask enums and state', () {
    test('status parser accepts exact codes and rejects unknown values', () {
      for (final status in ExecutableTaskStatus.values) {
        expect(ExecutableTaskStatus.fromCode(status.code), status);
      }

      expect(ExecutableTaskStatus.fromCode('TODO'), isNull);
      expect(ExecutableTaskStatus.fromCode('unknown'), isNull);
      expect(ExecutableTaskStatus.fromCode(null), isNull);
    });

    test('priority parser accepts exact codes and rejects unknown values', () {
      for (final priority in ExecutableTaskPriority.values) {
        expect(ExecutableTaskPriority.fromCode(priority.code), priority);
      }

      expect(ExecutableTaskPriority.fromCode('MEDIUM'), isNull);
      expect(ExecutableTaskPriority.fromCode('unknown'), isNull);
      expect(ExecutableTaskPriority.fromCode(null), isNull);
    });

    test('open and terminal status classifications are exhaustive', () {
      const expected = <ExecutableTaskStatus, (bool, bool)>{
        ExecutableTaskStatus.todo: (true, false),
        ExecutableTaskStatus.inProgress: (true, false),
        ExecutableTaskStatus.done: (false, true),
        ExecutableTaskStatus.cancelled: (false, true),
        ExecutableTaskStatus.archived: (false, true),
      };

      for (final status in ExecutableTaskStatus.values) {
        final task = _task(status: status);
        expect(task.isOpen, expected[status]!.$1, reason: status.code);
        expect(task.isTerminal, expected[status]!.$2, reason: status.code);
      }
    });
  });

  group('ExecutableTask.fromRow', () {
    test('parses and normalizes every supported field', () {
      final task = ExecutableTask.fromRow({
        'id': '  task-123  ',
        'title': '  Prepare launch  ',
        'description': '  Write the rollout checklist.  ',
        'status': 'in_progress',
        'priority': 'critical',
        'deadline': '2026-07-12T09:30:00+02:00',
        'estimated_minutes': 45.0,
        'completed_at': '2026-07-11T07:00:00Z',
        'cancelled_at': '2026-07-11T08:00:00Z',
        'updated_at': '2026-07-11T08:30:00Z',
      });

      expect(task.id, 'task-123');
      expect(task.title, 'Prepare launch');
      expect(task.description, 'Write the rollout checklist.');
      expect(task.status, ExecutableTaskStatus.inProgress);
      expect(task.priority, ExecutableTaskPriority.critical);
      expect(
        task.deadline,
        DateTime.parse('2026-07-12T09:30:00+02:00'),
      );
      expect(task.estimatedMinutes, 45);
      expect(task.completedAt, DateTime.parse('2026-07-11T07:00:00Z'));
      expect(task.cancelledAt, DateTime.parse('2026-07-11T08:00:00Z'));
      expect(task.updatedAt, DateTime.parse('2026-07-11T08:30:00Z'));
    });

    test('normalizes blank optional descriptions and nullable fields', () {
      final task = ExecutableTask.fromRow({
        'id': 'task-123',
        'title': 'Prepare launch',
        'description': '   ',
        'status': 'todo',
        'priority': 'medium',
        'deadline': null,
        'estimated_minutes': null,
        'completed_at': null,
        'cancelled_at': null,
        'updated_at': '2026-07-11T08:30:00Z',
      });

      expect(task.description, isNull);
      expect(task.deadline, isNull);
      expect(task.estimatedMinutes, isNull);
      expect(task.completedAt, isNull);
      expect(task.cancelledAt, isNull);
    });

    test('rejects missing or malformed required row fields', () {
      for (final override in <Map<String, Object?>>[
        {'id': null},
        {'id': ''},
        {'id': '   '},
        {'id': 123},
        {'title': null},
        {'title': ''},
        {'title': '   '},
        {'title': 123},
        {'status': null},
        {'status': 'unknown'},
        {'priority': null},
        {'priority': 'urgent'},
      ]) {
        expect(
          () => ExecutableTask.fromRow(_validRow()..addAll(override)),
          throwsA(isA<TaskCommandException>()),
          reason: '$override must be rejected',
        );
      }
    });

    test('rejects invalid optional field types and timestamps', () {
      for (final override in <Map<String, Object?>>[
        {'description': 123},
        {'deadline': 'not-a-timestamp'},
        {'completed_at': 'tomorrow'},
        {'cancelled_at': ''},
        {'updated_at': null},
        {'updated_at': 'tomorrow'},
        {'estimated_minutes': '30'},
        {'estimated_minutes': 30.5},
        {'estimated_minutes': true},
      ]) {
        expect(
          () => ExecutableTask.fromRow(_validRow()..addAll(override)),
          throwsA(isA<TaskCommandException>()),
          reason: '$override must be rejected',
        );
      }
    });

    test('parses every supported status and priority combination', () {
      for (final status in ExecutableTaskStatus.values) {
        for (final priority in ExecutableTaskPriority.values) {
          final task = ExecutableTask.fromRow(
            _validRow()
              ..['status'] = status.code
              ..['priority'] = priority.code,
          );

          expect(task.status, status);
          expect(task.priority, priority);
        }
      }
    });
  });

  group('ExecutableTaskDraft', () {
    test('normalizes text and defaults priority to medium', () {
      final draft = ExecutableTaskDraft(
        title: '  Prepare launch  ',
        description: '  Write the rollout checklist.  ',
      );

      expect(draft.title, 'Prepare launch');
      expect(draft.description, 'Write the rollout checklist.');
      expect(draft.priority, ExecutableTaskPriority.medium);
      expect(draft.deadline, isNull);
      expect(draft.estimatedMinutes, isNull);
    });

    test('normalizes a blank description to absent', () {
      final draft = ExecutableTaskDraft(
        title: 'Prepare launch',
        description: '   ',
      );

      expect(draft.description, isNull);
    });

    test('accepts exact title, description, and estimate boundaries', () {
      for (final title in ['x', 'x' * 160]) {
        for (final description in <String?>[null, 'x', 'x' * 2000]) {
          for (final estimate in <int?>[null, 5, 480]) {
            expect(
              () => ExecutableTaskDraft(
                title: title,
                description: description,
                estimatedMinutes: estimate,
              ),
              returnsNormally,
            );
          }
        }
      }
    });

    test('rejects title, description, and estimate outside boundaries', () {
      for (final title in ['', '   ', 'x' * 161]) {
        expect(
          () => ExecutableTaskDraft(title: title),
          throwsA(isA<TaskCommandException>()),
        );
      }
      expect(
        () => ExecutableTaskDraft(
          title: 'Valid title',
          description: 'x' * 2001,
        ),
        throwsA(isA<TaskCommandException>()),
      );
      for (final estimate in [-1, 0, 4, 481]) {
        expect(
          () => ExecutableTaskDraft(
            title: 'Valid title',
            estimatedMinutes: estimate,
          ),
          throwsA(isA<TaskCommandException>()),
        );
      }
    });

    test('preserves every supported priority and a typed deadline', () {
      final deadline = DateTime.parse('2026-07-12T09:30:00+02:00');

      for (final priority in ExecutableTaskPriority.values) {
        final draft = ExecutableTaskDraft(
          title: priority.code,
          priority: priority,
          deadline: deadline,
        );

        expect(draft.priority, priority);
        expect(draft.deadline, deadline);
      }
    });
  });

  group('validateTaskPostpone', () {
    final now = DateTime.parse('2026-07-11T10:00:00Z');

    test('accepts a future deadline when none exists', () {
      expect(
        () => validateTaskPostpone(
          currentDeadline: null,
          newDeadline: now.add(const Duration(seconds: 1)),
          now: now,
        ),
        returnsNormally,
      );
    });

    test('rejects a new deadline equal to or before now', () {
      for (final deadline in [
        now.subtract(const Duration(microseconds: 1)),
        now,
      ]) {
        expect(
          () => validateTaskPostpone(
            currentDeadline: null,
            newDeadline: deadline,
            now: now,
          ),
          throwsA(isA<TaskCommandException>()),
        );
      }
    });

    test('requires a deadline strictly later than the current deadline', () {
      final currentDeadline = now.add(const Duration(days: 1));

      for (final deadline in [
        now.add(const Duration(hours: 1)),
        currentDeadline,
      ]) {
        expect(
          () => validateTaskPostpone(
            currentDeadline: currentDeadline,
            newDeadline: deadline,
            now: now,
          ),
          throwsA(isA<TaskCommandException>()),
        );
      }
      expect(
        () => validateTaskPostpone(
          currentDeadline: currentDeadline,
          newDeadline: currentDeadline.add(const Duration(microseconds: 1)),
          now: now,
        ),
        returnsNormally,
      );
    });

    test('allows replacing a past deadline with a future deadline', () {
      expect(
        () => validateTaskPostpone(
          currentDeadline: now.subtract(const Duration(days: 1)),
          newDeadline: now.add(const Duration(days: 1)),
          now: now,
        ),
        returnsNormally,
      );
    });
  });

  group('TaskUndoToken', () {
    test('captures every restorable field without changing the task', () {
      final deadline = DateTime.parse('2026-07-12T09:30:00Z');
      final completedAt = DateTime.parse('2026-07-11T08:00:00Z');
      final cancelledAt = DateTime.parse('2026-07-11T09:00:00Z');
      final task = ExecutableTask(
        id: 'task-123',
        title: 'Prepare launch',
        status: ExecutableTaskStatus.cancelled,
        priority: ExecutableTaskPriority.high,
        deadline: deadline,
        completedAt: completedAt,
        cancelledAt: cancelledAt,
        updatedAt: DateTime.parse('2026-07-11T09:30:00Z'),
      );

      final token = TaskUndoToken.fromTask(task);

      expect(token.taskId, task.id);
      expect(token.status, task.status);
      expect(token.deadline, deadline);
      expect(token.completedAt, completedAt);
      expect(token.cancelledAt, cancelledAt);
      expect(token.expectedUpdatedAt, task.updatedAt);
      expect(task.status, ExecutableTaskStatus.cancelled);
    });

    test('preserves nullable restorable fields', () {
      final token = TaskUndoToken.fromTask(_task());

      expect(token.taskId, 'task-123');
      expect(token.status, ExecutableTaskStatus.todo);
      expect(token.deadline, isNull);
      expect(token.completedAt, isNull);
      expect(token.cancelledAt, isNull);
    });
  });
}

ExecutableTask _task({
  ExecutableTaskStatus status = ExecutableTaskStatus.todo,
}) =>
    ExecutableTask(
      id: 'task-123',
      title: 'Prepare launch',
      status: status,
      priority: ExecutableTaskPriority.medium,
      updatedAt: DateTime.parse('2026-07-11T10:00:00Z'),
    );

Map<String, dynamic> _validRow() => {
      'id': 'task-123',
      'title': 'Prepare launch',
      'description': null,
      'status': 'todo',
      'priority': 'medium',
      'deadline': null,
      'estimated_minutes': null,
      'completed_at': null,
      'cancelled_at': null,
      'updated_at': '2026-07-11T10:00:00Z',
    };
