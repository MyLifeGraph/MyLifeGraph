import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/auth/data/intake_api_data_source.dart';
import 'package:my_life_graph/features/auth/domain/intake_response.dart';

void main() {
  test('fetchSetup gets typed setup with bearer auth', () async {
    final apiClient = _FakeApiClient(
      getResponse: const {
        'exists': false,
        'revision': 0,
        'base_revision': 0,
        'request_id': null,
        'status': 'not_started',
        'intake_response_id': null,
        'snapshot_id': null,
        'completed_at': null,
        'responses': null,
        'summary': <String, dynamic>{},
      },
    );

    final result = await IntakeApiDataSource(apiClient).fetchSetup(
      accessToken: 'access-token-123',
    );

    expect(apiClient.method, 'GET');
    expect(apiClient.path, '/v1/intake/setup');
    expect(apiClient.headers, {'Authorization': 'Bearer access-token-123'});
    expect(result.exists, isFalse);
    expect(result.revision, 0);
    expect(result.responses, isNull);
  });

  test('completeIntake posts request id, revision, and structured responses',
      () async {
    const requestId = 'a65ee0f6-ddce-4f3a-a36a-eefe94ecf23d';
    final apiClient = _FakeApiClient(
      postResponse: _appliedResponse(requestId),
    );
    final request = IntakeSetupSaveRequest(
      requestId: requestId,
      baseRevision: 2,
      responses: const IntakeResponseDraft(
        displayName: 'Alex',
        primaryFocusAreas: ['energy', 'focus'],
        goals: [
          IntakeGoalDraft(
            key: '41c31425-baa6-4d58-8ac3-01f41ecb50d6',
            title: 'Protect focus time',
          ),
        ],
        frictionPoints: ['Late starts'],
        weekdayShape: 'school_or_work',
        bestEnergyWindow: 'morning',
        coachingStyle: 'direct',
        reminderPreference: IntakeReminderPreference(
          enabled: true,
          quietHoursStart: '21:00',
          quietHoursEnd: '07:00',
        ),
        routines: [
          IntakeRoutineDraft(
            key: '950e9a84-9539-41d8-bf89-0b2a9a46cecc',
            title: 'Walk after lunch',
          ),
        ],
        fixedCommitments: [
          IntakeCommitmentDraft(
            key: 'c5ce5c47-91f5-4505-8c8e-876c06137f39',
            title: 'Math',
            location: 'Room 204',
            weekday: 1,
            startsAt: '08:15',
            endsAt: '09:45',
          ),
        ],
        contextNote: 'Exam week soon.',
        calendarConnectionIntent: 'later',
      ),
    );

    final result = await IntakeApiDataSource(apiClient).completeIntake(
      accessToken: 'access-token-123',
      request: request,
    );

    expect(apiClient.method, 'POST');
    expect(apiClient.path, '/v1/intake/complete');
    expect(apiClient.headers, {'Authorization': 'Bearer access-token-123'});
    expect(apiClient.body?['version'], 'intake-v1');
    expect(apiClient.body?['request_id'], requestId);
    expect(apiClient.body?['base_revision'], 2);
    expect(apiClient.body, isNot(contains('metadata')));

    final responses = apiClient.body?['responses'] as Map<String, dynamic>;
    expect(responses['display_name'], 'Alex');
    expect(responses['primary_focus_areas'], ['energy', 'focus']);
    expect(responses['goals'], [
      {
        'key': '41c31425-baa6-4d58-8ac3-01f41ecb50d6',
        'title': 'Protect focus time',
        'status': 'active',
      },
    ]);
    expect(responses['routines'], [
      {
        'key': '950e9a84-9539-41d8-bf89-0b2a9a46cecc',
        'title': 'Walk after lunch',
        'status': 'candidate',
        'cadence_confirmed': false,
      },
    ]);
    expect(
      (responses['routines'] as List<dynamic>).single,
      isNot(contains('frequency')),
    );
    expect(
      (responses['routines'] as List<dynamic>).single,
      isNot(contains('target')),
    );
    expect(result.exists, isTrue);
    expect(result.status, 'applied');
    expect(result.revision, 3);
    expect(result.responses?.fixedCommitments.single.startsAt, '08:15');
  });
}

Map<String, dynamic> _appliedResponse(String requestId) {
  return {
    'exists': true,
    'revision': 3,
    'base_revision': 2,
    'request_id': requestId,
    'status': 'applied',
    'intake_response_id': 'intake-id',
    'snapshot_id': 'snapshot-id',
    'completed_at': '2026-07-10T08:30:00Z',
    'responses': {
      'display_name': 'Alex',
      'primary_focus_areas': ['energy', 'focus'],
      'goals': [
        {
          'key': '41c31425-baa6-4d58-8ac3-01f41ecb50d6',
          'title': 'Protect focus time',
          'status': 'active',
        },
      ],
      'friction_points': ['Late starts'],
      'weekday_shape': 'school_or_work',
      'best_energy_window': 'morning',
      'coaching_style': 'direct',
      'reminder_preference': {
        'enabled': true,
        'quiet_hours': {
          'starts_at': '21:00:00',
          'ends_at': '07:00:00',
        },
      },
      'routines': [
        {
          'key': '950e9a84-9539-41d8-bf89-0b2a9a46cecc',
          'title': 'Walk after lunch',
          'status': 'candidate',
          'cadence_confirmed': false,
        },
      ],
      'fixed_commitments': [
        {
          'key': 'c5ce5c47-91f5-4505-8c8e-876c06137f39',
          'title': 'Math',
          'location': 'Room 204',
          'weekday': 1,
          'starts_at': '08:15:00',
          'ends_at': '09:45:00',
          'status': 'active',
        },
      ],
      'context_note': 'Exam week soon.',
      'calendar_connection_intent': 'later',
    },
    'summary': {
      'routine_candidate_count': 1,
      'active_habit_count': 0,
    },
  };
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient({
    this.getResponse = const <String, dynamic>{},
    this.postResponse = const <String, dynamic>{},
  }) : super(Dio());

  final Map<String, dynamic> getResponse;
  final Map<String, dynamic> postResponse;
  String? method;
  String? path;
  Map<String, dynamic>? body;
  Map<String, String>? headers;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    method = 'GET';
    this.path = path;
    this.headers = headers;
    return getResponse;
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    method = 'POST';
    this.path = path;
    this.body = body;
    this.headers = headers;
    return postResponse;
  }
}
