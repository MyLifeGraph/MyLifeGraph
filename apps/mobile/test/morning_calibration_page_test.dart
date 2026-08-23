import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/features/auth/application/profile_local_date_source.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/morning_calibration_page.dart';
import 'package:my_life_graph/features/quick_action/presentation/widgets/daily_capture_controls.dart';
import 'package:my_life_graph/composition/quick_check_in_providers.dart';

void main() {
  testWidgets(
      'morning sleep step derives duration before the final check-in save',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final store = _MorningStore();
    await _pumpPage(tester, store);

    expect(find.text('MORNING · SLEEP'), findsOneWidget);
    expect(find.text('How did you sleep?'), findsOneWidget);
    expect(find.text('Estimated sleep quality'), findsNothing);
    expect(find.text('Current energy'), findsNothing);
    expect(find.text('Save morning check-in'), findsNothing);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .value,
      .5,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
          .onPressed,
      isNotNull,
    );

    await _tapVisible(tester, find.text('Next'));
    expect(find.text('MORNING · CHECK-IN'), findsOneWidget);
    expect(find.text('How are you starting today?'), findsOneWidget);
    expect(find.text('Estimated sleep duration'), findsNothing);
    expect(find.text('Save morning check-in'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .value,
      1,
    );

    await _performSemanticTap(tester, 'morning sleep quality 3 of 10');
    await _performSemanticTap(tester, 'morning energy 4 of 10');
    await tester.pump();
    await tester.tap(find.text('Save morning check-in'));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard destination'), findsOneWidget);
    expect(store.attempts, hasLength(1));
    final draft = store.attempts.single;
    expect(draft.estimatedSleepMinutes, 480);
    expect(draft.sleepHours, 8);
    expect(draft.sleepTargetMinutes, 480);
    expect(draft.sourceEveningCaptureId, 'latest-evening-plan');
    expect(draft.sleepQuality, 3);
    expect(draft.energy, 4);
    expect(draft.toMetadataJson(), isNot(contains('day_shape')));
    semantics.dispose();
  });

  testWidgets('morning retry retains exact values and capture identity',
      (tester) async {
    final store = _MorningStore(failOnce: true);
    await _pumpPage(tester, store);

    await _tapVisible(tester, find.text('Next'));
    await _performSemanticTap(tester, 'morning sleep quality 3 of 10');
    await _performSemanticTap(tester, 'morning energy 4 of 10');
    await tester.pump();
    await tester.ensureVisible(find.text('Save morning check-in'));
    await tester.tap(find.text('Save morning check-in'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Could not save. Your answers are still here. Try again.',
      ),
      findsWidgets,
    );
    expect(find.text('How are you starting today?'), findsOneWidget);
    expect(find.text('3 / 10'), findsOneWidget);
    expect(find.text('4 / 10'), findsOneWidget);
    await tester.ensureVisible(find.text('Save morning check-in'));
    await tester.tap(find.text('Save morning check-in'));
    await tester.pumpAndSettle();

    expect(store.attempts, hasLength(2));
    expect(store.attempts[1].captureId, store.attempts[0].captureId);
    expect(
      store.attempts[1].toMetadataJson(),
      store.attempts[0].toMetadataJson(),
    );
  });

  testWidgets('morning re-entry loads exact saved values', (tester) async {
    final now = DateTime.now();
    final saved = _savedMorning(now, estimatedMinutes: 510);
    final store = _MorningStore(
      initial: DailyCaptureEntry(entryDate: saved.entryDate, morning: saved),
    );
    await _pumpPage(tester, store);

    expect(
      find.text(
        'Today\'s morning check-in is loaded. Saving updates only these morning answers.',
      ),
      findsOneWidget,
    );
    await _tapVisible(tester, find.text('Next'));
    await tester.ensureVisible(find.text('Save morning check-in'));
    await tester.tap(find.text('Save morning check-in'));
    await tester.pumpAndSettle();
    final written = store.attempts.single;
    expect(written.sleepHours, saved.sleepHours);
    expect(written.sleepQuality, saved.sleepQuality);
    expect(written.energy, saved.energy);
    expect(written.toMetadataJson(), isNot(contains('day_shape')));
    expect(written.captureId, saved.captureId);
    expect(written.capturedAt, isNot(saved.capturedAt));
  });

  testWidgets('morning check-in remains usable at 320 pixels and 200% text',
      (tester) async {
    final store = _MorningStore();
    await _pumpPage(
      tester,
      store,
      viewSize: const Size(320, 700),
      textScale: 2,
      disableAnimations: true,
    );

    expect(tester.takeException(), isNull);
    await _tapVisible(
      tester,
      find.byKey(
        const ValueKey('capture-info-control-Estimated sleep duration'),
      ),
    );
    expect(tester.takeException(), isNull);
    await _tapVisible(tester, find.text('Next'));
    await _performSemanticTap(tester, 'morning sleep quality 7 of 10');
    await _performSemanticTap(tester, 'morning energy 7 of 10');
    final save = find.text('Save morning check-in');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'older morning capture stays readable and requires quality before resave',
      (tester) async {
    final now = DateTime.now();
    final saved = MorningCalibrationDraft(
      captureId: 'saved-morning-without-quality',
      entryDate: dailyCaptureEntryDate(now),
      capturedAt: now,
      sleepHours: 8,
      sleepQuality: null,
      energy: 7,
      legacyDayShapeCode: 'normal',
      branchVersion: dailyCaptureV3,
      isCompatibilityBranch: true,
    );
    final store = _MorningStore(
      initial: DailyCaptureEntry(entryDate: saved.entryDate, morning: saved),
    );
    await _pumpPage(tester, store);

    expect(find.text('Estimated sleep quality'), findsNothing);
    await _tapVisible(tester, find.text('Next'));
    expect(find.text('Estimated sleep quality'), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save morning check-in'),
    );
    expect(saveButton.onPressed, isNull);

    await _performSemanticTap(tester, 'morning sleep quality 6 of 10');
    await tester.ensureVisible(find.text('Save morning check-in'));
    await tester.tap(find.text('Save morning check-in'));
    await tester.pumpAndSettle();

    expect(store.attempts.single.sleepQuality, 6);
  });

  testWidgets(
      'sleep details gate Next and Back retains the complete two-step draft',
      (tester) async {
    final store = _NoSleepPlanMorningStore();
    await _pumpPage(tester, store);

    expect(find.text('—'), findsOneWidget);
    expect(
      find.text('Choose an ordered interval of no more than 16 hours.'),
      findsNothing,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
          .onPressed,
      isNull,
    );

    tester
        .widget<CaptureClockControl>(find.byType(CaptureClockControl).at(0))
        .onChanged('00:00');
    await tester.pump();
    tester
        .widget<CaptureClockControl>(find.byType(CaptureClockControl).at(1))
        .onChanged('23:00');
    await tester.pump();
    expect(find.text('—'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
          .onPressed,
      isNull,
    );

    tester
        .widget<CaptureSleepTargetControl>(
          find.byType(CaptureSleepTargetControl),
        )
        .onChanged(301);
    tester
        .widget<CaptureClockControl>(find.byType(CaptureClockControl).at(1))
        .onChanged('08:00');
    await tester.pump();
    expect(find.text('8 h'), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
          .onPressed,
      isNull,
    );

    tester
        .widget<CaptureSleepTargetControl>(
          find.byType(CaptureSleepTargetControl),
        )
        .onChanged(420);
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
          .onPressed,
      isNotNull,
    );

    await _tapVisible(tester, find.text('Next'));
    await _performSemanticTap(tester, 'morning sleep quality 6 of 10');
    await _performSemanticTap(tester, 'morning energy 7 of 10');
    expect(store.attempts, isEmpty);

    await _tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Back'),
    );
    final clocks = tester.widgetList<CaptureClockControl>(
      find.byType(CaptureClockControl),
    );
    expect(clocks.first.value, '00:00');
    expect(clocks.last.value, '08:00');
    expect(
      tester
          .widget<CaptureSleepTargetControl>(
            find.byType(CaptureSleepTargetControl),
          )
          .value,
      420,
    );

    await _tapVisible(tester, find.text('Next'));
    final ratings = tester.widgetList<CaptureRatingControl>(
      find.byType(CaptureRatingControl),
    );
    expect(ratings.first.value, 6);
    expect(ratings.last.value, 7);
    await _tapVisible(tester, find.text('Save morning check-in'));
    await tester.pumpAndSettle();
    expect(store.attempts, hasLength(1));
  });

  testWidgets('all three Morning explanations start closed and open alone',
      (tester) async {
    const durationHelp =
        'These are your own estimates, not objectively measured sleep.';
    const targetHelp =
        'Loaded from the latest saved Evening plan. You can correct it for this night.';
    const qualityHelp =
        'How restorative did your sleep feel, independently of how long you slept?';
    await _pumpPage(tester, _MorningStore());

    expect(find.text(durationHelp), findsNothing);
    expect(find.text(targetHelp), findsNothing);
    expect(
      find.bySemanticsLabel(
        'Show information about Estimated sleep duration',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Show information about Sleep target used for this night',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('capture-info-control-Estimated sleep duration'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(durationHelp), findsOneWidget);
    expect(find.text(targetHelp), findsNothing);

    await tester.tap(
      find.byKey(
        const ValueKey(
          'capture-info-control-Sleep target used for this night',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(durationHelp), findsOneWidget);
    expect(find.text(targetHelp), findsOneWidget);

    await _tapVisible(tester, find.text('Next'));
    expect(find.text(qualityHelp), findsNothing);
    expect(
      find.bySemanticsLabel(
        'Show information about Estimated sleep quality',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        const ValueKey('capture-info-control-Estimated sleep quality'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(qualityHelp), findsOneWidget);
  });
}

Future<void> _performSemanticTap(
  WidgetTester tester,
  String label,
) async {
  await tester.ensureVisible(find.bySemanticsLabel(label));
  await tester.pumpAndSettle();
  final node = tester.getSemantics(find.bySemanticsLabel(label));
  expect(
    node,
    matchesSemantics(
      label: label,
      isButton: true,
      hasSelectedState: true,
      isSelected: false,
      hasTapAction: true,
      hasFocusAction: false,
      isFocusable: false,
      hasEnabledState: false,
      isEnabled: false,
    ),
  );
  await tester.tap(find.bySemanticsLabel(label).hitTestable());
  await tester.pump();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _pumpPage(
  WidgetTester tester,
  QuickCheckInStore store, {
  Size viewSize = const Size(1200, 1500),
  double textScale = 1,
  bool disableAnimations = false,
}) async {
  final router = GoRouter(
    initialLocation: '/morning-calibration',
    routes: [
      GoRoute(
        path: '/morning-calibration',
        builder: (_, __) => const MorningCalibrationPage(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const Scaffold(body: Text('Dashboard destination')),
      ),
      GoRoute(
        path: '/quick-action',
        builder: (_, __) => const Scaffold(body: Text('Quick action')),
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
      overrides: [
        profileLocalDateSourceProvider.overrideWithValue(
          const SessionProfileLocalDateSource(session: null),
        ),
        quickCheckInStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _MorningStore implements QuickCheckInStore {
  _MorningStore({
    this.initial,
    this.failOnce = false,
    EveningShutdownDraft? sleepPlan,
  }) : sleepPlan = sleepPlan ?? _latestSleepPlan();

  final DailyCaptureEntry? initial;
  final bool failOnce;
  final EveningShutdownDraft sleepPlan;
  final List<MorningCalibrationDraft> attempts = [];

  @override
  QuickCheckInSaveTarget get target => QuickCheckInSaveTarget.guest;

  @override
  Future<DailyCaptureEntry?> loadToday(DateTime today) async => initial;

  @override
  Future<EveningShutdownDraft?> loadLatestEvening() async => sleepPlan;

  @override
  Future<void> saveEvening(EveningShutdownDraft draft) async {}

  @override
  Future<void> saveMorning(MorningCalibrationDraft draft) async {
    attempts.add(draft.normalized());
    if (failOnce && attempts.length == 1) {
      throw StateError('planned failure');
    }
  }
}

class _NoSleepPlanMorningStore extends _MorningStore {
  @override
  Future<EveningShutdownDraft?> loadLatestEvening() async => null;
}

EveningShutdownDraft _latestSleepPlan() {
  final now = DateTime.now();
  return EveningShutdownDraft(
    captureId: 'latest-evening-plan',
    entryDate: dailyCaptureEntryDate(now),
    capturedAt: now.subtract(const Duration(hours: 10)),
    mood: 7,
    energy: 6,
    stress: 3,
    stressSource: null,
    stressControllability: null,
    focusBand: null,
    tomorrowPriority: '',
    plannedSleepTime: dailyCaptureClock(
      now.subtract(const Duration(hours: 8)),
    ),
    sleepTargetMinutes: 480,
    branchVersion: dailyCaptureV4,
  );
}

MorningCalibrationDraft _savedMorning(
  DateTime now, {
  required int estimatedMinutes,
}) {
  final wokeAt = DateTime(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute,
  );
  return MorningCalibrationDraft(
    captureId: 'saved-morning',
    entryDate: dailyCaptureEntryDate(now),
    capturedAt: now,
    sleepQuality: 8,
    energy: 7,
    estimatedSleepStartedAt: wokeAt.subtract(
      Duration(minutes: estimatedMinutes),
    ),
    wokeAt: wokeAt,
    estimatedSleepMinutes: estimatedMinutes,
    sleepTargetMinutes: 480,
    sourceEveningCaptureId: 'latest-evening-plan',
    branchVersion: dailyCaptureV4,
  );
}
