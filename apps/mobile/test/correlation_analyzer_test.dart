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
      ]),
    );

    final result = report.resultFor('a', 'b');

    expect(result, isNotNull);
    expect(result!.coefficient, closeTo(1, 0.0001));
    expect(result.strengthLabel, 'Strong positive');
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
      ]),
    );

    final result = report.resultFor('a', 'b');

    expect(result, isNotNull);
    expect(result!.coefficient, closeTo(-1, 0.0001));
    expect(result.strengthLabel, 'Strong negative');
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
          ],
          start: today.add(const Duration(days: 2)),
        ),
      ],
    );

    final result = report.resultFor('a', 'b');

    expect(result, isNotNull);
    expect(result!.sampleSize, 5);
    expect(result.coefficient, closeTo(1, 0.0001));
  });

  test('requires at least five shared points', () {
    final report = analyzer.analyze(
      windowDays: 7,
      metrics: _testMetrics,
      points: _points([
        (1, 2),
        (2, 4),
        (3, 6),
        (4, 8),
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
      ]),
    );

    final result = report.resultFor('a', 'b');

    expect(result, isNotNull);
    expect(result!.status, CorrelationStatus.notEnoughVariation);
    expect(result.coefficient, isNull);
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
          sampleSize: 7,
          coefficient: -0.41,
          summary: 'Moderate signal',
        ),
      ],
    );

    expect(report.rankedResults, hasLength(1));
    expect(report.rankedResults.single.metricBId, 'c');
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
