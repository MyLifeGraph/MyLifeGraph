import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/morning_calibration_page.dart';
import 'package:my_life_graph/features/quick_action/presentation/providers/quick_check_in_providers.dart';

void main() {
  testWidgets('morning-only calibration saves three explicit answers',
      (tester) async {
    final store = _MorningStore();
    await _pumpPage(tester, store);

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save morning calibration'),
    );
    expect(saveButton.onPressed, isNull);

    await tester.tap(find.bySemanticsLabel('morning sleep 5.5 h'));
    await tester.tap(find.bySemanticsLabel('morning energy 4 of 10'));
    await tester.tap(find.bySemanticsLabel('day shape constrained'));
    await tester.pump();
    await tester.tap(find.text('Save morning calibration'));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard destination'), findsOneWidget);
    expect(store.attempts, hasLength(1));
    final draft = store.attempts.single;
    expect(draft.sleepHours, 5.5);
    expect(draft.energy, 4);
    expect(draft.dayShape, DayShape.constrained);
  });

  testWidgets('morning retry retains exact values and capture identity',
      (tester) async {
    final store = _MorningStore(failOnce: true);
    await _pumpPage(tester, store);

    await tester.tap(find.bySemanticsLabel('morning sleep 5.5 h'));
    await tester.tap(find.bySemanticsLabel('morning energy 4 of 10'));
    await tester.tap(find.bySemanticsLabel('day shape constrained'));
    await tester.pump();
    await tester.tap(find.text('Save morning calibration'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Could not save. Your exact Morning Calibration is still here. Try again.',
      ),
      findsWidgets,
    );
    await tester.tap(find.text('Save morning calibration'));
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
    final saved = MorningCalibrationDraft(
      captureId: 'saved-morning',
      entryDate: dailyCaptureEntryDate(now),
      capturedAt: now,
      sleepHours: 8.5,
      energy: 7,
      dayShape: DayShape.flexible,
    );
    final store = _MorningStore(
      initial: DailyCaptureEntry(entryDate: saved.entryDate, morning: saved),
    );
    await _pumpPage(tester, store);

    expect(
      find.text(
        'Today\'s Morning Calibration is loaded. Saving replaces only its morning state.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Save morning calibration'));
    await tester.pumpAndSettle();
    final written = store.attempts.single;
    expect(written.sleepHours, saved.sleepHours);
    expect(written.energy, saved.energy);
    expect(written.dayShape, saved.dayShape);
    expect(written.captureId, saved.captureId);
    expect(written.capturedAt, isNot(saved.capturedAt));
  });
}

Future<void> _pumpPage(WidgetTester tester, QuickCheckInStore store) async {
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
  tester.view.physicalSize = const Size(1200, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [quickCheckInStoreProvider.overrideWithValue(store)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

class _MorningStore implements QuickCheckInStore {
  _MorningStore({this.initial, this.failOnce = false});

  final DailyCaptureEntry? initial;
  final bool failOnce;
  final List<MorningCalibrationDraft> attempts = [];

  @override
  QuickCheckInSaveTarget get target => QuickCheckInSaveTarget.guest;

  @override
  Future<DailyCaptureEntry?> loadToday(DateTime today) async => initial;

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
