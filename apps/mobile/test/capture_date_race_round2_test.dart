import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/capture_draft_providers.dart';
import 'package:my_life_graph/composition/health_connect_providers.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import 'package:my_life_graph/composition/quick_check_in_providers.dart';
import 'package:my_life_graph/composition/skillset_providers.dart';
import 'package:my_life_graph/features/auth/application/profile_local_date_source.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/morning_calibration_page.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/quick_mood_check_in_page.dart';
import 'package:my_life_graph/features/quick_action/presentation/widgets/capture_date_picker.dart';

void main() {
  for (final morning in [true, false]) {
    testWidgets(
      '${morning ? 'Morning' : 'Evening'} duplicate Retry stays single-flight before a delayed date change',
      (tester) async {
        final store = _RetryRaceStore();
        final now = DateTime(2026, 9, 25, 18);
        tester.view.physicalSize = const Size(1000, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              captureDraftOwnerProvider.overrideWithValue(null),
              healthSleepSuggestionProvider.overrideWith(
                (ref, day) async => null,
              ),
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
            child: MaterialApp(
              home: morning
                  ? const MorningCalibrationPage()
                  : const QuickMoodCheckInPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final retry = find.widgetWithText(OutlinedButton, 'Retry load');
        expect(retry, findsOneWidget);
        // Two input activations in one rendered frame must still be serialized.
        await tester.tap(retry);
        await tester.tap(retry);
        await tester.pump();
        expect(
          store.todayReads,
          2,
          reason:
              'The failed initial read and one retry are the only permitted reads.',
        );
        store.firstRetry.complete(store.entry(DateTime(2026, 9, 25)));
        await tester.pumpAndSettle();
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
        expect(store.todayReads, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _RetryRaceStore implements QuickCheckInStore {
  final firstRetry = Completer<DailyCaptureEntry?>();
  final historicalRead = Completer<DailyCaptureEntry?>();
  var todayReads = 0;

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
    if (day.day == 24) return historicalRead.future;
    if (day.day != 25) return entry(day);
    todayReads++;
    if (todayReads == 1) throw StateError('Synthetic initial read failure');
    if (todayReads == 2) return firstRetry.future;
    throw StateError('Unexpected concurrent retry');
  }

  @override
  Future<EveningShutdownDraft?> loadLatestEvening() async => null;
  @override
  Future<void> saveMorning(MorningCalibrationDraft draft) async {}
  @override
  Future<void> saveEvening(EveningShutdownDraft draft) async {}
}
