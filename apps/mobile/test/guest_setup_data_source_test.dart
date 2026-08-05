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
    const routineKey = '43175389-cb37-478c-b309-b9551b904453';
    const store = GuestSetupDataSource();
    final firstRequest = IntakeSetupSaveRequest(
      requestId: firstRequestId,
      baseRevision: 0,
      responses: _requiredDraft().copyWith(
        routines: const [
          IntakeRoutineDraft(
            key: routineKey,
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
    expect(prefilled.responses?.routines.single.key, routineKey);
    expect(prefilled.responses?.routines.single.title, 'Evening reset');
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
        routines: [
          prefilled.responses!.routines.single.copyWith(
            title: 'Reset after dinner',
            status: IntakeRoutineStatus.archived,
          ),
        ],
      ),
    );
    final edited = await store.save(editRequest);

    expect(edited.revision, 2);
    expect(edited.responses?.routines, hasLength(1));
    expect(edited.responses?.routines.single.key, routineKey);
    expect(edited.responses?.routines.single.title, 'Reset after dinner');
    expect(
      edited.responses?.routines.single.status,
      IntakeRoutineStatus.archived,
    );
  });

  test('guest setup preserves the complete optional study payload locally',
      () async {
    const store = GuestSetupDataSource();
    final study = StudySetupDraft(
      focusRhythm: StudyFocusRhythmDraft(
        focusMinutes: 45,
        recoveryMinutes: 10,
        preparationItems: const [
          StudyPreparationItemDraft(
            key: '4abc0000-0000-4000-8000-000000000001',
            label: 'Water',
            active: true,
          ),
          StudyPreparationItemDraft(
            key: '5abc0000-0000-4000-8000-000000000002',
            label: 'My neutral custom item',
            active: false,
          ),
        ],
      ),
      semesterPlanning: StudySemesterPlanningDraft(
        currentSemester: StudySemesterDraft(
          name: 'Summer 2026',
          startsOn: DateTime.utc(2026, 4),
          endsOn: DateTime.utc(2026, 9, 30),
        ),
        nextSemester: StudyNextSemesterDraft(
          name: 'Winter 2026/27',
          startsOn: DateTime.utc(2026, 10),
          endsOn: DateTime.utc(2027, 3, 31),
          courseSelectionStartsOn: DateTime.utc(2026, 8, 15),
          courseSelectionEndsOn: DateTime.utc(2026, 9, 15),
          courseNames: const ['Algorithms', 'Linear algebra'],
          courseSelectionCompleted: false,
        ),
      ),
    );
    final saved = await store.save(
      IntakeSetupSaveRequest(
        requestId: 'f7747bb1-714f-47e5-a36a-dae218573946',
        baseRevision: 0,
        responses: _requiredDraft().copyWith(studySetup: study),
      ),
    );
    final reloaded = await store.read();

    expect(saved.responses?.studySetup?.toJson(), study.toJson());
    expect(reloaded.responses?.studySetup?.toJson(), study.toJson());
    expect(reloaded.responses?.studySetup?.focusRhythm?.focusMinutes, 45);
    expect(
      reloaded
          .responses?.studySetup?.semesterPlanning?.nextSemester.courseNames,
      ['Algorithms', 'Linear algebra'],
    );
  });

  test('same request id ignores changes to retired content', () async {
    const store = GuestSetupDataSource();
    const requestId = '30c126a8-b8e3-4e8a-9884-ad30bc1dc1de';
    final request = IntakeSetupSaveRequest(
      requestId: requestId,
      baseRevision: 0,
      responses: _requiredDraft(),
    );
    await store.save(request);

    final replay = await store.save(
      request.copyWith(
        responses: request.responses.copyWith(
          contextNote: 'Changed after the request was sent',
        ),
      ),
    );
    expect(replay.revision, 1);
    expect(replay.responses?.contextNote, isNull);
  });

  test('same request id rejects changed active content', () async {
    const store = GuestSetupDataSource();
    const requestId = '40c126a8-b8e3-4e8a-9884-ad30bc1dc1de';
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
            weekdayShape: 'school_or_work',
          ),
        ),
      ),
      throwsA(isA<GuestSetupIdempotencyException>()),
    );
  });

  test('legacy goal and friction fields are removed from local prefill',
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

    expect(state.responses?.frictionPoints, isEmpty);
    final preferences = await SharedPreferences.getInstance();
    final rewritten = preferences.getString(
      GuestSetupDataSource.legacyIntakeKey,
    )!;
    expect(rewritten, isNot(contains('primary_focus_areas')));
    expect(rewritten, isNot(contains('goals')));
    expect(rewritten, isNot(contains('friction_points')));
    expect(rewritten, isNot(contains('coaching_style')));
    expect(rewritten, isNot(contains('reminder_preference')));
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
              'valid_from': '2026-10-01',
              'valid_until': '2027-02-15',
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
    expect(
      state.responses?.fixedCommitments.single.validFrom,
      DateTime.utc(2026, 10, 1),
    );
    expect(
      state.responses?.fixedCommitments.single.validUntil,
      DateTime.utc(2027, 2, 15),
    );
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
    weekdayShape: 'flexible',
    bestEnergyWindow: 'morning',
    routines: [],
    fixedCommitments: [],
    calendarConnectionIntent: null,
  );
}
