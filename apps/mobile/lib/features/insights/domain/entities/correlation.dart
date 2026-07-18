class CorrelationMetric {
  const CorrelationMetric({
    required this.id,
    required this.label,
    required this.unit,
    required this.category,
    required this.higherIsPositive,
  });

  final String id;
  final String label;
  final String unit;
  final String category;
  final bool higherIsPositive;
}

const insightsWindowDayOptions = <int>[7, 14, 30, 90];
const maximumInsightsWindowDays = 90;

int normalizeInsightsWindowDays(int windowDays) {
  if (windowDays < 0 || windowDays > maximumInsightsWindowDays) {
    return maximumInsightsWindowDays;
  }
  if (windowDays < insightsWindowDayOptions.first) {
    return insightsWindowDayOptions.first;
  }
  return windowDays;
}

class CorrelationDataPoint {
  const CorrelationDataPoint({
    required this.date,
    required this.values,
  });

  final DateTime date;
  final Map<String, double> values;
}

class CorrelationReport {
  const CorrelationReport({
    required this.windowDays,
    required this.metrics,
    required this.points,
    required this.results,
  });

  final int windowDays;
  final List<CorrelationMetric> metrics;
  final List<CorrelationDataPoint> points;
  final List<CorrelationResult> results;

  CorrelationMetric metricById(String id) {
    return metrics.firstWhere(
      (metric) => metric.id == id,
      orElse: () => metrics.first,
    );
  }

  CorrelationResult? resultFor(String metricAId, String metricBId) {
    if (metricAId == metricBId) {
      return null;
    }
    for (final result in results) {
      final matchesForward =
          result.metricAId == metricAId && result.metricBId == metricBId;
      final matchesReverse =
          result.metricAId == metricBId && result.metricBId == metricAId;
      if (matchesForward || matchesReverse) {
        return result;
      }
    }
    return null;
  }

  List<CorrelationResult> get rankedResults {
    final ranked = results
        .where(
          (result) =>
              result.coefficient != null && result.coefficient!.abs() >= 0.2,
        )
        .toList(growable: false);
    return ranked
      ..sort(
        (a, b) => b.coefficient!.abs().compareTo(a.coefficient!.abs()),
      );
  }
}

class CorrelationResult {
  const CorrelationResult({
    required this.metricAId,
    required this.metricBId,
    required this.sampleSize,
    required this.summary,
    this.coefficient,
    this.status = CorrelationStatus.ready,
  });

  final String metricAId;
  final String metricBId;
  final int sampleSize;
  final double? coefficient;
  final CorrelationStatus status;
  final String summary;

  bool get isReady => status == CorrelationStatus.ready && coefficient != null;

  String get coefficientLabel {
    if (coefficient == null) {
      return '--';
    }
    return coefficient!.toStringAsFixed(2);
  }

  String get strengthLabel {
    if (coefficient == null) {
      return switch (status) {
        CorrelationStatus.notEnoughData => 'Not enough data',
        CorrelationStatus.notEnoughVariation => 'No useful variation',
        CorrelationStatus.ready => 'No result',
      };
    }

    final absValue = coefficient!.abs();
    final direction = coefficient! >= 0 ? 'positive' : 'negative';
    if (absValue >= 0.7) {
      return 'Strong $direction';
    }
    if (absValue >= 0.4) {
      return 'Moderate $direction';
    }
    if (absValue >= 0.2) {
      return 'Weak $direction';
    }
    return 'Little relationship';
  }
}

enum CorrelationStatus {
  ready,
  notEnoughData,
  notEnoughVariation,
}

class MetricPairValues {
  const MetricPairValues({
    required this.date,
    required this.metricAValue,
    required this.metricBValue,
  });

  final DateTime date;
  final double metricAValue;
  final double metricBValue;
}

const correlationMetrics = [
  CorrelationMetric(
    id: 'sleep_hours',
    label: 'Sleep',
    unit: 'h',
    category: 'Recovery',
    higherIsPositive: true,
  ),
  CorrelationMetric(
    id: 'focus_minutes',
    label: 'Focus',
    unit: 'min',
    category: 'Work',
    higherIsPositive: true,
  ),
  CorrelationMetric(
    id: 'planned_minutes',
    label: 'Current planned workload',
    unit: 'min',
    category: 'Work',
    higherIsPositive: false,
  ),
  CorrelationMetric(
    id: 'stress_level',
    label: 'Stress',
    unit: '/10',
    category: 'Recovery',
    higherIsPositive: false,
  ),
  CorrelationMetric(
    id: 'energy_level',
    label: 'Energy',
    unit: '/10',
    category: 'Recovery',
    higherIsPositive: true,
  ),
  CorrelationMetric(
    id: 'mood_score',
    label: 'Mood',
    unit: '/10',
    category: 'Mind',
    higherIsPositive: true,
  ),
  CorrelationMetric(
    id: 'screen_time_hours',
    label: 'Screen time',
    unit: 'h',
    category: 'Behavior',
    higherIsPositive: false,
  ),
  CorrelationMetric(
    id: 'activity_level',
    label: 'Activity',
    unit: '/10',
    category: 'Movement',
    higherIsPositive: true,
  ),
  CorrelationMetric(
    id: 'steps',
    label: 'Steps',
    unit: 'steps',
    category: 'Movement',
    higherIsPositive: true,
  ),
  CorrelationMetric(
    id: 'habit_completion_rate',
    label: 'Habits',
    unit: '%',
    category: 'Routine',
    higherIsPositive: true,
  ),
];
