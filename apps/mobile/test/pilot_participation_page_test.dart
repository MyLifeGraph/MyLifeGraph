import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/core/navigation/app_routes.dart';
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

  testWidgets(
    'optional hosted auth retains privacy and hides guest and prerequisite',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(_optionalConfig),
            authRepositoryProvider.overrideWithValue(
              _PilotAuthRepository(session: null),
            ),
          ],
          child: const MaterialApp(home: AuthPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('I confirm that I am 18 or older'), findsNothing);
      expect(find.text('Continue as guest'), findsNothing);
      expect(find.text('Read pilot privacy notice'), findsOneWidget);
    },
  );

  testWidgets('optional confirmation requires a deliberate checked submit', (
    tester,
  ) async {
    final repository = _PilotAuthRepository(
      session: AppSession.authenticated(_profile()),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_optionalConfig),
          authRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: PilotParticipationPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Optional. You can use the app without this confirmation.'),
      findsOneWidget,
    );
    final button = find.widgetWithText(FilledButton, 'Save confirmation');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(repository.acceptCalls, 0);
    await tester.tap(find.text('I confirm that I am 18 or older'));
    await tester.pump();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(repository.acceptCalls, 1);
  });

  testWidgets('failed optional confirmation keeps session and allows Back', (
    tester,
  ) async {
    final repository = _PilotAuthRepository(
      session: AppSession.authenticated(_profile()),
      failAcceptance: true,
    );
    final router = GoRouter(
      initialLocation: AppRoutes.pilotParticipation,
      routes: [
        GoRoute(
          path: AppRoutes.pilotParticipation,
          builder: (_, _) => const PilotParticipationPage(),
        ),
        GoRoute(
          path: AppRoutes.dashboard,
          builder: (_, _) => const Scaffold(body: Text('Product destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(_optionalConfig),
        authRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PilotParticipationPage)),
    );
    await tester.tap(find.text('I confirm that I am 18 or older'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save confirmation'));
    await tester.pumpAndSettle();

    expect(repository.acceptCalls, 1);
    expect(repository.signOutCalls, 0);
    final session = container.read(authControllerProvider).requireValue!;
    expect(session.isAuthenticated, isTrue);
    expect(session.profile.hasCurrentPilotParticipation, isFalse);
    expect(find.textContaining('You can keep using the app'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path,
        AppRoutes.pilotParticipation);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);

    await tester.tap(find.byKey(const ValueKey('app-page-back')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.dashboard);
    expect(find.text('Product destination'), findsOneWidget);
    expect(repository.signOutCalls, 0);
    expect(container.read(authControllerProvider).requireValue!.isAuthenticated,
        isTrue);
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
  _PilotAuthRepository({required this.session, this.failAcceptance = false})
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
  final bool failAcceptance;
  int acceptCalls = 0;
  int signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
  }

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Future<AppSession?> currentSession() async => session;

  @override
  Future<AppProfile> acceptCurrentPilotParticipation() async {
    acceptCalls += 1;
    if (failAcceptance) throw StateError('Synthetic acceptance failure');
    return _profile(accepted: true);
  }
}

const _optionalConfig = AppConfig(
  environment: 'pilot',
  supabaseUrl: 'https://abcdefghijklmnopqrst.supabase.co',
  supabasePublishableKey: 'sb_publishable_test',
  pilotContactEmail: 'pilot-contact@example.test',
  aiServiceBaseUrl: 'https://coach.example.test',
  useMockData: false,
  pilotParticipationRequired: false,
);
