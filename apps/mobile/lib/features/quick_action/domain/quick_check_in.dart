enum QuickCheckInSaveTarget { guest, supabase }

enum StressSource {
  workload('workload'),
  avoidablePressure('avoidable_pressure'),
  privateEmotional('private_emotional'),
  physicalRecovery('physical_recovery'),
  externalEnvironment('external_environment');

  const StressSource(this.code);

  final String code;

  static StressSource fromCode(Object? value) => _enumFromCode(
        values,
        value,
        (item) => item.code,
        'stress source',
      );
}

enum StressControllability {
  hardlyControllable('hardly_controllable'),
  partlyControllable('partly_controllable'),
  mostlyControllable('mostly_controllable');

  const StressControllability(this.code);

  final String code;

  static StressControllability fromCode(Object? value) => _enumFromCode(
        values,
        value,
        (item) => item.code,
        'stress controllability',
      );
}

enum FocusBand {
  none('none'),
  underThirtyMinutes('under_30_minutes'),
  thirtyToSixtyMinutes('30_to_60_minutes'),
  oneToTwoHours('1_to_2_hours'),
  overTwoHours('over_2_hours');

  const FocusBand(this.code);

  final String code;

  static FocusBand fromCode(Object? value) => _enumFromCode(
        values,
        value,
        (item) => item.code,
        'focus band',
      );
}

enum MainFriction {
  unclearPriorities('unclear_priorities'),
  tooMuchToDo('too_much_to_do'),
  interruptions('interruptions'),
  hardToStart('hard_to_start'),
  lowEnergy('low_energy'),
  emotionalLoad('emotional_load'),
  physicalRecovery('physical_recovery'),
  externalConstraints('external_constraints');

  const MainFriction(this.code);

  final String code;

  static MainFriction fromCode(Object? value) => _enumFromCode(
        values,
        value,
        (item) => item.code,
        'main friction',
      );
}

enum DayShape {
  normal('normal'),
  constrained('constrained'),
  flexible('flexible');

  const DayShape(this.code);

  final String code;

  static DayShape fromCode(Object? value) => _enumFromCode(
        values,
        value,
        (item) => item.code,
        'day shape',
      );
}

enum StressIntensityLabel {
  low('low'),
  medium('medium'),
  high('high');

  const StressIntensityLabel(this.code);

  final String code;
}

StressIntensityLabel stressIntensityLabelFor(int rating) {
  _validateRating('stress', rating);
  if (rating >= 8) {
    return StressIntensityLabel.high;
  }
  if (rating >= 5) {
    return StressIntensityLabel.medium;
  }
  return StressIntensityLabel.low;
}

String quickCheckInMoodCode(int rating) {
  if (rating >= 9) {
    return 'great';
  }
  if (rating >= 7) {
    return 'good';
  }
  if (rating >= 5) {
    return 'neutral';
  }
  if (rating >= 3) {
    return 'low';
  }
  return 'very_low';
}

String quickCheckInMoodLabel(int rating) {
  return switch (quickCheckInMoodCode(rating)) {
    'great' => 'Great',
    'good' => 'Good',
    'neutral' => 'Neutral',
    'low' => 'Low',
    _ => 'Heavy',
  };
}

String dailyCaptureEntryDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

class EveningShutdownDraft {
  const EveningShutdownDraft({
    required this.captureId,
    required this.entryDate,
    required this.capturedAt,
    required this.mood,
    required this.energy,
    required this.stress,
    required this.stressSource,
    required this.stressControllability,
    required this.focusBand,
    required this.mainFriction,
    required this.tomorrowPriority,
    this.reflectionNote = '',
    this.specificBlocker = '',
    this.makeTomorrowGentler = false,
  });

  factory EveningShutdownDraft.empty(
    DateTime capturedAt, {
    String? entryDate,
  }) {
    final date = entryDate ?? dailyCaptureEntryDate(capturedAt);
    return EveningShutdownDraft(
      captureId: 'evening-$date-${capturedAt.toUtc().microsecondsSinceEpoch}',
      entryDate: date,
      capturedAt: capturedAt,
      mood: null,
      energy: null,
      stress: null,
      stressSource: null,
      stressControllability: null,
      focusBand: null,
      mainFriction: null,
      tomorrowPriority: '',
    );
  }

  factory EveningShutdownDraft.fromJson(
    Map<String, dynamic> json, {
    required String entryDate,
  }) {
    if (json['capture_kind'] != 'evening' || json['entry_date'] != entryDate) {
      throw const FormatException('Evening capture identity is invalid.');
    }
    final draft = EveningShutdownDraft(
      captureId: _requiredString(json, 'capture_id'),
      entryDate: entryDate,
      capturedAt: _requiredDateTime(json, 'captured_at'),
      mood: (json['mood'] as num?)?.toInt(),
      energy: (json['energy'] as num?)?.toInt(),
      stress: (json['stress_intensity'] as num?)?.toInt(),
      stressSource: StressSource.fromCode(json['stress_source']),
      stressControllability:
          StressControllability.fromCode(json['stress_controllability']),
      focusBand: FocusBand.fromCode(json['focus_band']),
      mainFriction: MainFriction.fromCode(json['main_friction']),
      tomorrowPriority: _requiredString(json, 'tomorrow_priority'),
      reflectionNote: _optionalString(json['reflection_note']) ?? '',
      specificBlocker: _optionalString(json['specific_blocker']) ?? '',
      makeTomorrowGentler: json['gentle_tomorrow'] == true,
    );
    draft.validate();
    final storedLabel = _optionalString(json['stress_intensity_label']);
    if (storedLabel != null && storedLabel != draft.stressIntensityLabel.code) {
      throw const FormatException('Stress intensity label does not match.');
    }
    return draft.normalized();
  }

  static const maxCaptureIdLength = 160;
  static const maxTomorrowPriorityLength = 160;
  static const maxReflectionLength = 1000;
  static const maxSpecificBlockerLength = 280;

  final String captureId;
  final String entryDate;
  final DateTime capturedAt;
  final int? mood;
  final int? energy;
  final int? stress;
  final StressSource? stressSource;
  final StressControllability? stressControllability;
  final FocusBand? focusBand;
  final MainFriction? mainFriction;
  final String tomorrowPriority;
  final String reflectionNote;
  final String specificBlocker;
  final bool makeTomorrowGentler;

  bool get isComplete =>
      mood != null &&
      energy != null &&
      stress != null &&
      stressSource != null &&
      stressControllability != null &&
      focusBand != null &&
      mainFriction != null &&
      tomorrowPriority.trim().isNotEmpty;

  StressIntensityLabel get stressIntensityLabel =>
      stressIntensityLabelFor(stress!);

  EveningShutdownDraft copyWith({
    String? captureId,
    String? entryDate,
    DateTime? capturedAt,
    Object? mood = _unset,
    Object? energy = _unset,
    Object? stress = _unset,
    Object? stressSource = _unset,
    Object? stressControllability = _unset,
    Object? focusBand = _unset,
    Object? mainFriction = _unset,
    String? tomorrowPriority,
    String? reflectionNote,
    String? specificBlocker,
    bool? makeTomorrowGentler,
  }) {
    return EveningShutdownDraft(
      captureId: captureId ?? this.captureId,
      entryDate: entryDate ?? this.entryDate,
      capturedAt: capturedAt ?? this.capturedAt,
      mood: identical(mood, _unset) ? this.mood : mood as int?,
      energy: identical(energy, _unset) ? this.energy : energy as int?,
      stress: identical(stress, _unset) ? this.stress : stress as int?,
      stressSource: identical(stressSource, _unset)
          ? this.stressSource
          : stressSource as StressSource?,
      stressControllability: identical(stressControllability, _unset)
          ? this.stressControllability
          : stressControllability as StressControllability?,
      focusBand: identical(focusBand, _unset)
          ? this.focusBand
          : focusBand as FocusBand?,
      mainFriction: identical(mainFriction, _unset)
          ? this.mainFriction
          : mainFriction as MainFriction?,
      tomorrowPriority: tomorrowPriority ?? this.tomorrowPriority,
      reflectionNote: reflectionNote ?? this.reflectionNote,
      specificBlocker: specificBlocker ?? this.specificBlocker,
      makeTomorrowGentler: makeTomorrowGentler ?? this.makeTomorrowGentler,
    );
  }

  EveningShutdownDraft normalized() => copyWith(
        captureId: captureId.trim(),
        tomorrowPriority: tomorrowPriority.trim(),
        reflectionNote: reflectionNote.trim(),
        specificBlocker: specificBlocker.trim(),
      );

  void validate() {
    _validateCaptureIdentity(
      captureId: captureId,
      entryDate: entryDate,
      maxCaptureIdLength: maxCaptureIdLength,
    );
    if (!isComplete) {
      throw const FormatException(
        'All required Evening Shutdown answers must be selected.',
      );
    }
    _validateRating('mood', mood!);
    _validateRating('energy', energy!);
    _validateRating('stress', stress!);
    _validateBoundedString(
      'tomorrow priority',
      tomorrowPriority,
      maxTomorrowPriorityLength,
      required: true,
    );
    _validateBoundedString(
      'reflection note',
      reflectionNote,
      maxReflectionLength,
    );
    _validateBoundedString(
      'specific blocker',
      specificBlocker,
      maxSpecificBlockerLength,
    );
  }

  Map<String, dynamic> toMetadataJson() {
    validate();
    final value = normalized();
    return {
      'capture_kind': 'evening',
      'entry_date': value.entryDate,
      'capture_id': value.captureId,
      'captured_at': value.capturedAt.toUtc().toIso8601String(),
      'mood': value.mood,
      'energy': value.energy,
      'stress_intensity': value.stress,
      'stress_intensity_label': value.stressIntensityLabel.code,
      'stress_source': value.stressSource!.code,
      'stress_controllability': value.stressControllability!.code,
      'focus_band': value.focusBand!.code,
      'main_friction': value.mainFriction!.code,
      'tomorrow_priority': value.tomorrowPriority,
      if (value.reflectionNote.isNotEmpty)
        'reflection_note': value.reflectionNote,
      if (value.specificBlocker.isNotEmpty)
        'specific_blocker': value.specificBlocker,
      if (value.makeTomorrowGentler) 'gentle_tomorrow': true,
    };
  }
}

class MorningCalibrationDraft {
  const MorningCalibrationDraft({
    required this.captureId,
    required this.entryDate,
    required this.capturedAt,
    required this.sleepHours,
    required this.energy,
    required this.dayShape,
  });

  factory MorningCalibrationDraft.empty(
    DateTime capturedAt, {
    String? entryDate,
  }) {
    final date = entryDate ?? dailyCaptureEntryDate(capturedAt);
    return MorningCalibrationDraft(
      captureId: 'morning-$date-${capturedAt.toUtc().microsecondsSinceEpoch}',
      entryDate: date,
      capturedAt: capturedAt,
      sleepHours: null,
      energy: null,
      dayShape: null,
    );
  }

  factory MorningCalibrationDraft.fromJson(
    Map<String, dynamic> json, {
    required String entryDate,
  }) {
    if (json['capture_kind'] != 'morning' || json['entry_date'] != entryDate) {
      throw const FormatException('Morning capture identity is invalid.');
    }
    final draft = MorningCalibrationDraft(
      captureId: _requiredString(json, 'capture_id'),
      entryDate: entryDate,
      capturedAt: _requiredDateTime(json, 'captured_at'),
      sleepHours: (json['sleep_hours'] as num?)?.toDouble(),
      energy: (json['current_energy'] as num?)?.toInt(),
      dayShape: DayShape.fromCode(json['day_shape']),
    );
    draft.validate();
    return draft;
  }

  static const maxCaptureIdLength = 160;

  final String captureId;
  final String entryDate;
  final DateTime capturedAt;
  final double? sleepHours;
  final int? energy;
  final DayShape? dayShape;

  bool get isComplete =>
      sleepHours != null && energy != null && dayShape != null;

  MorningCalibrationDraft copyWith({
    String? captureId,
    String? entryDate,
    DateTime? capturedAt,
    Object? sleepHours = _unset,
    Object? energy = _unset,
    Object? dayShape = _unset,
  }) {
    return MorningCalibrationDraft(
      captureId: captureId ?? this.captureId,
      entryDate: entryDate ?? this.entryDate,
      capturedAt: capturedAt ?? this.capturedAt,
      sleepHours: identical(sleepHours, _unset)
          ? this.sleepHours
          : sleepHours as double?,
      energy: identical(energy, _unset) ? this.energy : energy as int?,
      dayShape:
          identical(dayShape, _unset) ? this.dayShape : dayShape as DayShape?,
    );
  }

  MorningCalibrationDraft normalized() => copyWith(
        captureId: captureId.trim(),
      );

  void validate() {
    _validateCaptureIdentity(
      captureId: captureId,
      entryDate: entryDate,
      maxCaptureIdLength: maxCaptureIdLength,
    );
    if (!isComplete) {
      throw const FormatException(
        'All Morning Calibration answers must be selected.',
      );
    }
    _validateRating('energy', energy!);
    if (!sleepHours!.isFinite || sleepHours! < 0 || sleepHours! > 12) {
      throw const FormatException('Sleep hours must be between 0 and 12.');
    }
    final halfHours = sleepHours! * 2;
    if ((halfHours - halfHours.round()).abs() > 0.0001) {
      throw const FormatException('Sleep hours must use half-hour steps.');
    }
  }

  Map<String, dynamic> toMetadataJson() {
    validate();
    final value = normalized();
    return {
      'capture_kind': 'morning',
      'entry_date': value.entryDate,
      'capture_id': value.captureId,
      'captured_at': value.capturedAt.toUtc().toIso8601String(),
      'sleep_hours': value.sleepHours,
      'current_energy': value.energy,
      'day_shape': value.dayShape!.code,
    };
  }
}

class LegacyQuickCheckInValues {
  const LegacyQuickCheckInValues({
    required this.captureId,
    required this.capturedAt,
    required this.mood,
    required this.energy,
    required this.sleepHours,
    required this.stress,
    required this.contextNote,
  });

  factory LegacyQuickCheckInValues.fromV1GuestJson(
    Map<String, dynamic> json,
  ) {
    final capturedAt = DateTime.parse('${json['createdAt']}');
    final value = LegacyQuickCheckInValues(
      captureId:
          '${json['captureId'] ?? 'daily-${capturedAt.toUtc().microsecondsSinceEpoch}'}',
      capturedAt: capturedAt,
      mood: (json['mood'] as num?)?.toInt(),
      energy: (json['energy'] as num?)?.toInt(),
      sleepHours: (json['sleepHours'] as num?)?.toDouble(),
      stress: (json['stress'] as num?)?.toInt(),
      contextNote: '${json['contextNote'] ?? json['coachNotes'] ?? ''}'.trim(),
    );
    value.validatePresentValues();
    return value;
  }

  final String captureId;
  final DateTime capturedAt;
  final int? mood;
  final int? energy;
  final double? sleepHours;
  final int? stress;
  final String contextNote;

  bool get hasAnySignal =>
      mood != null || energy != null || sleepHours != null || stress != null;

  void validatePresentValues() {
    if (captureId.trim().isEmpty) {
      throw const FormatException('The legacy capture id is required.');
    }
    if (mood != null) {
      _validateLegacyRating('mood', mood!);
    }
    if (energy != null) {
      _validateLegacyRating('energy', energy!);
    }
    if (stress != null) {
      _validateLegacyRating('stress', stress!);
    }
    if (sleepHours != null &&
        (!sleepHours!.isFinite || sleepHours! < 0 || sleepHours! > 12)) {
      throw const FormatException('Sleep hours must be between 0 and 12.');
    }
  }

  Map<String, dynamic> toGuestJson() => {
        'captureId': captureId,
        'createdAt': capturedAt.toIso8601String(),
        if (mood != null) 'mood': mood,
        if (energy != null) 'energy': energy,
        if (sleepHours != null) 'sleepHours': sleepHours,
        if (stress != null) 'stress': stress,
        if (contextNote.trim().isNotEmpty) 'contextNote': contextNote.trim(),
      };
}

class DailyCaptureEntry {
  const DailyCaptureEntry({
    required this.entryDate,
    this.evening,
    this.morning,
    this.legacy,
    this.preservedMetadata = const <String, dynamic>{},
  });

  factory DailyCaptureEntry.fromV1GuestJson(Map<String, dynamic> json) {
    final entryDate = _requiredEntryDate(
      json['entryDate'] ?? json['entry_date'],
    );
    return DailyCaptureEntry(
      entryDate: entryDate,
      legacy: LegacyQuickCheckInValues.fromV1GuestJson(json),
    );
  }

  factory DailyCaptureEntry.fromGuestJson(Map<String, dynamic> json) {
    if (!json.containsKey('captures') && json['captureVersion'] == null) {
      return DailyCaptureEntry.fromV1GuestJson(json);
    }
    if (json['captureVersion'] != captureVersion) {
      throw const FormatException('Unsupported daily capture version.');
    }
    final entryDate = _requiredEntryDate(json['entryDate']);
    final captures = _stringMap(json['captures'], 'captures');
    final eveningJson = captures['evening'];
    final morningJson = captures['morning'];
    final legacyJson = json['legacy'];
    final entry = DailyCaptureEntry(
      entryDate: entryDate,
      evening: eveningJson == null
          ? null
          : EveningShutdownDraft.fromJson(
              _stringMap(eveningJson, 'evening capture'),
              entryDate: entryDate,
            ),
      morning: morningJson == null
          ? null
          : MorningCalibrationDraft.fromJson(
              _stringMap(morningJson, 'morning capture'),
              entryDate: entryDate,
            ),
      legacy: legacyJson == null
          ? null
          : LegacyQuickCheckInValues.fromV1GuestJson(
              _stringMap(legacyJson, 'legacy capture'),
            ),
    );
    if (!entry.hasAnyCapture) {
      throw const FormatException('A daily capture entry cannot be empty.');
    }
    return entry;
  }

  static const captureVersion = 'daily-capture-v2';

  final String entryDate;
  final EveningShutdownDraft? evening;
  final MorningCalibrationDraft? morning;
  final LegacyQuickCheckInValues? legacy;
  final Map<String, dynamic> preservedMetadata;

  int? get mood => evening?.mood ?? legacy?.mood;
  int? get energy => morning?.energy ?? evening?.energy ?? legacy?.energy;
  double? get sleepHours => morning?.sleepHours ?? legacy?.sleepHours;
  int? get stress => evening?.stress ?? legacy?.stress;
  String get reflectionNote => evening != null
      ? evening!.reflectionNote.trim()
      : (legacy?.contextNote.trim() ?? '');

  bool get hasAnyCapture =>
      evening != null || morning != null || legacy?.hasAnySignal == true;

  DateTime? get latestCapturedAt {
    final values = [
      evening?.capturedAt,
      morning?.capturedAt,
      legacy?.capturedAt,
    ].whereType<DateTime>().toList();
    if (values.isEmpty) {
      return null;
    }
    values.sort();
    return values.last;
  }

  DailyCaptureEntry mergeEvening(EveningShutdownDraft draft) {
    draft.validate();
    _requireMatchingEntryDate(draft.entryDate);
    return DailyCaptureEntry(
      entryDate: entryDate,
      evening: draft.normalized(),
      morning: morning,
      legacy: legacy,
      preservedMetadata: preservedMetadata,
    );
  }

  DailyCaptureEntry mergeMorning(MorningCalibrationDraft draft) {
    draft.validate();
    _requireMatchingEntryDate(draft.entryDate);
    return DailyCaptureEntry(
      entryDate: entryDate,
      evening: evening,
      morning: draft.normalized(),
      legacy: legacy,
      preservedMetadata: preservedMetadata,
    );
  }

  DailyCaptureEntry mergeEntry(DailyCaptureEntry other) {
    _requireMatchingEntryDate(other.entryDate);
    return DailyCaptureEntry(
      entryDate: entryDate,
      evening: other.evening ?? evening,
      morning: other.morning ?? morning,
      legacy: other.legacy ?? legacy,
      preservedMetadata: {
        ...preservedMetadata,
        ...other.preservedMetadata,
      },
    );
  }

  DailyCaptureEntry copyWith({
    EveningShutdownDraft? evening,
    MorningCalibrationDraft? morning,
    LegacyQuickCheckInValues? legacy,
    Map<String, dynamic>? preservedMetadata,
  }) {
    return DailyCaptureEntry(
      entryDate: entryDate,
      evening: evening ?? this.evening,
      morning: morning ?? this.morning,
      legacy: legacy ?? this.legacy,
      preservedMetadata: preservedMetadata ?? this.preservedMetadata,
    );
  }

  Map<String, dynamic> toCaptureMetadata() => {
        ...preservedMetadata,
        'capture_version': captureVersion,
        'captures': {
          if (evening != null) 'evening': evening!.toMetadataJson(),
          if (morning != null) 'morning': morning!.toMetadataJson(),
        },
      };

  Map<String, dynamic> toGuestJson() => {
        'entryDate': entryDate,
        'captureVersion': captureVersion,
        'captures': {
          if (evening != null) 'evening': evening!.toMetadataJson(),
          if (morning != null) 'morning': morning!.toMetadataJson(),
        },
        if (legacy != null) 'legacy': legacy!.toGuestJson(),
      };

  void _requireMatchingEntryDate(String other) {
    if (entryDate != other) {
      throw FormatException(
        'Capture date $other does not match daily entry $entryDate.',
      );
    }
  }
}

/// Read-only compatibility model for legacy guest JSON and older call sites.
@Deprecated(
  'Use EveningShutdownDraft, MorningCalibrationDraft, and DailyCaptureEntry.',
)
class QuickCheckInDraft {
  const QuickCheckInDraft({
    required this.captureId,
    required this.capturedAt,
    required this.mood,
    required this.energy,
    required this.sleepHours,
    required this.stress,
    required this.contextNote,
  });

  factory QuickCheckInDraft.empty(DateTime capturedAt) => QuickCheckInDraft(
        captureId: 'daily-${capturedAt.toUtc().microsecondsSinceEpoch}',
        capturedAt: capturedAt,
        mood: null,
        energy: null,
        sleepHours: null,
        stress: null,
        contextNote: '',
      );

  factory QuickCheckInDraft.fromJson(Map<String, dynamic> json) {
    final legacy = LegacyQuickCheckInValues.fromV1GuestJson(json);
    return QuickCheckInDraft(
      captureId: legacy.captureId,
      capturedAt: legacy.capturedAt,
      mood: legacy.mood,
      energy: legacy.energy,
      sleepHours: legacy.sleepHours,
      stress: legacy.stress,
      contextNote: legacy.contextNote,
    );
  }

  final String captureId;
  final DateTime capturedAt;
  final int? mood;
  final int? energy;
  final double? sleepHours;
  final int? stress;
  final String contextNote;

  bool get isComplete =>
      mood != null && energy != null && sleepHours != null && stress != null;

  String get entryDate => dailyCaptureEntryDate(capturedAt);

  QuickCheckInDraft copyWith({
    int? mood,
    int? energy,
    double? sleepHours,
    int? stress,
    String? contextNote,
  }) =>
      QuickCheckInDraft(
        captureId: captureId,
        capturedAt: capturedAt,
        mood: mood ?? this.mood,
        energy: energy ?? this.energy,
        sleepHours: sleepHours ?? this.sleepHours,
        stress: stress ?? this.stress,
        contextNote: contextNote ?? this.contextNote,
      );

  QuickCheckInDraft normalized() => copyWith(contextNote: contextNote.trim());

  void validate() {
    if (!isComplete) {
      throw const FormatException('All check-in ratings must be selected.');
    }
    _validateRating('mood', mood!);
    _validateRating('energy', energy!);
    _validateRating('stress', stress!);
    final halfHours = sleepHours! * 2;
    if ((halfHours - halfHours.round()).abs() > 0.0001) {
      throw const FormatException('Sleep hours must use half-hour steps.');
    }
    LegacyQuickCheckInValues(
      captureId: captureId,
      capturedAt: capturedAt,
      mood: mood,
      energy: energy,
      sleepHours: sleepHours,
      stress: stress,
      contextNote: contextNote,
    ).validatePresentValues();
  }

  Map<String, dynamic> toJson() {
    validate();
    final value = normalized();
    return {
      'captureId': value.captureId,
      'createdAt': value.capturedAt.toIso8601String(),
      'entryDate': value.entryDate,
      'mood': value.mood,
      'energy': value.energy,
      'sleepHours': value.sleepHours,
      'stress': value.stress,
      'contextNote': value.contextNote,
    };
  }
}

abstract interface class QuickCheckInStore {
  QuickCheckInSaveTarget get target;

  Future<DailyCaptureEntry?> loadToday(DateTime today);

  Future<void> saveEvening(EveningShutdownDraft draft);

  Future<void> saveMorning(MorningCalibrationDraft draft);
}

class QuickCheckInUnavailableException implements Exception {
  const QuickCheckInUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

T _enumFromCode<T>(
  List<T> values,
  Object? raw,
  String Function(T value) code,
  String field,
) {
  final normalized = _optionalString(raw);
  for (final value in values) {
    if (code(value) == normalized) {
      return value;
    }
  }
  throw FormatException('Invalid $field.');
}

void _validateCaptureIdentity({
  required String captureId,
  required String entryDate,
  required int maxCaptureIdLength,
}) {
  _validateBoundedString(
    'capture id',
    captureId,
    maxCaptureIdLength,
    required: true,
  );
  _requiredEntryDate(entryDate);
}

void _validateRating(String field, int value) {
  if (value < 1 || value > 10) {
    throw FormatException('$field must be between 1 and 10.');
  }
}

void _validateLegacyRating(String field, int value) {
  if (value < 0 || value > 10) {
    throw FormatException('$field must be between 0 and 10.');
  }
}

void _validateBoundedString(
  String field,
  String value,
  int maxLength, {
  bool required = false,
}) {
  final normalized = value.trim();
  if (required && normalized.isEmpty) {
    throw FormatException('$field is required.');
  }
  if (normalized.length > maxLength) {
    throw FormatException('$field must be $maxLength characters or fewer.');
  }
}

String _requiredEntryDate(Object? raw) {
  final value = _optionalString(raw);
  if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Entry date must use YYYY-MM-DD.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || dailyCaptureEntryDate(parsed) != value) {
    throw const FormatException('Entry date is invalid.');
  }
  return value;
}

String _requiredString(Map<String, dynamic> json, String field) {
  final value = _optionalString(json[field]);
  if (value == null) {
    throw FormatException('$field is required.');
  }
  return value;
}

DateTime _requiredDateTime(Map<String, dynamic> json, String field) {
  final value = _optionalString(json[field]);
  final parsed = value == null ? null : DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$field must be an ISO-8601 timestamp.');
  }
  return parsed;
}

String? _optionalString(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

Map<String, dynamic> _stringMap(Object? value, String field) {
  if (value is! Map) {
    throw FormatException('$field must be an object.');
  }
  return Map<String, dynamic>.from(value);
}

const Object _unset = Object();
