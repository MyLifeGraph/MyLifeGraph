import 'correlation.dart';

enum PersonalPatternsStatus {
  disabled,
  collecting,
  emerging,
  stable;

  static PersonalPatternsStatus parse(Object? value) {
    return switch (value) {
      'disabled' => PersonalPatternsStatus.disabled,
      'collecting' => PersonalPatternsStatus.collecting,
      'emerging' => PersonalPatternsStatus.emerging,
      'stable' => PersonalPatternsStatus.stable,
      _ => throw const FormatException('Invalid personal patterns status.'),
    };
  }
}

class PersonalPatterns {
  const PersonalPatterns({
    required this.status,
    required this.summary,
    required this.timezone,
    required this.window,
    required this.sample,
    required this.baseline,
    required this.patterns,
    required this.plannerPreference,
    required this.limitations,
    required this.correlationPoints,
    required this.evidenceFingerprint,
  });

  factory PersonalPatterns.fromJson(Map<String, dynamic> json) {
    if (json['contract_version'] != 'personal-patterns-v1') {
      throw const FormatException('Unsupported personal patterns contract.');
    }
    final rawPatterns = _list(json, 'patterns');
    final rawLimitations = _list(json, 'limitations');
    final rawPoints = _list(json, 'correlation_points');
    final fingerprint = json['evidence_fingerprint'];
    if (fingerprint != null &&
        (fingerprint is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint))) {
      throw const FormatException('Invalid personal patterns fingerprint.');
    }
    return PersonalPatterns(
      status: PersonalPatternsStatus.parse(json['status']),
      summary: _string(json, 'summary'),
      timezone: _string(json, 'timezone'),
      window: PersonalPatternsWindow.fromJson(_map(json, 'window')),
      sample: PersonalPatternsSample.fromJson(_map(json, 'sample')),
      baseline: json['baseline'] == null
          ? null
          : PersonalPatternsBaseline.fromJson(_map(json, 'baseline')),
      patterns: rawPatterns
          .map((value) => PersonalPattern.fromJson(_typedMap(value)))
          .toList(growable: false),
      plannerPreference: LearnedPlannerPreference.fromJson(
        _map(json, 'planner_preference'),
      ),
      limitations: rawLimitations.map((value) {
        if (value is! String || value.isEmpty) {
          throw const FormatException(
            'Invalid personal pattern limitation.',
          );
        }
        return value;
      }).toList(growable: false),
      correlationPoints: rawPoints
          .map(
            (value) => PersonalPatternCorrelationPoint.fromJson(
              _typedMap(value),
            ),
          )
          .toList(growable: false),
      evidenceFingerprint: fingerprint as String?,
    );
  }

  final PersonalPatternsStatus status;
  final String summary;
  final String timezone;
  final PersonalPatternsWindow window;
  final PersonalPatternsSample sample;
  final PersonalPatternsBaseline? baseline;
  final List<PersonalPattern> patterns;
  final LearnedPlannerPreference plannerPreference;
  final List<String> limitations;
  final List<PersonalPatternCorrelationPoint> correlationPoints;
  final String? evidenceFingerprint;

  List<CorrelationDataPoint> correlationDataPoints({required int windowDays}) {
    final boundedDays = normalizeInsightsWindowDays(windowDays);
    final start = window.localEndsOn.subtract(Duration(days: boundedDays - 1));
    final byDate = <DateTime, _DailyCorrelationValues>{};
    for (final point in correlationPoints) {
      if (point.localDate.isBefore(start) ||
          point.localDate.isAfter(window.localEndsOn)) {
        continue;
      }
      byDate
          .putIfAbsent(point.localDate, _DailyCorrelationValues.new)
          .add(point);
    }
    final dates = byDate.keys.toList()..sort();
    return [
      for (final day in dates)
        CorrelationDataPoint(
          date: day,
          values: byDate[day]!.values,
        ),
    ];
  }
}

class PersonalPatternsWindow {
  const PersonalPatternsWindow({
    required this.startsAt,
    required this.endsAt,
    required this.localStartsOn,
    required this.localEndsOn,
  });

  factory PersonalPatternsWindow.fromJson(Map<String, dynamic> json) {
    if (json['rolling_days'] != 90) {
      throw const FormatException('Invalid personal patterns window.');
    }
    return PersonalPatternsWindow(
      startsAt: _instant(json, 'starts_at'),
      endsAt: _instant(json, 'ends_at'),
      localStartsOn: _localDate(json, 'local_starts_on'),
      localEndsOn: _localDate(json, 'local_ends_on'),
    );
  }

  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime localStartsOn;
  final DateTime localEndsOn;
}

class PersonalPatternsSample {
  const PersonalPatternsSample({
    required this.terminalSessions,
    required this.ratedSessions,
    required this.ratedLocalDays,
    required this.ratingCoverage,
    required this.firstRatedLocalDate,
    required this.lastRatedLocalDate,
  });

  factory PersonalPatternsSample.fromJson(Map<String, dynamic> json) {
    return PersonalPatternsSample(
      terminalSessions: _integer(json, 'terminal_sessions', minimum: 0),
      ratedSessions: _integer(json, 'rated_sessions', minimum: 0),
      ratedLocalDays: _integer(json, 'rated_local_days', minimum: 0),
      ratingCoverage: _number(json, 'rating_coverage', minimum: 0, maximum: 1),
      firstRatedLocalDate: _optionalLocalDate(
        json,
        'first_rated_local_date',
      ),
      lastRatedLocalDate: _optionalLocalDate(
        json,
        'last_rated_local_date',
      ),
    );
  }

  final int terminalSessions;
  final int ratedSessions;
  final int ratedLocalDays;
  final double ratingCoverage;
  final DateTime? firstRatedLocalDate;
  final DateTime? lastRatedLocalDate;
}

class PersonalPatternsBaseline {
  const PersonalPatternsBaseline({
    required this.medianFocusQuality,
    required this.medianUsefulProgress,
    required this.completionRate,
  });

  factory PersonalPatternsBaseline.fromJson(Map<String, dynamic> json) {
    return PersonalPatternsBaseline(
      medianFocusQuality: _number(
        json,
        'median_focus_quality',
        minimum: 1,
        maximum: 5,
      ),
      medianUsefulProgress: _number(
        json,
        'median_useful_progress',
        minimum: 1,
        maximum: 5,
      ),
      completionRate: _number(
        json,
        'completion_rate',
        minimum: 0,
        maximum: 1,
      ),
    );
  }

  final double medianFocusQuality;
  final double medianUsefulProgress;
  final double completionRate;
}

class PersonalPattern {
  const PersonalPattern({
    required this.kind,
    required this.maturity,
    required this.title,
    required this.summary,
    required this.evidence,
  });

  factory PersonalPattern.fromJson(Map<String, dynamic> json) {
    final kind = _string(json, 'kind');
    if (!const {
      'focus_timing',
      'sleep',
      'session_length_or_spacing',
    }.contains(kind)) {
      throw const FormatException('Invalid personal pattern kind.');
    }
    final maturity = _string(json, 'maturity');
    if (!const {'emerging', 'stable'}.contains(maturity)) {
      throw const FormatException('Invalid personal pattern maturity.');
    }
    return PersonalPattern(
      kind: kind,
      maturity: maturity,
      title: _string(json, 'title'),
      summary: _string(json, 'summary'),
      evidence: PersonalPatternEvidence.fromJson(_map(json, 'evidence')),
    );
  }

  final String kind;
  final String maturity;
  final String title;
  final String summary;
  final PersonalPatternEvidence evidence;
}

class PersonalPatternEvidence {
  const PersonalPatternEvidence({
    required this.preferredGroup,
    required this.comparisonGroup,
    required this.preferredCount,
    required this.comparisonCount,
    required this.details,
  });

  factory PersonalPatternEvidence.fromJson(Map<String, dynamic> json) {
    return PersonalPatternEvidence(
      preferredGroup: _string(json, 'preferred_group'),
      comparisonGroup: _string(json, 'comparison_group'),
      preferredCount: _integer(json, 'preferred_count', minimum: 1),
      comparisonCount: _integer(json, 'comparison_count', minimum: 1),
      details: _list(json, 'details').map((value) {
        if (value is! String || value.isEmpty) {
          throw const FormatException('Invalid pattern evidence detail.');
        }
        return value;
      }).toList(growable: false),
    );
  }

  final String preferredGroup;
  final String comparisonGroup;
  final int preferredCount;
  final int comparisonCount;
  final List<String> details;
}

class LearnedPlannerPreference {
  const LearnedPlannerPreference({
    required this.eligible,
    required this.reason,
    required this.window,
    required this.windowLabel,
    required this.evidenceCount,
  });

  factory LearnedPlannerPreference.fromJson(Map<String, dynamic> json) {
    return LearnedPlannerPreference(
      eligible: _boolean(json, 'eligible'),
      reason: _string(json, 'reason'),
      window: json['window'] as String?,
      windowLabel: json['window_label'] as String?,
      evidenceCount: _integer(json, 'evidence_count', minimum: 0),
    );
  }

  final bool eligible;
  final String reason;
  final String? window;
  final String? windowLabel;
  final int evidenceCount;
}

class PersonalPatternCorrelationPoint {
  const PersonalPatternCorrelationPoint({
    required this.localDate,
    required this.focusQuality,
    required this.usefulProgress,
    required this.plannedFocusMinutes,
    required this.actualFocusMinutes,
    required this.completed,
    required this.sleepHours,
    required this.sleepTargetDeviationMinutes,
    required this.sleepQuality,
    required this.morningEnergy,
  });

  factory PersonalPatternCorrelationPoint.fromJson(Map<String, dynamic> json) {
    return PersonalPatternCorrelationPoint(
      localDate: _localDate(json, 'local_date'),
      focusQuality: _integer(json, 'focus_quality', minimum: 1, maximum: 5),
      usefulProgress: _integer(json, 'useful_progress', minimum: 1, maximum: 5),
      plannedFocusMinutes: _integer(
        json,
        'planned_focus_minutes',
        minimum: 5,
        maximum: 240,
      ),
      actualFocusMinutes: _integer(json, 'actual_focus_minutes', minimum: 0),
      completed: _integer(json, 'completed', minimum: 0, maximum: 1),
      sleepHours: _optionalNumber(json, 'sleep_hours'),
      sleepTargetDeviationMinutes: _optionalInteger(
        json,
        'sleep_target_deviation_minutes',
      ),
      sleepQuality: _optionalInteger(json, 'sleep_quality'),
      morningEnergy: _optionalInteger(json, 'morning_energy'),
    );
  }

  final DateTime localDate;
  final int focusQuality;
  final int usefulProgress;
  final int plannedFocusMinutes;
  final int actualFocusMinutes;
  final int completed;
  final double? sleepHours;
  final int? sleepTargetDeviationMinutes;
  final int? sleepQuality;
  final int? morningEnergy;
}

class _DailyCorrelationValues {
  int count = 0;
  double focusMinutes = 0;
  double plannedFocusMinutes = 0;
  double focusQuality = 0;
  double usefulProgress = 0;
  double completed = 0;
  final List<double> sleepHours = [];
  final List<double> sleepTargetDeviation = [];
  final List<double> sleepQuality = [];
  final List<double> morningEnergy = [];

  void add(PersonalPatternCorrelationPoint point) {
    count += 1;
    focusMinutes += point.actualFocusMinutes;
    plannedFocusMinutes += point.plannedFocusMinutes;
    focusQuality += point.focusQuality;
    usefulProgress += point.usefulProgress;
    completed += point.completed;
    _addOptional(sleepHours, point.sleepHours);
    _addOptional(
      sleepTargetDeviation,
      point.sleepTargetDeviationMinutes?.toDouble(),
    );
    _addOptional(sleepQuality, point.sleepQuality?.toDouble());
    _addOptional(morningEnergy, point.morningEnergy?.toDouble());
  }

  Map<String, double> get values => {
        'focus_minutes': focusMinutes,
        'planned_focus_minutes': plannedFocusMinutes / count,
        'focus_quality': focusQuality / count,
        'useful_progress': usefulProgress / count,
        'focus_completion_rate': completed / count * 100,
        if (sleepHours.isNotEmpty) 'sleep_hours': _average(sleepHours),
        if (sleepTargetDeviation.isNotEmpty)
          'sleep_target_deviation_minutes': _average(sleepTargetDeviation),
        if (sleepQuality.isNotEmpty) 'sleep_quality': _average(sleepQuality),
        if (morningEnergy.isNotEmpty) 'energy_level': _average(morningEnergy),
      };
}

void _addOptional(List<double> values, double? value) {
  if (value != null) values.add(value);
}

double _average(List<double> values) =>
    values.reduce((left, right) => left + right) / values.length;

Map<String, dynamic> _map(Map<String, dynamic> json, String key) =>
    _typedMap(json[key]);

Map<String, dynamic> _typedMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected an object.');
  return Map<String, dynamic>.from(value);
}

List<dynamic> _list(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) throw FormatException('Expected list $key.');
  return value;
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected string $key.');
  }
  return value;
}

bool _boolean(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('Expected boolean $key.');
  return value;
}

int _integer(
  Map<String, dynamic> json,
  String key, {
  int? minimum,
  int? maximum,
}) {
  final value = json[key];
  if (value is! int ||
      minimum != null && value < minimum ||
      maximum != null && value > maximum) {
    throw FormatException('Expected integer $key.');
  }
  return value;
}

int? _optionalInteger(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int) throw FormatException('Expected optional integer $key.');
  return value;
}

double _number(
  Map<String, dynamic> json,
  String key, {
  double? minimum,
  double? maximum,
}) {
  final value = json[key];
  if (value is! num) throw FormatException('Expected number $key.');
  final numeric = value.toDouble();
  if (minimum != null && numeric < minimum ||
      maximum != null && numeric > maximum) {
    throw FormatException('Number $key is out of range.');
  }
  return numeric;
}

double? _optionalNumber(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! num) throw FormatException('Expected optional number $key.');
  return value.toDouble();
}

DateTime _instant(Map<String, dynamic> json, String key) {
  final value = _string(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      !parsed.isUtc && !value.contains(RegExp(r'[+-]\d\d:'))) {
    throw FormatException('Expected aware timestamp $key.');
  }
  return parsed;
}

DateTime _localDate(Map<String, dynamic> json, String key) {
  final value = _string(json, key);
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) throw FormatException('Expected local date $key.');
  final parsed = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  if (_dateKey(parsed) != value) {
    throw FormatException('Invalid local date $key.');
  }
  return parsed;
}

DateTime? _optionalLocalDate(Map<String, dynamic> json, String key) {
  if (json[key] == null) return null;
  return _localDate(json, key);
}

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
