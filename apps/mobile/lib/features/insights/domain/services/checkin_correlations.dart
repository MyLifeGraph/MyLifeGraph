import '../entities/correlation.dart';
import '../entities/personal_patterns.dart';
import 'correlation_analyzer.dart';

/// Additive display fallback. Never changes learned timing or backend evidence.
CorrelationReport checkInCorrelationReport(
  PersonalPatterns report, {
  required int windowDays,
  CorrelationAnalyzer analyzer = const CorrelationAnalyzer(),
}) {
  final legacy = report.correlationDataPoints(windowDays: windowDays);
  if (report.status == PersonalPatternsStatus.disabled ||
      report.correlationPoints.isNotEmpty) {
    return analyzer.analyze(windowDays: windowDays, points: legacy);
  }
  final metrics = [
    ...correlationMetrics.where(
      (m) => const {
        'sleep_hours',
        'sleep_quality',
        'energy_level',
        'mood_score',
        'stress_level',
      }.contains(m.id),
    ),
    const CorrelationMetric(
      id: 'sport_activity',
      label: 'Sport',
      unit: '/2',
      category: 'Movement',
      higherIsPositive: true,
      role: CorrelationMetricRole.factor,
    ),
    const CorrelationMetric(
      id: 'social_activity',
      label: 'Social activity',
      unit: '/2',
      category: 'Behavior',
      higherIsPositive: true,
      role: CorrelationMetricRole.factor,
    ),
    const CorrelationMetric(
      id: 'study_motivation',
      label: 'Study motivation',
      unit: '/2',
      category: 'Mind',
      higherIsPositive: true,
      role: CorrelationMetricRole.outcome,
    ),
  ];
  DateTime day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
  final end = day(report.window.localEndsOn);
  final start = end.subtract(
    Duration(days: normalizeInsightsWindowDays(windowDays) - 1),
  );
  final groups = <DateTime, List<CorrelationDataPoint>>{};
  for (final p in report.skillsetPoints) {
    if (p.date.hour != 0 ||
        p.date.minute != 0 ||
        p.date.second != 0 ||
        p.date.millisecond != 0 ||
        p.date.microsecond != 0) {
      continue;
    }
    final d = day(p.date);
    if (d.isBefore(start) ||
        d.isBefore(day(report.window.localStartsOn)) ||
        d.isAfter(end)) {
      continue;
    }
    groups.putIfAbsent(d, () => []).add(p);
  }
  final dates = groups.keys.toList()..sort();
  final points = [
    for (final d in dates)
      if (groups[d]!.length == 1)
        CorrelationDataPoint(
          date: d,
          values: {
            for (final m in metrics)
              if (_valid(m.id, groups[d]!.single.values[m.id]))
                m.id: groups[d]!.single.values[m.id]!,
          },
        ),
  ];
  final raw = analyzer.analyze(
    windowDays: windowDays,
    points: points,
    metrics: metrics,
  );
  final results = [
    for (final result in raw.results)
      _confidence(result, points, metrics, analyzer),
  ];
  return CorrelationReport(
    windowDays: windowDays,
    metrics: raw.metrics,
    points: points,
    results: results,
    isCheckInFallback: true,
  );
}

bool _valid(String id, double? value) =>
    value != null &&
    value.isFinite &&
    (id == 'sleep_hours'
        ? value > 0 && value <= 24
        : const {
            'sport_activity',
            'social_activity',
            'study_motivation',
          }.contains(id)
        ? value >= 0 && value <= 2 && value == value.truncateToDouble()
        : value >= 1 && value <= 10);

CorrelationResult _confidence(
  CorrelationResult result,
  List<CorrelationDataPoint> points,
  List<CorrelationMetric> metrics,
  CorrelationAnalyzer analyzer,
) {
  if (!result.isReady) return result;
  final paired = points
      .where(
        (p) =>
            p.values.containsKey(result.metricAId) &&
            p.values.containsKey(result.metricBId),
      )
      .toList();
  bool consistent = false;
  if (paired.length >= 28 &&
      paired.last.date.difference(paired.first.date).inDays >= 27 &&
      result.coefficient!.abs() >= .2) {
    final middle = paired.length ~/ 2;
    double? coefficient(List<CorrelationDataPoint> half) => analyzer
        .analyze(
          windowDays: 90,
          points: half,
          metrics: metrics
              .where(
                (m) => m.id == result.metricAId || m.id == result.metricBId,
              )
              .toList(),
        )
        .resultFor(result.metricAId, result.metricBId)
        ?.coefficient;
    final first = coefficient(paired.sublist(0, middle));
    final second = coefficient(paired.sublist(middle));
    consistent =
        first != null &&
        second != null &&
        first.abs() >= .2 &&
        second.abs() >= .2 &&
        first.sign == result.coefficient!.sign &&
        second.sign == result.coefficient!.sign;
  }
  return CorrelationResult(
    metricAId: result.metricAId,
    metricBId: result.metricBId,
    sampleSize: result.sampleSize,
    summary: result.summary,
    coefficient: result.coefficient,
    status: consistent
        ? CorrelationStatus.ready
        : CorrelationStatus.earlyEvidence,
  );
}
