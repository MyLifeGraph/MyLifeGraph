import 'package:flutter/material.dart';
import 'package:my_life_graph/composition/health_connect_providers.dart';
import 'package:my_life_graph/features/health_connect/domain/health_sleep_suggestion.dart';
import 'package:my_life_graph/composition/skillset_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/features/auth/application/profile_local_date_source.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/morning_calibration_page.dart';
import 'package:my_life_graph/features/quick_action/presentation/widgets/daily_capture_controls.dart';
import 'package:my_life_graph/features/quick_action/presentation/widgets/capture_date_picker.dart';
import 'package:my_life_graph/composition/quick_check_in_providers.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'support/ui_catalog_capture.dart';

void main() {
  if (captureUiCatalog) {
    testWidgets('compact morning note catalog', (tester) async {
      await loadCatalogFonts();
      final now = DateTime(2026, 9, 25, 9);
      final morning = _savedMorning(now, estimatedMinutes: 480).forEditing();
      await _pumpPage(
        tester,
        _MorningStore(
          initial: DailyCaptureEntry(
            entryDate: morning.entryDate,
            morning: morning,
          ),
        ),
        currentInstant: now,
        viewSize: const Size(390, 1200),
        theme: AppTheme.liquidGlass,
        skillsetEnabled: true,
      );
      await _tapVisible(tester, find.text('Next'));
      expect(find.text('Study motivation (optional)'), findsOneWidget);
      await captureCatalog(tester, 'morning-after');
    });
  }
  testWidgets(
    'Morning note is optional, tracks dirty edits, saves and reopens',
    (tester) async {
      final now = DateTime(2026, 9, 25, 9);
      final morning = _savedMorning(now, estimatedMinutes: 480).forEditing();
      final store = _MorningStore(
        initial: DailyCaptureEntry(
          entryDate: morning.entryDate,
          morning: morning,
        ),
      );
      await _pumpPage(tester, store, currentInstant: now);
      await _tapVisible(tester, find.text('Next'));
      expect(find.byType(ExpansionTile), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).maxLines, 2);
      await tester.enterText(find.byType(TextField), 'Ready for the exam.');
      await tester.pump();
      tester
          .widget<CaptureDatePicker>(find.byType(CaptureDatePicker))
          .onChanged(DateTime(2026, 9, 24));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('Save'));
      final saved = store.attempts.single;
      expect(saved.reflectionNote, 'Ready for the exam.');
      expect(saved.sleepQuality, morning.sleepQuality);
      expect(saved.energy, morning.energy);
      expect(saved.estimatedSleepMinutes, morning.estimatedSleepMinutes);
      await tester.pumpWidget(const SizedBox());
      await _pumpPage(
        tester,
        _MorningStore(
          initial: DailyCaptureEntry(
            entryDate: saved.entryDate,
            morning: saved,
          ),
        ),
        currentInstant: now,
      );
      await _tapVisible(tester, find.text('Next'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Ready for the exam.',
      );
    },
  );
  testWidgets(
    'opening during a repeated DST hour retains the known current instant',
    (tester) async {
      await _pumpPage(
        tester,
        _NoSleepPlanMorningStore(),
        currentInstant: DateTime.utc(2026, 10, 25, 1, 30),
        timezoneName: 'Europe/Berlin',
      );
      expect(
        tester
            .widget<CaptureClockControl>(find.byType(CaptureClockControl).at(1))
            .value,
        '02:30',
      );
      expect(find.textContaining('could not be loaded'), findsNothing);
    },
  );

  testWidgets('unresolvable prior sleep plan leaves Morning editable', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _MorningStore(
        sleepPlan: _latestSleepPlan().copyWith(
          entryDate: '2026-03-28',
          plannedSleepTime: '02:30',
        ),
      ),
      currentInstant: DateTime.utc(2026, 3, 29, 8),
      timezoneName: 'Europe/Berlin',
    );
    expect(find.textContaining('could not be loaded'), findsNothing);
    final start = tester.widget<CaptureClockControl>(
      find.byType(CaptureClockControl).first,
    );
    expect(start.value, isNull);
    start.onChanged('23:00');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CaptureClockControl>(find.byType(CaptureClockControl).first)
          .value,
      '23:00',
    );
  });
  for (final zone in ['Europe/Berlin', 'UTC', 'Asia/Kathmandu']) {
    testWidgets('watch acceptance, edit, save and reload use $zone', (
      tester,
    ) async {
      final now = DateTime.utc(2026, 9, 26, 12);
      final watch = HealthSleepSuggestion.parse(
        {
          'started_at': '2026-09-26T02:39:00Z',
          'woke_at': '2026-09-26T09:21:00Z',
        },
        '2026-09-26',
        zone,
        now,
      )!;
      final store = _NoSleepPlanMorningStore();
      await _pumpPage(
        tester,
        store,
        currentInstant: now,
        watchSleep: watch,
        timezoneName: zone,
      );
      final startClock = dailyCaptureClock(watch.startedAt);
      final wakeClock = dailyCaptureClock(watch.wokeAt);
      expect(find.text('Watch sleep\n$startClock–$wakeClock'), findsOneWidget);
      await tester.tap(find.text('Use times'));
      await tester.pumpAndSettle();
      CaptureClockControl clock(int index) =>
          tester.widget<CaptureClockControl>(
            find.byType(CaptureClockControl).at(index),
          );
      expect(clock(0).value, startClock);
      expect(clock(1).value, wakeClock);
      // Re-enter the displayed value: it must not shift the stored instant.
      clock(0).onChanged(startClock);
      await tester.pumpAndSettle();
      expect(clock(1).value, wakeClock);
      tester
          .widget<CaptureSleepTargetControl>(
            find.byType(CaptureSleepTargetControl),
          )
          .onChanged(480);
      await tester.pump();
      await _tapVisible(tester, find.text('Next'));
      await _performSemanticTap(tester, 'morning sleep quality 7 of 10');
      await _performSemanticTap(tester, 'morning energy 6 of 10');
      await _tapVisible(tester, find.text('Save'));
      final saved = store.attempts.single;
      expect(
        saved.estimatedSleepStartedAt!.toUtc(),
        DateTime.utc(2026, 9, 26, 2, 39),
      );
      expect(saved.wokeAt!.toUtc(), DateTime.utc(2026, 9, 26, 9, 21));
      expect(saved.estimatedSleepMinutes, 402);
      final reloaded = MorningCalibrationDraft.fromJson(
        saved.toMetadataJson(),
        entryDate: saved.entryDate,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpPage(
        tester,
        _MorningStore(
          initial: DailyCaptureEntry(
            entryDate: saved.entryDate,
            morning: reloaded,
          ),
        ),
        currentInstant: now,
        watchSleep: watch,
        timezoneName: zone,
      );
      expect(clock(0).value, startClock);
      expect(clock(1).value, wakeClock);
      expect(find.text('Use times'), findsNothing);
    });
  }
  testWidgets(
    'watch times are offered once and manual edits remain authoritative',
    (tester) async {
      final store = _NoSleepPlanMorningStore();
      await _pumpPage(
        tester,
        store,
        currentInstant: DateTime(2026, 9, 25, 9),
        watchSleep: HealthSleepSuggestion(
          DateTime(2026, 9, 24, 23),
          DateTime(2026, 9, 25, 7),
        ),
      );
      expect(find.text('Use times'), findsOneWidget);
      await tester.tap(find.text('Use times'));
      await tester.pumpAndSettle();
      expect(find.text('Use times'), findsNothing);
      expect(
        tester
            .widget<CaptureClockControl>(find.byType(CaptureClockControl).first)
            .value,
        '23:00',
      );
      tester
          .widget<CaptureClockControl>(find.byType(CaptureClockControl).first)
          .onChanged('22:00');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CaptureClockControl>(find.byType(CaptureClockControl).first)
            .value,
        '22:00',
      );
      expect(store.attempts, isEmpty);
      tester
          .widget<CaptureDatePicker>(find.byType(CaptureDatePicker))
          .onChanged(DateTime(2026, 9, 24));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CaptureClockControl>(find.byType(CaptureClockControl).first)
            .value,
        '22:00',
      );
    },
  );
  testWidgets('backfill saves the selected day without inventing sleep times', (
    tester,
  ) async {
    final store = _NoSleepPlanMorningStore();
    await _pumpPage(tester, store, currentInstant: DateTime(2026, 9, 25, 9));
    tester
        .widget<CaptureDatePicker>(find.byType(CaptureDatePicker))
        .onChanged(DateTime(2026, 9, 24));
    await tester.pumpAndSettle();
    final clocks = tester
        .widgetList<CaptureClockControl>(find.byType(CaptureClockControl))
        .toList();
    expect(clocks.every((clock) => clock.value == null), isTrue);
    clocks[0].onChanged('23:00');
    await tester.pump();
    tester
        .widget<CaptureClockControl>(find.byType(CaptureClockControl).at(1))
        .onChanged('07:00');
    await tester.pump();
    tester
        .widget<CaptureSleepTargetControl>(
          find.byType(CaptureSleepTargetControl),
        )
        .onChanged(480);
    await tester.pump();
    await _tapVisible(tester, find.text('Next'));
    await _performSemanticTap(tester, 'morning sleep quality 7 of 10');
    await _performSemanticTap(tester, 'morning energy 6 of 10');
    await _tapVisible(tester, find.text('Save'));
    expect(store.attempts.single.entryDate, '2026-09-24');
    expect(store.attempts.single.estimatedSleepMinutes, 480);
    expect(store.attempts.single.sourceEveningCaptureId, isNull);
  });
  testWidgets(
    'motivation is available and saved with no Insights dimensions selected',
    (tester) async {
      final store = _MorningStore();
      await _pumpPage(tester, store, skillsetEnabled: true);
      expect(
        tester
            .widget<CaptureFlowScaffold>(find.byType(CaptureFlowScaffold))
            .subtitle,
        isNull,
      );
      expect(find.text('How did you sleep?'), findsOneWidget);
      await _tapVisible(tester, find.text('Next'));
      expect(find.text('More (optional)'), findsNothing);
      expect(find.text('Study motivation (optional)'), findsOneWidget);
      await _tapVisible(tester, find.text('Low'));
      await _performSemanticTap(tester, 'morning sleep quality 3 of 10');
      await _performSemanticTap(tester, 'morning energy 4 of 10');
      await _tapVisible(tester, find.text('Save'));
      expect(store.attempts.single.skillset?.values['motivation'], 0);
    },
  );

  testWidgets(
    'morning sleep step derives duration before the final check-in save',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final store = _MorningStore(
        sleepPlan: _latestSleepPlan().copyWith(
          entryDate: '2026-08-19',
          plannedSleepTime: '23:00',
        ),
      );
      await _pumpPage(tester, store, currentInstant: DateTime(2026, 8, 20, 7));

      expect(find.text('MORNING · SLEEP'), findsOneWidget);
      expect(find.text('How did you sleep?'), findsOneWidget);
      expect(find.text('Sleep start'), findsOneWidget);
      // Check the loaded sleep plan, not an unrelated wall-clock wake label.
      expect(
        tester
            .widget<CaptureClockControl>(find.byType(CaptureClockControl).first)
            .value,
        store.sleepPlan.plannedSleepTime,
      );
      expect(find.text('Choose a value to continue.'), findsNothing);
      expect(find.text('Sleep quality'), findsNothing);
      expect(find.text('Current energy'), findsNothing);
      expect(find.text('Save'), findsNothing);
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

      tester
          .widget<CaptureClockControl>(find.byType(CaptureClockControl).at(0))
          .onChanged('23:00');
      await tester.pump();
      tester
          .widget<CaptureClockControl>(find.byType(CaptureClockControl).at(1))
          .onChanged('07:00');
      await tester.pump();

      await _tapVisible(
        tester,
        find.byTooltip('Sleep start 15 minutes earlier'),
      );
      expect(find.text('8 h 15 min'), findsOneWidget);
      await _tapVisible(tester, find.byTooltip('Wake time 15 minutes earlier'));

      await _tapVisible(tester, find.text('Next'));
      expect(find.text('MORNING · CHECK-IN'), findsOneWidget);
      expect(find.text('How are you starting today?'), findsOneWidget);
      expect(find.text('Estimated sleep duration'), findsNothing);
      expect(find.text('Save'), findsOneWidget);
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
      await tester.tap(find.text('Save'));
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
    },
  );

  testWidgets('morning retry retains exact values and capture identity', (
    tester,
  ) async {
    final store = _MorningStore(failOnce: true);
    await _pumpPage(tester, store);

    await _tapVisible(tester, find.text('Next'));
    await _performSemanticTap(tester, 'morning sleep quality 3 of 10');
    await _performSemanticTap(tester, 'morning energy 4 of 10');
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not save. Your answers are still here. Try again.'),
      findsWidgets,
    );
    expect(find.text('How are you starting today?'), findsOneWidget);
    expect(find.text('3 / 10'), findsOneWidget);
    expect(find.text('4 / 10'), findsOneWidget);
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
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
    await _pumpPage(
      tester,
      store,
      watchSleep: HealthSleepSuggestion(
        now.subtract(const Duration(hours: 6)),
        now,
      ),
    );
    expect(find.text('Use times'), findsNothing);

    await _tapVisible(tester, find.text('Next'));
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final written = store.attempts.single;
    expect(written.sleepHours, saved.sleepHours);
    expect(written.sleepQuality, saved.sleepQuality);
    expect(written.energy, saved.energy);
    expect(written.toMetadataJson(), isNot(contains('day_shape')));
    expect(written.captureId, saved.captureId);
    expect(written.capturedAt, isNot(saved.capturedAt));
  });

  testWidgets('morning check-in remains usable at 320 pixels and 200% text', (
    tester,
  ) async {
    final store = _MorningStore();
    await _pumpPage(
      tester,
      store,
      viewSize: const Size(320, 700),
      textScale: 2,
      disableAnimations: true,
      watchSleep: HealthSleepSuggestion(
        DateTime(2026, 9, 24, 23),
        DateTime(2026, 9, 25, 7),
      ),
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
    final save = find.text('Save');
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

      expect(find.text('Sleep quality'), findsNothing);
      await _tapVisible(tester, find.text('Next'));
      expect(find.text('Sleep quality'), findsOneWidget);
      final saveButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);

      await _performSemanticTap(tester, 'morning sleep quality 6 of 10');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(store.attempts.single.sleepQuality, 6);
    },
  );

  testWidgets(
    'sleep details gate Next and Back retains the complete two-step draft',
    (tester) async {
      final store = _NoSleepPlanMorningStore();
      await _pumpPage(tester, store);

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('morning-sleep-duration')))
            .data,
        '—',
      );
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
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('morning-sleep-duration')))
            .data,
        '—',
      );
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

      await _tapVisible(tester, find.widgetWithText(OutlinedButton, 'Back'));
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
      await _tapVisible(tester, find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.attempts, hasLength(1));
    },
  );

  testWidgets('all three Morning explanations start closed and open alone', (
    tester,
  ) async {
    const durationHelp =
        'Review the times before saving. Watch times remain editable.';
    const targetHelp =
        'Loaded from the latest saved Evening plan. You can correct it for this night.';
    const qualityHelp =
        'How restorative did your sleep feel, independently of how long you slept?';
    await _pumpPage(tester, _MorningStore());

    expect(find.text(durationHelp), findsNothing);
    expect(find.text(targetHelp), findsNothing);
    expect(
      find.bySemanticsLabel('Show information about Estimated sleep duration'),
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
        const ValueKey('capture-info-control-Sleep target used for this night'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(durationHelp), findsOneWidget);
    expect(find.text(targetHelp), findsOneWidget);

    await _tapVisible(tester, find.text('Next'));
    expect(find.text(qualityHelp), findsNothing);
    expect(
      find.bySemanticsLabel('Show information about Sleep quality'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('capture-info-control-Sleep quality')),
    );
    await tester.pumpAndSettle();
    expect(find.text(qualityHelp), findsOneWidget);
  });
}

Future<void> _performSemanticTap(WidgetTester tester, String label) async {
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
  bool skillsetEnabled = false,
  DateTime? currentInstant,
  HealthSleepSuggestion? watchSleep,
  String? timezoneName,
  ThemeData? theme,
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
        healthSleepSuggestionProvider.overrideWith(
          (ref, day) async => watchSleep,
        ),
        optionalSkillsetCaptureProvider.overrideWithValue(skillsetEnabled),
        skillsetDimensionsProvider.overrideWith((ref) => <String>{}),
        profileLocalDateSourceProvider.overrideWithValue(
          SessionProfileLocalDateSource(
            session: timezoneName == null
                ? null
                : AppSession.authenticated(
                    AppProfile(
                      id: 'timezone-user',
                      email: 'timezone@example.test',
                      name: 'Timezone',
                      timezone: timezoneName,
                      role: AppRole.user,
                      onboardingDone: true,
                      authProvider: 'email',
                    ),
                  ),
            currentInstant: currentInstant == null
                ? DateTime.now
                : () => currentInstant,
          ),
        ),
        if (currentInstant != null)
          currentInstantProvider.overrideWithValue(() => currentInstant),
        quickCheckInStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: theme,
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
    entryDate: dailyCaptureEntryDate(
      DateTime(now.year, now.month, now.day - 1),
    ),
    capturedAt: now.subtract(const Duration(hours: 10)),
    mood: 7,
    energy: 6,
    stress: 3,
    stressSource: null,
    stressControllability: null,
    focusBand: null,
    tomorrowPriority: '',
    plannedSleepTime: dailyCaptureClock(now.subtract(const Duration(hours: 8))),
    sleepTargetMinutes: 480,
    branchVersion: dailyCaptureV4,
  );
}

MorningCalibrationDraft _savedMorning(
  DateTime now, {
  required int estimatedMinutes,
}) {
  final wokeAt = DateTime(now.year, now.month, now.day, now.hour, now.minute);
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
