import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/auth/data/intake_api_data_source.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:my_life_graph/features/auth/domain/intake_response.dart';

void main() {
  test('completeIntake posts structured payload with bearer auth', () async {
    final apiClient = _FakeApiClient();
    final dataSource = IntakeApiDataSource(apiClient);

    await dataSource.completeIntake(
      accessToken: 'access-token-123',
      intake: const IntakeResponseDraft(
        displayName: 'Alex',
        primaryFocusAreas: ['energy', 'focus'],
        goals: ['Protect focus time'],
        frictionPoints: ['Late starts'],
        weekdayShape: 'school_or_work',
        bestEnergyWindow: 'morning',
        coachingStyle: 'direct',
        reminderPreference: IntakeReminderPreference(
          enabled: true,
          quietHoursStart: '21:00',
          quietHoursEnd: '07:00',
        ),
        existingHabits: ['Walk after lunch'],
        fixedCommitments: [
          TimetableDraft(
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

    expect(apiClient.path, '/v1/intake/complete');
    expect(apiClient.headers, {'Authorization': 'Bearer access-token-123'});
    expect(apiClient.body?['version'], 'intake-v1');
    expect(apiClient.body?['metadata'], {
      'client': 'flutter',
      'source': 'onboarding',
    });

    final responses = apiClient.body?['responses'] as Map<String, dynamic>;
    expect(responses['display_name'], 'Alex');
    expect(responses['primary_focus_areas'], ['energy', 'focus']);
    expect(responses['goals'], ['Protect focus time']);
    expect(responses['friction_points'], ['Late starts']);
    expect(responses['weekday_shape'], 'school_or_work');
    expect(responses['best_energy_window'], 'morning');
    expect(responses['coaching_style'], 'direct');
    expect(responses['calendar_connection_intent'], 'later');
    expect(responses['reminder_preference'], {
      'enabled': true,
      'quiet_hours': {
        'starts_at': '21:00',
        'ends_at': '07:00',
      },
    });
    expect(responses['fixed_commitments'], [
      {
        'title': 'Math',
        'location': 'Room 204',
        'weekday': 1,
        'starts_at': '08:15',
        'ends_at': '09:45',
      },
    ]);
  });
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(Dio());

  String? path;
  Map<String, dynamic>? body;
  Map<String, String>? headers;

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    this.path = path;
    this.body = body;
    this.headers = headers;
    return <String, dynamic>{};
  }
}
