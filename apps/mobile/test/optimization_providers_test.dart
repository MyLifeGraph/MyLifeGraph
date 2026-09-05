import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/optimization_providers.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/supabase/supabase_providers.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:my_life_graph/features/optimization/domain/entities/skillset_profile.dart';

void main() {
  final demoCases = <(String, AppSession?, bool)>[
    ('explicit mock', AppSession.authenticated(_profile()), true),
    ('mock without session', null, true),
    ('guest session', AppSession.guest(_profile()), false),
    (
      'guest role',
      AppSession.authenticated(_profile(role: AppRole.guest)),
      false,
    ),
    (
      'demo account',
      AppSession.authenticated(_profile(email: 'demo@personal-coach.local')),
      false,
    ),
    for (final provider in [
      'guest',
      ' GUEST ',
      'anonymous',
      'Anonymous',
      ' ANONYMOUS ',
    ])
      (
        provider,
        AppSession.authenticated(_profile(authProvider: provider)),
        false,
      ),
  ];
  for (final (label, session, useMockData) in demoCases) {
    test('$label loads only the local Skillset example', () async {
      final container = ProviderContainer(
        overrides: [
          appSurfaceCapabilitiesProvider.overrideWithValue(
            AppSurfaceCapabilities.forSession(
              session: session,
              useMockData: useMockData,
              hasSupabaseClient: true,
            ),
          ),
          supabaseClientProvider.overrideWith(
            (_) => throw StateError('No Skillset transport'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final profile = await container.read(skillsetProfileProvider.future);
      expect(profile.userName, 'Alex');
      expect(profile.primaryArchetype, 'Focused Builder');
    });
  }

  for (final session in [null, AppSession.authenticated(_profile())]) {
    test(
      '${session == null ? 'missing' : 'real'} session cannot load an example',
      () async {
        final container = ProviderContainer(
          overrides: [
            appSurfaceCapabilitiesProvider.overrideWithValue(
              AppSurfaceCapabilities.forSession(
                session: session,
                useMockData: false,
                hasSupabaseClient: true,
              ),
            ),
            optimizationMockDataSourceProvider.overrideWith(
              (_) => throw StateError('Example source must not be accessed'),
            ),
            supabaseClientProvider.overrideWith(
              (_) => throw StateError('No Skillset transport'),
            ),
          ],
        );
        addTearDown(container.dispose);

        await expectLater(
          container.read(skillsetProfileProvider.future),
          throwsA(isA<SkillsetProfileUnavailableException>()),
        );
      },
    );
  }

  test('leaving demo invalidates the cached example', () async {
    final demo = StateProvider<bool>((_) => true);
    final container = ProviderContainer(
      overrides: [
        appSurfaceCapabilitiesProvider.overrideWith(
          (ref) => AppSurfaceCapabilities(
            isLocalDemo: ref.watch(demo),
            canUseSyncedHabits: false,
          ),
        ),
        supabaseClientProvider.overrideWith(
          (_) => throw StateError('No Skillset transport'),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(skillsetProfileProvider.future);
    container.read(demo.notifier).state = false;
    await expectLater(
      container.read(skillsetProfileProvider.future),
      throwsA(isA<SkillsetProfileUnavailableException>()),
    );
  });
}

AppProfile _profile({
  String email = 'real@example.com',
  AppRole role = AppRole.user,
  String authProvider = 'email',
}) => AppProfile(
  id: 'profile-1',
  email: email,
  name: 'Test User',
  timezone: 'Europe/Berlin',
  role: role,
  onboardingDone: true,
  authProvider: authProvider,
);
