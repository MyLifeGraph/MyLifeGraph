import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:my_life_graph/features/optimization/presentation/providers/optimization_providers.dart';

void main() {
  test('explicit mock configuration selects recommendation demo data', () {
    expect(
      usesRecommendationDemoData(
        config: _config(useMockData: true),
        session: AppSession.authenticated(_profile()),
      ),
      isTrue,
    );
  });

  test('guest session selects recommendation demo data', () {
    expect(
      usesRecommendationDemoData(
        config: _config(useMockData: false),
        session: AppSession.guest(
          _profile(
            email: 'guest@personal-coach.local',
            role: AppRole.guest,
            authProvider: 'guest',
          ),
        ),
      ),
      isTrue,
    );
  });

  test('authenticated real session never selects recommendation demo data', () {
    expect(
      usesRecommendationDemoData(
        config: _config(useMockData: false),
        session: AppSession.authenticated(_profile()),
      ),
      isFalse,
    );
  });

  test('guest profile role cannot enter the real recommendation path', () {
    expect(
      usesRecommendationDemoData(
        config: _config(useMockData: false),
        session: AppSession.authenticated(_profile(role: AppRole.guest)),
      ),
      isTrue,
    );
  });

  test('missing session is not silently treated as demo', () {
    expect(
      usesRecommendationDemoData(
        config: _config(useMockData: false),
        session: null,
      ),
      isFalse,
    );
  });
}

AppConfig _config({required bool useMockData}) {
  return AppConfig(
    environment: 'test',
    supabaseUrl: 'http://127.0.0.1:54321',
    supabaseAnonKey: 'anon-key',
    aiServiceBaseUrl: 'http://localhost:8000',
    useMockData: useMockData,
  );
}

AppProfile _profile({
  String email = 'real@example.com',
  AppRole role = AppRole.user,
  String authProvider = 'email',
}) {
  return AppProfile(
    id: 'profile-1',
    email: email,
    name: 'Test User',
    timezone: 'Europe/Berlin',
    role: role,
    onboardingDone: true,
    authProvider: authProvider,
  );
}
