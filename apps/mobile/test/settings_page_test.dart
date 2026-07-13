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

    expect(find.text('Review Guest'), findsOneWidget);
    expect(find.text('guest@personal-coach.local'), findsOneWidget);
    expect(find.text('Europe/Berlin'), findsOneWidget);
    expect(find.text('Local guest'), findsOneWidget);
    expect(find.text('Applies until the app is restarted.'), findsOneWidget);
    expect(find.text('Setup and commitments'), findsOneWidget);
    expect(find.text('Calendar import (optional)'), findsOneWidget);
    expect(
      find.text('Import a selected .ics file as a read-only local copy.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Review goals, routine candidates, and fixed commitments.',
      ),
      findsOneWidget,
    );

    expect(find.text('Export data'), findsNothing);
    expect(find.text('Alert rules'), findsNothing);
    expect(find.text('Coach behavior'), findsNothing);
    expect(find.text('Personal memory'), findsNothing);
    expect(find.text('Biometric app lock'), findsNothing);

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.text('Light mode'));
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.scrollUntilVisible(
      find.text('Sign out'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Sign out'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('auth_guest_active'), isFalse);
  });
}
