import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/app.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/navigation/app_router.dart';
import 'package:my_life_graph/core/navigation/app_routes.dart';
import 'package:my_life_graph/features/auth/data/auth_repository.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:my_life_graph/features/auth/presentation/providers/auth_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('deep link survives asynchronous guest session restoration',
      (tester) async {
    final restoredSession = Completer<AppSession?>();
    final repository = _DelayedAuthRepository(restoredSession.future);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_testConfig),
          authRepositoryProvider.overrideWithValue(repository),
        ],
        child: const PersonalOptimizationApp(),
      ),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PersonalOptimizationApp)),
    );
    final router = container.read(appRouterProvider);
    final visitedLocations = <Uri>[];
    void recordLocation() {
      visitedLocations.add(router.routeInformationProvider.value.uri);
    }

    router.routeInformationProvider.addListener(recordLocation);
    addTearDown(
      () => router.routeInformationProvider.removeListener(recordLocation),
    );
    router.go(AppRoutes.calendarIntegration);
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutes.auth,
    );
    expect(
      router.routeInformationProvider.value.uri.queryParameters['continue'],
      AppRoutes.calendarIntegration,
    );

    restoredSession.complete(AppSession.guest(_guestProfile));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutes.calendarIntegration,
      reason: visitedLocations.toString(),
    );
    expect(
      find.text('Calendar import unavailable in local demo'),
      findsOneWidget,
    );
  });

  testWidgets('post-auth continuation rejects an external URL', (tester) async {
    final repository = _DelayedAuthRepository(
      Future.value(AppSession.guest(_guestProfile)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_testConfig),
          authRepositoryProvider.overrideWithValue(repository),
        ],
        child: const PersonalOptimizationApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PersonalOptimizationApp)),
    );
    final router = container.read(appRouterProvider);
    router.go(
      Uri(
        path: AppRoutes.auth,
        queryParameters: const {'continue': 'https://example.test/account'},
      ).toString(),
    );
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutes.dashboard,
    );
  });
}

const _testConfig = AppConfig(
  environment: 'test',
  supabaseUrl: '',
  supabaseAnonKey: '',
  aiServiceBaseUrl: 'http://localhost:8000',
  useMockData: true,
);

const _guestProfile = AppProfile(
  id: 'local_guest',
  email: 'guest@personal-coach.local',
  name: 'Deep Link Guest',
  timezone: localDeviceTimezoneMarker,
  role: AppRole.guest,
  onboardingDone: true,
  authProvider: 'guest',
);

class _DelayedAuthRepository extends AuthRepository {
  _DelayedAuthRepository(this.session)
      : super(
          SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
          useMockData: true,
        );

  final Future<AppSession?> session;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Future<AppSession?> currentSession() => session;
}
