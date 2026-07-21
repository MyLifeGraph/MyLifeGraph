import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
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
          appConfigProvider.overrideWithValue(
            const AppConfig(
              environment: 'test',
              supabaseUrl: '',
              supabaseAnonKey: '',
              aiServiceBaseUrl: 'http://localhost:8000',
              useMockData: true,
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
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
    expect(find.text('Setup and commitments'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('daily-preparation-budget-setting')),
      findsOneWidget,
    );
    await _revealText(tester, 'In-app reminders', pageScrollable);
    expect(find.text('In-app reminders'), findsOneWidget);
    await _revealText(tester, 'Calendar import (optional)', pageScrollable);
    expect(find.text('Calendar import (optional)'), findsOneWidget);
    expect(find.textContaining('Coach'), findsNothing);
    expect(
      find.text('Import a selected .ics file as a read-only local copy.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Review goals, routine candidates, and fixed commitments.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );

    await _revealText(tester, 'Export data', pageScrollable);
    expect(find.text('Export data'), findsOneWidget);
    await _revealText(tester, 'Delete account', pageScrollable);
    expect(find.text('Delete account'), findsOneWidget);
    expect(
      find.text(
        'Available only for a synced account.',
        skipOffstage: false,
      ),
      findsNWidgets(2),
    );
    expect(find.text('Alert rules'), findsNothing);
    expect(find.text('Coach behavior'), findsNothing);
    expect(find.text('Personal memory'), findsNothing);
    expect(find.text('Biometric app lock'), findsNothing);

    await _revealText(tester, 'Light mode', pageScrollable);
    expect(find.text('Saved on this device.'), findsOneWidget);

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.text('Light mode'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    final preferencesAfterTheme = await SharedPreferences.getInstance();
    expect(preferencesAfterTheme.getString('app_theme_mode'), 'light');

    await _revealText(tester, 'Sign out', pageScrollable);
    expect(find.text('Sign out'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('auth_guest_active'), isFalse);
  });
}

Future<void> _revealText(
  WidgetTester tester,
  String text,
  Finder pageScrollable,
) async {
  final target = find.text(text, skipOffstage: false);
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: pageScrollable,
    );
  }
  await Scrollable.ensureVisible(
    tester.element(target),
    alignment: 0.5,
  );
  await tester.pumpAndSettle();
}
