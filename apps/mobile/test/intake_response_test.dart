import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/auth/domain/intake_response.dart';

void main() {
  group('IntakeResponseDraft', () {
    test('zero optional answers serialize without invented records', () {
      const draft = IntakeResponseDraft(
        displayName: null,
        primaryFocusAreas: ['focus'],
        goals: [],
        frictionPoints: [],
        weekdayShape: 'flexible',
        bestEnergyWindow: 'variable',
        coachingStyle: 'gentle',
        reminderPreference: IntakeReminderPreference(enabled: false),
        routines: [],
        fixedCommitments: [],
        contextNote: null,
        calendarConnectionIntent: null,
      );

      final json = draft.toJson();

      expect(json['goals'], isEmpty);
      expect(json['friction_points'], isEmpty);
      expect(json['routines'], isEmpty);
      expect(json['fixed_commitments'], isEmpty);
      expect(json, isNot(contains('context_note')));
      expect(json, isNot(contains('calendar_connection_intent')));
      expect(json, isNot(contains('display_name')));
      expect(json['reminder_preference'], {'enabled': false});
    });

    test('candidate remains inactive and has no implicit cadence or target',
        () {
      const routine = IntakeRoutineDraft(
        key: '9a289e92-4f90-4cd9-8244-9152fd4fdc40',
        title: 'Read after lunch',
      );

      expect(routine.toJson(), {
        'key': '9a289e92-4f90-4cd9-8244-9152fd4fdc40',
        'title': 'Read after lunch',
        'status': 'candidate',
        'cadence_confirmed': false,
      });
    });

    test('active routine requires explicit valid cadence semantics', () {
      final invalid = _requiredDraft().copyWith(
        routines: const [
          IntakeRoutineDraft(
            key: 'ba9e8335-79c0-4624-9bea-6536ae49a2e2',
            title: 'Stretch',
            status: IntakeRoutineStatus.active,
          ),
        ],
      );
      final dailyTargetTooHigh = _requiredDraft().copyWith(
        routines: const [
          IntakeRoutineDraft(
            key: 'ba9e8335-79c0-4624-9bea-6536ae49a2e2',
            title: 'Stretch',
            status: IntakeRoutineStatus.active,
            cadenceConfirmed: true,
            frequency: 'daily',
            target: 2,
          ),
        ],
      );
      final validWeekly = _requiredDraft().copyWith(
        routines: const [
          IntakeRoutineDraft(
            key: 'ba9e8335-79c0-4624-9bea-6536ae49a2e2',
            title: 'Stretch',
            status: IntakeRoutineStatus.active,
            cadenceConfirmed: true,
            frequency: 'weekly',
            target: 3,
          ),
        ],
      );

      expect(invalid.validationErrors(), isNotEmpty);
      expect(
        dailyTargetTooHigh.validationErrors(),
        contains('A daily routine must have a target of 1.'),
      );
      expect(validWeekly.validationErrors(), isEmpty);
    });

    test('stable keys must be unique across different setup item kinds', () {
      const duplicateKey = '3709c7bd-5828-440a-964f-130465a5f13c';
      final draft = _requiredDraft().copyWith(
        goals: const [
          IntakeGoalDraft(key: duplicateKey, title: 'One goal'),
        ],
        routines: const [
          IntakeRoutineDraft(key: duplicateKey, title: 'One routine'),
        ],
      );

      expect(
        draft.validationErrors(),
        contains('Setup item keys must be unique across all item types.'),
      );
    });

    test('weekly cadence stays unconfirmed until target is explicit', () {
      final partial = _requiredDraft().copyWith(
        routines: const [
          IntakeRoutineDraft(
            key: '4020bec8-a3cf-4a08-b0ee-c822bb25eaf3',
            title: 'Weekly reset',
            frequency: 'weekly',
          ),
        ],
      );
      final confirmed = partial.copyWith(
        routines: const [
          IntakeRoutineDraft(
            key: '4020bec8-a3cf-4a08-b0ee-c822bb25eaf3',
            title: 'Weekly reset',
            frequency: 'weekly',
            target: 3,
            cadenceConfirmed: true,
          ),
        ],
      );

      expect(partial.validationErrors(), isNotEmpty);
      expect(confirmed.validationErrors(), isEmpty);
      expect(confirmed.routines.single.toJson()['target'], 3);
    });

    test('backend text-length boundaries are accepted', () {
      final draft = _requiredDraft().copyWith(
        displayName: _textOfLength(120),
        weekdayShape: _textOfLength(500),
        goals: [
          IntakeGoalDraft(
            key: 'a26ef957-c789-49f3-af61-1c71a2549a61',
            title: _textOfLength(200),
          ),
        ],
        routines: [
          IntakeRoutineDraft(
            key: 'b0d76c46-ed92-486c-857f-f2cfd5bb20e4',
            title: _textOfLength(200),
          ),
        ],
        fixedCommitments: [
          IntakeCommitmentDraft(
            key: 'a57a526d-0235-4589-bb1c-5fea71f9dce7',
            title: _textOfLength(120),
            location: _textOfLength(120),
            weekday: 1,
            startsAt: '08:15',
            endsAt: '09:45',
          ),
        ],
        contextNote: _textOfLength(1000),
      );

      expect(draft.validationErrors(), isEmpty);
    });

    test('backend text-length overages are rejected before save', () {
      final draft = _requiredDraft().copyWith(
        displayName: _textOfLength(121),
        weekdayShape: _textOfLength(501),
        goals: [
          IntakeGoalDraft(
            key: '88d225e1-7906-499e-8604-39cf2c2c6b44',
            title: _textOfLength(201),
          ),
        ],
        routines: [
          IntakeRoutineDraft(
            key: '67c32972-4b67-4d3f-b01c-11a60601bf59',
            title: _textOfLength(201),
          ),
        ],
        fixedCommitments: [
          IntakeCommitmentDraft(
            key: 'd2470a17-82c0-44a5-b0c8-ee9a37ed8501',
            title: _textOfLength(121),
            location: _textOfLength(121),
            weekday: 1,
            startsAt: '08:15',
            endsAt: '09:45',
          ),
        ],
        contextNote: _textOfLength(1001),
      );

      expect(
        draft.validationErrors(),
        containsAll(<String>[
          'Display name must be 120 characters or fewer.',
          'Weekday shape must be 500 characters or fewer.',
          'Goal titles must be 200 characters or fewer.',
          'Routine titles must be 200 characters or fewer.',
          'Commitment titles must be 120 characters or fewer.',
          'Commitment locations must be 120 characters or fewer.',
          'Context note must be 1000 characters or fewer.',
        ]),
      );
    });

    test('backend literals and item UUIDs are validated before save', () {
      final draft = _requiredDraft().copyWith(
        primaryFocusAreas: const ['unsupported_focus'],
        bestEnergyWindow: 'whenever',
        coachingStyle: 'mystery',
        calendarConnectionIntent: 'someday',
        goals: const [
          IntakeGoalDraft(key: 'not-a-uuid', title: 'A goal'),
        ],
      );

      expect(
        draft.validationErrors(),
        containsAll(<String>[
          'Focus areas must use supported values.',
          'Choose a supported energy window.',
          'Choose a supported coaching style.',
          'Choose a supported calendar connection intent.',
          'Every goal requires a valid UUID key.',
        ]),
      );
    });

    test('invalid and duplicate legacy item keys are repaired for editing', () {
      const duplicateKey = '4625887d-b9df-4d4d-9593-8d07441ec4bd';
      final repaired = repairSetupItemKeys(
        _requiredDraft().copyWith(
          goals: const [
            IntakeGoalDraft(key: 'legacy-key', title: 'Goal'),
          ],
          routines: const [
            IntakeRoutineDraft(key: duplicateKey, title: 'Routine'),
          ],
          fixedCommitments: const [
            IntakeCommitmentDraft(
              key: duplicateKey,
              title: 'Commitment',
              location: null,
              weekday: 1,
              startsAt: '08:00',
              endsAt: '09:00',
            ),
          ],
        ),
      );
      final keys = [
        repaired.goals.single.key,
        repaired.routines.single.key,
        repaired.fixedCommitments.single.key,
      ];

      expect(keys.every(isSetupUuid), isTrue);
      expect(keys.toSet(), hasLength(3));
      expect(repaired.goals.single.title, 'Goal');
      expect(repaired.routines.single.key, duplicateKey);
    });

    test('request serialization rejects a non-UUID request id', () {
      final request = IntakeSetupSaveRequest(
        requestId: 'legacy-request',
        baseRevision: 0,
        responses: _requiredDraft(),
      );

      expect(request.toJson, throwsStateError);
    });

    test('read model normalizes backend time values for exact prefill', () {
      final read = IntakeSetupReadState.fromJson({
        'exists': true,
        'revision': 4,
        'base_revision': 3,
        'request_id': 'fa84a358-aa30-43f7-af57-f95a9de45268',
        'status': 'applied',
        'intake_response_id': 'intake',
        'snapshot_id': 'snapshot',
        'completed_at': '2026-07-10T08:30:00Z',
        'responses': {
          ..._requiredDraft().toJson(),
          'reminder_preference': {
            'enabled': true,
            'quiet_hours': {
              'starts_at': '21:00:00',
              'ends_at': '07:00:00',
            },
          },
          'fixed_commitments': [
            {
              'key': '6ecb196b-0b8c-4849-ac03-5479fe343b2c',
              'title': 'Class',
              'weekday': 2,
              'starts_at': '09:15:00',
              'ends_at': '10:45:00',
              'status': 'active',
            },
          ],
        },
        'summary': <String, dynamic>{},
      });

      expect(read.responses?.reminderPreference?.quietHoursStart, '21:00');
      expect(read.responses?.reminderPreference?.quietHoursEnd, '07:00');
      expect(read.responses?.fixedCommitments.single.startsAt, '09:15');
      expect(read.responses?.fixedCommitments.single.endsAt, '10:45');
    });
  });

  test('secure setup uuid has RFC 4122 v4 shape', () {
    final first = generateSetupUuid();
    final second = generateSetupUuid();

    expect(
      first,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(second, isNot(first));
  });
}

String _textOfLength(int length) => List.filled(length, 'x').join();

IntakeResponseDraft _requiredDraft() {
  return const IntakeResponseDraft(
    displayName: null,
    primaryFocusAreas: ['focus'],
    goals: [],
    frictionPoints: [],
    weekdayShape: 'flexible',
    bestEnergyWindow: 'morning',
    coachingStyle: 'direct',
    reminderPreference: IntakeReminderPreference(enabled: false),
    routines: [],
    fixedCommitments: [],
    contextNote: null,
    calendarConnectionIntent: null,
  );
}
