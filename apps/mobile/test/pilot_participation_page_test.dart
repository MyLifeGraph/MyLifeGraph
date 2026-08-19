import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/auth_providers.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/features/auth/data/auth_repository.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:my_life_graph/features/auth/domain/pilot_participation.dart';
import 'package:my_life_graph/features/auth/presentation/pages/auth_page.dart';
import 'package:my_life_graph/features/auth/presentation/pages/pilot_participation_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('hosted auth presents notice and has no guest bypass', (
    tester,
  ) async {
    final repository = _PilotAuthRepository(session: null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_stagingConfig),
          authRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: AuthPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Adult pilot and privacy notice'), findsOneWidget);
    expect(find.text('I confirm that I am 18 or older'), findsOneWidget);
    expect(find.text('Continue as guest'), findsNothing);
    expect(find.textContaining('mood, sleep, stress'), findsOneWidget);
  });

  testWidgets('post-auth gate records only after explicit confirmation', (
    tester,
  ) async {
    final repository = _PilotAuthRepository(
      session: AppSession.authenticated(_profile()),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_stagingConfig),
          authRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: PilotParticipationPage()),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(
      FilledButton,
      'Continue to MyLifeGraph',
    );
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.tap(find.text('I confirm that I am 18 or older'));
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(repository.acceptCalls, 1);
  });
}

const _stagingConfig = AppConfig(
  environment: 'staging',
  supabaseUrl: 'https://abcdefghijklmnopqrst.supabase.co',
  supabasePublishableKey: 'sb_publishable_test',
  stagingSupabaseProjectRef: 'abcdefghijklmnopqrst',
  pilotContactEmail: 'pilot-contact@example.test',
  aiServiceBaseUrl: 'https://coach-staging.example.test',
  useMockData: false,
);

AppProfile _profile({bool accepted = false}) => AppProfile(
      id: 'pilot-user',
      email: 'pilot@example.test',
      name: 'Pilot User',
      timezone: 'Europe/Berlin',
      role: AppRole.user,
      onboardingDone: false,
      authProvider: 'email',
      pilotParticipationNoticeVersion:
          accepted ? pilotParticipationNoticeVersion : null,
      pilotParticipationAcceptedAt:
          accepted ? DateTime.utc(2026, 8, 19, 12) : null,
    );

class _PilotAuthRepository extends AuthRepository {
  _PilotAuthRepository({required this.session})
      : super(
          SupabaseClient(
            'http://127.0.0.1:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
          useMockData: false,
          requiresPilotParticipation: true,
        );

  final AppSession? session;
  int acceptCalls = 0;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Future<AppSession?> currentSession() async => session;

  @override
  Future<AppProfile> acceptCurrentPilotParticipation() async {
    acceptCalls += 1;
    return _profile(accepted: true);
  }
}
