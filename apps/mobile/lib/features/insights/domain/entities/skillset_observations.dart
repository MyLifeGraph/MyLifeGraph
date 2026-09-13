import 'correlation.dart';

const skillsetViewVersion = 'skillset-observations-v1';

List<CorrelationDataPoint> parseSkillsetPoints(Map<String, dynamic> json) {
  if (json['skillset_version'] == null) return const [];
  if (json['skillset_version'] != skillsetViewVersion ||
      json['skillset_points'] is! List) {
    throw const FormatException('Unsupported Skillset observations.');
  }
  final result = <CorrelationDataPoint>[];
  final seenDays = <DateTime>{};
  if ((json['skillset_points'] as List).length > 91) {
    throw const FormatException('Too many Skillset observations.');
  }
  for (final raw in json['skillset_points'] as List) {
    if (raw is! Map || raw['local_date'] is! String || raw['values'] is! Map) {
      throw const FormatException('Invalid Skillset observation.');
    }
    final dateText = raw['local_date'] as String;
    final day = DateTime.tryParse(dateText);
    if (day == null ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateText) ||
        !day.toIso8601String().startsWith(dateText) ||
        !seenDays.add(day)) {
      throw const FormatException('Invalid Skillset date.');
    }
    final values = <String, double>{};
    for (final entry in (raw['values'] as Map).entries) {
      if (entry.key is! String ||
          entry.value is! num ||
          !(entry.value as num).isFinite) {
        throw const FormatException('Invalid Skillset value.');
      }
      values[entry.key as String] = (entry.value as num).toDouble();
    }
    result.add(CorrelationDataPoint(date: day, values: values));
  }
  return result;
}

CorrelationReport skillsetReport(
  List<CorrelationDataPoint> points,
  DateTime lastDay,
  int windowDays,
) {
  final days = normalizeInsightsWindowDays(windowDays);
  final first = lastDay.subtract(Duration(days: days - 1));
  final selected = points
      .where((p) => !p.date.isBefore(first) && !p.date.isAfter(lastDay))
      .toList();
  double total(String key) =>
      selected.fold(0, (sum, p) => sum + (p.values[key] ?? 0));
  final focusCount = total('focus_count');
  final studyCount = total('learning_count');
  final sportDays = selected
      .where((p) => p.values.containsKey('sport_activity'))
      .toList();
  final components = <double>[
    if (focusCount >= 3) total('focus_completed') / focusCount * 100,
    if (sportDays.length >= 3)
      sportDays.where((p) => p.values['sport_activity']! > 0).length /
          sportDays.length *
          100,
  ];
  // Window totals belong to one synthetic summary point, never each observed day.
  return CorrelationReport(
    windowDays: days,
    metrics: const [],
    results: const [],
    points: [
      ...selected,
      CorrelationDataPoint(
        date: lastDay,
        values: {
          if (studyCount >= 3)
            'learning_completion_rate':
                total('learning_completed') / studyCount * 100,
          if (components.isNotEmpty)
            'regularity':
                components.reduce((a, b) => a + b) / components.length,
        },
      ),
    ],
  );
}
