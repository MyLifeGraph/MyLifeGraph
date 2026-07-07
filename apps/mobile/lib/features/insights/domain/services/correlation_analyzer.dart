import 'dart:math' as math;

import '../entities/correlation.dart';

class CorrelationAnalyzer {
  const CorrelationAnalyzer();

  static const minimumSampleSize = 5;

  CorrelationReport analyze({
    required int windowDays,
    required List<CorrelationDataPoint> points,
    List<CorrelationMetric> metrics = correlationMetrics,
  }) {
    final sortedPoints = points.toList(growable: false)
      ..sort((a, b) => a.date.compareTo(b.date));
    final results = <CorrelationResult>[];

    for (var i = 0; i < metrics.length; i++) {
      for (var j = i + 1; j < metrics.length; j++) {
        results.add(
          _analyzePair(
            metricA: metrics[i],
            metricB: metrics[j],
            points: sortedPoints,
          ),
        );
      }
    }

    return CorrelationReport(
      windowDays: windowDays,
      metrics: metrics,
      points: sortedPoints,
      results: results,
    );
  }

  List<MetricPairValues> pairValues({
    required List<CorrelationDataPoint> points,
    required String metricAId,
    required String metricBId,
  }) {
    return points
        .map((point) {
          final valueA = point.values[metricAId];
          final valueB = point.values[metricBId];
          if (valueA == null ||
              valueB == null ||
              !valueA.isFinite ||
              !valueB.isFinite) {
            return null;
          }
          return MetricPairValues(
            date: point.date,
            metricAValue: valueA,
            metricBValue: valueB,
          );
        })
        .nonNulls
        .toList(growable: false);
  }

  CorrelationResult _analyzePair({
    required CorrelationMetric metricA,
    required CorrelationMetric metricB,
    required List<CorrelationDataPoint> points,
  }) {
    final values = pairValues(
      points: points,
      metricAId: metricA.id,
      metricBId: metricB.id,
    );

    if (values.length < minimumSampleSize) {
      return CorrelationResult(
        metricAId: metricA.id,
        metricBId: metricB.id,
        sampleSize: values.length,
        status: CorrelationStatus.notEnoughData,
        summary:
            'Need at least $minimumSampleSize shared days to compare ${metricA.label} and ${metricB.label}.',
      );
    }

    final coefficient = _pearson(values);
    if (coefficient == null) {
      return CorrelationResult(
        metricAId: metricA.id,
        metricBId: metricB.id,
        sampleSize: values.length,
        status: CorrelationStatus.notEnoughVariation,
        summary:
            '${metricA.label} and ${metricB.label} did not vary enough in this window.',
      );
    }

    return CorrelationResult(
      metricAId: metricA.id,
      metricBId: metricB.id,
      sampleSize: values.length,
      coefficient: coefficient,
      summary: _summary(metricA, metricB, coefficient),
    );
  }

  double? _pearson(List<MetricPairValues> values) {
    final meanA = values
            .map((value) => value.metricAValue)
            .reduce((value, element) => value + element) /
        values.length;
    final meanB = values
            .map((value) => value.metricBValue)
            .reduce((value, element) => value + element) /
        values.length;

    var numerator = 0.0;
    var sumSquaredA = 0.0;
    var sumSquaredB = 0.0;

    for (final value in values) {
      final diffA = value.metricAValue - meanA;
      final diffB = value.metricBValue - meanB;
      numerator += diffA * diffB;
      sumSquaredA += diffA * diffA;
      sumSquaredB += diffB * diffB;
    }

    final denominator = math.sqrt(sumSquaredA * sumSquaredB);
    if (denominator == 0) {
      return null;
    }

    return (numerator / denominator).clamp(-1, 1);
  }

  String _summary(
    CorrelationMetric metricA,
    CorrelationMetric metricB,
    double coefficient,
  ) {
    final absValue = coefficient.abs();
    final direction = coefficient >= 0 ? 'move together' : 'move opposite';
    final strength = switch (absValue) {
      >= 0.7 => 'strongly',
      >= 0.4 => 'moderately',
      >= 0.2 => 'weakly',
      _ => 'only lightly',
    };

    return '${metricA.label} and ${metricB.label} $strength $direction in this window.';
  }
}
