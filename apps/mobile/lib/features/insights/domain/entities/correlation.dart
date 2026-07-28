class CorrelationMetric {
  const CorrelationMetric({
    required this.id,
    required this.label,
    required this.unit,
    required this.category,
    required this.higherIsPositive,
    this.timing = CorrelationEvidenceTiming.sameLocalDay,
    this.role = CorrelationMetricRole.context,
    this.canBeExperimentFactor = false,
  });

  final String id;
  final String label;
  final String unit;
  final String category;
  final bool higherIsPositive;
  final CorrelationEvidenceTiming timing;
  final CorrelationMetricRole role;
  final bool canBeExperimentFactor;
}

enum CorrelationEvidenceTiming {
  previousNightOnLocalWakeDay,
  ratedSessionDaily,
  sameLocalDay,
}

enum CorrelationMetricRole { factor, outcome, context }

enum CorrelationPairDecision { compare, overlappingSignals }

class CorrelationExperimentPair {
  const CorrelationExperimentPair({
    required this.factor,
    required this.outcome,
  });

  final CorrelationMetric factor;
  final CorrelationMetric outcome;
}

class CorrelationPairPolicy {
  const CorrelationPairPolicy();

  CorrelationPairDecision decision(String metricAId, String metricBId) {
    final pair = {metricAId, metricBId};
    if (_samePair(
          pair,
          'sleep_hours',
          'sleep_target_deviation_minutes',
        ) ||
        _samePair(pair, 'activity_level', 'steps')) {
      return CorrelationPairDecision.overlappingSignals;
    }
    return CorrelationPairDecision.compare;
  }

  bool isBlocked(String metricAId, String metricBId) =>
      decision(metricAId, metricBId) != CorrelationPairDecision.compare;

  CorrelationExperimentPair? experimentFor(
    CorrelationMetric metricA,
    CorrelationMetric metricB,
  ) {
    if (isBlocked(metricA.id, metricB.id)) return null;
    if (metricA.canBeExperimentFactor &&
        metricA.role == CorrelationMetricRole.factor &&
        metricB.role == CorrelationMetricRole.outcome) {
      return CorrelationExperimentPair(factor: metricA, outcome: metricB);
    }
    if (metricB.canBeExperimentFactor &&
        metricB.role == CorrelationMetricRole.factor &&
        metricA.role == CorrelationMetricRole.outcome) {
      return CorrelationExperimentPair(factor: metricB, outcome: metricA);
    }
    return null;
  }

  bool _samePair(Set<String> pair, String first, String second) =>
      pair.length == 2 && pair.contains(first) && pair.contains(second);
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
              result.status == CorrelationStatus.ready &&
              result.sampleSize >= 14 &&
              result.coefficient != null &&
              result.coefficient!.abs() >= 0.2,
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

  bool get isReady =>
      coefficient != null &&
      {
        CorrelationStatus.ready,
        CorrelationStatus.earlyEvidence,
      }.contains(status);

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
        CorrelationStatus.overlappingSignals =>
          'Not compared · overlapping signals',
        CorrelationStatus.earlyEvidence => 'Early evidence',
        CorrelationStatus.ready => 'No result',
      };
    }
    if (status == CorrelationStatus.earlyEvidence) {
      return 'Early evidence';
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
  earlyEvidence,
  notEnoughData,
  notEnoughVariation,
  overlappingSignals,
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
    label: 'Previous-night sleep',
    unit: 'h',
    category: 'Recovery',
    higherIsPositive: true,
    timing: CorrelationEvidenceTiming.previousNightOnLocalWakeDay,
    role: CorrelationMetricRole.factor,
  ),
  CorrelationMetric(
    id: 'focus_minutes',
    label: 'Rated focus time',
    unit: 'min',
    category: 'Work',
    higherIsPositive: true,
    timing: CorrelationEvidenceTiming.ratedSessionDaily,
    role: CorrelationMetricRole.outcome,
  ),
  CorrelationMetric(
    id: 'planned_focus_minutes',
    label: 'Planned focus time',
    unit: 'min',
    category: 'Work',
    higherIsPositive: true,
    timing: CorrelationEvidenceTiming.ratedSessionDaily,
    role: CorrelationMetricRole.factor,
    canBeExperimentFactor: true,
  ),
  CorrelationMetric(
    id: 'focus_quality',
    label: 'Rated focus quality',
    unit: '/5',
    category: 'Work',
    higherIsPositive: true,
    timing: CorrelationEvidenceTiming.ratedSessionDaily,
    role: CorrelationMetricRole.outcome,
  ),
  CorrelationMetric(
    id: 'useful_progress',
    label: 'Rated useful progress',
    unit: '/5',
    category: 'Work',
    higherIsPositive: true,
    timing: CorrelationEvidenceTiming.ratedSessionDaily,
    role: CorrelationMetricRole.outcome,
  ),
  CorrelationMetric(
    id: 'focus_completion_rate',
    label: 'Rated session completion',
    unit: '%',
    category: 'Work',
    higherIsPositive: true,
    timing: CorrelationEvidenceTiming.ratedSessionDaily,
    role: CorrelationMetricRole.outcome,
  ),
  CorrelationMetric(
    id: 'sleep_quality',
    label: 'Previous-night sleep quality',
    unit: '/10',
    category: 'Recovery',
    higherIsPositive: true,
    timing: CorrelationEvidenceTiming.previousNightOnLocalWakeDay,
    role: CorrelationMetricRole.factor,
  ),
  CorrelationMetric(
    id: 'sleep_target_deviation_minutes',
    label: 'Sleep shortfall',
    unit: 'min',
    category: 'Recovery',
    higherIsPositive: false,
    timing: CorrelationEvidenceTiming.previousNightOnLocalWakeDay,
    role: CorrelationMetricRole.factor,
  ),
  CorrelationMetric(
    id: 'stress_level',
    label: 'Stress',
    unit: '/10',
    category: 'Recovery',
    higherIsPositive: false,
    role: CorrelationMetricRole.outcome,
  ),
  CorrelationMetric(
    id: 'energy_level',
    label: 'Energy',
    unit: '/10',
    category: 'Recovery',
    higherIsPositive: true,
    role: CorrelationMetricRole.outcome,
  ),
  CorrelationMetric(
    id: 'mood_score',
    label: 'Mood',
    unit: '/10',
    category: 'Mind',
    higherIsPositive: true,
    role: CorrelationMetricRole.outcome,
  ),
  CorrelationMetric(
    id: 'screen_time_hours',
    label: 'Screen time',
    unit: 'h',
    category: 'Behavior',
    higherIsPositive: false,
    role: CorrelationMetricRole.factor,
    canBeExperimentFactor: true,
  ),
  CorrelationMetric(
    id: 'activity_level',
    label: 'Activity',
    unit: '/10',
    category: 'Movement',
    higherIsPositive: true,
    role: CorrelationMetricRole.factor,
    canBeExperimentFactor: true,
  ),
  CorrelationMetric(
    id: 'steps',
    label: 'Steps',
    unit: 'steps',
    category: 'Movement',
    higherIsPositive: true,
    role: CorrelationMetricRole.factor,
    canBeExperimentFactor: true,
  ),
];
