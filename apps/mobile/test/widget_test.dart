import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_life_graph/app.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders authentication gate first', (tester) async {
    await _pumpTestApp(tester);

    expect(find.text('Build your day-aware coach'), findsOneWidget);
    expect(find.text('Login'), findsWidgets);
    expect(find.text('Register'), findsOneWidget);
    expect(find.text('Continue as guest'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('guest can complete onboarding and reach dashboard',
      (tester) async {
    await _pumpTestApp(tester);

    await tester.ensureVisible(find.text('Continue as guest'));
    await tester.tap(find.text('Continue as guest'));
    await tester.pumpAndSettle();

    expect(find.text('Your profile'), findsOneWidget);
    expect(find.text('Focus areas'), findsOneWidget);

    await tester.ensureVisible(find.text('Skip timetable for now'));
    await tester.tap(find.text('Skip timetable for now'));
    await tester.pumpAndSettle();

    expect(find.text('Today\'s wellness score'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final rawIntake = prefs.getString('auth_guest_intake_response');
    expect(rawIntake, isNotNull);
    final intake = jsonDecode(rawIntake!) as Map<String, dynamic>;
    final responses = intake['responses'] as Map<String, dynamic>;
    expect(responses['primary_focus_areas'], contains('focus'));
    expect(responses['goals'], contains('Build a steadier weekly routine'));
  });

  testWidgets('guest can save a quick mood check-in locally', (tester) async {
    await _pumpTestApp(tester);

    await tester.ensureVisible(find.text('Continue as guest'));
    await tester.tap(find.text('Continue as guest'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Skip timetable for now'));
    await tester.tap(find.text('Skip timetable for now'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    expect(find.text('Add signal'), findsOneWidget);

    await tester.tap(find.text('Mood check-in'));
    await tester.pumpAndSettle();

    for (var index = 0; index < 4; index++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    await tester.enterText(
      find.byType(EditableText).last,
      'Automated guest smoke test',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Today\'s wellness score'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('guest_quick_checkins'), isNotNull);
  });

  testWidgets('guest can open habit completion without Supabase',
      (tester) async {
    await _pumpTestApp(tester);

    await tester.ensureVisible(find.text('Continue as guest'));
    await tester.tap(find.text('Continue as guest'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Skip timetable for now'));
    await tester.tap(find.text('Skip timetable for now'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Habit completion'));
    await tester.pumpAndSettle();

    expect(find.text('Habit completion'), findsOneWidget);
    expect(find.text('No active habits found.'), findsOneWidget);
  });

  testWidgets('guest can open habit management without Supabase',
      (tester) async {
    await _pumpTestApp(tester);

    await tester.ensureVisible(find.text('Continue as guest'));
    await tester.tap(find.text('Continue as guest'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Skip timetable for now'));
    await tester.tap(find.text('Skip timetable for now'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Habit management'));
    await tester.pumpAndSettle();

    expect(find.text('Habit management'), findsOneWidget);
    expect(find.text('Supabase is not configured.'), findsOneWidget);
  });

  testWidgets('guest can inspect correlation insights', (tester) async {
    await _pumpTestApp(tester);

    await tester.ensureVisible(find.text('Continue as guest'));
    await tester.tap(find.text('Continue as guest'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Skip timetable for now'));
    await tester.tap(find.text('Skip timetable for now'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();

    expect(find.text('Compare'), findsOneWidget);
    expect(find.text('3M'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Trend overlay'), findsOneWidget);
    expect(find.text('0-100 normalized'), findsOneWidget);

    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();

    expect(find.text('Top patterns'), findsOneWidget);
    expect(find.text('Correlation matrix'), findsOneWidget);
  });
}

Future<void> _pumpTestApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
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
      child: const PersonalOptimizationApp(),
    ),
  );

  await tester.pumpAndSettle();
}
