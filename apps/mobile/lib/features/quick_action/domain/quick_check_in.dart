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
  noMajorFriction('no_major_friction'),
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

String dailyCaptureClock(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

({DateTime estimatedSleepStartedAt, DateTime wokeAt})
    estimatedSleepIntervalForLocalClocks({
  required String entryDate,
  required String estimatedSleepStartedAt,
  required String wokeAt,
}) {
  final date = DateTime.parse(_requiredEntryDate(entryDate));
  _validateSleepClock(estimatedSleepStartedAt);
  _validateSleepClock(wokeAt);
  final startParts = estimatedSleepStartedAt.split(':');
  final wakeParts = wokeAt.split(':');
  final startMinute =
      int.parse(startParts.first) * 60 + int.parse(startParts.last);
  final wakeMinute =
      int.parse(wakeParts.first) * 60 + int.parse(wakeParts.last);
  final wake = DateTime(
    date.year,
    date.month,
    date.day,
    int.parse(wakeParts.first),
    int.parse(wakeParts.last),
  );
  final startDate = startMinute >= wakeMinute
      ? DateTime(date.year, date.month, date.day - 1)
      : date;
  final start = DateTime(
    startDate.year,
    startDate.month,
    startDate.day,
    int.parse(startParts.first),
    int.parse(startParts.last),
  );
  return (estimatedSleepStartedAt: start, wokeAt: wake);
}

const dailyCaptureV5 = 'daily-capture-v5';
const dailyCaptureV4 = 'daily-capture-v4';
const dailyCaptureV3 = 'daily-capture-v3';
const dailyCaptureV2 = 'daily-capture-v2';

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
    MainFriction? mainFriction,
    required this.tomorrowPriority,
    List<MainFriction> additionalFrictions = const <MainFriction>[],
    this.reflectionNote = '',
    this.specificBlocker = '',
    this.plannedSleepTime,
    this.sleepTargetMinutes,
    this.branchVersion = dailyCaptureV5,
    this.isCompatibilityBranch = false,
  })  : mainFriction = null,
        additionalFrictions = const <MainFriction>[];

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
      sleepTargetMinutes: defaultSleepTargetMinutes,
      branchVersion: dailyCaptureV5,
    );
  }

  factory EveningShutdownDraft.fromJson(
    Map<String, dynamic> json, {
    required String entryDate,
    String containerVersion = dailyCaptureV5,
  }) {
    if (json['capture_kind'] != 'evening' || json['entry_date'] != entryDate) {
      throw const FormatException('Evening capture identity is invalid.');
    }
    final branch = _captureBranchIdentity(
      json,
      containerVersion: containerVersion,
    );
    final draft = EveningShutdownDraft(
      captureId: _requiredString(json, 'capture_id'),
      entryDate: entryDate,
      capturedAt: _requiredDateTime(json, 'captured_at'),
      mood: (json['mood'] as num?)?.toInt(),
      energy: (json['energy'] as num?)?.toInt(),
      stress: (json['stress_intensity'] as num?)?.toInt(),
      stressSource: _optionalEnumFromCode(
        StressSource.values,
        json['stress_source'],
        (item) => item.code,
        'stress source',
      ),
      stressControllability: _optionalEnumFromCode(
        StressControllability.values,
        json['stress_controllability'],
        (item) => item.code,
        'stress controllability',
      ),
      focusBand: _optionalEnumFromCode(
        FocusBand.values,
        json['focus_band'],
        (item) => item.code,
        'focus band',
      ),
      tomorrowPriority: _optionalString(json['tomorrow_priority']) ?? '',
      reflectionNote: _optionalString(json['reflection_note']) ?? '',
      specificBlocker: _optionalString(json['specific_blocker']) ?? '',
      plannedSleepTime: _optionalString(json['planned_sleep_time']),
      sleepTargetMinutes: _optionalWholeNumber(
        json,
        'sleep_target_minutes',
      ),
      branchVersion: branch.version,
      isCompatibilityBranch: branch.isCompatibility,
    );
    draft.validate(preservingCompatibility: true);
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
  static const defaultSleepTargetMinutes = 480;

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
  final List<MainFriction> additionalFrictions;
  final String tomorrowPriority;
  final String reflectionNote;
  final String specificBlocker;
  final String? plannedSleepTime;
  final int? sleepTargetMinutes;
  final String branchVersion;
  final bool isCompatibilityBranch;

  bool get isV5 => branchVersion == dailyCaptureV5;

  bool get hasPreciseSleepPlan =>
      branchVersion == dailyCaptureV4 || branchVersion == dailyCaptureV5;

  bool get requiresStressContext => stress != null && stress! >= 5;

  bool get hasConsistentStressContext =>
      (stressSource == null) == (stressControllability == null) &&
      (!requiresStressContext || stressSource != null);

  bool get isComplete =>
      mood != null &&
      energy != null &&
      stress != null &&
      hasConsistentStressContext &&
      (!hasPreciseSleepPlan ||
          (plannedSleepTime != null && sleepTargetMinutes != null));

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
    List<MainFriction>? additionalFrictions,
    String? tomorrowPriority,
    String? reflectionNote,
    String? specificBlocker,
    Object? plannedSleepTime = _unset,
    Object? sleepTargetMinutes = _unset,
    String? branchVersion,
    bool? isCompatibilityBranch,
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
      tomorrowPriority: tomorrowPriority ?? this.tomorrowPriority,
      reflectionNote: reflectionNote ?? this.reflectionNote,
      specificBlocker: specificBlocker ?? this.specificBlocker,
      plannedSleepTime: identical(plannedSleepTime, _unset)
          ? this.plannedSleepTime
          : plannedSleepTime as String?,
      sleepTargetMinutes: identical(sleepTargetMinutes, _unset)
          ? this.sleepTargetMinutes
          : sleepTargetMinutes as int?,
      branchVersion: branchVersion ?? this.branchVersion,
      isCompatibilityBranch:
          isCompatibilityBranch ?? this.isCompatibilityBranch,
    );
  }

  EveningShutdownDraft normalized() => copyWith(
        captureId: captureId.trim(),
        tomorrowPriority: tomorrowPriority.trim(),
        reflectionNote: reflectionNote.trim(),
        specificBlocker: specificBlocker.trim(),
        plannedSleepTime: plannedSleepTime?.trim(),
      );

  EveningShutdownDraft forEditing() => copyWith(
        branchVersion: dailyCaptureV5,
        isCompatibilityBranch: false,
        sleepTargetMinutes: sleepTargetMinutes ?? defaultSleepTargetMinutes,
      );

  void validate({bool preservingCompatibility = false}) {
    _validateCaptureIdentity(
      captureId: captureId,
      entryDate: entryDate,
      maxCaptureIdLength: maxCaptureIdLength,
    );
    _validateEditableBranch(
      branchVersion: branchVersion,
      isCompatibilityBranch: isCompatibilityBranch,
      preservingCompatibility: preservingCompatibility,
    );
    if (!isComplete) {
      throw const FormatException(
        'All required evening check-in answers must be selected.',
      );
    }
    _validateRating('mood', mood!);
    _validateRating('energy', energy!);
    _validateRating('stress', stress!);
    if (!hasConsistentStressContext) {
      throw const FormatException(
        'Stress source and controllability must be supplied together when '
        'stress is medium or high.',
      );
    }
    _validateBoundedString(
      'tomorrow priority',
      tomorrowPriority,
      maxTomorrowPriorityLength,
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
    if (hasPreciseSleepPlan) {
      _validateSleepClock(plannedSleepTime);
      _validateSleepTarget(sleepTargetMinutes);
    }
  }

  Map<String, dynamic> toMetadataJson({
    bool preservingCompatibility = true,
  }) {
    validate(preservingCompatibility: preservingCompatibility);
    final value = normalized();
    return {
      'branch_version': value.branchVersion,
      if (!value.isV5) 'compatibility': true,
      'capture_kind': 'evening',
      'entry_date': value.entryDate,
      'capture_id': value.captureId,
      'captured_at': value.capturedAt.toUtc().toIso8601String(),
      'mood': value.mood,
      'energy': value.energy,
      'stress_intensity': value.stress,
      'stress_intensity_label': value.stressIntensityLabel.code,
      if (value.stressSource != null) 'stress_source': value.stressSource!.code,
      if (value.stressControllability != null)
        'stress_controllability': value.stressControllability!.code,
      if (value.focusBand != null) 'focus_band': value.focusBand!.code,
      if (value.tomorrowPriority.isNotEmpty)
        'tomorrow_priority': value.tomorrowPriority,
      if (value.reflectionNote.isNotEmpty)
        'reflection_note': value.reflectionNote,
      if (value.specificBlocker.isNotEmpty)
        'specific_blocker': value.specificBlocker,
      if (value.hasPreciseSleepPlan) ...{
        'planned_sleep_time': value.plannedSleepTime,
        'sleep_target_minutes': value.sleepTargetMinutes,
      },
    };
  }
}

class MorningCalibrationDraft {
  MorningCalibrationDraft({
    required this.captureId,
    required this.entryDate,
    required this.capturedAt,
    double? sleepHours,
    required this.sleepQuality,
    required this.energy,
    this.estimatedSleepStartedAt,
    this.wokeAt,
    this.estimatedSleepMinutes,
    this.sleepTargetMinutes,
    this.sourceEveningCaptureId,
    this.branchVersion = dailyCaptureV5,
    this.isCompatibilityBranch = false,
    String? legacyDayShapeCode,
  })  : _legacyDayShapeCode = legacyDayShapeCode,
        sleepHours = estimatedSleepMinutes == null
            ? sleepHours
            : estimatedSleepMinutes / 60;

  factory MorningCalibrationDraft.empty(
    DateTime capturedAt, {
    String? entryDate,
  }) {
    final date = entryDate ?? dailyCaptureEntryDate(capturedAt);
    return MorningCalibrationDraft(
      captureId: 'morning-$date-${capturedAt.toUtc().microsecondsSinceEpoch}',
      entryDate: date,
      capturedAt: capturedAt,
      sleepQuality: null,
      energy: null,
      sleepTargetMinutes: EveningShutdownDraft.defaultSleepTargetMinutes,
      branchVersion: dailyCaptureV5,
    );
  }

  factory MorningCalibrationDraft.fromJson(
    Map<String, dynamic> json, {
    required String entryDate,
    String containerVersion = dailyCaptureV5,
  }) {
    if (json['capture_kind'] != 'morning' || json['entry_date'] != entryDate) {
      throw const FormatException('Morning capture identity is invalid.');
    }
    final branch = _captureBranchIdentity(
      json,
      containerVersion: containerVersion,
    );
    final sleepQuality = json['sleep_quality'];
    if (json.containsKey('sleep_quality') && sleepQuality is! int) {
      throw const FormatException('Sleep quality must be a whole number.');
    }
    final estimatedSleepMinutes = _optionalWholeNumber(
      json,
      'estimated_sleep_minutes',
    );
    final storedSleepHours = (json['sleep_hours'] as num?)?.toDouble();
    final hasPreciseSleep =
        branch.version == dailyCaptureV4 || branch.version == dailyCaptureV5;
    if (branch.version == dailyCaptureV5 && json.containsKey('day_shape')) {
      throw const FormatException(
        'Daily Capture V5 does not accept day_shape.',
      );
    }
    final legacyDayShapeCode = branch.version == dailyCaptureV5
        ? null
        : _parseLegacyDayShapeCode(json['day_shape']);
    if (hasPreciseSleep &&
        estimatedSleepMinutes != null &&
        storedSleepHours != null &&
        (storedSleepHours - estimatedSleepMinutes / 60).abs() > 0.0001) {
      throw const FormatException(
        'Estimated sleep minutes do not match sleep hours.',
      );
    }
    final draft = MorningCalibrationDraft(
      captureId: _requiredString(json, 'capture_id'),
      entryDate: entryDate,
      capturedAt: _requiredDateTime(json, 'captured_at'),
      sleepHours: storedSleepHours,
      sleepQuality: sleepQuality as int?,
      energy: (json['current_energy'] as num?)?.toInt(),
      estimatedSleepStartedAt: hasPreciseSleep
          ? _requiredAwareDateTime(json, 'estimated_sleep_started_at')
          : null,
      wokeAt: hasPreciseSleep ? _requiredAwareDateTime(json, 'woke_at') : null,
      estimatedSleepMinutes: estimatedSleepMinutes,
      sleepTargetMinutes: _optionalWholeNumber(
        json,
        'sleep_target_minutes',
      ),
      sourceEveningCaptureId:
          _optionalString(json['source_evening_capture_id']),
      branchVersion: branch.version,
      isCompatibilityBranch: branch.isCompatibility,
      legacyDayShapeCode: legacyDayShapeCode,
    );
    // V2 Morning captures written before sleep quality was introduced remain
    // readable. A new Morning save still requires an explicit value.
    draft.validate(
      requireSleepQuality: false,
      preservingCompatibility: true,
    );
    return draft;
  }

  static const maxCaptureIdLength = 160;

  final String captureId;
  final String entryDate;
  final DateTime capturedAt;
  final double? sleepHours;
  final int? sleepQuality;
  final int? energy;
  final DateTime? estimatedSleepStartedAt;
  final DateTime? wokeAt;
  final int? estimatedSleepMinutes;
  final int? sleepTargetMinutes;
  final String? sourceEveningCaptureId;
  final String branchVersion;
  final bool isCompatibilityBranch;
  final String? _legacyDayShapeCode;

  bool get isV5 => branchVersion == dailyCaptureV5;

  bool get hasPreciseSleepEpisode =>
      branchVersion == dailyCaptureV4 || branchVersion == dailyCaptureV5;

  bool get isComplete =>
      sleepHours != null &&
      sleepQuality != null &&
      energy != null &&
      (!hasPreciseSleepEpisode ||
          (estimatedSleepStartedAt != null &&
              wokeAt != null &&
              estimatedSleepMinutes != null &&
              sleepTargetMinutes != null));

  bool get _hasLegacyRequiredAnswers =>
      sleepHours != null &&
      energy != null &&
      (isV5 || _legacyDayShapeCode != null);

  MorningCalibrationDraft copyWith({
    String? captureId,
    String? entryDate,
    DateTime? capturedAt,
    Object? sleepHours = _unset,
    Object? sleepQuality = _unset,
    Object? energy = _unset,
    Object? estimatedSleepStartedAt = _unset,
    Object? wokeAt = _unset,
    Object? estimatedSleepMinutes = _unset,
    Object? sleepTargetMinutes = _unset,
    Object? sourceEveningCaptureId = _unset,
    String? branchVersion,
    bool? isCompatibilityBranch,
    Object? legacyDayShapeCode = _unset,
  }) {
    final nextEstimatedMinutes = identical(estimatedSleepMinutes, _unset)
        ? this.estimatedSleepMinutes
        : estimatedSleepMinutes as int?;
    return MorningCalibrationDraft(
      captureId: captureId ?? this.captureId,
      entryDate: entryDate ?? this.entryDate,
      capturedAt: capturedAt ?? this.capturedAt,
      sleepHours: nextEstimatedMinutes == null
          ? (identical(sleepHours, _unset)
              ? this.sleepHours
              : sleepHours as double?)
          : null,
      sleepQuality: identical(sleepQuality, _unset)
          ? this.sleepQuality
          : sleepQuality as int?,
      energy: identical(energy, _unset) ? this.energy : energy as int?,
      estimatedSleepStartedAt: identical(estimatedSleepStartedAt, _unset)
          ? this.estimatedSleepStartedAt
          : estimatedSleepStartedAt as DateTime?,
      wokeAt: identical(wokeAt, _unset) ? this.wokeAt : wokeAt as DateTime?,
      estimatedSleepMinutes: nextEstimatedMinutes,
      sleepTargetMinutes: identical(sleepTargetMinutes, _unset)
          ? this.sleepTargetMinutes
          : sleepTargetMinutes as int?,
      sourceEveningCaptureId: identical(sourceEveningCaptureId, _unset)
          ? this.sourceEveningCaptureId
          : sourceEveningCaptureId as String?,
      branchVersion: branchVersion ?? this.branchVersion,
      isCompatibilityBranch:
          isCompatibilityBranch ?? this.isCompatibilityBranch,
      legacyDayShapeCode: identical(legacyDayShapeCode, _unset)
          ? _legacyDayShapeCode
          : legacyDayShapeCode as String?,
    );
  }

  MorningCalibrationDraft normalized() => copyWith(
        captureId: captureId.trim(),
        sourceEveningCaptureId: sourceEveningCaptureId?.trim(),
      );

  MorningCalibrationDraft forEditing({
    EveningShutdownDraft? sleepPlan,
  }) =>
      copyWith(
        branchVersion: dailyCaptureV5,
        isCompatibilityBranch: false,
        legacyDayShapeCode: null,
        sleepTargetMinutes: sleepTargetMinutes ??
            sleepPlan?.sleepTargetMinutes ??
            EveningShutdownDraft.defaultSleepTargetMinutes,
        sourceEveningCaptureId: sourceEveningCaptureId ?? sleepPlan?.captureId,
      );

  MorningCalibrationDraft withSleepInterval({
    required DateTime estimatedSleepStartedAt,
    required DateTime wokeAt,
  }) {
    final seconds = wokeAt.difference(estimatedSleepStartedAt).inSeconds;
    final minutes = seconds > 0 && seconds <= 16 * 60 * 60 && seconds % 60 == 0
        ? seconds ~/ 60
        : null;
    return copyWith(
      estimatedSleepStartedAt: estimatedSleepStartedAt,
      wokeAt: wokeAt,
      estimatedSleepMinutes: minutes,
      sleepHours: null,
    );
  }

  void validate({
    bool requireSleepQuality = true,
    bool preservingCompatibility = false,
  }) {
    _validateCaptureIdentity(
      captureId: captureId,
      entryDate: entryDate,
      maxCaptureIdLength: maxCaptureIdLength,
    );
    _validateEditableBranch(
      branchVersion: branchVersion,
      isCompatibilityBranch: isCompatibilityBranch,
      preservingCompatibility: preservingCompatibility,
    );
    if (!_hasLegacyRequiredAnswers ||
        (requireSleepQuality && sleepQuality == null)) {
      throw const FormatException(
        'All morning check-in answers must be selected.',
      );
    }
    _validateRating('energy', energy!);
    if (sleepQuality != null) {
      _validateRating('sleep quality', sleepQuality!);
    }
    if (hasPreciseSleepEpisode) {
      _validateSleepTarget(sleepTargetMinutes);
      final start = estimatedSleepStartedAt;
      final end = wokeAt;
      final minutes = estimatedSleepMinutes;
      if (start == null || end == null || minutes == null) {
        throw const FormatException(
          'Estimated sleep start and wake time are required.',
        );
      }
      final seconds = end.difference(start).inSeconds;
      if (seconds <= 0 || seconds > 16 * 60 * 60 || seconds % 60 != 0) {
        throw const FormatException(
          'Estimated sleep must be ordered and no longer than 16 hours.',
        );
      }
      if (minutes != seconds ~/ 60 ||
          (sleepHours! - minutes / 60).abs() > 0.0001) {
        throw const FormatException(
          'Estimated sleep duration does not match its timestamps.',
        );
      }
      if (sourceEveningCaptureId != null) {
        _validateBoundedString(
          'source evening capture id',
          sourceEveningCaptureId!,
          EveningShutdownDraft.maxCaptureIdLength,
          required: true,
        );
      }
    } else {
      if (!sleepHours!.isFinite || sleepHours! < 0 || sleepHours! > 12) {
        throw const FormatException('Sleep hours must be between 0 and 12.');
      }
      final halfHours = sleepHours! * 2;
      if ((halfHours - halfHours.round()).abs() > 0.0001) {
        throw const FormatException('Sleep hours must use half-hour steps.');
      }
    }
  }

  Map<String, dynamic> toMetadataJson({
    bool preservingCompatibility = true,
  }) {
    // This serializer is also used while preserving an older Morning branch
    // during an Evening-only edit.
    validate(
      requireSleepQuality: false,
      preservingCompatibility: preservingCompatibility,
    );
    final value = normalized();
    return {
      'branch_version': value.branchVersion,
      if (!value.isV5) 'compatibility': true,
      'capture_kind': 'morning',
      'entry_date': value.entryDate,
      'capture_id': value.captureId,
      'captured_at': value.capturedAt.toUtc().toIso8601String(),
      'sleep_hours': value.sleepHours,
      if (value.sleepQuality != null) 'sleep_quality': value.sleepQuality,
      'current_energy': value.energy,
      if (!value.isV5) 'day_shape': value._legacyDayShapeCode,
      if (value.hasPreciseSleepEpisode) ...{
        'estimated_sleep_started_at':
            _awareIso8601String(value.estimatedSleepStartedAt!),
        'woke_at': _awareIso8601String(value.wokeAt!),
        'estimated_sleep_minutes': value.estimatedSleepMinutes,
        'sleep_target_minutes': value.sleepTargetMinutes,
        if (value.sourceEveningCaptureId != null)
          'source_evening_capture_id': value.sourceEveningCaptureId,
      },
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
    final containerVersion = json['captureVersion'];
    if (!supportedCaptureVersions.contains(containerVersion)) {
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
              containerVersion: '$containerVersion',
            ),
      morning: morningJson == null
          ? null
          : MorningCalibrationDraft.fromJson(
              _stringMap(morningJson, 'morning capture'),
              entryDate: entryDate,
              containerVersion: '$containerVersion',
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

  static const captureVersion = dailyCaptureV5;
  static const priorCaptureVersion = dailyCaptureV4;
  static const legacyCaptureVersion = dailyCaptureV3;
  static const oldestCaptureVersion = dailyCaptureV2;
  static const supportedCaptureVersions = <String>{
    captureVersion,
    priorCaptureVersion,
    legacyCaptureVersion,
    oldestCaptureVersion,
  };

  final String entryDate;
  final EveningShutdownDraft? evening;
  final MorningCalibrationDraft? morning;
  final LegacyQuickCheckInValues? legacy;
  final Map<String, dynamic> preservedMetadata;

  int? get mood => evening?.mood ?? legacy?.mood;
  int? get energy => morning?.energy ?? evening?.energy ?? legacy?.energy;
  double? get sleepHours => morning?.sleepHours ?? legacy?.sleepHours;
  int? get sleepQuality => morning?.sleepQuality;
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

  DailyCaptureEntry forAuthenticatedMigration() {
    final migratedEvening = evening?.branchVersion == dailyCaptureV4
        ? evening!.forEditing()
        : evening;
    final migratedMorning = morning?.branchVersion == dailyCaptureV4
        ? morning!.forEditing(sleepPlan: migratedEvening)
        : morning;
    return DailyCaptureEntry(
      entryDate: entryDate,
      evening: migratedEvening,
      morning: migratedMorning,
      legacy: legacy,
      preservedMetadata: preservedMetadata,
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
          if (evening != null)
            'evening': evening!.toMetadataJson(
              preservingCompatibility: !evening!.isV5,
            ),
          if (morning != null)
            'morning': morning!.toMetadataJson(
              preservingCompatibility: !morning!.isV5,
            ),
        },
      };

  Map<String, dynamic> toGuestJson() => {
        'entryDate': entryDate,
        'captureVersion': captureVersion,
        'captures': {
          if (evening != null)
            'evening': evening!.toMetadataJson(
              preservingCompatibility: !evening!.isV5,
            ),
          if (morning != null)
            'morning': morning!.toMetadataJson(
              preservingCompatibility: !morning!.isV5,
            ),
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

  Future<EveningShutdownDraft?> loadLatestEvening();

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

T? _optionalEnumFromCode<T>(
  List<T> values,
  Object? raw,
  String Function(T value) code,
  String field,
) {
  if (raw == null) {
    return null;
  }
  return _enumFromCode<T>(values, raw, code, field);
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

int? _optionalWholeNumber(
  Map<String, dynamic> json,
  String field,
) {
  final raw = json[field];
  if (raw == null) {
    return null;
  }
  if (raw is! num ||
      !raw.toDouble().isFinite ||
      raw.toDouble() != raw.toInt()) {
    throw FormatException('$field must be a whole number.');
  }
  return raw.toInt();
}

DateTime _requiredDateTime(Map<String, dynamic> json, String field) {
  final value = _optionalString(json[field]);
  final parsed = value == null ? null : DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$field must be an ISO-8601 timestamp.');
  }
  return parsed;
}

DateTime _requiredAwareDateTime(
  Map<String, dynamic> json,
  String field,
) {
  final value = _optionalString(json[field]);
  final hasOffset =
      value != null && RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(value);
  final parsed = value == null ? null : DateTime.tryParse(value);
  if (parsed == null || !hasOffset) {
    throw FormatException(
      '$field must be an ISO-8601 timestamp with a timezone offset.',
    );
  }
  return parsed;
}

String _awareIso8601String(DateTime value) {
  if (value.isUtc) {
    return value.toIso8601String();
  }
  final base = value.toIso8601String();
  final offset = value.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final absoluteMinutes = offset.inMinutes.abs();
  final hours = (absoluteMinutes ~/ 60).toString().padLeft(2, '0');
  final minutes = (absoluteMinutes % 60).toString().padLeft(2, '0');
  return '$base$sign$hours:$minutes';
}

void _validateSleepClock(String? value) {
  if (value == null ||
      !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
    throw const FormatException('Planned sleep time must use HH:mm.');
  }
}

void _validateSleepTarget(int? value) {
  if (value == null || value < 300 || value > 720 || value % 15 != 0) {
    throw const FormatException(
      'Sleep target must be 300 to 720 minutes in 15-minute steps.',
    );
  }
}

void _validateEditableBranch({
  required String branchVersion,
  required bool isCompatibilityBranch,
  required bool preservingCompatibility,
}) {
  if (!DailyCaptureEntry.supportedCaptureVersions.contains(branchVersion)) {
    throw const FormatException('Unsupported capture branch version.');
  }
  if (branchVersion == dailyCaptureV5) {
    if (isCompatibilityBranch) {
      throw const FormatException(
        'A V5 capture cannot be a compatibility branch.',
      );
    }
    return;
  }
  if (!preservingCompatibility) {
    throw const FormatException(
      'An edited compatibility capture must be completed as V5.',
    );
  }
}

_CaptureBranchIdentity _captureBranchIdentity(
  Map<String, dynamic> json, {
  required String containerVersion,
}) {
  if (!DailyCaptureEntry.supportedCaptureVersions.contains(containerVersion)) {
    throw const FormatException('Unsupported capture container version.');
  }
  if (containerVersion != dailyCaptureV4 &&
      containerVersion != dailyCaptureV5) {
    return _CaptureBranchIdentity(
      version: containerVersion,
      isCompatibility: true,
    );
  }

  final version = _optionalString(json['branch_version']);
  if (version == null ||
      !DailyCaptureEntry.supportedCaptureVersions.contains(version) ||
      _captureVersionOrder(version) > _captureVersionOrder(containerVersion)) {
    throw const FormatException('Capture branch version is invalid.');
  }
  final compatibility = json['compatibility'];
  if (version == containerVersion) {
    if (compatibility != null && compatibility != false) {
      throw const FormatException(
        'Current capture branch cannot be compatibility data.',
      );
    }
    return _CaptureBranchIdentity(
      version: version,
      isCompatibility: false,
    );
  }
  if (compatibility != true) {
    throw const FormatException(
      'An older branch inside a current container must be explicit compatibility data.',
    );
  }
  return _CaptureBranchIdentity(
    version: version,
    isCompatibility: true,
  );
}

int _captureVersionOrder(String value) => switch (value) {
      dailyCaptureV2 => 2,
      dailyCaptureV3 => 3,
      dailyCaptureV4 => 4,
      dailyCaptureV5 => 5,
      _ => 99,
    };

String _parseLegacyDayShapeCode(Object? value) {
  if (value is String && _legacyDayShapeCodes.contains(value)) {
    return value;
  }
  throw FormatException('Unknown historical day shape: $value');
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
const _legacyDayShapeCodes = {'normal', 'constrained', 'flexible'};

class _CaptureBranchIdentity {
  const _CaptureBranchIdentity({
    required this.version,
    required this.isCompatibility,
  });

  final String version;
  final bool isCompatibility;
}
