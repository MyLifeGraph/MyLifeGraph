import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/auth/data/guest_setup_data_source.dart';
import 'package:my_life_graph/features/auth/domain/intake_response.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('empty guest setup has revision zero and no invented responses',
      () async {
    final state = await const GuestSetupDataSource().read();

    expect(state.exists, isFalse);
    expect(state.revision, 0);
    expect(state.responses, isNull);
  });

  test('guest save, retry, prefill, and edit are revision-safe', () async {
    const firstRequestId = 'e7747bb1-714f-47e5-a36a-dae218573946';
    const goalKey = 'e6621043-bdab-432b-ad80-cf53dfef0bd3';
    const store = GuestSetupDataSource();
    final firstRequest = IntakeSetupSaveRequest(
      requestId: firstRequestId,
      baseRevision: 0,
      responses: _requiredDraft().copyWith(
        goals: const [
          IntakeGoalDraft(key: goalKey, title: 'Ship the real setup'),
        ],
        routines: const [
          IntakeRoutineDraft(
            key: '43175389-cb37-478c-b309-b9551b904453',
            title: 'Evening reset',
          ),
        ],
      ),
    );

    final saved = await store.save(firstRequest);
    final retry = await store.save(firstRequest);
    final prefilled = await store.read();

    expect(saved.revision, 1);
    expect(saved.status, 'applied');
    expect(retry.revision, 1);
    expect(retry.intakeResponseId, saved.intakeResponseId);
    expect(prefilled.responses?.goals.single.key, goalKey);
    expect(prefilled.responses?.goals.single.title, 'Ship the real setup');
    expect(
      prefilled.responses?.routines.single.status,
      IntakeRoutineStatus.candidate,
    );
    expect(prefilled.summary['routine_candidate_count'], 1);
    expect(prefilled.summary['active_habit_count'], 0);

    final editRequest = IntakeSetupSaveRequest(
      requestId: 'cc9b4111-04cb-4420-8d76-cc4c718d266b',
      baseRevision: 1,
      responses: prefilled.responses!.copyWith(
        goals: [
          prefilled.responses!.goals.single.copyWith(
            title: 'Ship setup safely',
            status: IntakeGoalStatus.archived,
          ),
        ],
      ),
    );
    final edited = await store.save(editRequest);

    expect(edited.revision, 2);
    expect(edited.responses?.goals, hasLength(1));
    expect(edited.responses?.goals.single.key, goalKey);
    expect(edited.responses?.goals.single.title, 'Ship setup safely');
    expect(
      edited.responses?.goals.single.status,
      IntakeGoalStatus.archived,
    );
  });

  test(
      'same request id rejects changed content instead of silently applying it',
      () async {
    const store = GuestSetupDataSource();
    const requestId = '30c126a8-b8e3-4e8a-9884-ad30bc1dc1de';
    final request = IntakeSetupSaveRequest(
      requestId: requestId,
      baseRevision: 0,
      responses: _requiredDraft(),
    );
    await store.save(request);

    expect(
      () => store.save(
        request.copyWith(
          responses: request.responses.copyWith(
            contextNote: 'Changed after the request was sent',
          ),
        ),
      ),
      throwsA(isA<GuestSetupIdempotencyException>()),
    );
  });

  test('legacy fallback goal and friction are not promoted on prefill',
      () async {
    SharedPreferences.setMockInitialValues({
      GuestSetupDataSource.legacyIntakeKey: jsonEncode({
        'version': 'intake-v1',
        'responses': {
          'primary_focus_areas': ['focus'],
          'goals': ['Build a steadier weekly routine'],
          'friction_points': ['Unclear priorities'],
          'weekday_shape': 'flexible',
          'best_energy_window': 'morning',
          'coaching_style': 'direct',
          'reminder_preference': {'enabled': false},
          'existing_habits': <String>[],
          'fixed_commitments': <Map<String, dynamic>>[],
        },
      }),
    });

    final state = await const GuestSetupDataSource().read();

    expect(state.responses?.goals, isEmpty);
    expect(state.responses?.frictionPoints, isEmpty);
  });

  test('legacy migration drops only the exact keyless fake commitment',
      () async {
    const explicitKey = '60010f89-d755-45c5-b69f-d3a57e7060f9';
    SharedPreferences.setMockInitialValues({
      GuestSetupDataSource.legacyIntakeKey: jsonEncode({
        'version': 'intake-v1',
        'responses': {
          'primary_focus_areas': ['focus'],
          'goals': <Map<String, dynamic>>[],
          'friction_points': <String>[],
          'weekday_shape': 'flexible',
          'best_energy_window': 'morning',
          'coaching_style': 'direct',
          'reminder_preference': {'enabled': false},
          'routines': <Map<String, dynamic>>[],
          'fixed_commitments': [
            {
              'title': 'Math',
              'location': 'Room 204',
              'weekday': 'Monday',
              'startsAt': '08:15:00',
              'endsAt': '09:45:00',
            },
            {
              'key': explicitKey,
              'title': 'Math',
              'location': 'Room 204',
              'weekday': 1,
              'starts_at': '08:15',
              'ends_at': '09:45',
              'status': 'active',
            },
          ],
        },
      }),
    });

    final state = await const GuestSetupDataSource().read();

    expect(state.responses?.fixedCommitments, hasLength(1));
    expect(state.responses?.fixedCommitments.single.key, explicitKey);
    expect(state.responses?.fixedCommitments.single.title, 'Math');
    expect(state.responses?.fixedCommitments.single.weekday, 1);
    expect(state.responses?.fixedCommitments.single.startsAt, '08:15');
    expect(state.responses?.fixedCommitments.single.endsAt, '09:45');
  });

  test('legacy migration drops incomplete keyless commitments', () async {
    SharedPreferences.setMockInitialValues({
      GuestSetupDataSource.legacyIntakeKey: jsonEncode({
        'version': 'intake-v1',
        'responses': {
          'primary_focus_areas': ['focus'],
          'goals': <Map<String, dynamic>>[],
          'friction_points': <String>[],
          'weekday_shape': 'flexible',
          'best_energy_window': 'morning',
          'coaching_style': 'direct',
          'reminder_preference': {'enabled': false},
          'routines': <Map<String, dynamic>>[],
          'fixed_commitments': [
            {
              'title': 'Missing times',
              'weekday': 2,
            },
            {
              'title': 'Invalid weekday',
              'weekday': 9,
              'startsAt': '10:00',
              'endsAt': '11:00',
            },
            {
              'title': 'Invalid time',
              'weekday': 3,
              'startsAt': '28:00',
              'endsAt': '29:00',
            },
            {
              'title': 'Ends first',
              'weekday': 4,
              'startsAt': '12:00',
              'endsAt': '11:00',
            },
            {
              'title': 'Real block',
              'weekday': 'Friday',
              'startsAt': '14:00:00',
              'endsAt': '15:30:00',
            },
          ],
        },
      }),
    });

    final state = await const GuestSetupDataSource().read();

    expect(state.responses?.fixedCommitments, hasLength(1));
    expect(state.responses?.fixedCommitments.single.title, 'Real block');
    expect(state.responses?.fixedCommitments.single.weekday, 5);
    expect(
      isSetupUuid(state.responses!.fixedCommitments.single.key),
      isTrue,
    );
  });
}

IntakeResponseDraft _requiredDraft() {
  return const IntakeResponseDraft(
    displayName: 'Local Review',
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
