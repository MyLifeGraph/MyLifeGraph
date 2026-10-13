import '../entities/correlation.dart';
import '../entities/personal_patterns.dart';
import 'checkin_correlations.dart';

/// Descriptive fallbacks only: never a correlation or learned preference.
enum OverviewObservationTier { general, preliminary, supported }

class OverviewObservation {
  OverviewObservation({
    required this.tier,
    required this.title,
    required List<String> bullets,
    required this.observedDays,
    required List<String> details,
    required List<String> missingSources,
    List<String> sourceUrls = const [],
    this.sourceLabel = 'General advice',
    this.isCorrelation = false,
  }) : bullets = List.unmodifiable(bullets),
       details = List.unmodifiable(details),
       missingSources = List.unmodifiable(missingSources),
       sourceUrls = List.unmodifiable(sourceUrls);

  final OverviewObservationTier tier;
  final String title;
  final List<String> bullets;
  final int observedDays;
  final List<String> details;
  final List<String> missingSources;
  final List<String> sourceUrls;
  final String sourceLabel;
  final bool isCorrelation;

  String get label => switch (tier) {
    OverviewObservationTier.general => 'General guidance',
    OverviewObservationTier.preliminary =>
      isCorrelation ? 'Early patterns' : 'Early observations',
    OverviewObservationTier.supported => 'Consistent observations',
  };
}

class OverviewObservations {
  const OverviewObservations({required this.study, required this.sleep});

  /// Null means analysis is disabled, not insufficient observations.
  final OverviewObservation? study;
  final OverviewObservation? sleep;
}

const overviewMinimumObservedDays = 7;
const _studySource =
    'https://www.psychologicalscience.org/journals/pspi/1529100612453266/';
const _sleepSource =
    'https://www.nhlbi.nih.gov/health/sleep-deprivation/healthy-sleep-habits';

/// Projects the consent-gated Skillset observations without changing the report.
/// Profile-local civil dates are used as supplied; device timezone is irrelevant.
OverviewObservations overviewObservations(PersonalPatterns report) {
  if (report.status == PersonalPatternsStatus.disabled) {
    return const OverviewObservations(study: null, sleep: null);
  }
  final days = _uniqueBoundedDays(report);
  final checkins = <_Metric>[
    _metric(days, 'energy_level', 'Energy', 1, 10),
    _metric(days, 'mood_score', 'Mood', 1, 10),
    _metric(days, 'stress_level', 'Stress', 1, 10),
  ];
  final focus = days
      .where((point) {
        final count = point.values['focus_count'];
        final completed = point.values['focus_completed'];
        return count != null &&
            completed != null &&
            count.isFinite &&
            completed.isFinite &&
            count > 0 &&
            // Beyond this, a double cannot reliably represent an integer count.
            count <= 9007199254740991 &&
            count == count.truncateToDouble() &&
            completed >= 0 &&
            completed <= count &&
            completed == completed.truncateToDouble();
      })
      .toList(growable: false);
  final sleep = <_Metric>[
    _metric(
      days,
      'sleep_hours',
      'Sleep duration',
      0,
      24,
      exclusiveMinimum: true,
    ),
    _metric(days, 'sleep_quality', 'Sleep quality', 1, 10),
  ];
  final studyMetrics = checkins
      .where((metric) => metric.ready)
      .take(2)
      .toList();
  final sleepMetrics = sleep.where((metric) => metric.ready).toList();
  final checkinDays = _unionDays(checkins);
  final studyMissing = <String>[
    if (focus.length < overviewMinimumObservedDays)
      'Focus history: ${focus.length}/7 days',
    if (!checkins.any((metric) => metric.ready))
      'Check-in history: ${_maximumMetricDays(checkins)}/7 days',
  ];
  final sleepMissing = <String>[
    if (sleepMetrics.isEmpty)
      'Sleep history: ${_maximumMetricDays(sleep)}/7 days',
    if (focus.length < overviewMinimumObservedDays)
      'Focus history: ${focus.length}/7 days',
  ];

  final OverviewObservation study;
  if (studyMetrics.isNotEmpty) {
    study = _descriptive(
      title: 'Your check-ins',
      metrics: studyMetrics,
      missing: studyMissing,
      sourceLabel: 'Check-in data',
    );
  } else if (focus.length >= overviewMinimumObservedDays) {
    final count = focus.fold<double>(
      0,
      (sum, p) => sum + p.values['focus_count']!,
    );
    final completed = focus.fold<double>(
      0,
      (sum, p) => sum + p.values['focus_completed']!,
    );
    study = OverviewObservation(
      tier: OverviewObservationTier.preliminary,
      title: 'Your Focus activity',
      sourceLabel: 'Focus activity',
      bullets: [
        '${count.toStringAsFixed(0)} terminal Focus sessions · ${focus.length} days',
        '${(completed / count * 100).toStringAsFixed(0)}% completed',
      ],
      observedDays: focus.length,
      details: [
        '${completed.toStringAsFixed(0)} of ${count.toStringAsFixed(0)} terminal sessions completed.',
        'Recorded activity only; no timing or causal conclusion.',
      ],
      missingSources: studyMissing,
    );
  } else {
    study = OverviewObservation(
      tier: OverviewObservationTier.general,
      title: 'Study guidance',
      bullets: const [
        'Space study across several days.',
        'Test yourself, not just reread.',
      ],
      observedDays: checkinDays > focus.length ? checkinDays : focus.length,
      details: const [
        'General study strategies, not a finding from your data.',
        'Personal summaries need 7 valid days for each displayed measure.',
      ],
      missingSources: studyMissing,
      sourceUrls: const [_studySource],
    );
  }

  return OverviewObservations(
    study: _checkInPattern(report, sleep: false) ?? study,
    sleep:
        _checkInPattern(report, sleep: true) ??
        (sleepMetrics.isNotEmpty
            ? _descriptive(
                title: 'Your sleep observations',
                metrics: sleepMetrics,
                missing: sleepMissing,
                sourceLabel: 'Sleep check-in data',
              )
            : OverviewObservation(
                tier: OverviewObservationTier.general,
                title: 'Sleep guidance',
                bullets: const [
                  'Keep a regular sleep routine.',
                  'Wind down before bed.',
                ],
                observedDays: _unionDays(sleep),
                details: const [
                  'General sleep habits, not a personal sleep recommendation.',
                  'Personal summaries need 7 valid days for each displayed measure.',
                ],
                missingSources: sleepMissing,
                sourceUrls: const [_sleepSource],
              )),
  );
}

OverviewObservation? _checkInPattern(
  PersonalPatterns report, {
  required bool sleep,
}) {
  final correlations = checkInCorrelationReport(report, windowDays: 90);
  if (!correlations.isCheckInFallback) return null;
  final matches = correlations.rankedResults
      .where((r) {
        final sleepPair = {
          r.metricAId,
          r.metricBId,
        }.any((id) => id == 'sleep_hours' || id == 'sleep_quality');
        return sleepPair == sleep;
      })
      .take(2)
      .toList();
  if (matches.isEmpty) return null;
  final supported = matches.every((r) => r.status == CorrelationStatus.ready);
  return OverviewObservation(
    tier: supported
        ? OverviewObservationTier.supported
        : OverviewObservationTier.preliminary,
    isCorrelation: true,
    title: sleep ? 'Your sleep patterns' : 'Your check-in patterns',
    bullets: matches.map((r) => r.summary).toList(),
    observedDays: matches
        .map((r) => r.sampleSize)
        .reduce((a, b) => a < b ? a : b),
    sourceLabel: 'Check-in data',
    missingSources: const [],
    details: [
      for (final r in matches)
        '${correlations.metricById(r.metricAId).label} / ${correlations.metricById(r.metricBId).label}: ${r.sampleSize} shared days, r = ${r.coefficientLabel}.',
      'Associations, not causes or recommended targets.',
      'For more reliable insights: 28 shared days and the same direction in both chronological halves.',
      'Focus learning patterns remain separate.',
    ],
  );
}

OverviewObservation _descriptive({
  required String title,
  required List<_Metric> metrics,
  required List<String> missing,
  required String sourceLabel,
}) => OverviewObservation(
  tier: OverviewObservationTier.preliminary,
  title: title,
  sourceLabel: sourceLabel,
  bullets: [for (final metric in metrics) metric.summary],
  observedDays: _unionDays(metrics),
  details: [
    for (final metric in metrics)
      '${metric.label}: median of ${metric.points.length} observed days.',
    'Descriptive observations only; not a stable pattern or a causal conclusion.',
    if (metrics.any((metric) => metric.key == 'stress_level'))
      'Stress is not inverted; lower means calmer.',
  ],
  missingSources: missing,
);

List<CorrelationDataPoint> _uniqueBoundedDays(PersonalPatterns report) {
  // Convert civil date components, never instants or duration-based DST math.
  DateTime day(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
  final start = day(report.window.localStartsOn);
  final end = day(report.window.localEndsOn);
  final grouped = <DateTime, List<CorrelationDataPoint>>{};
  for (final point in report.skillsetPoints) {
    if (point.date.hour != 0 ||
        point.date.minute != 0 ||
        point.date.second != 0 ||
        point.date.millisecond != 0 ||
        point.date.microsecond != 0) {
      continue;
    }
    final date = day(point.date);
    if (date.isBefore(start) || date.isAfter(end)) continue;
    grouped.putIfAbsent(date, () => []).add(point);
  }
  final dates = grouped.keys.toList()..sort();
  return [
    for (final date in dates)
      if (grouped[date]!.length == 1)
        CorrelationDataPoint(date: date, values: grouped[date]!.single.values),
  ];
}

_Metric _metric(
  List<CorrelationDataPoint> days,
  String key,
  String label,
  double minimum,
  double maximum, {
  bool exclusiveMinimum = false,
}) => _Metric(
  key,
  label,
  days
      .where((point) {
        final value = point.values[key];
        return value != null &&
            value.isFinite &&
            (exclusiveMinimum ? value > minimum : value >= minimum) &&
            value <= maximum;
      })
      .toList(growable: false),
);

int _unionDays(List<_Metric> metrics) => {
  for (final metric in metrics)
    for (final point in metric.points) point.date,
}.length;

int _maximumMetricDays(List<_Metric> metrics) => metrics.fold(
  0,
  (maximum, metric) =>
      metric.points.length > maximum ? metric.points.length : maximum,
);

class _Metric {
  const _Metric(this.key, this.label, this.points);

  final String key;
  final String label;
  final List<CorrelationDataPoint> points;

  bool get ready => points.length >= overviewMinimumObservedDays;

  String get summary {
    final sorted = points.map((point) => point.values[key]!).toList()..sort();
    final middle = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[middle]
        : sorted[middle - 1] / 2 + sorted[middle] / 2;
    if (key == 'sleep_hours') {
      final minutes = (median * 60).round();
      final hours = minutes ~/ 60;
      final remaining = minutes % 60;
      final value = minutes == 0
          ? '<1m'
          : [
              if (hours > 0) '${hours}h',
              if (remaining > 0) '${remaining}m',
            ].join(' ');
      return '$label · $value median';
    }
    final value = median.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    return '$label · $value/10 median';
  }
}
