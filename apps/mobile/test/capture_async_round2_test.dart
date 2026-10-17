import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/composition/capture_draft_providers.dart';
import 'package:my_life_graph/composition/health_connect_providers.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import 'package:my_life_graph/composition/quick_check_in_providers.dart';
import 'package:my_life_graph/composition/skillset_providers.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/auth/application/profile_local_date_source.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/morning_calibration_page.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/quick_mood_check_in_page.dart';
import 'package:my_life_graph/features/quick_action/presentation/widgets/capture_date_picker.dart';
import 'package:my_life_graph/features/quick_action/presentation/widgets/daily_capture_controls.dart';
import 'support/ui_catalog_capture.dart';

void main() {
  testWidgets(
    'Capture save releases keyboard focus from an active editable field',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final focus = FocusNode();
        final controller = TextEditingController(text: 'Submitted text');
        addTearDown(focus.dispose);
        addTearDown(controller.dispose);
        var saving = false;
        late StateSetter rebuild;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return CaptureFlowScaffold(
                  eyebrow: 'SYNTHETIC CAPTURE',
                  title: 'Synthetic capture',
                  progress: 1,
                  canGoBack: true,
                  canContinue: true,
                  isLastStep: true,
                  isLoading: false,
                  isSaving: saving,
                  saveLabel: 'Save',
                  onClose: () {},
                  onBack: () {},
                  onNext: () {},
                  child: TextField(focusNode: focus, controller: controller),
                );
              },
            ),
          ),
        );
        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(focus.hasFocus, isTrue);
        expect(
          _hasActionInSubtree(
            tester.getSemantics(find.byType(TextField)),
            SemanticsAction.setText,
          ),
          isTrue,
        );
        rebuild(() => saving = true);
        await tester.pump();
        expect(
          focus.hasFocus,
          isFalse,
          reason:
              'Keyboard editing must stop with pointer editing during a pending save.',
        );
        expect(
          _hasActionInSubtree(
            tester.getSemantics(find.byType(TextField)),
            SemanticsAction.setText,
          ),
          isFalse,
        );
        expect(controller.text, 'Submitted text');
      } finally {
        semantics.dispose();
      }
    },
  );

  for (final morning in [true, false]) {
    testWidgets(
      '${morning ? 'Morning' : 'Evening'} footer Back stays locked during save',
      (tester) async {
        final store = _DelayedSaveStore();
        await _pump(tester, store, morning: morning);
        await _lastStep(tester, morning: morning);
        await tester.tap(find.text('Save'));
        await tester.pump();
        expect(store.attempts, 1);
        final back = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Back'),
        );
        expect(
          back.onPressed,
          isNull,
          reason: 'Internal Back must obey the same save lock as header Back.',
        );
        store.saved.complete();
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('Morning rating cannot be changed and silently lost during save', (
    tester,
  ) async {
    final store = _DelayedSaveStore();
    await _pump(tester, store, morning: true);
    await _lastStep(tester, morning: true);
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(store.morningAttempt!.energy, 7);
    final rating = find.bySemanticsLabel('morning energy 2 of 10');
    await tester.tap(rating, warnIfMissed: false);
    await tester.pump();
    final energy = tester
        .widgetList<CaptureRatingControl>(find.byType(CaptureRatingControl))
        .singleWhere((control) => control.semanticPrefix == 'morning energy');
    expect(
      energy.value,
      7,
      reason:
          'A pending save must freeze inputs; its completion replaces the draft with energy 7.',
    );
    store.saved.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Morning delayed date read blocks a second date change and restores drafts',
    (tester) async {
      final store = _DelayedSaveStore()..delayHistoricalRead = true;
      await _pump(tester, store, morning: true);
      await _lastStep(tester, morning: true);
      await tester.enterText(find.byType(TextField), 'Synthetic today draft');
      final changeDate = tester
          .widget<CaptureDatePicker>(find.byType(CaptureDatePicker))
          .onChanged;
      changeDate(DateTime(2026, 9, 24));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      changeDate(DateTime(2026, 9, 23));
      store.historicalRead.complete(store.entry(DateTime(2026, 9, 24)));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CaptureDatePicker>(find.byType(CaptureDatePicker)).date,
        DateTime(2026, 9, 24),
      );
      tester
          .widget<CaptureDatePicker>(find.byType(CaptureDatePicker))
          .onChanged(DateTime(2026, 9, 25));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic today draft'), findsOneWidget);
      expect(store.attempts, 0);
    },
  );

  testWidgets(
    'Morning failed save re-enables editing and submits the corrected retry',
    (tester) async {
      final store = _DelayedSaveStore();
      await _pump(tester, store, morning: true);
      await _lastStep(tester, morning: true);
      await tester.tap(find.text('Save'));
      await tester.pump();
      store.saved.completeError(StateError('Synthetic save failure'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save. Your answers are still here. Try again.'),
        findsWidgets,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Back'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.bySemanticsLabel('morning energy 2 of 10'));
      await tester.pump();
      await tester.enterText(
        find.byType(TextField),
        'Corrected synthetic note',
      );
      store.saved = Completer<void>();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(store.attempts, 2);
      expect(store.morningAttempt!.energy, 2);
      expect(store.morningAttempt!.reflectionNote, 'Corrected synthetic note');
      store.saved.complete();
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsOneWidget);
    },
  );

  if (captureUiCatalog) {
    testWidgets('round2 actual Morning idle and pending save catalog', (
      tester,
    ) async {
      await loadCatalogFonts();
      final store = _DelayedSaveStore();
      await _pump(
        tester,
        store,
        morning: true,
        viewSize: const Size(390, 1000),
      );
      await _lastStep(tester, morning: true);
      await tester.ensureVisible(find.text('Save'));
      await captureCatalog(tester, 'round2-capture-idle');
      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 200));
      const variant = String.fromEnvironment(
        'UI_CATALOG_VARIANT',
        defaultValue: 'before',
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../../.tools/ui-catalog/$variant/round2-capture-saving.png',
        ),
      );
      store.saved.complete();
      await tester.pumpAndSettle();
    });
  }
}

bool _hasActionInSubtree(SemanticsNode node, SemanticsAction action) {
  var found = node.getSemanticsData().hasAction(action);
  node.visitChildren((child) {
    found = found || _hasActionInSubtree(child, action);
    return !found;
  });
  return found;
}

Future<void> _lastStep(WidgetTester tester, {required bool morning}) async {
  for (var step = 0; step < (morning ? 1 : 2); step++) {
    await tester.ensureVisible(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }
}

Future<void> _pump(
  WidgetTester tester,
  _DelayedSaveStore store, {
  required bool morning,
  Size viewSize = const Size(1000, 1600),
}) async {
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final now = DateTime(2026, 9, 25, 18);
  final router = GoRouter(
    initialLocation: '/capture',
    routes: [
      GoRoute(
        path: '/capture',
        builder: (_, _) => morning
            ? const MorningCalibrationPage()
            : const QuickMoodCheckInPage(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, _) => const Scaffold(body: Text('Dashboard')),
      ),
      GoRoute(
        path: '/quick-action',
        builder: (_, _) => const Scaffold(body: Text('Quick action')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        captureDraftOwnerProvider.overrideWithValue(null),
        healthSleepSuggestionProvider.overrideWith((ref, day) async => null),
        optionalSkillsetCaptureProvider.overrideWithValue(false),
        profileLocalDateSourceProvider.overrideWithValue(
          SessionProfileLocalDateSource(
            session: null,
            currentInstant: () => now,
          ),
        ),
        currentInstantProvider.overrideWithValue(() => now),
        quickCheckInStoreProvider.overrideWithValue(store),
        eveningFocusReflectionSourceProvider.overrideWithValue(null),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

class _DelayedSaveStore implements QuickCheckInStore {
  var saved = Completer<void>();
  final historicalRead = Completer<DailyCaptureEntry?>();
  bool delayHistoricalRead = false;
  int attempts = 0;
  MorningCalibrationDraft? morningAttempt;

  DailyCaptureEntry entry(DateTime day) => DailyCaptureEntry(
    entryDate: dailyCaptureEntryDate(day),
    morning: MorningCalibrationDraft(
      captureId: 'synthetic-morning-${day.day}',
      entryDate: dailyCaptureEntryDate(day),
      capturedAt: day,
      sleepQuality: 8,
      energy: 7,
      estimatedSleepStartedAt: DateTime(day.year, day.month, day.day, 0),
      wokeAt: DateTime(day.year, day.month, day.day, 8),
      estimatedSleepMinutes: 480,
      sleepTargetMinutes: 480,
    ),
    evening:
        EveningShutdownDraft.empty(
          day,
          entryDate: dailyCaptureEntryDate(day),
        ).copyWith(
          mood: 7,
          energy: 6,
          stress: 3,
          plannedSleepTime: '23:00',
          sleepTargetMinutes: 480,
        ),
  );

  @override
  QuickCheckInSaveTarget get target => QuickCheckInSaveTarget.guest;
  @override
  Future<DailyCaptureEntry?> loadToday(DateTime day) async {
    if (delayHistoricalRead && day.day == 24) return historicalRead.future;
    return entry(day);
  }

  @override
  Future<EveningShutdownDraft?> loadLatestEvening() async => null;
  @override
  Future<void> saveMorning(MorningCalibrationDraft draft) {
    attempts++;
    morningAttempt = draft;
    return saved.future;
  }

  @override
  Future<void> saveEvening(EveningShutdownDraft draft) {
    attempts++;
    return saved.future;
  }
}
