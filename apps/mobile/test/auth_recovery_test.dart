import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/app.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/navigation/app_router.dart';
import 'package:my_life_graph/core/navigation/app_routes.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/auth/data/auth_repository.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:my_life_graph/features/auth/domain/auth_failure.dart';
import 'package:my_life_graph/features/auth/domain/auth_captcha.dart';
import 'package:my_life_graph/features/auth/presentation/captcha/auth_captcha_challenge.dart';
import 'package:my_life_graph/features/auth/presentation/pages/auth_page.dart';
import 'package:my_life_graph/features/auth/presentation/pages/password_recovery_page.dart';
import 'package:my_life_graph/composition/auth_providers.dart';
import 'package:my_life_graph/composition/coach_credential_store_provider.dart';
import 'package:my_life_graph/features/coach/data/coach_credential_store.dart';
import 'package:my_life_graph/features/coach/domain/coach.dart';
import 'package:my_life_graph/features/settings/presentation/pages/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late PlatformCoachCredentialStore credentialStore;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    credentialStore = PlatformCoachCredentialStore(web: true);
  });

  testWidgets('auth uses a focused two-column layout on wide screens',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_testAppConfig),
          authRepositoryProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AuthPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final intro = find.text('Build your day-aware coach');
    final email = find.widgetWithText(TextField, 'Email');
    expect(intro, findsOneWidget);
    expect(email, findsOneWidget);
    expect(tester.getCenter(intro).dx, lessThan(tester.getCenter(email).dx));
    expect(find.text('Continue as guest'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth remains usable at 320 px with 200 percent text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_testAppConfig),
          authRepositoryProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const AuthPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Build your day-aware coach'), findsOneWidget);
    await tester.ensureVisible(find.text('Continue as guest'));
    await tester.pumpAndSettle();
    expect(find.text('Continue as guest'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth help requests reset and confirmation emails honestly',
      (tester) async {
    final repository = _FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_testAppConfig),
          authRepositoryProvider.overrideWithValue(repository),
          coachCredentialStoreProvider.overrideWithValue(credentialStore),
        ],
        child: const MaterialApp(home: AuthPage()),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AuthPage)),
    );
    container.read(authNoticeProvider.notifier).state = const AuthNotice(
      'Account and saved synced data deleted.',
    );
    await tester.pump();
    expect(
      find.text('Account and saved synced data deleted.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Dismiss'));
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    expect(
      find.text('Account and saved synced data deleted.'),
      findsNothing,
    );
    container.read(authNoticeProvider.notifier).state = const AuthNotice(
      'Deletion could not be confirmed.',
      isError: true,
    );
    await tester.pump();
    expect(
      find.bySemanticsLabel('Error. Deletion could not be confirmed.'),
      findsOneWidget,
    );
    container.read(authNoticeProvider.notifier).state = null;
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'person@example.test',
    );
    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(repository.passwordResetEmails, ['person@example.test']);
    expect(
      find.textContaining('a password-reset link has been sent'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account').first);
    await tester.pump();
    await tester.ensureVisible(find.text('Resend confirmation email'));
    await tester.tap(find.text('Resend confirmation email'));
    await tester.pumpAndSettle();

    expect(repository.confirmationEmails, ['person@example.test']);
    expect(
      find.text('If confirmation is still pending, a new email has been sent.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Continue as guest'));
    final guestSemantics =
        tester.widgetList<Semantics>(find.byType(Semantics)).singleWhere(
              (widget) => widget.properties.label == 'Continue as guest',
            );
    expect(guestSemantics.properties.button, isTrue);
    expect(guestSemantics.properties.enabled, isTrue);
    expect(guestSemantics.properties.onTap, isNotNull);
    expect(guestSemantics.properties.hint, isNotEmpty);
    expect(
      find.ancestor(
        of: find.text('Sign in with Google'),
        matching: find.byType(InkWell),
      ),
      findsOneWidget,
    );
  });

  testWidgets('failed registration never claims that confirmation was sent',
      (tester) async {
    final repository = _FakeAuthRepository(failRegistration: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_testAppConfig),
          authRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: AuthPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create account').first);
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'person@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password',
    );
    final createAccount = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(createAccount);
    await tester.tap(createAccount);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Authentication failed. Check your details and connection, then try again.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Check your email to confirm registration'),
      findsNothing,
    );
  });

  testWidgets('hosted email actions acquire and forward a fresh CAPTCHA token',
      (tester) async {
    final repository = _FakeAuthRepository();
    final captcha = _RecordingCaptchaChallenge();
    const hostedConfig = AppConfig(
      environment: 'staging',
      supabaseUrl: 'https://abcdefghijklmnopqrst.supabase.co',
      supabasePublishableKey: 'sb_publishable_test',
      stagingSupabaseProjectRef: 'abcdefghijklmnopqrst',
      pilotContactEmail: 'pilot-contact@example.test',
      appPublicOrigin: 'https://app.example.test',
      turnstileSiteKey: '1x00000000000000000000AA',
      aiServiceBaseUrl: 'https://coach.example.test',
      useMockData: false,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(hostedConfig),
          authRepositoryProvider.overrideWithValue(repository),
          authCaptchaChallengeProvider.overrideWithValue(captcha),
        ],
        child: const MaterialApp(home: AuthPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'person@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password',
    );
    final signIn = find.widgetWithText(FilledButton, 'Sign in');
    await tester.ensureVisible(signIn);
    await tester.tap(signIn);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(captcha.actions, [
      AuthCaptchaAction.signIn,
      AuthCaptchaAction.passwordReset,
    ]);
    expect(repository.signInCaptchaTokens, ['captcha-signin-1']);
    expect(repository.passwordResetCaptchaTokens, [
      'captcha-password_reset-2',
    ]);
  });

  testWidgets('missing synced profile fails closed and offers sign-out',
      (tester) async {
    final repository = _FakeAuthRepository(
      signInError: const MissingProfileInvariantException(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_testAppConfig),
          authRepositoryProvider.overrideWithValue(repository),
          coachCredentialStoreProvider.overrideWithValue(credentialStore),
        ],
        child: const MaterialApp(home: AuthPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'profile-less@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password',
    );
    final loginButton = find.widgetWithText(FilledButton, 'Sign in');
    await tester.ensureVisible(loginButton);
    await tester.tap(loginButton);
    await tester.pumpAndSettle();

    const unavailable =
        'Your sign-in succeeded, but this synced account could not be opened. No account data was changed. Sign out, then try again. If it continues, the account needs repair.';
    expect(find.text(unavailable), findsOneWidget);
    expect(
      find.text(
        'Authentication failed. Check your details and connection, then try again.',
      ),
      findsNothing,
    );

    final signOut = find.widgetWithText(TextButton, 'Sign out');
    await tester.ensureVisible(signOut);
    await tester.tap(signOut);
    await tester.pumpAndSettle();

    expect(repository.signOutCalls, 1);
    expect(find.text(unavailable), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing Supabase configuration keeps email auth honest',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_testAppConfig),
          authRepositoryProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: AuthPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'person@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password',
    );
    final loginButton = find.widgetWithText(FilledButton, 'Sign in');
    await tester.ensureVisible(loginButton);
    await tester.tap(loginButton);
    await tester.pumpAndSettle();

    const unavailable =
        'Synced sign-in is unavailable right now. Continue as guest or try again later.';
    expect(find.text(unavailable), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account').first);
    await tester.pump();
    final createButton = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(find.text(unavailable), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Google OAuth false launch result is an explicit failure', () async {
    String? receivedRedirect;
    final repository = AuthRepository(
      SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
      useMockData: false,
      googleOAuthLauncher: (redirectTo) async {
        receivedRedirect = redirectTo;
        return false;
      },
    );

    await expectLater(
      repository.signInWithGoogle(),
      throwsA(isA<AuthException>()),
    );
    expect(receivedRedirect, authRedirectUrl());
  });

  testWidgets('late Google OAuth failure is safe after leaving auth',
      (tester) async {
    final launch = Completer<void>();
    final showAuth = ValueNotifier<bool>(true);
    addTearDown(showAuth.dispose);
    final repository = _FakeAuthRepository(
      googleSignInCompleter: launch,
      googleSignInError: StateError('launcher failed'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_testAppConfig),
          authRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: showAuth,
            builder: (_, visible, __) => visible
                ? const AuthPage()
                : const Scaffold(body: Text('Different page')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Sign in with Google'));
    await tester.tap(find.text('Sign in with Google'));
    await tester.pump();
    showAuth.value = false;
    await tester.pump();
    expect(find.text('Different page'), findsOneWidget);

    launch.complete();
    await tester.pumpAndSettle();

    expect(repository.googleSignInCalls, 1);
    expect(tester.takeException(), isNull);
  });

  test('password recovery auth event activates the recovery route state',
      () async {
    final repository = _FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        coachCredentialStoreProvider.overrideWithValue(credentialStore),
      ],
    );
    addTearDown(container.dispose);
    container.read(authControllerProvider);
    await Future<void>.delayed(Duration.zero);

    repository.emitPasswordRecovery();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(passwordRecoveryActiveProvider), isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(passwordRecoveryActivePreferenceKey),
      isTrue,
    );
  });

  test('startup restore cannot overwrite a newer recovery auth event',
      () async {
    final repository = _FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        coachCredentialStoreProvider.overrideWithValue(credentialStore),
      ],
    );
    addTearDown(container.dispose);

    container.read(authControllerProvider);
    repository.emitPasswordRecovery();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(passwordRecoveryActiveProvider), isTrue);
  });

  test('password recovery route state survives provider recreation', () async {
    SharedPreferences.setMockInitialValues({
      passwordRecoveryActivePreferenceKey: true,
    });
    final first = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
      ],
    );
    first.read(authControllerProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(first.read(passwordRecoveryActiveProvider), isTrue);
    first.dispose();

    final second = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
      ],
    );
    addTearDown(second.dispose);
    second.read(authControllerProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(second.read(passwordRecoveryActiveProvider), isTrue);
  });

  test(
      'deleted-account finalization clears state even if remote sign-out fails',
      () async {
    final repository = _FakeAuthRepository(
      current: AppSession.authenticated(_profile()),
      failDeletedAccountSignOut: true,
    );
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        coachCredentialStoreProvider.overrideWithValue(credentialStore),
      ],
    );
    addTearDown(container.dispose);
    container.read(authControllerProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(authControllerProvider).valueOrNull, isNotNull);

    await expectLater(
      container.read(authControllerProvider.notifier).finalizeDeletedAccount(),
      throwsStateError,
    );

    expect(container.read(authControllerProvider).valueOrNull, isNull);
    expect(container.read(authControllerProvider).isLoading, isFalse);
    expect(repository.deletedAccountSignOutCalls, 1);
  });

  test('normal sign-out clears controller state even when cleanup throws',
      () async {
    final repository = _FakeAuthRepository(
      current: AppSession.authenticated(_profile()),
      failSignOut: true,
    );
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        coachCredentialStoreProvider.overrideWithValue(credentialStore),
      ],
    );
    addTearDown(container.dispose);
    container.read(authControllerProvider);
    await Future<void>.delayed(Duration.zero);

    await expectLater(
      container.read(authControllerProvider.notifier).signOut(),
      throwsStateError,
    );

    expect(container.read(authControllerProvider).valueOrNull, isNull);
    expect(container.read(authControllerProvider).isLoading, isFalse);
    expect(repository.signOutCalls, 1);
  });

  test(
      'provider-wired sign-out deletes BYOK credentials before remote sign-out',
      () async {
    final repository = _FakeAuthRepository(
      current: AppSession.authenticated(_profile()),
    );
    await credentialStore.write(
      _profile().id,
      CoachProviderName.openai,
      'device-secret',
    );
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        coachCredentialStoreProvider.overrideWithValue(credentialStore),
      ],
    );
    addTearDown(container.dispose);
    container.read(authControllerProvider);
    await Future<void>.delayed(Duration.zero);

    await container.read(authControllerProvider.notifier).signOut();

    expect(
      await credentialStore.read(_profile().id, CoachProviderName.openai),
      isNull,
    );
    expect(repository.signOutCalls, 1);
  });

  test('credential cleanup failure blocks sign-out and preserves the session',
      () async {
    final repository = _FakeAuthRepository(
      current: AppSession.authenticated(_profile()),
    );
    final controller = AuthController(
      repository,
      clearCoachCredentials: () async {
        throw StateError('secure storage cleanup failed');
      },
    );
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);

    await expectLater(controller.signOut(), throwsStateError);

    expect(controller.state.valueOrNull, isNotNull);
    expect(repository.signOutCalls, 0);
  });

  test('sign-out waits for credential cleanup before calling Supabase',
      () async {
    final repository = _FakeAuthRepository(
      current: AppSession.authenticated(_profile()),
    );
    final cleanup = Completer<void>();
    final controller = AuthController(
      repository,
      clearCoachCredentials: () => cleanup.future,
    );
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);

    final signOut = controller.signOut();
    await Future<void>.delayed(Duration.zero);
    expect(repository.signOutCalls, 0);
    cleanup.complete();
    await signOut;

    expect(repository.signOutCalls, 1);
    expect(controller.state.valueOrNull, isNull);
  });

  test('a delayed pre-logout profile load cannot resurrect the session',
      () async {
    final repository = _FakeAuthRepository(
      current: AppSession.authenticated(_profile()),
    );
    final controller = AuthController(repository);
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.valueOrNull, isNotNull);

    final delayed = Completer<AppSession?>();
    repository.delayedCurrentSession = delayed;
    final staleRefresh = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    await controller.signOut();
    delayed.complete(AppSession.authenticated(_profile()));
    await staleRefresh;

    expect(controller.state.valueOrNull, isNull);
    expect(repository.signOutCalls, 1);
  });

  test('a delayed pre-deletion profile load cannot resurrect the session',
      () async {
    final repository = _FakeAuthRepository(
      current: AppSession.authenticated(_profile()),
    );
    final controller = AuthController(repository);
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);

    final delayed = Completer<AppSession?>();
    repository.delayedCurrentSession = delayed;
    final staleRefresh = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    await controller.finalizeDeletedAccount(
      coachCredentialsAlreadyCleared: true,
    );
    delayed.complete(AppSession.authenticated(_profile()));
    await staleRefresh;

    expect(controller.state.valueOrNull, isNull);
    expect(repository.deletedAccountSignOutCalls, 1);
  });

  test('account deletion preparation fails closed on credential cleanup error',
      () async {
    final repository = _FakeAuthRepository(
      current: AppSession.authenticated(_profile()),
    );
    final controller = AuthController(
      repository,
      clearCoachCredentials: () async {
        throw StateError('secure storage cleanup failed');
      },
    );
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);

    await expectLater(controller.prepareAccountDeletion(), throwsStateError);

    expect(controller.state.valueOrNull, isNotNull);
    expect(repository.deletedAccountSignOutCalls, 0);
  });

  test('deleted-account finalization can reuse an already completed cleanup',
      () async {
    final repository = _FakeAuthRepository(
      current: AppSession.authenticated(_profile()),
    );
    var cleanupCalls = 0;
    final controller = AuthController(
      repository,
      clearCoachCredentials: () async {
        cleanupCalls += 1;
      },
    );
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);

    await controller.finalizeDeletedAccount(
      coachCredentialsAlreadyCleared: true,
    );

    expect(cleanupCalls, 0);
    expect(repository.deletedAccountSignOutCalls, 1);
    expect(controller.state.valueOrNull, isNull);
  });

  testWidgets('recovery page validates and completes a new password',
      (tester) async {
    final repository = _FakeAuthRepository(
      current: AppSession.authenticated(_profile()),
    );
    final router = GoRouter(
      initialLocation: AppRoutes.passwordRecovery,
      routes: [
        GoRoute(
          path: AppRoutes.passwordRecovery,
          builder: (_, __) => const PasswordRecoveryPage(),
        ),
        GoRoute(
          path: AppRoutes.dashboard,
          builder: (_, __) => const Scaffold(body: Text('Recovered dashboard')),
        ),
        GoRoute(
          path: AppRoutes.auth,
          builder: (_, __) => const Scaffold(body: Text('Login page')),
        ),
        GoRoute(
          path: AppRoutes.onboarding,
          builder: (_, __) => const Scaffold(body: Text('Setup page')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'New password'),
      'new-secure-password',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm new password'),
      'different-password',
    );
    await tester.tap(find.text('Update password'));
    await tester.pump();
    expect(find.text('The passwords do not match.'), findsOneWidget);
    expect(repository.updatedPasswords, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm new password'),
      'new-secure-password',
    );
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();

    expect(repository.updatedPasswords, ['new-secure-password']);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(passwordRecoveryActivePreferenceKey),
      isFalse,
    );
    expect(find.text('Recovered dashboard'), findsOneWidget);
  });

  testWidgets('app router prioritizes an active password recovery event',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      passwordRecoveryActivePreferenceKey: true,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              environment: 'test',
              supabaseUrl: '',
              supabaseAnonKey: '',
              aiServiceBaseUrl: 'http://localhost:8000',
              useMockData: true,
            ),
          ),
          passwordRecoveryActiveProvider.overrideWith((_) => true),
        ],
        child: const PersonalOptimizationApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose a new password'), findsOneWidget);
  });

  testWidgets('real app keeps recovery feedback visible through route exit',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      passwordRecoveryActivePreferenceKey: true,
    });
    final repository = _FakeAuthRepository(
      current: AppSession.authenticated(_profile()),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_testAppConfig),
          authRepositoryProvider.overrideWithValue(repository),
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseSyncedExecution: true,
            ),
          ),
        ],
        child: const PersonalOptimizationApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PasswordRecoveryPage), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'New password'),
      'new-secure-password',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm new password'),
      'new-secure-password',
    );
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();

    expect(repository.updatedPasswords, ['new-secure-password']);
    expect(find.byType(PasswordRecoveryPage), findsNothing);
    expect(find.text('Password updated.'), findsOneWidget);
  });

  testWidgets('profile projection refresh keeps the current Settings route',
      (tester) async {
    final repository = _FakeAuthRepository(
      current: AppSession.authenticated(_profile()),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_testAppConfig),
          authRepositoryProvider.overrideWithValue(repository),
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseSyncedExecution: true,
            ),
          ),
        ],
        child: const PersonalOptimizationApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PersonalOptimizationApp)),
    );
    final router = container.read(appRouterProvider);
    router.go(AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    container
        .read(authControllerProvider.notifier)
        .updateProfileTimezone('Europe/London', revision: 2);
    await tester.pumpAndSettle();

    expect(identical(router, container.read(appRouterProvider)), isTrue);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('Europe/London'), findsOneWidget);
  });
}

const _testAppConfig = AppConfig(
  environment: 'test',
  supabaseUrl: '',
  supabaseAnonKey: '',
  aiServiceBaseUrl: 'http://localhost:8000',
  useMockData: true,
);

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({
    this.current,
    this.failSignOut = false,
    this.failDeletedAccountSignOut = false,
    this.failRegistration = false,
    this.signInError,
    this.googleSignInCompleter,
    this.googleSignInError,
  }) : super(
          SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
          useMockData: false,
        );

  final AppSession? current;
  final bool failSignOut;
  final bool failDeletedAccountSignOut;
  final bool failRegistration;
  final Object? signInError;
  final Completer<void>? googleSignInCompleter;
  final Object? googleSignInError;
  Completer<AppSession?>? delayedCurrentSession;
  final _authStates = StreamController<AuthState>.broadcast();
  final List<String> passwordResetEmails = [];
  final List<String?> passwordResetCaptchaTokens = [];
  final List<String> confirmationEmails = [];
  final List<String?> signInCaptchaTokens = [];
  final List<String> updatedPasswords = [];
  int signOutCalls = 0;
  int deletedAccountSignOutCalls = 0;
  int googleSignInCalls = 0;

  @override
  Stream<AuthState> get authStateChanges => _authStates.stream;

  @override
  Future<AppSession?> currentSession() async {
    final delayed = delayedCurrentSession;
    if (delayed != null) {
      delayedCurrentSession = null;
      return delayed.future;
    }
    return current;
  }

  @override
  Future<void> requestPasswordReset({
    required String email,
    String? captchaToken,
  }) async {
    passwordResetEmails.add(email);
    passwordResetCaptchaTokens.add(captchaToken);
  }

  @override
  Future<AppSession> signInWithEmail({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    final error = signInError;
    if (error != null) throw error;
    signInCaptchaTokens.add(captchaToken);
    return AppSession.authenticated(_profile());
  }

  @override
  Future<AppSession?> registerWithEmail({
    required String email,
    required String password,
    String? name,
    bool confirmed18OrOlder = false,
    String? captchaToken,
  }) async {
    if (failRegistration) {
      throw const AuthException('registration failed');
    }
    return null;
  }

  @override
  Future<void> resendSignupConfirmation({
    required String email,
    String? captchaToken,
  }) async {
    confirmationEmails.add(email);
  }

  @override
  Future<void> updatePassword({required String password}) async {
    updatedPasswords.add(password);
  }

  @override
  Future<void> signInWithGoogle({bool confirmed18OrOlder = false}) async {
    googleSignInCalls += 1;
    final completer = googleSignInCompleter;
    if (completer != null) await completer.future;
    final error = googleSignInError;
    if (error != null) throw error;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    if (failSignOut) {
      throw StateError('remote sign-out failed');
    }
  }

  @override
  Future<void> signOutAfterAccountDeletion() async {
    deletedAccountSignOutCalls += 1;
    if (failDeletedAccountSignOut) {
      throw StateError('remote sign-out failed after deletion');
    }
  }

  void emitPasswordRecovery() {
    _authStates.add(const AuthState(AuthChangeEvent.passwordRecovery, null));
  }
}

class _RecordingCaptchaChallenge implements AuthCaptchaChallenge {
  final List<AuthCaptchaAction> actions = [];

  @override
  Future<String?> acquire(
    BuildContext context, {
    required AuthCaptchaAction action,
  }) async {
    actions.add(action);
    return 'captcha-${action.wireValue}-${actions.length}';
  }
}

AppProfile _profile() => const AppProfile(
      id: 'account-id',
      email: 'person@example.test',
      name: 'Account Person',
      timezone: 'Europe/Berlin',
      role: AppRole.user,
      onboardingDone: true,
      authProvider: 'email',
    );
