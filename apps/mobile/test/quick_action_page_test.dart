import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/composition/quick_check_in_providers.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/navigation/app_routes.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/quick_action_page.dart';

const _eveningTitle = 'Evening check-in';
const _eveningSubtitle = 'Close today with three ratings and useful context';
const _morningTitle = 'Morning check-in';
const _morningSubtitle = 'Add sleep timing, sleep quality, and current energy';

void main() {
  testWidgets('maps each loaded capture branch to its matching action status',
      (tester) async {
    final cases = <({
      String name,
      DailyCaptureEntry? entry,
      bool eveningCompleted,
      bool morningCompleted,
    })>[
      (
        name: 'none',
        entry: null,
        eveningCompleted: false,
        morningCompleted: false,
      ),
      (
        name: 'evening only',
        entry: _entry(evening: true),
        eveningCompleted: true,
        morningCompleted: false,
      ),
      (
        name: 'morning only',
        entry: _entry(morning: true),
        eveningCompleted: false,
        morningCompleted: true,
      ),
      (
        name: 'both',
        entry: _entry(evening: true, morning: true),
        eveningCompleted: true,
        morningCompleted: true,
      ),
    ];

    for (final testCase in cases) {
      await _pumpPage(tester, load: () async => testCase.entry);

      expect(
        _actionControl(
          title: _eveningTitle,
          subtitle: _eveningSubtitle,
          completed: testCase.eveningCompleted,
        ),
        findsOneWidget,
        reason: testCase.name,
      );
      expect(
        _actionControl(
          title: _morningTitle,
          subtitle: _morningSubtitle,
          completed: testCase.morningCompleted,
        ),
        findsOneWidget,
        reason: testCase.name,
      );
      expect(
        find.text('Completed today'),
        findsNWidgets(
          (testCase.eveningCompleted ? 1 : 0) +
              (testCase.morningCompleted ? 1 : 0),
        ),
        reason: testCase.name,
      );
      expect(find.text('Today\'s saved captures'), findsNothing);
    }
  });

  testWidgets('completed action remains an accessible edit entry',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpPage(
      tester,
      load: () async => _entry(evening: true),
    );

    final control = _actionControl(
      title: _eveningTitle,
      subtitle: _eveningSubtitle,
      completed: true,
    );
    expect(
      tester.getSemantics(control),
      matchesSemantics(
        label: _actionLabel(
          title: _eveningTitle,
          subtitle: _eveningSubtitle,
          completed: true,
        ),
        isButton: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(control);
    await tester.pumpAndSettle();

    expect(find.text('Evening destination'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('loading and error states never infer completion',
      (tester) async {
    final pending = Completer<DailyCaptureEntry?>();
    await _pumpPage(
      tester,
      load: () => pending.future,
      settle: false,
    );
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Completed today'), findsNothing);

    pending.complete(null);
    await tester.pumpAndSettle();
    await _pumpPage(
      tester,
      load: () async => throw StateError('planned load failure'),
    );

    expect(find.text('Completed today'), findsNothing);
    expect(
      find.text('Today\'s saved check-in could not be loaded.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Retry loading check-in'), findsOneWidget);
  });

  testWidgets('completion badges fit at 320px with 200 percent text',
      (tester) async {
    await _pumpPage(
      tester,
      load: () async => _entry(evening: true, morning: true),
      viewSize: const Size(320, 800),
      textScale: 2,
    );

    expect(
      _actionControl(
        title: _eveningTitle,
        subtitle: _eveningSubtitle,
        completed: true,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text(_morningTitle),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      _actionControl(
        title: _morningTitle,
        subtitle: _morningSubtitle,
        completed: true,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required Future<DailyCaptureEntry?> Function() load,
  Size viewSize = const Size(900, 1100),
  double textScale = 1,
  bool settle = true,
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.quickAction,
    routes: [
      GoRoute(
        path: AppRoutes.quickAction,
        builder: (_, __) => const Scaffold(body: QuickActionPage()),
      ),
      GoRoute(
        path: AppRoutes.quickMoodCheckIn,
        builder: (_, __) => const Scaffold(body: Text('Evening destination')),
      ),
      GoRoute(
        path: AppRoutes.morningCalibration,
        builder: (_, __) => const Scaffold(body: Text('Morning destination')),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, __) => const Scaffold(body: Text('Settings destination')),
      ),
    ],
  );
  addTearDown(router.dispose);
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        appSurfaceCapabilitiesProvider.overrideWithValue(
          const AppSurfaceCapabilities(
            isLocalDemo: true,
            canUseSyncedHabits: false,
          ),
        ),
        latestQuickCheckInProvider.overrideWith((_) => load()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  }
}

Finder _actionControl({
  required String title,
  required String subtitle,
  required bool completed,
}) =>
    find.bySemanticsLabel(
      _actionLabel(
        title: title,
        subtitle: subtitle,
        completed: completed,
      ),
    );

String _actionLabel({
  required String title,
  required String subtitle,
  required bool completed,
}) =>
    completed
        ? '$title. $subtitle. Completed today. '
            'Opens today\'s saved answers for editing.'
        : '$title. $subtitle.';

DailyCaptureEntry _entry({
  bool evening = false,
  bool morning = false,
}) {
  const entryDate = '2026-08-02';
  final capturedAt = DateTime.utc(2026, 8, 2, 18);
  return DailyCaptureEntry(
    entryDate: entryDate,
    evening: evening
        ? EveningShutdownDraft(
            captureId: 'saved-evening',
            entryDate: entryDate,
            capturedAt: capturedAt,
            mood: 7,
            energy: 6,
            stress: 3,
            stressSource: StressSource.workload,
            stressControllability: StressControllability.mostlyControllable,
            focusBand: FocusBand.none,
            tomorrowPriority: '',
            plannedSleepTime: '23:00',
            sleepTargetMinutes: 480,
            branchVersion: dailyCaptureV4,
          )
        : null,
    morning: morning
        ? MorningCalibrationDraft(
            captureId: 'saved-morning',
            entryDate: entryDate,
            capturedAt: capturedAt,
            sleepQuality: 8,
            energy: 7,
            estimatedSleepStartedAt: DateTime.utc(2026, 8, 1, 23),
            wokeAt: DateTime.utc(2026, 8, 2, 7),
            estimatedSleepMinutes: 480,
            sleepTargetMinutes: 480,
            sourceEveningCaptureId: evening ? 'saved-evening' : null,
            branchVersion: dailyCaptureV4,
          )
        : null,
  );
}
