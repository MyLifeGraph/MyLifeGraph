class PlanningTimingPreference {
  const PlanningTimingPreference({
    required this.source,
    required this.window,
    required this.evidenceCount,
    required this.evidenceStartsOn,
    required this.evidenceEndsOn,
    required this.evidenceFingerprint,
    required this.fellBackToSetup,
    required this.warning,
  });

  factory PlanningTimingPreference.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Planning timing must be an object.');
    }
    final json = Map<String, dynamic>.from(value);
    const requiredKeys = {
      'source',
      'evidence_count',
      'fell_back_to_setup',
    };
    const optionalKeys = {
      'window',
      'evidence_starts_on',
      'evidence_ends_on',
      'evidence_fingerprint',
      'warning',
    };
    final actualKeys = json.keys.toSet();
    if (actualKeys.difference({...requiredKeys, ...optionalKeys}).isNotEmpty ||
        requiredKeys.difference(actualKeys).isNotEmpty) {
      throw const FormatException('Planning timing keys are invalid.');
    }
    final source = json['source'];
    final window = json['window'];
    final count = json['evidence_count'];
    final startsOn = json['evidence_starts_on'];
    final endsOn = json['evidence_ends_on'];
    final fingerprint = json['evidence_fingerprint'];
    final fellBack = json['fell_back_to_setup'];
    final warning = json['warning'];
    if (source is! String ||
        !const {'setup', 'learned_personal_pattern'}.contains(source) ||
        window != null &&
            (window is! String ||
                !const {'05-09', '09-13', '13-18', '18-23'}.contains(window)) ||
        count is! int ||
        count < 0 ||
        count > 10000 ||
        startsOn != null && !_isDate(startsOn) ||
        endsOn != null && !_isDate(endsOn) ||
        fingerprint != null &&
            (fingerprint is! String ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint)) ||
        fellBack is! bool ||
        warning != null && warning != 'personal_patterns_unavailable') {
      throw const FormatException('Planning timing values are invalid.');
    }
    final learned = source == 'learned_personal_pattern';
    if (learned
        ? window == null ||
            count < 1 ||
            startsOn == null ||
            endsOn == null ||
            fingerprint == null ||
            DateTime.parse(startsOn as String).isAfter(
              DateTime.parse(endsOn as String),
            ) ||
            warning != null
        : window != null ||
            count != 0 ||
            startsOn != null ||
            endsOn != null ||
            fingerprint != null ||
            warning != null && !fellBack) {
      throw const FormatException('Planning timing shape is inconsistent.');
    }
    return PlanningTimingPreference(
      source: source,
      window: window as String?,
      evidenceCount: count,
      evidenceStartsOn: startsOn as String?,
      evidenceEndsOn: endsOn as String?,
      evidenceFingerprint: fingerprint as String?,
      fellBackToSetup: fellBack,
      warning: warning as String?,
    );
  }

  final String source;
  final String? window;
  final int evidenceCount;
  final String? evidenceStartsOn;
  final String? evidenceEndsOn;
  final String? evidenceFingerprint;
  final bool fellBackToSetup;
  final String? warning;

  bool get usedLearnedPattern => source == 'learned_personal_pattern';

  static bool _isDate(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return false;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return false;
    return '${parsed.year.toString().padLeft(4, '0')}-'
            '${parsed.month.toString().padLeft(2, '0')}-'
            '${parsed.day.toString().padLeft(2, '0')}' ==
        value;
  }
}
