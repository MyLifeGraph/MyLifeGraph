import 'correlation.dart';
import 'skillset_observations.dart';

enum PeriodComparisonMode { rolling, weekdays }

class PeriodMetric {
  const PeriodMetric(
    this.id,
    this.label,
    this.unit,
    this.max, {
    this.min = 0,
    this.rollingSummary = false,
  });
  final String id;
  final String label;
  final String unit;
  final double min;
  final double max;
  final bool rollingSummary;
}

const periodMetrics = [
  PeriodMetric('sleep_hours', 'Sleep duration', 'hours', 24),
  PeriodMetric('sleep_quality', 'Sleep quality', '/10', 10, min: 1),
  PeriodMetric('sport_activity', 'Sport', '0–2', 2),
  PeriodMetric('energy_level', 'Energy', '/10', 10, min: 1),
  PeriodMetric('social_activity', 'Social contact', '0–2', 2),
  PeriodMetric(
    'learning_completion_rate',
    'Learning',
    '%',
    100,
    rollingSummary: true,
  ),
  PeriodMetric('focus_quality', 'Concentration', '/5', 5, min: 1),
  PeriodMetric('stress_level', 'Stress', '/10', 10),
  PeriodMetric('mood_score', 'Mood', '/10', 10, min: 1),
  PeriodMetric('useful_progress', 'Productivity', '/5', 5, min: 1),
  PeriodMetric('study_motivation', 'Motivation', '0–2', 2),
  PeriodMetric('regularity', 'Discipline', '%', 100, rollingSummary: true),
  PeriodMetric('focus_minutes', 'Focus time', 'min', 1440),
];

/// Calendar dates, not instants: DST must not shift a comparison's weekdays.
DateTime comparisonDay(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day);

class PeriodComparisonData {
  const PeriodComparisonData({
    required this.points,
    required this.today,
    required this.timezone,
    this.enabled = true,
    this.isDemo = false,
  });
  final List<CorrelationDataPoint> points;
  final DateTime today;
  final String timezone;
  final bool enabled;
  final bool isDemo;
}

class PeriodComparison {
  const PeriodComparison({
    required this.currentStart,
    required this.previousStart,
    required this.current,
    required this.previous,
  });
  final DateTime currentStart;
  final DateTime previousStart;
  final List<double?> current;
  final List<double?> previous;
  bool get hasValues => [...current, ...previous].any((value) => value != null);

  static PeriodComparison build({
    required List<CorrelationDataPoint> points,
    required DateTime today,
    required PeriodMetric metric,
    required PeriodComparisonMode mode,
    int days = 7,
  }) {
    final last = comparisonDay(today);
    final length = mode == PeriodComparisonMode.weekdays
        ? 7
        : const [7, 14, 30].contains(days)
        ? days
        : 7;
    final start = last.subtract(
      Duration(
        days: mode == PeriodComparisonMode.weekdays
            ? last.weekday - 1
            : length - 1,
      ),
    );
    final previousStart = start.subtract(Duration(days: length));
    final byDay = <DateTime, Map<String, double>>{};
    for (final point in points) {
      final day = comparisonDay(point.date);
      if (!day.isAfter(last)) {
        byDay.putIfAbsent(day, () => {}).addAll(point.values);
      }
    }
    final normalized = [
      for (final entry in byDay.entries)
        CorrelationDataPoint(date: entry.key, values: entry.value),
    ];
    double? read(DateTime day) {
      if (day.isAfter(last)) return null;
      // These are existing window summaries, not invented daily ratings.
      // Use the same seven-day formula and minimum samples at each plotted day.
      final raw = metric.rollingSummary
          ? skillsetReport(normalized, day, 7).points.last.values[metric.id]
          : byDay[day]?[metric.id];
      return raw != null &&
              raw.isFinite &&
              raw >= metric.min &&
              raw <= metric.max
          ? raw
          : null;
    }

    return PeriodComparison(
      currentStart: start,
      previousStart: previousStart,
      current: List.generate(length, (i) => read(start.add(Duration(days: i)))),
      previous: List.generate(
        length,
        (i) => read(previousStart.add(Duration(days: i))),
      ),
    );
  }
}
