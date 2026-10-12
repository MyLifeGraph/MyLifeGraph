import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:my_life_graph/core/theme/app_visual_tokens.dart';
import 'package:my_life_graph/core/widgets/app_backdrop.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';
import 'package:my_life_graph/features/quick_action/presentation/widgets/capture_date_picker.dart';
import 'support/ui_catalog_capture.dart';

void main() {
  final today = DateTime(2026, 10, 12);
  test('bounded read status distinguishes branches and failed reads', () async {
    final store = _Store();
    final morning = await loadCaptureCalendarStatuses(
      store,
      today,
      morning: true,
    );
    final evening = await loadCaptureCalendarStatuses(
      store,
      today,
      morning: false,
    );
    expect(store.reads.length, 16);
    expect(
      store.reads.every(
        (d) => !d.isBefore(DateTime(2026, 10, 5)) && !d.isAfter(today),
      ),
      isTrue,
    );
    expect(morning['2026-10-05'], CaptureDayStatus.done);
    expect(evening['2026-10-05'], CaptureDayStatus.open);
    expect(morning['2026-10-06'], CaptureDayStatus.open);
    expect(evening['2026-10-06'], CaptureDayStatus.done);
    expect(morning['2026-10-08'], CaptureDayStatus.unknown);
    expect(evening['2026-10-08'], CaptureDayStatus.unknown);
    expect(morning['2026-10-09'], CaptureDayStatus.unknown);
  });
  for (final theme in {
    'glass': AppTheme.liquidGlass,
    'dark': AppTheme.dark,
    'light': AppTheme.light,
    'space': AppTheme.space,
  }.entries) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'calendar ${theme.key} 320px scale$scale preserves readable today and status',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.value,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: CaptureCalendarDialog(
                  date: DateTime(2026, 10, 11),
                  today: today,
                  loadStatuses: () async => {
                    '2026-10-05': CaptureDayStatus.done,
                    '2026-10-08': CaptureDayStatus.open,
                    '2026-10-09': CaptureDayStatus.unknown,
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          TextButton day(int number) => tester.widget<TextButton>(
            find.byKey(
              Key('capture-day-2026-10-${number.toString().padLeft(2, '0')}'),
            ),
          );
          final tokens = tester
              .element(find.byType(CaptureCalendarDialog))
              .visualTokens;
          BoxDecoration face(int number) =>
              tester
                      .widget<Container>(
                        find.byKey(
                          Key(
                            'capture-day-face-2026-10-${number.toString().padLeft(2, '0')}',
                          ),
                        ),
                      )
                      .decoration!
                  as BoxDecoration;
          expect(face(12).color, tokens.brand);
          expect(day(12).style!.foregroundColor!.resolve({}), tokens.onBrand);
          expect((face(5).border! as Border).top.color, tokens.success);
          expect((face(8).border! as Border).top.color, tokens.danger);
          expect((face(9).border! as Border).top, BorderSide.none);
          expect(day(13).onPressed, isNull);
          expect(find.byIcon(Icons.check), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'month navigation crosses boundary but cannot escape eight-day window',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CaptureCalendarDialog(
              date: DateTime(2026, 4, 1),
              today: DateTime(2026, 4, 1),
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, AppIcons.chevronRight),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('March 2026'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, AppIcons.chevronLeft),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('capture-day-2026-03-24')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('capture-day-2026-03-25')))
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets('late result after calendar is closed is harmless', (
    tester,
  ) async {
    final result = Completer<Map<String, CaptureDayStatus>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CaptureCalendarDialog(
            date: today,
            today: today,
            loadStatuses: () => result.future,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    result.complete({'2026-10-05': CaptureDayStatus.done});
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  if (captureUiCatalog) {
    testWidgets('approved calendar actual widget catalog', (tester) async {
      await loadCatalogFonts();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.liquidGlass,
          builder: (_, child) => AppBackdrop(child: child!),
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: CaptureCalendarDialog(
              date: today,
              today: today,
              loadStatuses: () async => {
                for (final day in [5, 6, 7, 9, 11])
                  '2026-10-${day.toString().padLeft(2, '0')}':
                      CaptureDayStatus.done,
                '2026-10-08': CaptureDayStatus.open,
                '2026-10-10': CaptureDayStatus.open,
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await captureCatalog(tester, 'calendar-implemented');
    });
  }
}

class _Store implements QuickCheckInStore {
  final reads = <DateTime>[];
  @override
  QuickCheckInSaveTarget get target => QuickCheckInSaveTarget.guest;
  @override
  Future<DailyCaptureEntry?> loadToday(DateTime date) async {
    reads.add(date);
    if (date.day == 8) throw StateError('unavailable');
    if (date.day == 9) return const DailyCaptureEntry(entryDate: '2026-10-01');
    if (date.day == 5) {
      return DailyCaptureEntry(
        entryDate: dailyCaptureEntryDate(date),
        morning: MorningCalibrationDraft.empty(date)
            .withSleepInterval(
              estimatedSleepStartedAt: date.subtract(const Duration(hours: 1)),
              wokeAt: date.add(const Duration(hours: 7)),
            )
            .copyWith(sleepQuality: 7, energy: 7, sleepTargetMinutes: 480),
      );
    }
    if (date.day == 6) {
      return DailyCaptureEntry(
        entryDate: dailyCaptureEntryDate(date),
        evening: EveningShutdownDraft.empty(date).copyWith(
          mood: 7,
          energy: 7,
          stress: 3,
          plannedSleepTime: '23:00',
          sleepTargetMinutes: 480,
        ),
      );
    }
    return null;
  }

  @override
  Future<EveningShutdownDraft?> loadLatestEvening() async => null;
  @override
  Future<void> saveMorning(MorningCalibrationDraft draft) async =>
      throw StateError('read only');
  @override
  Future<void> saveEvening(EveningShutdownDraft draft) async =>
      throw StateError('read only');
}
