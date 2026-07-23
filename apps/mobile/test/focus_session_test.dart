import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/focus/domain/focus_session.dart';

void main() {
  group('Focus enums and target options', () {
    test('status and target-kind parsers accept only exact known codes', () {
      for (final status in FocusSessionStatus.values) {
        expect(FocusSessionStatus.fromCode(status.code), status);
      }
      for (final kind in FocusTargetKind.values) {
        expect(FocusTargetKind.fromCode(kind.code), kind);
      }

      expect(FocusSessionStatus.fromCode('ACTIVE'), isNull);
      expect(FocusSessionStatus.fromCode('paused'), isNull);
      expect(FocusSessionStatus.fromCode(null), isNull);
      expect(FocusTargetKind.fromCode('TASK'), isNull);
      expect(FocusTargetKind.fromCode('goal'), isNull);
      expect(FocusTargetKind.fromCode(null), isNull);
    });

    test('target option exposes a stable kind-prefixed value', () {
      const task = FocusTargetOption(
        kind: FocusTargetKind.task,
        id: 'task-123',
        title: 'Prepare launch',
      );
      const habit = FocusTargetOption(
        kind: FocusTargetKind.habit,
        id: 'habit-123',
        title: 'Read',
      );

      expect(task.value, 'task:task-123');
      expect(habit.value, 'habit:habit-123');
    });
  });

  group('FocusSession.fromRow strict parsing', () {
    test('parses a complete active session', () {
      final session = FocusSession.fromRow(
        _activeRow()
          ..['label'] = '  Launch sprint  '
          ..['task_id'] = '  task-123  ',
      );

      expect(session.id, 'session-123');
      expect(session.status, FocusSessionStatus.active);
      expect(session.isActive, isTrue);
      expect(session.startedAt, DateTime.parse('2026-07-11T10:00:00Z'));
      expect(session.endedAt, isNull);
      expect(session.plannedMinutes, 30);
      expect(session.actualMinutes, isNull);
      expect(session.label, 'Launch sprint');
      expect(session.targetKind, FocusTargetKind.task);
      expect(session.targetId, 'task-123');
      expect(session.updatedAt, DateTime.parse('2026-07-11T10:00:00Z'));
    });

    test('parses completed and abandoned lifecycle rows', () {
      for (final status in [
        FocusSessionStatus.completed,
        FocusSessionStatus.abandoned,
      ]) {
        final session = FocusSession.fromRow(_terminalRow(status));

        expect(session.status, status);
        expect(session.isActive, isFalse);
        expect(session.endedAt, DateTime.parse('2026-07-11T10:45:00Z'));
        expect(session.actualMinutes, 45);
      }
    });

    test('parses a valid local entry date from metadata', () {
      final session = FocusSession.fromRow(
        _activeRow()
          ..['metadata'] = const {
            'entry_date': '2026-03-29',
            'source': 'deep_work',
          },
      );

      expect(session.entryDate, '2026-03-29');
      expect(session.snapshotEntryDate, '2026-03-29');
    });

    test('parses bounded recovery from existing session metadata', () {
      final session = FocusSession.fromRow(
        _activeRow()
          ..['metadata'] = const {
            'entry_date': '2026-07-11',
            'recovery_minutes': 10,
          },
      );

      expect(session.recoveryMinutes, 10);
      expect(FocusSession.fromRow(_activeRow()).recoveryMinutes, 0);
      for (final value in <Object?>[null, 0, 4, 11, 65, '10', 10.0]) {
        expect(
          () => FocusSession.fromRow(
            _activeRow()
              ..['metadata'] = {
                'recovery_minutes': value,
              },
          ),
          throwsA(isA<FocusCommandException>()),
          reason: '$value must not become a recovery duration',
        );
      }
    });

    test('missing or invalid metadata entry dates safely fall back to absent',
        () {
      expect(FocusSession.fromRow(_activeRow()).entryDate, isNull);

      for (final metadata in <Object?>[
        null,
        'entry_date=2026-07-11',
        const <String, Object?>{},
        const {'entry_date': null},
        const {'entry_date': 20260711},
        const {'entry_date': ''},
        const {'entry_date': '2026-7-11'},
        const {'entry_date': ' 2026-07-11 '},
        const {'entry_date': '2026-02-30'},
        const {'entry_date': '2026-13-01'},
      ]) {
        final session = FocusSession.fromRow(
          _activeRow()..['metadata'] = metadata,
        );

        expect(
          session.entryDate,
          isNull,
          reason: '$metadata must not become a local focus entry date',
        );
      }
    });

    test('snapshot date uses a deterministic UTC fallback without metadata',
        () {
      final session = FocusSession.fromRow(
        _activeRow()..['started_at'] = '2026-07-02T00:30:00+02:00',
      );

      expect(session.entryDate, isNull);
      expect(session.snapshotEntryDate, '2026-07-01');
    });

    test('normalizes blank optional label to absent', () {
      final session = FocusSession.fromRow(_activeRow()..['label'] = '   ');

      expect(session.label, isNull);
    });

    test('rejects missing, wrongly typed, blank, and malformed identity', () {
      for (final override in <Map<String, Object?>>[
        {'id': null},
        {'id': 123},
        {'id': ''},
        {'id': '   '},
        {'started_at': null},
        {'started_at': DateTime(2026, 7, 11)},
        {'started_at': ''},
        {'started_at': 'tomorrow'},
        {'updated_at': null},
        {'updated_at': DateTime(2026, 7, 11)},
        {'updated_at': ''},
        {'updated_at': 'tomorrow'},
        {'status': null},
        {'status': 'paused'},
      ]) {
        expect(
          () => FocusSession.fromRow(_activeRow()..addAll(override)),
          throwsA(isA<FocusCommandException>()),
          reason: '$override must be rejected',
        );
      }
    });

    test('enforces planned-duration integer and range', () {
      for (final duration in <Object>[5, 30, 240, 30.0]) {
        final session = FocusSession.fromRow(
          _activeRow()..['planned_minutes'] = duration,
        );
        expect(session.plannedMinutes, (duration as num).toInt());
      }

      for (final duration in <Object?>[
        null,
        -1,
        0,
        4,
        241,
        30.5,
        '30',
        true,
      ]) {
        expect(
          () => FocusSession.fromRow(
            _activeRow()..['planned_minutes'] = duration,
          ),
          throwsA(isA<FocusCommandException>()),
          reason: '$duration is not a valid planned duration',
        );
      }
    });

    test('rejects invalid optional field types and values', () {
      for (final override in <Map<String, Object?>>[
        {'label': 123},
        {'ended_at': 123},
        {'ended_at': 'tomorrow'},
        {'actual_minutes': -1},
        {'actual_minutes': 1.5},
        {'actual_minutes': '1'},
        {'task_id': 123},
        {'habit_id': true},
      ]) {
        expect(
          () => FocusSession.fromRow(_activeRow()..addAll(override)),
          throwsA(isA<FocusCommandException>()),
          reason: '$override must be rejected',
        );
      }
    });
  });

  group('FocusSession lifecycle invariants', () {
    test('active requires both terminal fields to be absent', () {
      expect(
        () => FocusSession.fromRow(
          _activeRow()
            ..['ended_at'] = '2026-07-11T10:45:00Z'
            ..['actual_minutes'] = 45,
        ),
        throwsA(isA<FocusCommandException>()),
      );
      expect(
        () => FocusSession.fromRow(_activeRow()..['actual_minutes'] = 1),
        throwsA(isA<FocusCommandException>()),
      );
    });

    test('terminal status requires both end timestamp and actual duration', () {
      for (final status in [
        FocusSessionStatus.completed,
        FocusSessionStatus.abandoned,
      ]) {
        expect(
          () => FocusSession.fromRow(
            _terminalRow(status)..['ended_at'] = null,
          ),
          throwsA(isA<FocusCommandException>()),
        );
        expect(
          () => FocusSession.fromRow(
            _terminalRow(status)..['actual_minutes'] = null,
          ),
          throwsA(isA<FocusCommandException>()),
        );
      }
    });

    test('terminal end cannot precede start', () {
      expect(
        () => FocusSession.fromRow(
          _terminalRow(FocusSessionStatus.completed)
            ..['ended_at'] = '2026-07-11T09:59:59Z'
            ..['actual_minutes'] = 0,
        ),
        throwsA(isA<FocusCommandException>()),
      );
    });

    test('terminal duration must equal measured whole minutes', () {
      for (final actualMinutes in [30, 44, 46, 90]) {
        expect(
          () => FocusSession.fromRow(
            _terminalRow(FocusSessionStatus.completed)
              ..['actual_minutes'] = actualMinutes,
          ),
          throwsA(isA<FocusCommandException>()),
          reason: '$actualMinutes does not match the 45-minute interval',
        );
      }
    });
  });

  group('Focus preference suggestion', () {
    test('waits for five completed sessions', () {
      final sessions = [
        for (var index = 0; index < 4; index++)
          _completedSession(index: index, actualMinutes: 30),
      ];

      expect(FocusPreferenceSuggestion.fromSessions(sessions), isNull);
    });

    test('uses completed-session median and a repeated time window', () {
      final sessions = [
        _completedSession(index: 0, actualMinutes: 24),
        _completedSession(index: 1, actualMinutes: 28),
        _completedSession(index: 2, actualMinutes: 30),
        _completedSession(index: 3, actualMinutes: 34),
        _completedSession(index: 4, actualMinutes: 80, startHour: 18),
        FocusSession(
          id: 'abandoned',
          status: FocusSessionStatus.abandoned,
          startedAt: DateTime(2026, 7, 10, 9),
          endedAt: DateTime(2026, 7, 10, 9, 40),
          plannedMinutes: 40,
          actualMinutes: 40,
          updatedAt: DateTime(2026, 7, 10, 9, 40),
        ),
      ];

      final suggestion = FocusPreferenceSuggestion.fromSessions(sessions);

      expect(suggestion, isNotNull);
      expect(suggestion!.durationMinutes, 30);
      expect(suggestion.evidenceSessions, 5);
      expect(suggestion.timeWindowLabel, 'in the morning');
    });
  });

  group('FocusSession target pairing', () {
    test('supports no target, one task, or one habit', () {
      final none = FocusSession.fromRow(_activeRow());
      final task = FocusSession.fromRow(
        _activeRow()..['task_id'] = 'task-123',
      );
      final habit = FocusSession.fromRow(
        _activeRow()..['habit_id'] = 'habit-123',
      );

      expect(none.targetKind, isNull);
      expect(none.targetId, isNull);
      expect(task.targetKind, FocusTargetKind.task);
      expect(task.targetId, 'task-123');
      expect(habit.targetKind, FocusTargetKind.habit);
      expect(habit.targetId, 'habit-123');
    });

    test('rejects simultaneous task and habit targets', () {
      expect(
        () => FocusSession.fromRow(
          _activeRow()
            ..['task_id'] = 'task-123'
            ..['habit_id'] = 'habit-123',
        ),
        throwsA(isA<FocusCommandException>()),
      );
    });

    test('rejects blank persisted target ids instead of erasing linkage', () {
      for (final key in ['task_id', 'habit_id']) {
        for (final value in ['', '   ']) {
          expect(
            () => FocusSession.fromRow(_activeRow()..[key] = value),
            throwsA(isA<FocusCommandException>()),
            reason: '$key=$value must not become an unlinked session',
          );
        }
      }
    });
  });

  group('FocusStartDraft', () {
    test('accepts exact duration boundaries and every target kind', () {
      for (final duration in [5, 240]) {
        expect(
          () => FocusStartDraft(plannedMinutes: duration),
          returnsNormally,
        );
        for (final kind in FocusTargetKind.values) {
          final draft = FocusStartDraft(
            plannedMinutes: duration,
            targetKind: kind,
            targetId: '${kind.code}-123',
          );

          expect(draft.targetKind, kind);
          expect(draft.targetId, '${kind.code}-123');
        }
      }
    });

    test('rejects durations outside five through 240 minutes', () {
      for (final duration in [-1, 0, 4, 241]) {
        expect(
          () => FocusStartDraft(plannedMinutes: duration),
          throwsA(isA<FocusCommandException>()),
        );
      }
    });

    test('allows one-session duration overrides with bounded recovery', () {
      final draft = FocusStartDraft(
        plannedMinutes: 37,
        recoveryMinutes: 10,
      );

      expect(draft.plannedMinutes, 37);
      expect(draft.recoveryMinutes, 10);
      for (final recovery in [-1, 4, 11, 65]) {
        expect(
          () => FocusStartDraft(
            plannedMinutes: 37,
            recoveryMinutes: recovery,
          ),
          throwsA(isA<FocusCommandException>()),
        );
      }
    });

    test('requires target kind and id together and rejects blank ids', () {
      expect(
        () => FocusStartDraft(
          plannedMinutes: 30,
          targetKind: FocusTargetKind.task,
        ),
        throwsA(isA<FocusCommandException>()),
      );
      expect(
        () => FocusStartDraft(
          plannedMinutes: 30,
          targetId: 'task-123',
        ),
        throwsA(isA<FocusCommandException>()),
      );
      for (final targetId in ['', '   ']) {
        expect(
          () => FocusStartDraft(
            plannedMinutes: 30,
            targetKind: FocusTargetKind.task,
            targetId: targetId,
          ),
          throwsA(isA<FocusCommandException>()),
        );
      }
    });

    test('normalizes label and accepts zero through 160 characters', () {
      final absent = FocusStartDraft(plannedMinutes: 30);
      final blank = FocusStartDraft(plannedMinutes: 30, label: '   ');
      final one = FocusStartDraft(plannedMinutes: 30, label: ' x ');
      final boundary = FocusStartDraft(
        plannedMinutes: 30,
        label: ' ${'x' * 160} ',
      );

      expect(absent.label, isNull);
      expect(blank.label, isNull);
      expect(one.label, 'x');
      expect(boundary.label, 'x' * 160);
    });

    test('rejects a normalized label longer than 160 characters', () {
      expect(
        () => FocusStartDraft(
          plannedMinutes: 30,
          label: 'x' * 161,
        ),
        throwsA(isA<FocusCommandException>()),
      );
    });
  });

  group('StudyFocusSettings', () {
    test('parses an ordered exact focus ritual projection', () {
      final settings = StudyFocusSettings.fromRow({
        'focus_minutes': 45,
        'recovery_minutes': 10,
        'setup_revision': 3,
        'preparation_items': const [
          {
            'key': '4abc0000-0000-4000-8000-000000000001',
            'label': 'Water',
            'active': true,
          },
          {
            'key': '5abc0000-0000-4000-8000-000000000002',
            'label': 'Study materials',
            'active': false,
          },
        ],
      });

      expect(settings.focusMinutes, 45);
      expect(settings.recoveryMinutes, 10);
      expect(settings.setupRevision, 3);
      expect(
        settings.preparationItems.map((item) => item.label).toList(),
        ['Water', 'Study materials'],
      );
    });

    test('rejects coercion, noncanonical UUIDs, and duplicate labels', () {
      final preparationItems = <Map<String, Object>>[
        {
          'key': '4abc0000-0000-4000-8000-000000000001',
          'label': 'Water',
          'active': true,
        },
      ];
      final valid = <String, dynamic>{
        'focus_minutes': 45,
        'recovery_minutes': 10,
        'setup_revision': 3,
        'preparation_items': preparationItems,
      };
      final invalid = <Map<String, dynamic>>[
        {...valid, 'focus_minutes': '45'},
        {
          ...valid,
          'preparation_items': [
            {
              ...preparationItems.first,
              'key': '4ABC0000-0000-4000-8000-000000000001',
            },
          ],
        },
        {
          ...valid,
          'preparation_items': [
            preparationItems.first,
            {
              'key': '5abc0000-0000-4000-8000-000000000002',
              'label': 'water',
              'active': false,
            },
          ],
        },
        {
          ...valid,
          'preparation_items': [
            {
              ...preparationItems.first,
              'label': ' Water ',
            },
          ],
        },
      ];

      for (final row in invalid) {
        expect(
          () => StudyFocusSettings.fromRow(row),
          throwsA(isA<FocusCommandException>()),
        );
      }
    });
  });

  group('measuredFocusMinutes', () {
    final start = DateTime.parse('2026-07-11T10:00:00Z');

    test('uses elapsed whole wall-clock minutes', () {
      const cases = <(Duration, int)>[
        (Duration.zero, 0),
        (Duration(seconds: 59), 0),
        (Duration(minutes: 1), 1),
        (Duration(minutes: 1, seconds: 59), 1),
        (Duration(minutes: 45, seconds: 30), 45),
        (Duration(hours: 4), 240),
      ];

      for (final entry in cases) {
        expect(
          measuredFocusMinutes(
            startedAt: start,
            endedAt: start.add(entry.$1),
          ),
          entry.$2,
          reason: '${entry.$1} must use completed whole minutes',
        );
      }
    });

    test('compares instants across timezone offsets', () {
      expect(
        measuredFocusMinutes(
          startedAt: DateTime.parse('2026-07-11T12:00:00+02:00'),
          endedAt: DateTime.parse('2026-07-11T10:45:00Z'),
        ),
        45,
      );
    });

    test('rejects an end instant before the start', () {
      expect(
        () => measuredFocusMinutes(
          startedAt: start,
          endedAt: start.subtract(const Duration(microseconds: 1)),
        ),
        throwsA(isA<FocusCommandException>()),
      );
    });
  });
}

FocusSession _completedSession({
  required int index,
  required int actualMinutes,
  int startHour = 9,
}) {
  final start = DateTime(2026, 7, index + 1, startHour);
  final end = start.add(Duration(minutes: actualMinutes));
  return FocusSession(
    id: 'completed-$index',
    status: FocusSessionStatus.completed,
    startedAt: start,
    endedAt: end,
    plannedMinutes: 30,
    actualMinutes: actualMinutes,
    updatedAt: end,
  );
}

Map<String, dynamic> _activeRow() => {
      'id': 'session-123',
      'status': 'active',
      'started_at': '2026-07-11T10:00:00Z',
      'ended_at': null,
      'planned_minutes': 30,
      'actual_minutes': null,
      'label': null,
      'task_id': null,
      'habit_id': null,
      'updated_at': '2026-07-11T10:00:00Z',
    };

Map<String, dynamic> _terminalRow(FocusSessionStatus status) => {
      'id': 'session-123',
      'status': status.code,
      'started_at': '2026-07-11T10:00:00Z',
      'ended_at': '2026-07-11T10:45:00Z',
      'planned_minutes': 30,
      'actual_minutes': 45,
      'label': null,
      'task_id': null,
      'habit_id': null,
      'updated_at': '2026-07-11T10:45:00Z',
    };
