import 'quick_check_in.dart';
import 'skillset_signals.dart';
import '../../../core/time/profile_timezone.dart';
import '../../../core/contracts/strict_contract.dart';

const dailyCaptureDraftVersion = 'daily-capture-draft-v1';

/// A reviewed-input proposal, never a persisted or complete check-in.
class CaptureDraftProposal {
  CaptureDraftProposal._({
    required this.ownerId,
    required this.entryDate,
    required this.timezone,
    required this.branch,
    required this.requestId,
    required Map<String, Object> fields,
    required Map<String, String> evidence,
  }) : fields = Map.unmodifiable(fields),
       evidence = Map.unmodifiable(evidence);

  final String ownerId;
  final String entryDate;
  final String timezone;
  final String branch;
  final String requestId;
  final Map<String, Object> fields;
  final Map<String, String> evidence;

  factory CaptureDraftProposal.fromJson(
    Map<String, dynamic> json, {
    required String ownerId,
  }) {
    const rootKeys = {
      'contract_version',
      'request_id',
      'owner_id',
      'entry_date',
      'timezone',
      'branch',
      'fields',
      'evidence',
    };
    if (json.length != rootKeys.length ||
        !json.keys.every(rootKeys.contains) ||
        json['contract_version'] != dailyCaptureDraftVersion ||
        json['owner_id'] != ownerId ||
        ownerId.isEmpty ||
        json['request_id'] is! String ||
        !isStrictUuid(json['request_id'] as String) ||
        json['timezone'] is! String ||
        (json['timezone'] as String).isEmpty ||
        json['branch'] != 'morning' && json['branch'] != 'evening' ||
        json['entry_date'] is! String ||
        json['fields'] is! Map<String, dynamic> ||
        json['evidence'] is! Map<String, dynamic>) {
      throw const FormatException('Check-in draft is invalid.');
    }
    final date = json['entry_date'] as String;
    final parsed = DateTime.tryParse(date);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        dailyCaptureEntryDate(parsed) != date) {
      throw const FormatException('Check-in draft date is invalid.');
    }
    final morning = json['branch'] == 'morning';
    final allowed = morning ? _morningFields : _eveningFields;
    final rawFields = json['fields'] as Map<String, dynamic>;
    final rawEvidence = json['evidence'] as Map<String, dynamic>;
    if (!rawFields.keys.every(allowed.contains) ||
        !rawEvidence.keys.every(allowed.contains)) {
      throw const FormatException('Check-in draft fields are invalid.');
    }
    final fields = <String, Object>{};
    final evidence = <String, String>{};
    final populatedKeys = rawFields.entries
        .where((entry) => entry.value != null)
        .map((entry) => entry.key)
        .toSet();
    if (rawEvidence.length != populatedKeys.length ||
        !rawEvidence.keys.every(populatedKeys.contains)) {
      throw const FormatException(
        'Check-in draft evidence does not match its fields.',
      );
    }
    for (final entry in rawFields.entries) {
      final value = entry.value;
      if (value == null) continue;
      _validateField(entry.key, value);
      final quote = rawEvidence[entry.key];
      if (quote is! String || quote.trim().isEmpty || quote.length > 1000) {
        throw const FormatException('Check-in draft evidence is missing.');
      }
      fields[entry.key] = value as Object;
      evidence[entry.key] = quote;
    }
    return CaptureDraftProposal._(
      ownerId: ownerId,
      entryDate: date,
      timezone: json['timezone'] as String,
      branch: json['branch'] as String,
      requestId: json['request_id'] as String,
      fields: fields,
      evidence: evidence,
    );
  }

  bool matches({
    required String? ownerId,
    required String entryDate,
    required String? timezone,
    required String branch,
  }) =>
      this.ownerId == ownerId &&
      this.entryDate == entryDate &&
      this.timezone == timezone &&
      this.branch == branch;

  MorningCalibrationDraft applyToMorning(
    MorningCalibrationDraft draft, {
    required bool allowSkillset,
  }) {
    if (branch != 'morning' || draft.entryDate != entryDate) {
      throw const FormatException('Check-in draft does not match.');
    }
    var next = draft.copyWith(
      sleepQuality: fields['sleep_quality'] ?? draft.sleepQuality,
      energy: fields['current_energy'] ?? draft.energy,
      sleepTargetMinutes:
          fields['sleep_target_minutes'] ?? draft.sleepTargetMinutes,
    );
    if (fields.containsKey('sleep_start') || fields.containsKey('wake_time')) {
      final start =
          fields['sleep_start'] as String? ??
          (draft.estimatedSleepStartedAt == null
              ? null
              : clockForInstant(draft.estimatedSleepStartedAt!));
      final wake =
          fields['wake_time'] as String? ??
          (draft.wokeAt == null ? null : clockForInstant(draft.wokeAt!));
      try {
        if (start != null && wake != null) {
          final interval = sleepInterval(start: start, wake: wake);
          next = next.withSleepInterval(
            estimatedSleepStartedAt: interval.estimatedSleepStartedAt,
            wokeAt: interval.wokeAt,
          );
        } else {
          // A single spoken clock must not invent the missing boundary.
          final value = clockOnEntryDate(start ?? wake!);
          next = next.copyWith(
            estimatedSleepStartedAt: start == null ? null : value,
            wokeAt: wake == null ? null : value,
            estimatedSleepMinutes: null,
            sleepHours: null,
          );
        }
      } on ProfileTimezoneException {
        // Ambiguous/nonexistent clock times need explicit correction, not an offset guess.
        next = next.copyWith(
          estimatedSleepStartedAt: fields.containsKey('sleep_start')
              ? null
              : draft.estimatedSleepStartedAt,
          wokeAt: fields.containsKey('wake_time') ? null : draft.wokeAt,
          estimatedSleepMinutes: null,
          sleepHours: null,
        );
      }
    }
    if (allowSkillset && fields.containsKey('motivation')) {
      next = next.copyWith(
        skillset: (draft.skillset ?? const SkillsetSignals({})).withValue(
          'motivation',
          fields['motivation'] as int,
        ),
      );
    }
    return next;
  }

  EveningShutdownDraft applyToEvening(
    EveningShutdownDraft draft, {
    required bool allowSkillset,
  }) {
    if (branch != 'evening' || draft.entryDate != entryDate) {
      throw const FormatException('Check-in draft does not match.');
    }
    final stress = fields['stress_intensity'] as int? ?? draft.stress;
    final clearStressContext =
        stress != null &&
        stress < 5 &&
        (fields.containsKey('stress_intensity') ||
            fields.containsKey('stress_source') ||
            fields.containsKey('stress_controllability'));
    var next = draft.copyWith(
      mood: fields['mood'] ?? draft.mood,
      energy: fields['energy'] ?? draft.energy,
      stress: stress,
      stressSource: clearStressContext
          ? null
          : fields['stress_source'] == null
          ? draft.stressSource
          : StressSource.fromCode(fields['stress_source']),
      stressControllability: clearStressContext
          ? null
          : fields['stress_controllability'] == null
          ? draft.stressControllability
          : StressControllability.fromCode(fields['stress_controllability']),
      plannedSleepTime: fields['planned_sleep_time'] ?? draft.plannedSleepTime,
      sleepTargetMinutes:
          fields['sleep_target_minutes'] ?? draft.sleepTargetMinutes,
      reflectionNote:
          fields['reflection_note'] as String? ?? draft.reflectionNote,
      specificBlocker:
          fields['specific_blocker'] as String? ?? draft.specificBlocker,
    );
    if (allowSkillset) {
      var skillset = draft.skillset ?? const SkillsetSignals({});
      for (final id in ['sport', 'social']) {
        if (fields.containsKey(id)) {
          skillset = skillset.withValue(id, fields[id] as int);
        }
      }
      if (fields.containsKey('sport') || fields.containsKey('social')) {
        next = next.copyWith(skillset: skillset);
      }
    }
    return next;
  }

  String clockForInstant(DateTime instant) {
    final local = profileDateTimeAt(instant: instant, timezoneName: timezone);
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  DateTime clockOnEntryDate(String clock) =>
      _resolveClock(DateTime.parse(entryDate), clock);

  ({DateTime estimatedSleepStartedAt, DateTime wokeAt}) sleepInterval({
    required String start,
    required String wake,
  }) {
    final date = DateTime.parse(entryDate);
    final startDate = start.compareTo(wake) >= 0
        ? DateTime(date.year, date.month, date.day - 1)
        : date;
    return (
      estimatedSleepStartedAt: _resolveClock(startDate, start),
      wokeAt: _resolveClock(date, wake),
    );
  }

  DateTime _resolveClock(DateTime date, String clock) {
    _validateField('wake_time', clock);
    final parts = clock.split(':');
    return profileDateTimeFromComponents(
      year: date.year,
      month: date.month,
      day: date.day,
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
      timezoneName: timezone,
    );
  }
}

const _morningFields = {
  'sleep_start',
  'wake_time',
  'sleep_target_minutes',
  'sleep_quality',
  'current_energy',
  'motivation',
};
const _eveningFields = {
  'mood',
  'energy',
  'stress_intensity',
  'planned_sleep_time',
  'sleep_target_minutes',
  'stress_source',
  'stress_controllability',
  'reflection_note',
  'specific_blocker',
  'sport',
  'social',
};

void _validateField(String key, Object value) {
  var valid = false;
  if ({'sleep_start', 'wake_time', 'planned_sleep_time'}.contains(key)) {
    valid =
        value is String &&
        RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value);
  } else if (key == 'sleep_target_minutes') {
    valid = value is int && value >= 300 && value <= 720 && value % 15 == 0;
  } else if ({'motivation', 'sport', 'social'}.contains(key)) {
    valid = value is int && value >= 0 && value <= 2;
  } else if (key == 'stress_source') {
    valid = StressSource.values.any((item) => item.code == value);
  } else if (key == 'stress_controllability') {
    valid = StressControllability.values.any((item) => item.code == value);
  } else if (key == 'reflection_note' || key == 'specific_blocker') {
    valid =
        value is String &&
        value.trim().isNotEmpty &&
        value.length <=
            (key == 'reflection_note'
                ? EveningShutdownDraft.maxReflectionLength
                : EveningShutdownDraft.maxSpecificBlockerLength);
  } else {
    valid = value is int && value >= 1 && value <= 10;
  }
  if (!valid) throw const FormatException('Check-in draft value is invalid.');
}
