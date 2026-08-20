import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/theme/app_theme_selection_provider.dart';
import 'package:my_life_graph/core/theme/app_visual_tokens.dart';
import 'package:my_life_graph/features/settings/presentation/pages/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings exposes only truthful session controls',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth_guest_active': true,
      'auth_guest_onboarding_done': true,
      'auth_guest_name': 'Review Guest',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_testConfig),
        ],
        child: const _ThemeAwareSettingsApp(),
      ),
    );
    await tester.pumpAndSettle();
    final pageScrollable = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;

    expect(find.text('Review Guest'), findsOneWidget);
    expect(find.text('guest@personal-coach.local'), findsOneWidget);
    expect(find.textContaining('Device local ('), findsOneWidget);
    expect(find.text('Local dates follow this device'), findsOneWidget);
    expect(
      find.textContaining('no account timezone is stored'),
      findsOneWidget,
    );
    expect(find.text('Local guest'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Planning and learning'), findsOneWidget);
    await _revealText(tester, 'Daily preparation budget', pageScrollable);
    expect(
      find.byKey(const ValueKey('daily-preparation-budget-setting')),
      findsOneWidget,
    );
    await _revealText(tester, 'In-app reminders', pageScrollable);
    expect(find.text('Tools and connections'), findsOneWidget);
    expect(find.text('In-app reminders'), findsOneWidget);
    await _revealText(tester, 'Personal learning', pageScrollable);
    expect(find.text('Personal learning'), findsOneWidget);
    await _revealText(tester, 'Calendar import (optional)', pageScrollable);
    expect(find.text('Calendar import (optional)'), findsOneWidget);
    expect(find.textContaining('Coach'), findsNothing);
    expect(
      find.text('Import a selected .ics file as a read-only local copy.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Review routine candidates, study setup, and fixed commitments.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );

    await _revealText(tester, 'Export data', pageScrollable);
    expect(find.text('Account and appearance'), findsOneWidget);
    expect(find.text('Export data'), findsOneWidget);
    await _revealText(tester, 'Delete account', pageScrollable);
    expect(find.text('Delete account'), findsOneWidget);
    expect(
      find.text(
        'Available only for a synced account.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.text('Alert rules'), findsNothing);
    expect(find.text('Coach behavior'), findsNothing);
    expect(find.text('Personal memory'), findsNothing);
    expect(find.text('Biometric app lock'), findsNothing);

    await _revealText(tester, 'Appearance', pageScrollable);
    expect(find.text('Dark · Saved on this device.'), findsOneWidget);
    await _revealText(tester, 'Build identity', pageScrollable);
    expect(
      find.text('test · v0.1.0-pilot.0 · 0123456789ab'),
      findsOneWidget,
    );

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Choose appearance'), findsOneWidget);
    expect(find.text('Calm dark default'), findsOneWidget);
    expect(find.text('Bright neutral'), findsOneWidget);
    expect(find.text('Animated violet and cyan'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('appearance-option-space')));
    await tester.pumpAndSettle();
    expect(find.text('Space · Saved on this device.'), findsOneWidget);
    expect(
      Theme.of(
        tester.element(
          find.byKey(const ValueKey('appearance-setting-entry')),
        ),
      ).extension<AppVisualTokens>()?.background,
      AppVisualTokens.space.background,
    );
    final preferencesAfterTheme = await SharedPreferences.getInstance();
    expect(preferencesAfterTheme.getString('app_theme_mode'), 'space');

    await _revealText(tester, 'Sign out', pageScrollable);
    expect(find.text('Sign out'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('auth_guest_active'), isFalse);
  });

  testWidgets('appearance dialog fits 320 px at 200 percent text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'auth_guest_active': true,
      'auth_guest_onboarding_done': true,
      'auth_guest_name': 'Review Guest',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_testConfig),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const Scaffold(body: SettingsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pageScrollable = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    await _revealText(tester, 'Appearance', pageScrollable);
    await tester.tap(find.text('Appearance'));
    tester.view.physicalSize = const Size(320, 720);
    await tester.pumpAndSettle();

    expect(find.text('Choose appearance'), findsOneWidget);
    for (final key in const ['dark', 'light', 'space']) {
      expect(find.byKey(ValueKey('appearance-option-$key')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed appearance persistence rolls back and reports the error',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth_guest_active': true,
      'auth_guest_onboarding_done': true,
      'auth_guest_name': 'Review Guest',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_testConfig),
          appThemeSelectionStoreProvider.overrideWithValue(
            const _FailingThemeSelectionStore(),
          ),
        ],
        child: const _ThemeAwareSettingsApp(),
      ),
    );
    await tester.pumpAndSettle();
    final pageScrollable = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    await _revealText(tester, 'Appearance', pageScrollable);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('appearance-option-space')));
    await tester.pumpAndSettle();

    expect(find.text('Dark · Saved on this device.'), findsOneWidget);
    expect(
      find.text('Could not save the appearance setting. Try again.'),
      findsOneWidget,
    );
  });
}

const _testConfig = AppConfig(
  environment: 'test',
  supabaseUrl: '',
  supabaseAnonKey: '',
  aiServiceBaseUrl: 'http://localhost:8000',
  appBuildSha: '0123456789abcdef0123456789abcdef01234567',
  appReleaseTag: 'v0.1.0-pilot.0',
  useMockData: true,
);

class _FailingThemeSelectionStore implements AppThemeSelectionStore {
  const _FailingThemeSelectionStore();

  @override
  Future<AppThemeId?> read() async => AppThemeId.dark;

  @override
  Future<void> write(AppThemeId id) =>
      Future<void>.error(StateError('write failed'));
}

class _ThemeAwareSettingsApp extends ConsumerWidget {
  const _ThemeAwareSettingsApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(appThemeSelectionProvider);
    return MaterialApp(
      theme: AppTheme.resolve(selection),
      home: const Scaffold(body: SettingsPage()),
    );
  }
}

Future<void> _revealText(
  WidgetTester tester,
  String text,
  Finder pageScrollable,
) async {
  final target = find.text(text, skipOffstage: false);
  for (var attempt = 0; attempt < 30 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(pageScrollable, const Offset(0, -180));
    await tester.pump();
  }
  expect(target, findsWidgets);
  await Scrollable.ensureVisible(
    tester.element(target.first),
    alignment: 0.5,
  );
  await tester.pumpAndSettle();
}
