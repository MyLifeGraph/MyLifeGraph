import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/insights/domain/entities/correlation.dart';
import 'package:my_life_graph/features/insights/domain/entities/period_comparison.dart';
import 'package:my_life_graph/features/insights/presentation/providers/insights_providers.dart';
import 'package:my_life_graph/features/insights/presentation/widgets/period_comparison_card.dart';

void main() {
  final today = DateTime(2026, 9, 16); // Wednesday.
  final metric = periodMetrics.first;
  CorrelationDataPoint point(DateTime day, double value) =>
      CorrelationDataPoint(date: day, values: {'sleep_hours': value});

  for (final days in [7, 14, 30]) {
    test(
      '$days-day periods are adjacent, equally sized and keep missing days',
      () {
        final result = PeriodComparison.build(
          today: today,
          metric: metric,
          mode: PeriodComparisonMode.rolling,
          days: days,
          points: [
            point(today, 7),
            point(today.subtract(Duration(days: days)), 8),
          ],
        );
        expect(result.current.length, days);
        expect(result.previous.length, days);
        expect(result.current.last, 7);
        expect(result.previous.last, 8);
        expect(result.current.first, isNull);
        expect(result.currentStart,
          comparisonDay(today).subtract(Duration(days: days - 1)));
        expect(result.previousStart,
          comparisonDay(today).subtract(Duration(days: days * 2 - 1)));
        expect(result.currentStart.add(Duration(days: days - 1)),
          comparisonDay(today));
        expect(
          result.previousStart.add(Duration(days: days)),
          result.currentStart,
        );
      },
    );
  }
  test('weekday view aligns Monday–Sunday and excludes future values', () {
    final result = PeriodComparison.build(
      today: today,
      metric: metric,
      mode: PeriodComparisonMode.weekdays,
      points: [
        point(DateTime(2026, 9, 14), 5),
        point(DateTime(2026, 9, 15), 6),
        point(today, 7),
        point(DateTime(2026, 9, 20), 9),
        for (var day = 7; day <= 13; day++)
          point(DateTime(2026, 9, day), 8),
      ],
    );
    expect(result.currentStart, DateTime.utc(2026, 9, 14));
    expect(result.previousStart, DateTime.utc(2026, 9, 7));
    expect(result.current, [5, 6, 7, null, null, null, null]);
    expect(result.previous, List.filled(7, 8));
  });
  test('dates survive month/year/DST boundaries without skipped weekdays', () {
    for (final date in [
      DateTime(2026, 1, 1),
      DateTime(2026, 3, 30),
      DateTime(2026, 10, 26),
    ]) {
      final result = PeriodComparison.build(
        today: date,
        metric: metric,
        mode: PeriodComparisonMode.weekdays,
        points: [],
      );
      expect(result.currentStart.weekday, DateTime.monday);
      expect(result.previousStart.weekday, DateTime.monday);
      expect(result.currentStart.difference(result.previousStart).inDays, 7);
    }
  });
  test('missing, nonfinite and invalid values never become zero', () {
    final result = PeriodComparison.build(
      today: today,
      metric: metric,
      mode: PeriodComparisonMode.rolling,
      points: [
        point(today, double.nan),
        point(today.subtract(const Duration(days: 1)), 25),
      ],
    );
    expect(result.hasValues, isFalse);
  });
  test('explicit zero remains a real observation', () {
    final result = PeriodComparison.build(
      today: today,
      metric: periodMetrics.firstWhere((m) => m.id == 'sport_activity'),
      mode: PeriodComparisonMode.rolling,
      points: [
        CorrelationDataPoint(date: today, values: const {'sport_activity': 0}),
      ],
    );
    expect(result.current.last, 0);
    expect(result.hasValues, isTrue);
  });
  test('Discipline keeps existing window formula and minimum evidence', () {
    final dimension = periodMetrics.firstWhere((m) => m.id == 'regularity');
    final points = [
      for (var i = 0; i < 3; i++)
        CorrelationDataPoint(
          date: today.subtract(Duration(days: i)),
          values: {
            'sport_activity': i == 0 ? 0 : 2,
            'focus_count': 1,
            'focus_completed': 1,
          },
        ),
    ];
    final result = PeriodComparison.build(
      today: today,
      metric: dimension,
      mode: PeriodComparisonMode.rolling,
      points: points,
    );
    expect(result.current.last, closeTo((100 + 200 / 3) / 2, .0001));
    expect(result.current[5], isNull); // Only two prior observations.
  });
  for (final width in [320.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('comparison controls fit $width at text $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              periodComparisonDataProvider.overrideWith(
                (ref) async => PeriodComparisonData(
                  today: today,
                  timezone: 'Europe/Berlin',
                  points: [
                    point(today, 7),
                    point(today.subtract(const Duration(days: 7)), 8),
                  ],
                ),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.dark,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const Scaffold(
                body: SingleChildScrollView(child: PeriodComparisonCard()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Past comparison'), findsOneWidget);
        expect(find.text('Latest 7 days · Sep 10 – Sep 16'), findsOneWidget);
        expect(find.text('Previous 7 days · Sep 3 – Sep 9'), findsOneWidget);
        await tester.tap(find.text('14 days'));
        await tester.pumpAndSettle();
        expect(find.text('Latest 14 days · Sep 3 – Sep 16'), findsOneWidget);
        expect(find.text('Previous 14 days · Aug 20 – Sep 2'), findsOneWidget);
        await tester.tap(find.text('Weekdays'));
        await tester.pumpAndSettle();
        expect(find.text('This week · Sep 14 – Sep 16'), findsOneWidget);
        expect(find.text('Last week · Sep 7 – Sep 13'), findsOneWidget);
        expect(find.text('30 days'), findsNothing);
        await tester.ensureVisible(find.text('Details'));
        await tester.tap(find.text('Details'));
        await tester.pumpAndSettle();
        expect(find.text('Sep 16 · 7 hours'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
