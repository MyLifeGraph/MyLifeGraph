import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/features/auth/application/profile_local_date_source.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/morning_calibration_page.dart';
import 'package:my_life_graph/composition/quick_check_in_providers.dart';

void main() {
  testWidgets('morning calibration derives duration from the Evening proposal',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final store = _MorningStore();
    await _pumpPage(tester, store);

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save morning check-in'),
    );
    expect(saveButton.onPressed, isNull);

    await _performSemanticTap(tester, 'morning sleep quality 3 of 10');
    await _performSemanticTap(tester, 'morning energy 4 of 10');
    await _performSemanticTap(tester, 'day shape constrained');
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
    expect(draft.dayShape, DayShape.constrained);
    semantics.dispose();
  });

  testWidgets('morning retry retains exact values and capture identity',
      (tester) async {
    final store = _MorningStore(failOnce: true);
    await _pumpPage(tester, store);

    await _performSemanticTap(tester, 'morning sleep quality 3 of 10');
    await _performSemanticTap(tester, 'morning energy 4 of 10');
    await _performSemanticTap(tester, 'day shape constrained');
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
    await tester.ensureVisible(find.text('Save morning check-in'));
    await tester.tap(find.text('Save morning check-in'));
    await tester.pumpAndSettle();
    final written = store.attempts.single;
    expect(written.sleepHours, saved.sleepHours);
    expect(written.sleepQuality, saved.sleepQuality);
    expect(written.energy, saved.energy);
    expect(written.dayShape, saved.dayShape);
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
    );

    expect(tester.takeException(), isNull);
    await _performSemanticTap(tester, 'morning sleep quality 7 of 10');
    await _performSemanticTap(tester, 'morning energy 7 of 10');
    await _performSemanticTap(tester, 'day shape flexible');
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
      dayShape: DayShape.normal,
      branchVersion: dailyCaptureV3,
      isCompatibilityBranch: true,
    );
    final store = _MorningStore(
      initial: DailyCaptureEntry(entryDate: saved.entryDate, morning: saved),
    );
    await _pumpPage(tester, store);

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
}

Future<void> _performSemanticTap(
  WidgetTester tester,
  String label,
) async {
  await tester.ensureVisible(find.bySemanticsLabel(label));
  await tester.pumpAndSettle();
  final node = tester.getSemantics(find.bySemanticsLabel(label));
  final isChoice = label.startsWith('day shape ');
  expect(
    node,
    matchesSemantics(
      label: label,
      isButton: true,
      hasSelectedState: true,
      isSelected: false,
      hasTapAction: true,
      hasFocusAction: isChoice,
      isFocusable: isChoice,
      hasEnabledState: isChoice,
      isEnabled: isChoice,
    ),
  );
  await tester.tap(find.bySemanticsLabel(label).hitTestable());
  await tester.pump();
}

Future<void> _pumpPage(
  WidgetTester tester,
  QuickCheckInStore store, {
  Size viewSize = const Size(1200, 1500),
  double textScale = 1,
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
    dayShape: DayShape.flexible,
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
