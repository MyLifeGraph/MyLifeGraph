import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';

void main() {
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
  });
}

AppProfile _profile({
  String email = 'guest@personal-coach.local',
  String authProvider = 'guest',
}) {
  return AppProfile(
    id: 'profile-id',
    email: email,
    name: 'Review User',
    timezone: 'Europe/Berlin',
    role: authProvider == 'guest' ? AppRole.guest : AppRole.user,
    onboardingDone: true,
    authProvider: authProvider,
  );
}
