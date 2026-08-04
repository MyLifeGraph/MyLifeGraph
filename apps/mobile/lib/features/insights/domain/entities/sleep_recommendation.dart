const sleepRecommendationContractVersion = 'sleep-recommendation-v1';

enum SleepRecommendationStatus { disabled, collecting, unstable, ready }

class SleepRecommendation {
  const SleepRecommendation({
    required this.status,
    required this.reason,
    required this.generatedAt,
    required this.timezone,
    required this.validNights,
    required this.eligibleFocusDays,
    required this.ratedSessions,
    required this.progress,
    required this.summary,
    required this.limitations,
    required this.recommendation,
  });

  factory SleepRecommendation.fromJson(Map<String, dynamic> json) {
    if (json['contract_version'] != sleepRecommendationContractVersion) {
      throw const FormatException(
        'Unsupported sleep recommendation contract.',
      );
    }
    final status = _status(json['status']);
    final reason = _requiredString(json, 'reason');
    final generatedAt = _requiredAwareDateTime(json, 'generated_at');
    final timezone = _requiredString(json, 'timezone');
    final window = _requiredMap(json, 'window');
    if (window['rolling_days'] != 90 ||
        _requiredAwareDateTime(window, 'starts_at')
            .isAfter(_requiredAwareDateTime(window, 'ends_at'))) {
      throw const FormatException('Sleep recommendation window is invalid.');
    }
    final sample = _requiredMap(json, 'sample');
    final validNights = _wholeNumber(sample, 'valid_nights', minimum: 0);
    final eligible = _wholeNumber(
      sample,
      'eligible_focus_days',
      minimum: 0,
    );
    final rated = _wholeNumber(sample, 'rated_sessions', minimum: 0);
    if (sample['required_eligible_days'] != 30 ||
        sample['progress'] != '${eligible.clamp(0, 30)}/30' ||
        eligible > validNights) {
      throw const FormatException(
        'Sleep recommendation sample is inconsistent.',
      );
    }
    final recommendationJson = json['recommendation'];
    final ready = recommendationJson == null
        ? null
        : SleepRecommendationReady.fromJson(
            _stringMap(recommendationJson, 'recommendation'),
          );
    if ((status == SleepRecommendationStatus.ready) != (ready != null) ||
        (status == SleepRecommendationStatus.ready) != (reason == 'ready')) {
      throw const FormatException(
        'Sleep recommendation state is inconsistent.',
      );
    }
    final limitations = json['limitations'];
    if (limitations is! List ||
        limitations.length > 8 ||
        limitations.any((value) => value is! String)) {
      throw const FormatException(
        'Sleep recommendation limitations are invalid.',
      );
    }
    return SleepRecommendation(
      status: status,
      reason: reason,
      generatedAt: generatedAt,
      timezone: timezone,
      validNights: validNights,
      eligibleFocusDays: eligible,
      ratedSessions: rated,
      progress: '${sample['progress']}',
      summary: _requiredString(json, 'summary'),
      limitations: limitations.cast<String>(),
      recommendation: ready,
    );
  }

  final SleepRecommendationStatus status;
  final String reason;
  final DateTime generatedAt;
  final String timezone;
  final int validNights;
  final int eligibleFocusDays;
  final int ratedSessions;
  final String progress;
  final String summary;
  final List<String> limitations;
  final SleepRecommendationReady? recommendation;
}

class SleepRecommendationReady {
  const SleepRecommendationReady({
    required this.bedtime,
    required this.wakeTime,
    required this.duration,
    required this.wakeDayOffset,
    required this.warning,
    required this.candidateDays,
    required this.comparisonDays,
    required this.evidenceFingerprint,
  });

  factory SleepRecommendationReady.fromJson(Map<String, dynamic> json) {
    final wakeDayOffset = _wholeNumber(
      json,
      'wake_day_offset',
      minimum: 0,
      maximum: 1,
    );
    final warning = json['warning'];
    if (warning != null && warning != 'below_confirmed_sleep_target') {
      throw const FormatException('Sleep recommendation warning is invalid.');
    }
    final evidence = _requiredMap(json, 'evidence');
    final fingerprint = _requiredString(json, 'evidence_fingerprint');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint) ||
        evidence['consistent_in_both_halves'] != true) {
      throw const FormatException('Sleep recommendation evidence is invalid.');
    }
    return SleepRecommendationReady(
      bedtime: SleepClockWindow.fromJson(_requiredMap(json, 'bedtime')),
      wakeTime: SleepClockWindow.fromJson(_requiredMap(json, 'wake_time')),
      duration: SleepDurationWindow.fromJson(_requiredMap(json, 'duration')),
      wakeDayOffset: wakeDayOffset,
      warning: warning as String?,
      candidateDays: _wholeNumber(
        evidence,
        'candidate_days',
        minimum: 10,
      ),
      comparisonDays: _wholeNumber(
        evidence,
        'comparison_days',
        minimum: 10,
      ),
      evidenceFingerprint: fingerprint,
    );
  }

  final SleepClockWindow bedtime;
  final SleepClockWindow wakeTime;
  final SleepDurationWindow duration;
  final int wakeDayOffset;
  final String? warning;
  final int candidateDays;
  final int comparisonDays;
  final String evidenceFingerprint;
}

class SleepClockWindow {
  const SleepClockWindow({
    required this.startLocalTime,
    required this.endLocalTime,
    required this.endDayOffset,
    required this.widthMinutes,
  });

  factory SleepClockWindow.fromJson(Map<String, dynamic> json) {
    final start = _requiredString(json, 'start_local_time');
    final end = _requiredString(json, 'end_local_time');
    final clock = RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$');
    if (!clock.hasMatch(start) || !clock.hasMatch(end)) {
      throw const FormatException('Sleep clock window is invalid.');
    }
    return SleepClockWindow(
      startLocalTime: start,
      endLocalTime: end,
      endDayOffset: _wholeNumber(
        json,
        'end_day_offset',
        minimum: 0,
        maximum: 1,
      ),
      widthMinutes: _wholeNumber(
        json,
        'width_minutes',
        minimum: 0,
        maximum: 60,
      ),
    );
  }

  final String startLocalTime;
  final String endLocalTime;
  final int endDayOffset;
  final int widthMinutes;

  String get label => '$startLocalTime–$endLocalTime'
      '${endDayOffset == 1 ? ' (+1 day)' : ''}';
}

class SleepDurationWindow {
  const SleepDurationWindow({
    required this.minimumMinutes,
    required this.maximumMinutes,
  });

  factory SleepDurationWindow.fromJson(Map<String, dynamic> json) {
    final minimum = _wholeNumber(
      json,
      'minimum_minutes',
      minimum: 1,
      maximum: 960,
    );
    final maximum = _wholeNumber(
      json,
      'maximum_minutes',
      minimum: minimum,
      maximum: 960,
    );
    return SleepDurationWindow(
      minimumMinutes: minimum,
      maximumMinutes: maximum,
    );
  }

  final int minimumMinutes;
  final int maximumMinutes;

  String get label => minimumMinutes == maximumMinutes
      ? _durationLabel(minimumMinutes)
      : '${_durationLabel(minimumMinutes)}–${_durationLabel(maximumMinutes)}';
}

SleepRecommendationStatus _status(Object? value) => switch (value) {
      'disabled' => SleepRecommendationStatus.disabled,
      'collecting' => SleepRecommendationStatus.collecting,
      'unstable' => SleepRecommendationStatus.unstable,
      'ready' => SleepRecommendationStatus.ready,
      _ => throw const FormatException(
          'Sleep recommendation status is invalid.',
        ),
    };

String _durationLabel(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '$remainder min';
  if (remainder == 0) return '$hours h';
  return '$hours h $remainder min';
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String field) =>
    _stringMap(json[field], field);

Map<String, dynamic> _stringMap(Object? value, String field) {
  if (value is! Map) {
    throw FormatException('$field must be an object.');
  }
  return Map<String, dynamic>.from(value);
}

String _requiredString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value;
}

DateTime _requiredAwareDateTime(Map<String, dynamic> json, String field) {
  final raw = json[field];
  final value = raw is String ? DateTime.tryParse(raw) : null;
  if (value == null ||
      !raw!.contains(RegExp(r'(?:Z|[+-][0-9]{2}:[0-9]{2})$'))) {
    throw FormatException('$field must be timezone-aware.');
  }
  return value;
}

int _wholeNumber(
  Map<String, dynamic> json,
  String field, {
  required int minimum,
  int? maximum,
}) {
  final value = json[field];
  if (value is! int ||
      value < minimum ||
      (maximum != null && value > maximum)) {
    throw FormatException('$field must be a bounded whole number.');
  }
  return value;
}
