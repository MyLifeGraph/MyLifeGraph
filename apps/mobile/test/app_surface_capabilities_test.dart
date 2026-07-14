import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';

void main() {
  test('explicit release gating hides Coach and blocks backend access', () {
    final capabilities = AppSurfaceCapabilities.forSession(
      session: AppSession.authenticated(
        _profile(email: 'person@example.test', authProvider: 'email'),
      ),
      useMockData: false,
      hasSupabaseClient: true,
      coachSurfaceEnabled: false,
    );

    expect(capabilities.canShowCoachSurface, isFalse);
    expect(capabilities.canAccessCoachBackend, isFalse);
  });

  test('guest session exposes only local capabilities', () {
    final capabilities = AppSurfaceCapabilities.forSession(
      session: AppSession.guest(_profile(authProvider: 'guest')),
      useMockData: false,
      hasSupabaseClient: true,
    );

    expect(capabilities.isLocalDemo, isTrue);
    expect(capabilities.canUseSyncedHabits, isFalse);
    expect(capabilities.canUseSyncedExecution, isFalse);
    expect(capabilities.canUseWeeklyReview, isFalse);
    expect(capabilities.canUseCalendarIntegration, isFalse);
    expect(capabilities.canAccessCoachBackend, isFalse);
  });

  test('demo account remains local even with a Supabase client', () {
    final capabilities = AppSurfaceCapabilities.forSession(
      session: AppSession.authenticated(
        _profile(
          email: 'demo@personal-coach.local',
          authProvider: 'email',
        ),
      ),
      useMockData: false,
      hasSupabaseClient: true,
    );

    expect(capabilities.isLocalDemo, isTrue);
    expect(capabilities.canUseSyncedHabits, isFalse);
    expect(capabilities.canUseSyncedExecution, isFalse);
    expect(capabilities.canUseWeeklyReview, isFalse);
    expect(capabilities.canUseCalendarIntegration, isFalse);
    expect(capabilities.canAccessCoachBackend, isFalse);
  });

  test('authenticated profile with guest role cannot access Coach backend', () {
    final capabilities = AppSurfaceCapabilities.forSession(
      session: AppSession.authenticated(
        _profile(
          email: 'guest-role@example.test',
          authProvider: 'email',
          role: AppRole.guest,
        ),
      ),
      useMockData: false,
      hasSupabaseClient: true,
    );

    expect(capabilities.isLocalDemo, isTrue);
    expect(capabilities.canUseSyncedExecution, isFalse);
    expect(capabilities.canAccessCoachBackend, isFalse);
  });

  test('Supabase anonymous auth provider is local regardless of casing', () {
    for (final authProvider in ['anonymous', 'Anonymous', ' ANONYMOUS ']) {
      final capabilities = AppSurfaceCapabilities.forSession(
        session: AppSession.authenticated(
          _profile(
            email: '',
            authProvider: authProvider,
            role: AppRole.user,
          ),
        ),
        useMockData: false,
        hasSupabaseClient: true,
      );

      expect(
        capabilities.isLocalDemo,
        isTrue,
        reason: 'provider=$authProvider',
      );
      expect(
        capabilities.canUseSyncedExecution,
        isFalse,
        reason: 'provider=$authProvider',
      );
      expect(
        capabilities.canAccessCoachBackend,
        isFalse,
        reason: 'provider=$authProvider',
      );
    }
  });

  test('authenticated account can use Supabase-backed habits', () {
    final capabilities = AppSurfaceCapabilities.forSession(
      session: AppSession.authenticated(
        _profile(email: 'person@example.test', authProvider: 'email'),
      ),
      useMockData: false,
      hasSupabaseClient: true,
    );

    expect(capabilities.isLocalDemo, isFalse);
    expect(capabilities.canUseSyncedHabits, isTrue);
    expect(capabilities.canUseSyncedExecution, isTrue);
    expect(capabilities.canUseWeeklyReview, isTrue);
    expect(capabilities.canUseCalendarIntegration, isTrue);
    expect(capabilities.canAccessCoachBackend, isTrue);
  });

  test('mock configuration never exposes synced habits', () {
    final capabilities = AppSurfaceCapabilities.forSession(
      session: AppSession.authenticated(
        _profile(email: 'person@example.test', authProvider: 'email'),
      ),
      useMockData: true,
      hasSupabaseClient: true,
    );

    expect(capabilities.isLocalDemo, isTrue);
    expect(capabilities.canUseSyncedHabits, isFalse);
    expect(capabilities.canUseSyncedExecution, isFalse);
    expect(capabilities.canUseWeeklyReview, isFalse);
    expect(capabilities.canUseCalendarIntegration, isFalse);
    expect(capabilities.canAccessCoachBackend, isFalse);
  });
}

AppProfile _profile({
  String email = 'guest@personal-coach.local',
  String authProvider = 'guest',
  AppRole? role,
}) {
  return AppProfile(
    id: 'profile-id',
    email: email,
    name: 'Review User',
    timezone: 'Europe/Berlin',
    role: role ?? (authProvider == 'guest' ? AppRole.guest : AppRole.user),
    onboardingDone: true,
    authProvider: authProvider,
  );
}
