import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/auth/data/auth_repository.dart';
import 'package:my_life_graph/features/auth/data/guest_setup_data_source.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:my_life_graph/features/auth/domain/intake_response.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
