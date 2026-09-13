const skillsetCaptureVersion = 'skillset-capture-v1';

/// Optional additive branch data. Null means an unanswered/cleared question.
class SkillsetSignals {
  const SkillsetSignals(this.values);
  final Map<String, int?> values;

  factory SkillsetSignals.fromJson(Object? raw, {required bool morning}) {
    if (raw is! Map || raw['version'] != skillsetCaptureVersion) {
      throw const FormatException('Unsupported optional check-in signals.');
    }
    final allowed = morning ? const {'motivation'} : const {'sport', 'social'};
    final values = <String, int?>{};
    for (final key in raw.keys) {
      if (key == 'version') continue;
      final value = raw[key];
      if (!allowed.contains(key) ||
          value != null && (value is! int || value < 0 || value > 2)) {
        throw const FormatException('Invalid optional check-in signal.');
      }
      values[key as String] = value as int?;
    }
    return SkillsetSignals(Map.unmodifiable(values));
  }

  SkillsetSignals withValue(String key, int? value) =>
      SkillsetSignals({...values, key: value});

  Map<String, dynamic> toJson({required bool morning}) {
    final result = <String, dynamic>{
      'version': skillsetCaptureVersion,
      ...values,
    };
    SkillsetSignals.fromJson(result, morning: morning);
    return result;
  }
}
