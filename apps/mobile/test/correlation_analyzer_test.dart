import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/insights/domain/entities/correlation.dart';
import 'package:my_life_graph/features/insights/domain/services/correlation_analyzer.dart';

void main() {
  const analyzer = CorrelationAnalyzer();

  test('detects a perfect positive correlation', () {
    final report = analyzer.analyze(
      windowDays: 7,
      metrics: _testMetrics,
      points: _points([
        (1, 2),
        (2, 4),
        (3, 6),
        (4, 8),
        (5, 10),
        (6, 12),
        (7, 14),
      ]),
    );

    final result = report.resultFor('a', 'b');

    expect(result, isNotNull);
    expect(result!.coefficient, closeTo(1, 0.0001));
    expect(result.status, CorrelationStatus.earlyEvidence);
    expect(result.strengthLabel, 'Early evidence');
  });

  test('detects a perfect negative correlation', () {
    final report = analyzer.analyze(
      windowDays: 7,
      metrics: _testMetrics,
      points: _points([
        (1, 10),
        (2, 8),
        (3, 6),
        (4, 4),
        (5, 2),
        (6, 0),
        (7, -2),
      ]),
    );

    final result = report.resultFor('a', 'b');

    expect(result, isNotNull);
    expect(result!.coefficient, closeTo(-1, 0.0001));
    expect(result.strengthLabel, 'Early evidence');
  });

  test('ignores missing paired days', () {
    final today = DateTime(2026, 7, 4);
    final report = analyzer.analyze(
      windowDays: 7,
      metrics: _testMetrics,
      points: [
        CorrelationDataPoint(
          date: today,
          values: const {'a': 1, 'b': 2},
        ),
        CorrelationDataPoint(
          date: today.add(const Duration(days: 1)),
          values: const {'a': 2},
        ),
        ..._points(
          [
            (2, 4),
            (3, 6),
            (4, 8),
            (5, 10),
            (6, 12),
            (7, 14),
          ],
          start: today.add(const Duration(days: 2)),
        ),
      ],
    );

    final result = report.resultFor('a', 'b');

    expect(result, isNotNull);
    expect(result!.sampleSize, 7);
    expect(result.coefficient, closeTo(1, 0.0001));
  });

  test('requires at least seven shared points', () {
    final report = analyzer.analyze(
      windowDays: 7,
      metrics: _testMetrics,
      points: _points([
        (1, 2),
        (2, 4),
        (3, 6),
        (4, 8),
        (5, 10),
        (6, 12),
      ]),
    );

    final result = report.resultFor('a', 'b');

    expect(result, isNotNull);
    expect(result!.status, CorrelationStatus.notEnoughData);
    expect(result.coefficient, isNull);
  });

  test('handles series without useful variation', () {
    final report = analyzer.analyze(
      windowDays: 7,
      metrics: _testMetrics,
      points: _points([
        (1, 2),
        (1, 4),
        (1, 6),
        (1, 8),
        (1, 10),
        (1, 12),
        (1, 14),
      ]),
    );

    final result = report.resultFor('a', 'b');

    expect(result, isNotNull);
    expect(result!.status, CorrelationStatus.notEnoughVariation);
    expect(result.coefficient, isNull);
  });

  test('does not offer metrics that were never measured', () {
    final report = analyzer.analyze(
      windowDays: 7,
      metrics: _testMetrics,
      points: _points([
        (1, 2),
        (2, 4),
        (3, 6),
        (4, 8),
        (5, 10),
        (6, 12),
        (7, 14),
      ]),
    );

    expect(report.metrics.map((metric) => metric.id), ['a', 'b']);
    expect(report.resultFor('a', 'c'), isNull);
  });

  test('ranked results ignore weak relationships', () {
    final report = CorrelationReport(
      windowDays: 7,
      metrics: _testMetrics,
      points: const [],
      results: const [
        CorrelationResult(
          metricAId: 'a',
          metricBId: 'b',
          sampleSize: 7,
          coefficient: 0.19,
          summary: 'Weak noise',
        ),
        CorrelationResult(
          metricAId: 'a',
          metricBId: 'c',
          sampleSize: 14,
          coefficient: -0.41,
          summary: 'Moderate signal',
        ),
      ],
    );

    expect(report.rankedResults, hasLength(1));
    expect(report.rankedResults.single.metricBId, 'c');
  });

  test('keeps 7 through 13 days as early evidence and ranks from 14', () {
    final early = analyzer.analyze(
      windowDays: 14,
      metrics: _testMetrics,
      points: _points([
        (1, 2),
        (2, 4),
        (3, 6),
        (4, 8),
        (5, 10),
        (6, 12),
        (7, 14),
        (8, 16),
        (9, 18),
        (10, 20),
        (11, 22),
        (12, 24),
        (13, 26),
      ]),
    );
    final mature = analyzer.analyze(
      windowDays: 14,
      metrics: _testMetrics,
      points: _points([
        for (var day = 1; day <= 14; day++) (day.toDouble(), day * 2.0),
      ]),
    );

    expect(early.resultFor('a', 'b')?.status, CorrelationStatus.earlyEvidence);
    expect(early.rankedResults, isEmpty);
    expect(mature.resultFor('a', 'b')?.status, CorrelationStatus.ready);
    expect(mature.rankedResults, isNotEmpty);
  });

  test('does not compare the two explicitly overlapping signal pairs', () {
    final points = [
      for (var day = 0; day < 14; day++)
        CorrelationDataPoint(
          date: DateTime(2026, 7, day + 1),
          values: {
            'sleep_hours': 7 + day / 10,
            'sleep_target_deviation_minutes': day.toDouble(),
            'activity_level': (day % 10).toDouble(),
            'steps': 3000 + day * 100,
          },
        ),
    ];
    final report = analyzer.analyze(
      windowDays: 14,
      points: points,
    );

    expect(
      report.resultFor('sleep_hours', 'sleep_target_deviation_minutes')?.status,
      CorrelationStatus.overlappingSignals,
    );
    expect(
      report.resultFor('activity_level', 'steps')?.status,
      CorrelationStatus.overlappingSignals,
    );
    expect(
      report.rankedResults.any(
        (result) => const CorrelationPairPolicy().isBlocked(
          result.metricAId,
          result.metricBId,
        ),
      ),
      isFalse,
    );
    expect(
      analyzer.pairValues(
        points: points,
        metricAId: 'activity_level',
        metricBId: 'steps',
      ),
      isEmpty,
    );
  });
}

const _testMetrics = [
  CorrelationMetric(
    id: 'a',
    label: 'A',
    unit: '',
    category: 'Test',
    higherIsPositive: true,
  ),
  CorrelationMetric(
    id: 'b',
    label: 'B',
    unit: '',
    category: 'Test',
    higherIsPositive: true,
  ),
  CorrelationMetric(
    id: 'c',
    label: 'C',
    unit: '',
    category: 'Test',
    higherIsPositive: true,
  ),
];

List<CorrelationDataPoint> _points(
  List<(double, double)> values, {
  DateTime? start,
}) {
  final firstDate = start ?? DateTime(2026, 7, 4);
  return [
    for (var index = 0; index < values.length; index++)
      CorrelationDataPoint(
        date: firstDate.add(Duration(days: index)),
        values: {
          'a': values[index].$1,
          'b': values[index].$2,
        },
      ),
  ];
}
