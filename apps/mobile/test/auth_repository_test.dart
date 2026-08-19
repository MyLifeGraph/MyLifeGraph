import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/auth/data/auth_repository.dart';
import 'package:my_life_graph/features/auth/data/guest_setup_data_source.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:my_life_graph/features/auth/domain/auth_failure.dart';
import 'package:my_life_graph/features/auth/domain/intake_response.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('mock and authenticated demo profiles never migrate guest check-ins',
      () {
    final regular = _profile(email: 'person@example.test');
    final demo = _profile(email: 'demo@personal-coach.local');

    expect(
      shouldMigrateGuestCheckIns(useMockData: true, profile: regular),
      isFalse,
    );
    expect(
      shouldMigrateGuestCheckIns(useMockData: false, profile: demo),
      isFalse,
    );
    expect(
      shouldMigrateGuestCheckIns(useMockData: false, profile: regular),
      isTrue,
    );
  });

  test('mock and demo auth identities skip remote profile reads at boot', () {
    expect(
      shouldReadRemoteProfileForAuthIdentity(
        useMockData: true,
        email: 'stale-auth@example.test',
        authProvider: 'email',
      ),
      isFalse,
    );
    expect(
      shouldReadRemoteProfileForAuthIdentity(
        useMockData: false,
        email: 'demo@personal-coach.local',
        authProvider: 'email',
      ),
      isFalse,
    );
    expect(
      shouldReadRemoteProfileForAuthIdentity(
        useMockData: false,
        email: 'person@example.test',
        authProvider: 'email',
      ),
      isTrue,
    );
  });

  test('missing real profile fails after one read without a repair write',
      () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-anon-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
      accessToken: () async => 'test-access-token',
    );
    addTearDown(client.dispose);
    final repository = AuthRepository(client, useMockData: false);
    const user = User(
      id: 'missing-profile-user',
      appMetadata: {'provider': 'email'},
      userMetadata: {'display_name': 'Profile-less Person'},
      aud: 'authenticated',
      email: 'profile-less@example.test',
      createdAt: '2026-07-31T08:00:00Z',
    );

    await expectLater(
      repository.requireProfileForAuthUser(user),
      throwsA(isA<MissingProfileInvariantException>()),
    );

    expect(requests, hasLength(1));
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/rest/v1/profiles');
    expect(
      requests.single.url.queryParameters['id'],
      'eq.missing-profile-user',
    );
  });

  test('authenticated local-demo reload overlays local setup name and state',
      () async {
    const dataSource = GuestSetupDataSource();
    await dataSource.save(
      IntakeSetupSaveRequest(
        requestId: 'd486cd80-dd1c-4252-abde-481a75f08042',
        baseRevision: 0,
        responses: _requiredDraft().copyWith(displayName: 'Local Setup Name'),
      ),
    );
    final remoteProfile = _profile(
      email: 'demo@personal-coach.local',
      name: 'Remote Profile Name',
      onboardingDone: false,
    );

    final overlaid = await overlayLocalDemoSetup(
      profile: remoteProfile,
      dataSource: dataSource,
    );

    expect(overlaid.name, 'Local Setup Name');
    expect(overlaid.onboardingDone, isTrue);
  });

  test('profile participation comes from backend columns, not user metadata',
      () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-anon-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          '''[{"id":"profile-id","email":"person@example.test","display_name":"Person","timezone":"Europe/Berlin","daily_preparation_budget_minutes":null,"timezone_revision":1,"preparation_budget_revision":1,"auth_provider":"email","onboarding_completed_at":null,"role":"user","pilot_participation_notice_version":"pilot-participation-notice-v1","pilot_participation_accepted_at":"2026-08-19T12:00:00Z"}]''',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
      accessToken: () async => 'test-access-token',
    );
    addTearDown(client.dispose);
    final repository = AuthRepository(client, useMockData: false);
    const user = User(
      id: 'profile-id',
      appMetadata: {'provider': 'email'},
      userMetadata: {'pilot_participation_notice_version': 'forged-v99'},
      aud: 'authenticated',
      email: 'person@example.test',
      createdAt: '2026-08-19T08:00:00Z',
    );

    final profile = await repository.requireProfileForAuthUser(user);

    expect(profile.hasCurrentPilotParticipation, isTrue);
    expect(requests, hasLength(1));
    expect(
      requests.single.url.queryParameters['select'],
      contains('pilot_participation_accepted_at'),
    );
  });

  test('authenticated local-demo reload honors compatibility setup prefs',
      () async {
    SharedPreferences.setMockInitialValues({
      GuestSetupDataSource.guestNameKey: 'Compatibility Name',
      GuestSetupDataSource.guestOnboardingDoneKey: true,
    });

    final overlaid = await overlayLocalDemoSetup(
      profile: _profile(
        email: 'demo@personal-coach.local',
        name: 'Auth Metadata Name',
        onboardingDone: false,
      ),
      dataSource: const GuestSetupDataSource(),
    );

    expect(overlaid.name, 'Compatibility Name');
    expect(overlaid.onboardingDone, isTrue);
  });

  test('local-demo onboarding state never falls through from a remote profile',
      () async {
    final overlaid = await overlayLocalDemoSetup(
      profile: _profile(
        email: 'demo@personal-coach.local',
        onboardingDone: true,
      ),
      dataSource: const GuestSetupDataSource(),
    );

    expect(overlaid.onboardingDone, isFalse);
  });
}

AppProfile _profile({
  required String email,
  String name = 'Remote Name',
  bool onboardingDone = false,
}) {
  return AppProfile(
    id: 'profile-id',
    email: email,
    name: name,
    timezone: 'Europe/Berlin',
    role: AppRole.user,
    onboardingDone: onboardingDone,
    authProvider: 'email',
  );
}

IntakeResponseDraft _requiredDraft() {
  return const IntakeResponseDraft(
    displayName: null,
    weekdayShape: 'flexible',
    bestEnergyWindow: 'morning',
    routines: [],
    fixedCommitments: [],
    calendarConnectionIntent: null,
  );
}
