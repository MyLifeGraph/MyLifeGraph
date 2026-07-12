import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/app.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/navigation/app_routes.dart';
import 'package:my_life_graph/features/auth/domain/intake_response.dart';
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

    await _startGuestAndCompleteSetup(tester);

    expect(find.text('Latest check-in'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final rawIntake = prefs.getString('auth_guest_intake_response');
    expect(rawIntake, isNotNull);
    final intake = jsonDecode(rawIntake!) as Map<String, dynamic>;
    final responses = intake['responses'] as Map<String, dynamic>;
    expect(responses['primary_focus_areas'], ['focus']);
    expect(responses['goals'], isEmpty);
    expect(responses['friction_points'], isEmpty);
    expect(responses['routines'], isEmpty);
    expect(responses['fixed_commitments'], isEmpty);
    expect(jsonEncode(responses), isNot(contains('Math')));
  });

  testWidgets('setup requires explicit core selections', (tester) async {
    await _pumpTestApp(tester);

    await tester.ensureVisible(find.text('Continue as guest'));
    await tester.tap(find.text('Continue as guest'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save setup'));
    await tester.tap(find.text('Save setup'));
    await tester.pump();

    expect(find.text('Choose at least one focus area.'), findsOneWidget);
    expect(find.text('Required setup'), findsOneWidget);
  });

  testWidgets('named guest routine stays candidate until cadence activation',
      (tester) async {
    await _pumpTestApp(tester);
    await _startGuestAndFillRequiredSetup(tester);

    await tester.ensureVisible(find.text('Routines'));
    await tester.tap(find.text('Routines'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add routine candidate'));
    await tester.tap(find.text('Add routine candidate'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Routine name'),
      'Evening reset',
    );
    await tester.pump();

    final statusDropdown = find.descendant(
      of: find.ancestor(
        of: find.text('Routine status'),
        matching: find.byType(InputDecorator),
      ),
      matching: find.byType(DropdownButton<IntakeRoutineStatus>),
    );
    await tester.ensureVisible(statusDropdown);
    await tester.tap(statusDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Active').last);
    await tester.pump();
    expect(
      find.text(
        'Choose and confirm cadence before activating or pausing this routine.',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Save setup'));
    await tester.tap(find.text('Save setup'));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    final envelope = jsonDecode(
      preferences.getString('auth_guest_setup_v1')!,
    ) as Map<String, dynamic>;
    final responses = envelope['responses'] as Map<String, dynamic>;
    final routine =
        (responses['routines'] as List<dynamic>).single as Map<String, dynamic>;
    expect(routine['title'], 'Evening reset');
    expect(routine['status'], 'candidate');
    expect(routine['cadence_confirmed'], isFalse);
    expect(routine, isNot(contains('frequency')));
    expect(routine, isNot(contains('target')));
  });

  testWidgets(
      'weekly routine requires explicit target and resets across cadence',
      (tester) async {
    await _pumpTestApp(tester);
    await _startGuestAndFillRequiredSetup(tester);
    await tester.ensureVisible(find.text('Routines'));
    await tester.tap(find.text('Routines'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add routine candidate'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Routine name'),
      'Weekly review',
    );

    await _selectLabeledDropdown<String>(
      tester,
      'Cadence (required before activation)',
      'Weekly',
    );
    var targetField = find.widgetWithText(
      TextFormField,
      'Weekly target (1–7)',
    );
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: targetField,
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      isEmpty,
    );
    await tester.enterText(targetField, '3');
    await tester.pump();

    await _selectLabeledDropdown<String>(
      tester,
      'Cadence (required before activation)',
      'Daily',
    );
    targetField = find.widgetWithText(TextFormField, 'Daily target (fixed)');
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: targetField,
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      '1',
    );

    await _selectLabeledDropdown<String>(
      tester,
      'Cadence (required before activation)',
      'Weekly',
    );
    targetField = find.widgetWithText(
      TextFormField,
      'Weekly target (1–7)',
    );
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: targetField,
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      isEmpty,
    );
    await tester.enterText(targetField, '3');
    await tester.pump();
    await _selectLabeledDropdown<IntakeRoutineStatus>(
      tester,
      'Routine status',
      'Active',
    );

    await tester.ensureVisible(find.text('Save setup'));
    await tester.tap(find.text('Save setup'));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    final envelope = jsonDecode(
      preferences.getString('auth_guest_setup_v1')!,
    ) as Map<String, dynamic>;
    final responses = envelope['responses'] as Map<String, dynamic>;
    final routine =
        (responses['routines'] as List<dynamic>).single as Map<String, dynamic>;
    expect(routine['status'], 'active');
    expect(routine['cadence_confirmed'], isTrue);
    expect(routine['frequency'], 'weekly');
    expect(routine['target'], 3);
  });

  testWidgets('edit setup preserves a custom saved weekday shape',
      (tester) async {
    const customWeekday = 'four-day rotating schedule';
    final setupState = IntakeSetupReadState(
      exists: true,
      revision: 2,
      baseRevision: 1,
      requestId: '6948e550-67d4-4fd9-bb29-bb80382ea8fe',
      status: 'applied',
      intakeResponseId: 'local-intake',
      snapshotId: 'local-snapshot',
      completedAt: DateTime.utc(2026, 7, 10),
      responses: _requiredSetupDraft().copyWith(
        weekdayShape: customWeekday,
      ),
      summary: const {},
    );
    await _pumpTestApp(
      tester,
      initialPreferences: {
        'auth_guest_active': true,
        'auth_guest_onboarding_done': true,
        'auth_guest_setup_v1': jsonEncode(setupState.toJson()),
      },
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Setup and commitments'));
    await tester.pumpAndSettle();

    expect(find.text('Review your setup'), findsOneWidget);
    expect(find.text(customWeekday), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest can merge evening and morning captures locally',
      (tester) async {
    await _pumpTestApp(tester);

    await _startGuestAndCompleteSetup(tester);

    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    expect(find.text('Add signal'), findsOneWidget);

    await tester.tap(find.text('Evening Shutdown'));
    await tester.pumpAndSettle();

    for (final label in [
      'evening mood 2 of 10',
      'evening energy 9 of 10',
      'evening stress 8 of 10',
      'stress source private_emotional',
      'stress controllability hardly_controllable',
      'focus band 30_to_60_minutes',
      'main friction emotional_load',
    ]) {
      await tester.tap(find.bySemanticsLabel(label));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      _textFieldWithLabel('Tomorrow priority'),
      'Protect the guest morning',
    );
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save evening shutdown'));
    await tester.pumpAndSettle();

    expect(find.text('Latest check-in'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Morning Calibration'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('morning sleep 5.5 h'));
    await tester.tap(find.bySemanticsLabel('morning energy 4 of 10'));
    final constrainedDay = find.bySemanticsLabel('day shape constrained');
    await tester.ensureVisible(constrainedDay);
    await tester.tap(constrainedDay);
    await tester.pump();
    await tester.ensureVisible(find.text('Save morning calibration'));
    await tester.tap(find.text('Save morning calibration'));
    await tester.pumpAndSettle();

    expect(find.text('Latest check-in'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonDecode(
      prefs.getString('guest_quick_checkins')!,
    ) as List<dynamic>;
    expect(raw, hasLength(1));
    final captures = (raw.single as Map<String, dynamic>)['captures'] as Map;
    final evening = captures['evening'] as Map;
    final morning = captures['morning'] as Map;
    expect(evening['mood'], 2);
    expect(evening['energy'], 9);
    expect(evening['stress_intensity'], 8);
    expect(evening['stress_source'], 'private_emotional');
    expect(evening['stress_controllability'], 'hardly_controllable');
    expect(evening['tomorrow_priority'], 'Protect the guest morning');
    expect(evening.containsKey('reflection_note'), isFalse);
    expect(evening.containsKey('specific_blocker'), isFalse);
    expect(evening.containsKey('gentle_tomorrow'), isFalse);
    expect(morning['sleep_hours'], 5.5);
    expect(morning['current_energy'], 4);
    expect(morning['day_shape'], 'constrained');

    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    expect(find.text('Today\'s saved captures'), findsOneWidget);
    expect(
      find.text('Mood 2 | Energy 4 | Sleep 5.5 h | Stress 8'),
      findsOneWidget,
    );
    expect(find.text('Local'), findsOneWidget);
  });

  testWidgets('guest only sees quick actions that work locally',
      (tester) async {
    await _pumpTestApp(tester);

    await _startGuestAndCompleteSetup(tester);

    expect(find.text('Local demo'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();

    expect(find.text('Evening Shutdown'), findsOneWidget);
    expect(find.text('Morning Calibration'), findsOneWidget);
    expect(find.text('Habit completion'), findsNothing);
    expect(find.text('Habit management'), findsNothing);
  });

  testWidgets('guest shell gates previews and keeps settings honest',
      (tester) async {
    await _pumpTestApp(tester);

    await _startGuestAndCompleteSetup(tester);

    expect(find.text('Coach'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);

    final router = GoRouter.of(
      tester.element(find.text('Latest check-in')),
    );
    router.go(AppRoutes.coach);
    await tester.pumpAndSettle();
    expect(find.text('Latest check-in'), findsOneWidget);

    router.go(AppRoutes.deepWork);
    await tester.pumpAndSettle();
    expect(find.text('Alerts'), findsWidgets);

    router.go(AppRoutes.habitManagement);
    await tester.pumpAndSettle();
    expect(find.text('Add signal'), findsOneWidget);
    expect(find.text('Habit management'), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Guest Coach User'), findsOneWidget);
    expect(find.text('guest@personal-coach.local'), findsOneWidget);
    expect(find.text('Light mode'), findsOneWidget);
    expect(find.text('Applies until the app is restarted.'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Setup and commitments'), findsOneWidget);
    expect(find.text('Export data'), findsNothing);
    expect(find.text('Alert rules'), findsNothing);
    expect(find.text('Coach behavior'), findsNothing);
    expect(find.text('Personal memory'), findsNothing);
    expect(find.text('Biometric app lock'), findsNothing);

    await tester.ensureVisible(find.text('Setup and commitments'));
    await tester.tap(find.text('Setup and commitments'));
    await tester.pumpAndSettle();
    expect(find.text('Review your setup'), findsOneWidget);
    expect(find.text('Flexible schedule'), findsOneWidget);
    expect(find.text('No optional setup commitments.'), findsOneWidget);
  });

  testWidgets('guest can inspect correlation insights', (tester) async {
    await _pumpTestApp(tester);

    await _startGuestAndCompleteSetup(tester);

    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();

    expect(find.text('ONE OBSERVATION'), findsOneWidget);
    expect(find.text('Advanced correlation exploration'), findsOneWidget);
    expect(find.text('Compare'), findsNothing);

    await tester.tap(find.text('Advanced correlation exploration'));
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

Future<void> _pumpTestApp(
  WidgetTester tester, {
  Map<String, Object> initialPreferences = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialPreferences);
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

IntakeResponseDraft _requiredSetupDraft() {
  return const IntakeResponseDraft(
    displayName: null,
    primaryFocusAreas: ['focus'],
    goals: [],
    frictionPoints: [],
    weekdayShape: 'flexible',
    bestEnergyWindow: 'morning',
    coachingStyle: 'direct',
    reminderPreference: IntakeReminderPreference(enabled: false),
    routines: [],
    fixedCommitments: [],
    contextNote: null,
    calendarConnectionIntent: null,
  );
}

Future<void> _startGuestAndCompleteSetup(WidgetTester tester) async {
  await _startGuestAndFillRequiredSetup(tester);

  await tester.ensureVisible(find.text('Save setup'));
  await tester.tap(find.text('Save setup'));
  await tester.pumpAndSettle();
}

Future<void> _startGuestAndFillRequiredSetup(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Continue as guest'));
  await tester.tap(find.text('Continue as guest'));
  await tester.pumpAndSettle();

  expect(find.text('Required setup'), findsOneWidget);
  expect(find.text('Math'), findsNothing);
  expect(find.text('Build a steadier weekly routine'), findsNothing);

  await tester.tap(find.widgetWithText(ChoiceChip, 'Focus'));
  await tester.pump();
  await _selectDropdownValue(tester, 0, 'Flexible schedule');
  await _selectDropdownValue(tester, 1, 'Morning');
  await _selectDropdownValue(tester, 2, 'Direct');
  await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'No reminders'));
  await tester.tap(find.widgetWithText(ChoiceChip, 'No reminders'));
  await tester.pump();
}

Future<void> _selectDropdownValue(
  WidgetTester tester,
  int index,
  String value,
) async {
  final dropdown = find.byType(DropdownButton<String>).at(index);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> _selectLabeledDropdown<T>(
  WidgetTester tester,
  String label,
  String value,
) async {
  final dropdown = find.descendant(
    of: find.ancestor(
      of: find.text(label),
      matching: find.byType(InputDecorator),
    ),
    matching: find.byType(DropdownButton<T>),
  );
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Finder _textFieldWithLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
      description: 'TextField with label $label',
    );
