import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/actions/domain/executable_action_target.dart';

void main() {
  group('ExecutableActionTarget command compatibility', () {
    const requiredKinds = <ExecutableActionCommand, ExecutableActionKind>{
      ExecutableActionCommand.openTask: ExecutableActionKind.task,
      ExecutableActionCommand.completeTask: ExecutableActionKind.task,
      ExecutableActionCommand.logHabit: ExecutableActionKind.habit,
      ExecutableActionCommand.startFocus: ExecutableActionKind.focus,
      ExecutableActionCommand.reviewPlan: ExecutableActionKind.planning,
      ExecutableActionCommand.openCapture: ExecutableActionKind.capture,
    };

    for (final command in ExecutableActionCommand.values) {
      for (final kind in ExecutableActionKind.values) {
        test('${command.code} ${kind.code} compatibility is explicit', () {
          ExecutableActionTarget build() => ExecutableActionTarget(
                id: '${command.code}:${kind.code}',
                kind: kind,
                command: command,
                targetId: _targetIdFor(command),
                metadata: _metadataFor(command),
              );

          if (requiredKinds[command] == kind) {
            expect(build, returnsNormally);
          } else {
            expect(build, throwsA(isA<UnsupportedActionTargetException>()));
          }
        });
      }
    }

    test('task and habit commands require a non-blank target id', () {
      for (final command in const [
        ExecutableActionCommand.openTask,
        ExecutableActionCommand.completeTask,
        ExecutableActionCommand.logHabit,
      ]) {
        final kind = command == ExecutableActionCommand.logHabit
            ? ExecutableActionKind.habit
            : ExecutableActionKind.task;

        for (final targetId in <String?>[null, '', '   ']) {
          expect(
            () => ExecutableActionTarget(
              id: command.code,
              kind: kind,
              command: command,
              targetId: targetId,
            ),
            throwsA(isA<UnsupportedActionTargetException>()),
            reason: '${command.code} must reject target id $targetId',
          );
        }
      }
    });

    test('focus and planning accept an optional bounded target context', () {
      for (final values in const [
        (
          ExecutableActionKind.focus,
          ExecutableActionCommand.startFocus,
        ),
        (
          ExecutableActionKind.planning,
          ExecutableActionCommand.reviewPlan,
        ),
      ]) {
        expect(
          () => ExecutableActionTarget(
            id: values.$2.code,
            kind: values.$1,
            command: values.$2,
          ),
          returnsNormally,
        );
        expect(
          () => ExecutableActionTarget(
            id: '${values.$2.code}:target',
            kind: values.$1,
            command: values.$2,
            targetId: 'owned-context-id',
            metadata: values.$2 == ExecutableActionCommand.startFocus
                ? const {'target_kind': 'task'}
                : const {},
          ),
          returnsNormally,
        );
      }
    });

    test('capture accepts only the two implemented exact routes', () {
      for (final route in ExecutableActionTarget.allowedCaptureRoutes) {
        expect(
          () => ExecutableActionTarget(
            id: 'capture:${route.endsWith('morning-calibration') ? 'morning' : 'evening'}',
            kind: ExecutableActionKind.capture,
            command: ExecutableActionCommand.openCapture,
            metadata: {'route': route},
          ),
          returnsNormally,
        );
      }

      for (final route in <Object>[
        '',
        ' /morning-calibration',
        '/daily-check-in',
        '/deep-work',
        'https://example.com/morning-calibration',
        true,
      ]) {
        expect(
          () => ExecutableActionTarget(
            id: 'bad-capture',
            kind: ExecutableActionKind.capture,
            command: ExecutableActionCommand.openCapture,
            metadata: {'route': route},
          ),
          throwsA(isA<UnsupportedActionTargetException>()),
          reason: '$route must not become an enabled capture route',
        );
      }
    });
  });

  group('ExecutableActionTarget metadata', () {
    test('accepts the bounded typed metadata for each command', () {
      expect(
        () => ExecutableActionTarget(
          id: 'habit:today',
          kind: ExecutableActionKind.habit,
          command: ExecutableActionCommand.logHabit,
          targetId: 'habit-1',
          metadata: const {
            'entry_date': '2026-07-11',
            'habit_outcome': 'skipped',
            'source': 'today',
          },
        ),
        returnsNormally,
      );
      expect(
        () => ExecutableActionTarget(
          id: 'focus:task-1',
          kind: ExecutableActionKind.focus,
          command: ExecutableActionCommand.startFocus,
          targetId: 'task-1',
          estimatedMinutes: 25,
          metadata: const {
            'focus_minutes': 25,
            'target_kind': 'task',
            'source': 'today',
          },
        ),
        returnsNormally,
      );
    });

    test('rejects unknown keys and non-scalar values', () {
      for (final metadata in <Map<String, Object>>[
        {'user_id': 'someone-else'},
        {'url': 'https://example.com'},
        {'unknown': true},
        {
          'source': ['nested'],
        },
        {
          'source': {'nested': true},
        },
        {'focus_minutes': 12.5},
        {'focus_minutes': 4},
        {'habit_outcome': 'open'},
        {'entry_date': '2026-02-30'},
        {'source': 'Upper Case'},
        {'target_kind': 'planning'},
      ]) {
        expect(
          () => ExecutableActionTarget(
            id: 'invalid-metadata',
            kind: ExecutableActionKind.focus,
            command: ExecutableActionCommand.startFocus,
            metadata: metadata,
          ),
          throwsA(isA<UnsupportedActionTargetException>()),
          reason: '$metadata must be rejected',
        );
      }
    });

    test('fromJson rejects a non-object, non-string key, and null value', () {
      for (final metadata in <Object>[
        'source=briefing',
        [
          {'source': 'briefing'},
        ],
        {1: 'briefing'},
        {'source': null},
      ]) {
        expect(
          () => ExecutableActionTarget.fromJson(
            _validJson(metadata: metadata),
          ),
          throwsA(isA<UnsupportedActionTargetException>()),
          reason: '$metadata must be rejected',
        );
      }
      expect(
        () => ExecutableActionTarget.fromJson(
          _validJson(metadata: null),
        ),
        throwsA(isA<UnsupportedActionTargetException>()),
      );
    });

    test('metadata is copied and exposed as unmodifiable', () {
      final input = <String, Object>{'source': 'briefing'};
      final target = ExecutableActionTarget(
        id: 'focus:immutable',
        kind: ExecutableActionKind.focus,
        command: ExecutableActionCommand.startFocus,
        metadata: input,
      );

      input['source'] = 'mutated';

      expect(target.metadata, {'source': 'briefing'});
      expect(
        () => target.metadata['source'] = 'mutated',
        throwsUnsupportedError,
      );
    });
  });

  group('ExecutableActionTarget parsing and round trip', () {
    test('round-trips the complete typed envelope', () {
      final original = ExecutableActionTarget(
        id: 'complete_task:task-123',
        kind: ExecutableActionKind.task,
        command: ExecutableActionCommand.completeTask,
        targetId: 'task-123',
        estimatedMinutes: 45,
        metadata: const {
          'source': 'daily_state',
        },
      );

      final json = original.toJson();
      final parsed = ExecutableActionTarget.fromJson(json);

      expect(json, {
        'contract_version': ExecutableActionTarget.contractVersion,
        'id': 'complete_task:task-123',
        'kind': 'task',
        'command': 'complete_task',
        'target_id': 'task-123',
        'estimated_minutes': 45,
        'metadata': {
          'source': 'daily_state',
        },
      });
      expect(parsed.id, original.id);
      expect(parsed.kind, original.kind);
      expect(parsed.command, original.command);
      expect(parsed.targetId, original.targetId);
      expect(parsed.estimatedMinutes, original.estimatedMinutes);
      expect(parsed.metadata, original.metadata);
    });

    test('enum parsers accept exact codes and reject unknown values', () {
      for (final kind in ExecutableActionKind.values) {
        expect(ExecutableActionKind.fromCode(kind.code), kind);
      }
      for (final command in ExecutableActionCommand.values) {
        expect(ExecutableActionCommand.fromCode(command.code), command);
      }

      expect(ExecutableActionKind.fromCode('TASK'), isNull);
      expect(ExecutableActionKind.fromCode('unknown'), isNull);
      expect(ExecutableActionKind.fromCode(null), isNull);
      expect(ExecutableActionCommand.fromCode('OPEN_TASK'), isNull);
      expect(ExecutableActionCommand.fromCode('unknown'), isNull);
      expect(ExecutableActionCommand.fromCode(null), isNull);
    });

    test('rejects unknown contract, kind, and command values', () {
      expect(
        () => ExecutableActionTarget.fromJson(
          _validJson(contractVersion: 'executable-action-v2'),
        ),
        throwsA(isA<UnsupportedActionTargetException>()),
      );
      expect(
        () => ExecutableActionTarget.fromJson(
          _validJson(kind: 'recovery'),
        ),
        throwsA(isA<UnsupportedActionTargetException>()),
      );
      expect(
        () => ExecutableActionTarget.fromJson(
          _validJson(command: 'delete_task'),
        ),
        throwsA(isA<UnsupportedActionTargetException>()),
      );
    });

    test('requires string ids in parsed envelopes', () {
      for (final json in [
        _validJson(id: 123),
        _validJson(id: '   '),
        _validJson(targetId: 123),
        _validJson(targetId: '   '),
        _validJson(targetId: ' task-123 '),
      ]) {
        expect(
          () => ExecutableActionTarget.fromJson(json),
          throwsA(isA<UnsupportedActionTargetException>()),
          reason: '$json must not fabricate an identifier',
        );
      }
    });

    test('rejects unknown top-level fields', () {
      expect(
        () => ExecutableActionTarget.fromJson(
          _validJson()..['unexpected'] = true,
        ),
        throwsA(isA<UnsupportedActionTargetException>()),
      );
    });

    test('rejects fractional and non-numeric parsed estimates', () {
      for (final estimate in <Object>[12.5, '12', true]) {
        expect(
          () => ExecutableActionTarget.fromJson(
            _validJson(estimatedMinutes: estimate),
          ),
          throwsA(isA<UnsupportedActionTargetException>()),
          reason: '$estimate is not an integer estimate',
        );
      }
    });

    test('enforces id, target id, and estimate boundaries', () {
      expect(
        () => _focusTarget(id: 'x'),
        returnsNormally,
      );
      expect(
        () => _focusTarget(id: 'x' * 200),
        returnsNormally,
      );
      for (final id in ['', '   ', 'x' * 201]) {
        expect(
          () => _focusTarget(id: id),
          throwsA(isA<UnsupportedActionTargetException>()),
        );
      }

      expect(
        () => _focusTarget(id: 'focus', targetId: 'x' * 200),
        returnsNormally,
      );
      expect(
        () => _focusTarget(id: 'focus', targetId: 'x' * 201),
        throwsA(isA<UnsupportedActionTargetException>()),
      );

      for (final estimate in [5, 240]) {
        expect(
          () => _focusTarget(id: 'focus:$estimate', estimate: estimate),
          returnsNormally,
        );
      }
      for (final estimate in [0, -1, 1, 4, 241, 480, 481]) {
        expect(
          () => _focusTarget(id: 'focus:$estimate', estimate: estimate),
          throwsA(isA<UnsupportedActionTargetException>()),
        );
      }
    });
  });

  group('ExecutableActionAvailability', () {
    test('plan review follows the explicit weekly review capability', () {
      final target = ExecutableActionTarget(
        id: 'review-plan',
        kind: ExecutableActionKind.planning,
        command: ExecutableActionCommand.reviewPlan,
      );

      final unavailable = target.availability(
        canUseSyncedExecution: true,
      );
      final available = target.availability(
        canUseSyncedExecution: true,
        canUseWeeklyReview: true,
      );

      expect(unavailable.isAvailable, isFalse);
      expect(unavailable.reason, 'Weekly review requires a synced account.');
      expect(available.isAvailable, isTrue);
      expect(available.reason, isNull);
    });

    test('capture remains available without a synced account', () {
      final target = ExecutableActionTarget(
        id: 'morning-capture',
        kind: ExecutableActionKind.capture,
        command: ExecutableActionCommand.openCapture,
        metadata: const {'route': '/morning-calibration'},
      );

      for (final canUseSyncedExecution in [false, true]) {
        final availability = target.availability(
          canUseSyncedExecution: canUseSyncedExecution,
        );
        expect(availability.isAvailable, isTrue);
        expect(availability.reason, isNull);
      }
    });

    test('synced commands expose a reason when execution is unavailable', () {
      for (final target in [
        ExecutableActionTarget(
          id: 'open-task',
          kind: ExecutableActionKind.task,
          command: ExecutableActionCommand.openTask,
          targetId: 'task-1',
        ),
        ExecutableActionTarget(
          id: 'complete-task',
          kind: ExecutableActionKind.task,
          command: ExecutableActionCommand.completeTask,
          targetId: 'task-1',
        ),
        ExecutableActionTarget(
          id: 'log-habit',
          kind: ExecutableActionKind.habit,
          command: ExecutableActionCommand.logHabit,
          targetId: 'habit-1',
        ),
        ExecutableActionTarget(
          id: 'start-focus',
          kind: ExecutableActionKind.focus,
          command: ExecutableActionCommand.startFocus,
        ),
      ]) {
        final unavailable = target.availability(
          canUseSyncedExecution: false,
        );
        final available = target.availability(
          canUseSyncedExecution: true,
        );

        expect(unavailable.isAvailable, isFalse);
        expect(unavailable.reason, 'This action requires a synced account.');
        expect(available.isAvailable, isTrue);
        expect(available.reason, isNull);
      }
    });
  });
}

String? _targetIdFor(ExecutableActionCommand command) {
  switch (command) {
    case ExecutableActionCommand.openTask:
    case ExecutableActionCommand.completeTask:
      return 'task-123';
    case ExecutableActionCommand.logHabit:
      return 'habit-123';
    case ExecutableActionCommand.startFocus:
    case ExecutableActionCommand.reviewPlan:
    case ExecutableActionCommand.openCapture:
      return null;
  }
}

Map<String, Object> _metadataFor(ExecutableActionCommand command) {
  if (command == ExecutableActionCommand.openCapture) {
    return const {'route': '/morning-calibration'};
  }
  return const {};
}

Map<String, dynamic> _validJson({
  Object? contractVersion = ExecutableActionTarget.contractVersion,
  Object? id = 'complete_task:task-123',
  Object? kind = 'task',
  Object? command = 'complete_task',
  Object? targetId = 'task-123',
  Object? estimatedMinutes = 30,
  Object? metadata = const <String, Object>{},
}) =>
    {
      'contract_version': contractVersion,
      'id': id,
      'kind': kind,
      'command': command,
      'target_id': targetId,
      'estimated_minutes': estimatedMinutes,
      'metadata': metadata,
    };

ExecutableActionTarget _focusTarget({
  required String id,
  String? targetId,
  int? estimate,
}) =>
    ExecutableActionTarget(
      id: id,
      kind: ExecutableActionKind.focus,
      command: ExecutableActionCommand.startFocus,
      targetId: targetId,
      estimatedMinutes: estimate,
      metadata: targetId == null ? const {} : const {'target_kind': 'task'},
    );
