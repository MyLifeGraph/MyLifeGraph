import 'dart:math';

const _allowedFocusAreas = {
  'focus',
  'energy',
  'sleep',
  'stress',
  'planning',
  'movement',
};
const _allowedEnergyWindows = {
  'early_morning',
  'morning',
  'afternoon',
  'evening',
  'variable',
};
const _allowedCoachingStyles = {
  'direct',
  'gentle',
  'analytical',
  'accountability',
};
const _allowedCalendarIntents = {'not_now', 'later', 'interested'};

enum IntakeGoalStatus {
  active,
  paused,
  archived;

  static IntakeGoalStatus fromJson(Object? value) {
    return switch (value) {
      'active' => IntakeGoalStatus.active,
      'paused' => IntakeGoalStatus.paused,
      'archived' => IntakeGoalStatus.archived,
      _ => throw FormatException('Unsupported goal status: $value'),
    };
  }
}

enum IntakeRoutineStatus {
  candidate,
  active,
  paused,
  archived;

  static IntakeRoutineStatus fromJson(Object? value) {
    return switch (value) {
      'candidate' => IntakeRoutineStatus.candidate,
      'active' => IntakeRoutineStatus.active,
      'paused' => IntakeRoutineStatus.paused,
      'archived' => IntakeRoutineStatus.archived,
      _ => throw FormatException('Unsupported routine status: $value'),
    };
  }

  bool get requiresCadence =>
      this == IntakeRoutineStatus.active || this == IntakeRoutineStatus.paused;
}

enum IntakeCommitmentStatus {
  active,
  archived;

  static IntakeCommitmentStatus fromJson(Object? value) {
    return switch (value) {
      'active' => IntakeCommitmentStatus.active,
      'archived' => IntakeCommitmentStatus.archived,
      _ => throw FormatException('Unsupported commitment status: $value'),
    };
  }
}

const studyPreparationSuggestions = <String>[
  'Water',
  'Small snack',
  'Bathroom',
  'Flight or focus mode',
  'Study materials',
];

class StudyPreparationItemDraft {
  const StudyPreparationItemDraft({
    required this.key,
    required this.label,
    required this.active,
  });

  factory StudyPreparationItemDraft.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'key', 'label', 'active'},
      'Study preparation item',
    );
    final key = _requiredExactText(json['key'], 'preparation item key', 36);
    if (!isCanonicalStudyUuid(key)) {
      throw const FormatException(
        'Study preparation item key must be a UUID.',
      );
    }
    return StudyPreparationItemDraft(
      key: key,
      label: _requiredExactText(
        json['label'],
        'preparation item label',
        120,
      ),
      active: _requiredBool(json, 'active'),
    );
  }

  final String key;
  final String label;
  final bool active;

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label.trim(),
        'active': active,
      };

  StudyPreparationItemDraft copyWith({
    String? key,
    String? label,
    bool? active,
  }) {
    return StudyPreparationItemDraft(
      key: key ?? this.key,
      label: label ?? this.label,
      active: active ?? this.active,
    );
  }
}

class StudyFocusRhythmDraft {
  StudyFocusRhythmDraft({
    required this.focusMinutes,
    required this.recoveryMinutes,
    required List<StudyPreparationItemDraft> preparationItems,
  }) : preparationItems = List.unmodifiable(preparationItems);

  factory StudyFocusRhythmDraft.defaults() {
    return StudyFocusRhythmDraft(
      focusMinutes: 45,
      recoveryMinutes: 10,
      preparationItems: studyPreparationSuggestions
          .map(
            (label) => StudyPreparationItemDraft(
              key: generateSetupUuid(),
              label: label,
              active: true,
            ),
          )
          .toList(growable: false),
    );
  }

  factory StudyFocusRhythmDraft.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'focus_minutes', 'recovery_minutes', 'preparation_items'},
      'Study focus rhythm',
    );
    return StudyFocusRhythmDraft(
      focusMinutes: _requiredExactInt(json['focus_minutes'], 'focus_minutes'),
      recoveryMinutes:
          _requiredExactInt(json['recovery_minutes'], 'recovery_minutes'),
      preparationItems: _modelList(
        json['preparation_items'],
        modelName: 'Study preparation item',
        fromJson: StudyPreparationItemDraft.fromJson,
      ),
    );
  }

  final int focusMinutes;
  final int recoveryMinutes;
  final List<StudyPreparationItemDraft> preparationItems;

  Map<String, dynamic> toJson() => {
        'focus_minutes': focusMinutes,
        'recovery_minutes': recoveryMinutes,
        'preparation_items': preparationItems
            .map((item) => item.toJson())
            .toList(growable: false),
      };

  StudyFocusRhythmDraft copyWith({
    int? focusMinutes,
    int? recoveryMinutes,
    List<StudyPreparationItemDraft>? preparationItems,
  }) {
    return StudyFocusRhythmDraft(
      focusMinutes: focusMinutes ?? this.focusMinutes,
      recoveryMinutes: recoveryMinutes ?? this.recoveryMinutes,
      preparationItems: preparationItems ?? this.preparationItems,
    );
  }
}

class StudySemesterDraft {
  const StudySemesterDraft({
    required this.name,
    required this.startsOn,
    required this.endsOn,
  });

  factory StudySemesterDraft.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'name', 'starts_on', 'ends_on'},
      'Study semester',
    );
    return StudySemesterDraft(
      name: _requiredExactText(json['name'], 'semester name', 120),
      startsOn: _requiredCalendarDate(json['starts_on'], 'semester starts_on'),
      endsOn: _requiredCalendarDate(json['ends_on'], 'semester ends_on'),
    );
  }

  final String name;
  final DateTime? startsOn;
  final DateTime? endsOn;

  Map<String, dynamic> toJson() {
    final start = startsOn;
    final end = endsOn;
    if (name.trim().isEmpty || start == null || end == null) {
      throw StateError('Complete the current semester name and dates.');
    }
    return {
      'name': name.trim(),
      'starts_on': _calendarDate(start),
      'ends_on': _calendarDate(end),
    };
  }

  StudySemesterDraft copyWith({
    String? name,
    Object? startsOn = _unset,
    Object? endsOn = _unset,
  }) {
    return StudySemesterDraft(
      name: name ?? this.name,
      startsOn:
          identical(startsOn, _unset) ? this.startsOn : startsOn as DateTime?,
      endsOn: identical(endsOn, _unset) ? this.endsOn : endsOn as DateTime?,
    );
  }
}

class StudyNextSemesterDraft {
  StudyNextSemesterDraft({
    required this.name,
    required this.startsOn,
    required this.endsOn,
    required this.courseSelectionStartsOn,
    required this.courseSelectionEndsOn,
    required List<String> courseNames,
    required this.courseSelectionCompleted,
  }) : courseNames = List.unmodifiable(courseNames);

  factory StudyNextSemesterDraft.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'name',
        'starts_on',
        'ends_on',
        'course_selection_starts_on',
        'course_selection_ends_on',
        'course_names',
        'course_selection_completed',
      },
      'Next Study semester',
    );
    return StudyNextSemesterDraft(
      name: _requiredExactText(json['name'], 'next semester name', 120),
      startsOn:
          _requiredCalendarDate(json['starts_on'], 'next semester starts_on'),
      endsOn: _requiredCalendarDate(json['ends_on'], 'next semester ends_on'),
      courseSelectionStartsOn: _requiredCalendarDate(
        json['course_selection_starts_on'],
        'course selection starts_on',
      ),
      courseSelectionEndsOn: _requiredCalendarDate(
        json['course_selection_ends_on'],
        'course selection ends_on',
      ),
      courseNames: _exactTextList(
        json['course_names'],
        'course names',
        maxItems: 12,
        maxLength: 120,
      ),
      courseSelectionCompleted:
          _requiredBool(json, 'course_selection_completed'),
    );
  }

  final String name;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final DateTime? courseSelectionStartsOn;
  final DateTime? courseSelectionEndsOn;
  final List<String> courseNames;
  final bool courseSelectionCompleted;

  Map<String, dynamic> toJson() {
    final start = startsOn;
    final end = endsOn;
    final selectionStart = courseSelectionStartsOn;
    final selectionEnd = courseSelectionEndsOn;
    if (name.trim().isEmpty ||
        start == null ||
        end == null ||
        selectionStart == null ||
        selectionEnd == null) {
      throw StateError('Complete the next semester and selection dates.');
    }
    return {
      'name': name.trim(),
      'starts_on': _calendarDate(start),
      'ends_on': _calendarDate(end),
      'course_selection_starts_on': _calendarDate(selectionStart),
      'course_selection_ends_on': _calendarDate(selectionEnd),
      'course_names': courseNames.map((name) => name.trim()).toList(),
      'course_selection_completed': courseSelectionCompleted,
    };
  }

  StudyNextSemesterDraft copyWith({
    String? name,
    Object? startsOn = _unset,
    Object? endsOn = _unset,
    Object? courseSelectionStartsOn = _unset,
    Object? courseSelectionEndsOn = _unset,
    List<String>? courseNames,
    bool? courseSelectionCompleted,
  }) {
    return StudyNextSemesterDraft(
      name: name ?? this.name,
      startsOn:
          identical(startsOn, _unset) ? this.startsOn : startsOn as DateTime?,
      endsOn: identical(endsOn, _unset) ? this.endsOn : endsOn as DateTime?,
      courseSelectionStartsOn: identical(courseSelectionStartsOn, _unset)
          ? this.courseSelectionStartsOn
          : courseSelectionStartsOn as DateTime?,
      courseSelectionEndsOn: identical(courseSelectionEndsOn, _unset)
          ? this.courseSelectionEndsOn
          : courseSelectionEndsOn as DateTime?,
      courseNames: courseNames ?? this.courseNames,
      courseSelectionCompleted:
          courseSelectionCompleted ?? this.courseSelectionCompleted,
    );
  }
}

class StudySemesterPlanningDraft {
  const StudySemesterPlanningDraft({
    required this.currentSemester,
    required this.nextSemester,
  });

  factory StudySemesterPlanningDraft.empty() {
    return StudySemesterPlanningDraft(
      currentSemester: const StudySemesterDraft(
        name: '',
        startsOn: null,
        endsOn: null,
      ),
      nextSemester: StudyNextSemesterDraft(
        name: '',
        startsOn: null,
        endsOn: null,
        courseSelectionStartsOn: null,
        courseSelectionEndsOn: null,
        courseNames: const [],
        courseSelectionCompleted: false,
      ),
    );
  }

  factory StudySemesterPlanningDraft.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'current_semester', 'next_semester'},
      'Study semester planning',
    );
    return StudySemesterPlanningDraft(
      currentSemester: StudySemesterDraft.fromJson(
        _requiredMap(json['current_semester'], 'current_semester'),
      ),
      nextSemester: StudyNextSemesterDraft.fromJson(
        _requiredMap(json['next_semester'], 'next_semester'),
      ),
    );
  }

  final StudySemesterDraft currentSemester;
  final StudyNextSemesterDraft nextSemester;

  Map<String, dynamic> toJson() => {
        'current_semester': currentSemester.toJson(),
        'next_semester': nextSemester.toJson(),
      };

  StudySemesterPlanningDraft copyWith({
    StudySemesterDraft? currentSemester,
    StudyNextSemesterDraft? nextSemester,
  }) {
    return StudySemesterPlanningDraft(
      currentSemester: currentSemester ?? this.currentSemester,
      nextSemester: nextSemester ?? this.nextSemester,
    );
  }
}

class StudySetupDraft {
  const StudySetupDraft({
    required this.focusRhythm,
    required this.semesterPlanning,
  });

  factory StudySetupDraft.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'focus_rhythm', 'semester_planning'},
      'Study setup',
      optional: const {'focus_rhythm', 'semester_planning'},
    );
    if (json.isEmpty || json.values.any((value) => value == null)) {
      throw const FormatException(
        'Study setup must contain a non-null optional section.',
      );
    }
    return StudySetupDraft(
      focusRhythm: json.containsKey('focus_rhythm')
          ? StudyFocusRhythmDraft.fromJson(
              _requiredMap(json['focus_rhythm'], 'focus_rhythm'),
            )
          : null,
      semesterPlanning: json.containsKey('semester_planning')
          ? StudySemesterPlanningDraft.fromJson(
              _requiredMap(json['semester_planning'], 'semester_planning'),
            )
          : null,
    );
  }

  final StudyFocusRhythmDraft? focusRhythm;
  final StudySemesterPlanningDraft? semesterPlanning;

  bool get isEmpty => focusRhythm == null && semesterPlanning == null;

  Map<String, dynamic> toJson() {
    if (isEmpty) {
      throw StateError('Study setup must contain an enabled section.');
    }
    return {
      if (focusRhythm != null) 'focus_rhythm': focusRhythm!.toJson(),
      if (semesterPlanning != null)
        'semester_planning': semesterPlanning!.toJson(),
    };
  }

  StudySetupDraft copyWith({
    Object? focusRhythm = _unset,
    Object? semesterPlanning = _unset,
  }) {
    return StudySetupDraft(
      focusRhythm: identical(focusRhythm, _unset)
          ? this.focusRhythm
          : focusRhythm as StudyFocusRhythmDraft?,
      semesterPlanning: identical(semesterPlanning, _unset)
          ? this.semesterPlanning
          : semesterPlanning as StudySemesterPlanningDraft?,
    );
  }
}

class IntakeGoalDraft {
  const IntakeGoalDraft({
    required this.key,
    required this.title,
    this.status = IntakeGoalStatus.active,
  });

  factory IntakeGoalDraft.fromJson(Map<String, dynamic> json) {
    return IntakeGoalDraft(
      key: _requiredString(json, 'key'),
      title: _requiredString(json, 'title'),
      status: IntakeGoalStatus.fromJson(json['status']),
    );
  }

  final String key;
  final String title;
  final IntakeGoalStatus status;

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title.trim(),
        'status': status.name,
      };

  IntakeGoalDraft copyWith({
    String? key,
    String? title,
    IntakeGoalStatus? status,
  }) {
    return IntakeGoalDraft(
      key: key ?? this.key,
      title: title ?? this.title,
      status: status ?? this.status,
    );
  }
}

class IntakeRoutineDraft {
  const IntakeRoutineDraft({
    required this.key,
    required this.title,
    this.status = IntakeRoutineStatus.candidate,
    this.cadenceConfirmed = false,
    this.frequency,
    this.target,
  });

  factory IntakeRoutineDraft.fromJson(Map<String, dynamic> json) {
    return IntakeRoutineDraft(
      key: _requiredString(json, 'key'),
      title: _requiredString(json, 'title'),
      status: IntakeRoutineStatus.fromJson(json['status']),
      cadenceConfirmed: json['cadence_confirmed'] == true,
      frequency: _optionalString(json['frequency']),
      target: _intValue(json['target'], field: 'target'),
    );
  }

  final String key;
  final String title;
  final IntakeRoutineStatus status;
  final bool cadenceConfirmed;
  final String? frequency;
  final int? target;

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title.trim(),
        'status': status.name,
        'cadence_confirmed': cadenceConfirmed,
        if (frequency != null && frequency!.trim().isNotEmpty)
          'frequency': frequency!.trim(),
        if (cadenceConfirmed && frequency != null && target != null)
          'target': target,
      };

  IntakeRoutineDraft copyWith({
    String? key,
    String? title,
    IntakeRoutineStatus? status,
    bool? cadenceConfirmed,
    Object? frequency = _unset,
    Object? target = _unset,
  }) {
    return IntakeRoutineDraft(
      key: key ?? this.key,
      title: title ?? this.title,
      status: status ?? this.status,
      cadenceConfirmed: cadenceConfirmed ?? this.cadenceConfirmed,
      frequency:
          identical(frequency, _unset) ? this.frequency : frequency as String?,
      target: identical(target, _unset) ? this.target : target as int?,
    );
  }
}

class IntakeCommitmentDraft {
  const IntakeCommitmentDraft({
    required this.key,
    required this.title,
    required this.location,
    required this.weekday,
    required this.startsAt,
    required this.endsAt,
    this.validFrom,
    this.validUntil,
    this.status = IntakeCommitmentStatus.active,
  });

  factory IntakeCommitmentDraft.fromJson(Map<String, dynamic> json) {
    return IntakeCommitmentDraft(
      key: _requiredString(json, 'key'),
      title: _requiredString(json, 'title'),
      location: _optionalString(json['location']),
      weekday: _intValue(json['weekday'], field: 'weekday'),
      startsAt: _requiredTime(json, 'starts_at'),
      endsAt: _requiredTime(json, 'ends_at'),
      validFrom: _optionalCalendarDate(json['valid_from']),
      validUntil: _optionalCalendarDate(json['valid_until']),
      status: IntakeCommitmentStatus.fromJson(json['status']),
    );
  }

  final String key;
  final String title;
  final String? location;
  final int? weekday;
  final String startsAt;
  final String endsAt;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final IntakeCommitmentStatus status;

  Map<String, dynamic> toJson() {
    final selectedWeekday = weekday;
    if (selectedWeekday == null) {
      throw StateError('A fixed commitment requires a weekday.');
    }
    return {
      'key': key,
      'title': title.trim(),
      if (location != null && location!.trim().isNotEmpty)
        'location': location!.trim(),
      'weekday': selectedWeekday,
      'starts_at': _normalizedTime(startsAt) ?? startsAt.trim(),
      'ends_at': _normalizedTime(endsAt) ?? endsAt.trim(),
      if (validFrom != null) 'valid_from': _calendarDate(validFrom!),
      if (validUntil != null) 'valid_until': _calendarDate(validUntil!),
      'status': status.name,
    };
  }

  IntakeCommitmentDraft copyWith({
    String? key,
    String? title,
    Object? location = _unset,
    Object? weekday = _unset,
    String? startsAt,
    String? endsAt,
    Object? validFrom = _unset,
    Object? validUntil = _unset,
    IntakeCommitmentStatus? status,
  }) {
    return IntakeCommitmentDraft(
      key: key ?? this.key,
      title: title ?? this.title,
      location:
          identical(location, _unset) ? this.location : location as String?,
      weekday: identical(weekday, _unset) ? this.weekday : weekday as int?,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      validFrom: identical(validFrom, _unset)
          ? this.validFrom
          : validFrom as DateTime?,
      validUntil: identical(validUntil, _unset)
          ? this.validUntil
          : validUntil as DateTime?,
      status: status ?? this.status,
    );
  }
}

class IntakeReminderPreference {
  const IntakeReminderPreference({
    required this.enabled,
    this.quietHoursStart,
    this.quietHoursEnd,
  });

  factory IntakeReminderPreference.fromJson(Map<String, dynamic> json) {
    final quietHours = _optionalMap(json['quiet_hours']);
    return IntakeReminderPreference(
      enabled: _requiredBool(json, 'enabled'),
      quietHoursStart: _optionalTime(quietHours?['starts_at']),
      quietHoursEnd: _optionalTime(quietHours?['ends_at']),
    );
  }

  final bool enabled;
  final String? quietHoursStart;
  final String? quietHoursEnd;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (quietHoursStart != null && quietHoursEnd != null)
          'quiet_hours': {
            'starts_at':
                _normalizedTime(quietHoursStart!) ?? quietHoursStart!.trim(),
            'ends_at': _normalizedTime(quietHoursEnd!) ?? quietHoursEnd!.trim(),
          },
      };

  IntakeReminderPreference copyWith({
    bool? enabled,
    Object? quietHoursStart = _unset,
    Object? quietHoursEnd = _unset,
  }) {
    return IntakeReminderPreference(
      enabled: enabled ?? this.enabled,
      quietHoursStart: identical(quietHoursStart, _unset)
          ? this.quietHoursStart
          : quietHoursStart as String?,
      quietHoursEnd: identical(quietHoursEnd, _unset)
          ? this.quietHoursEnd
          : quietHoursEnd as String?,
    );
  }
}

class IntakeResponseDraft {
  const IntakeResponseDraft({
    required this.displayName,
    required this.primaryFocusAreas,
    required this.goals,
    required this.frictionPoints,
    required this.weekdayShape,
    required this.bestEnergyWindow,
    required this.coachingStyle,
    required this.reminderPreference,
    required this.routines,
    required this.fixedCommitments,
    required this.contextNote,
    required this.calendarConnectionIntent,
    this.studySetup,
  });

  const IntakeResponseDraft.empty({this.displayName})
      : primaryFocusAreas = const [],
        goals = const [],
        frictionPoints = const [],
        weekdayShape = null,
        bestEnergyWindow = null,
        coachingStyle = null,
        reminderPreference = null,
        routines = const [],
        fixedCommitments = const [],
        contextNote = null,
        calendarConnectionIntent = null,
        studySetup = null;

  factory IntakeResponseDraft.fromJson(Map<String, dynamic> json) {
    return IntakeResponseDraft(
      displayName: _optionalString(json['display_name']),
      primaryFocusAreas: _stringList(json['primary_focus_areas']),
      goals: _modelList(
        json['goals'],
        modelName: 'goal',
        fromJson: IntakeGoalDraft.fromJson,
      ),
      frictionPoints: _stringList(json['friction_points']),
      weekdayShape: _optionalString(json['weekday_shape']),
      bestEnergyWindow: _optionalString(json['best_energy_window']),
      coachingStyle: _optionalString(json['coaching_style']),
      reminderPreference: json['reminder_preference'] == null
          ? null
          : IntakeReminderPreference.fromJson(
              _requiredMap(json['reminder_preference'], 'reminder_preference'),
            ),
      routines: _modelList(
        json['routines'],
        modelName: 'routine',
        fromJson: IntakeRoutineDraft.fromJson,
      ),
      fixedCommitments: _modelList(
        json['fixed_commitments'],
        modelName: 'fixed commitment',
        fromJson: IntakeCommitmentDraft.fromJson,
      ),
      contextNote: _optionalString(json['context_note']),
      calendarConnectionIntent:
          _optionalString(json['calendar_connection_intent']),
      studySetup: json.containsKey('study_setup')
          ? StudySetupDraft.fromJson(
              _requiredMap(json['study_setup'], 'study_setup'),
            )
          : null,
    );
  }

  final String? displayName;
  final List<String> primaryFocusAreas;
  final List<IntakeGoalDraft> goals;
  final List<String> frictionPoints;
  final String? weekdayShape;
  final String? bestEnergyWindow;
  final String? coachingStyle;
  final IntakeReminderPreference? reminderPreference;
  final List<IntakeRoutineDraft> routines;
  final List<IntakeCommitmentDraft> fixedCommitments;
  final String? contextNote;
  final String? calendarConnectionIntent;
  final StudySetupDraft? studySetup;

  Map<String, dynamic> toJson() {
    if (!hasRequiredAnswers) {
      throw StateError('Required setup answers are incomplete.');
    }
    final errors = validationErrors();
    if (errors.isNotEmpty) {
      throw StateError(errors.first);
    }
    return {
      if (displayName != null && displayName!.trim().isNotEmpty)
        'display_name': displayName!.trim(),
      'primary_focus_areas': primaryFocusAreas,
      'goals': goals.map((goal) => goal.toJson()).toList(growable: false),
      'friction_points': frictionPoints,
      'weekday_shape': weekdayShape,
      'best_energy_window': bestEnergyWindow,
      'coaching_style': coachingStyle,
      'reminder_preference': reminderPreference!.toJson(),
      'routines':
          routines.map((habit) => habit.toJson()).toList(growable: false),
      'fixed_commitments': fixedCommitments
          .map((commitment) => commitment.toJson())
          .toList(growable: false),
      if (contextNote != null && contextNote!.trim().isNotEmpty)
        'context_note': contextNote!.trim(),
      if (calendarConnectionIntent != null &&
          calendarConnectionIntent!.trim().isNotEmpty)
        'calendar_connection_intent': calendarConnectionIntent!.trim(),
      if (studySetup != null && !studySetup!.isEmpty)
        'study_setup': studySetup!.toJson(),
    };
  }

  bool get hasRequiredAnswers =>
      primaryFocusAreas.isNotEmpty &&
      weekdayShape != null &&
      bestEnergyWindow != null &&
      coachingStyle != null &&
      reminderPreference != null;

  IntakeResponseDraft normalized() {
    final normalizedGoals = goals
        .where((goal) => goal.title.trim().isNotEmpty)
        .map(
          (goal) => goal.copyWith(
            key: goal.key.trim(),
            title: goal.title.trim(),
          ),
        )
        .toList(growable: false);
    final normalizedHabits = routines
        .where((habit) => habit.title.trim().isNotEmpty)
        .map(
          (habit) => habit.copyWith(
            key: habit.key.trim(),
            title: habit.title.trim(),
          ),
        )
        .toList(growable: false);
    final normalizedCommitments = fixedCommitments.where((commitment) {
      return commitment.title.trim().isNotEmpty ||
          (commitment.location?.trim().isNotEmpty ?? false) ||
          commitment.weekday != null ||
          commitment.startsAt.trim().isNotEmpty ||
          commitment.endsAt.trim().isNotEmpty;
    }).map((commitment) {
      return commitment.copyWith(
        key: commitment.key.trim(),
        title: commitment.title.trim(),
        location: _optionalString(commitment.location),
        startsAt:
            _normalizedTime(commitment.startsAt) ?? commitment.startsAt.trim(),
        endsAt: _normalizedTime(commitment.endsAt) ?? commitment.endsAt.trim(),
      );
    }).toList(growable: false);

    return copyWith(
      displayName: _optionalString(displayName),
      primaryFocusAreas: _cleanStringList(primaryFocusAreas),
      goals: normalizedGoals,
      frictionPoints: _cleanStringList(frictionPoints),
      weekdayShape: _optionalString(weekdayShape),
      bestEnergyWindow: _optionalString(bestEnergyWindow),
      coachingStyle: _optionalString(coachingStyle),
      routines: normalizedHabits,
      fixedCommitments: normalizedCommitments,
      contextNote: _optionalString(contextNote),
      calendarConnectionIntent: _optionalString(calendarConnectionIntent),
      studySetup: _normalizedStudySetup(studySetup),
    );
  }

  List<String> validationErrors() {
    final draft = normalized();
    final errors = <String>[];
    if (draft.displayName != null && _textLength(draft.displayName!) > 120) {
      errors.add('Display name must be 120 characters or fewer.');
    }
    if (draft.primaryFocusAreas.isEmpty) {
      errors.add('Choose at least one focus area.');
    }
    if (draft.primaryFocusAreas.length > 6) {
      errors.add('Choose no more than six focus areas.');
    }
    if (draft.primaryFocusAreas.any(
      (area) => !_allowedFocusAreas.contains(area),
    )) {
      errors.add('Focus areas must use supported values.');
    }
    if (draft.weekdayShape == null) {
      errors.add('Choose a typical weekday shape.');
    } else if (_textLength(draft.weekdayShape!) > 500) {
      errors.add('Weekday shape must be 500 characters or fewer.');
    }
    if (draft.bestEnergyWindow == null) {
      errors.add('Choose your best energy window.');
    } else if (!_allowedEnergyWindows.contains(draft.bestEnergyWindow)) {
      errors.add('Choose a supported energy window.');
    }
    if (draft.coachingStyle == null) {
      errors.add('Choose a coaching style.');
    } else if (!_allowedCoachingStyles.contains(draft.coachingStyle)) {
      errors.add('Choose a supported coaching style.');
    }
    final reminder = draft.reminderPreference;
    if (reminder == null) {
      errors.add('Choose whether reminders are enabled.');
    } else if (reminder.enabled &&
        (!_isTime(reminder.quietHoursStart) ||
            !_isTime(reminder.quietHoursEnd))) {
      errors.add('Enter quiet hours in HH:mm format.');
    }
    if (draft.goals.length > 3) {
      errors.add('Add no more than three goals.');
    }
    if (draft.frictionPoints.length > 5) {
      errors.add('Add no more than five friction points.');
    }
    if (draft.routines.length > 5) {
      errors.add('Add no more than five routines.');
    }
    if (draft.fixedCommitments.length > 10) {
      errors.add('Add no more than ten fixed commitments.');
    }
    if (draft.contextNote != null && _textLength(draft.contextNote!) > 1000) {
      errors.add('Context note must be 1000 characters or fewer.');
    }
    if (draft.calendarConnectionIntent != null &&
        !_allowedCalendarIntents.contains(draft.calendarConnectionIntent)) {
      errors.add('Choose a supported calendar connection intent.');
    }
    final study = draft.studySetup;
    final rhythm = study?.focusRhythm;
    if (rhythm != null) {
      if (rhythm.focusMinutes < 25 ||
          rhythm.focusMinutes > 180 ||
          rhythm.focusMinutes % 5 != 0) {
        errors.add('Focus rhythm must be 25–180 minutes in five-minute steps.');
      }
      if (rhythm.recoveryMinutes < 5 ||
          rhythm.recoveryMinutes > 60 ||
          rhythm.recoveryMinutes % 5 != 0) {
        errors.add('Recovery must be 5–60 minutes in five-minute steps.');
      }
      if (rhythm.preparationItems.length > 12) {
        errors.add('Add no more than twelve preparation items.');
      }
      final ritualKeys = <String>{};
      final ritualLabels = <String>{};
      for (final item in rhythm.preparationItems) {
        if (!isCanonicalStudyUuid(item.key) ||
            !ritualKeys.add(item.key.toLowerCase())) {
          errors.add('Preparation items need unique UUID keys.');
          break;
        }
        final label = item.label.trim();
        if (label.isEmpty ||
            _textLength(label) > 120 ||
            !ritualLabels.add(label.toLowerCase())) {
          errors.add(
            'Preparation item labels must be unique and 120 characters or fewer.',
          );
          break;
        }
      }
    }
    final semesters = study?.semesterPlanning;
    if (semesters != null) {
      final current = semesters.currentSemester;
      final next = semesters.nextSemester;
      if (current.name.trim().isEmpty ||
          next.name.trim().isEmpty ||
          _textLength(current.name.trim()) > 120 ||
          _textLength(next.name.trim()) > 120 ||
          current.startsOn == null ||
          current.endsOn == null ||
          next.startsOn == null ||
          next.endsOn == null ||
          next.courseSelectionStartsOn == null ||
          next.courseSelectionEndsOn == null) {
        errors.add('Complete both semesters and the course selection window.');
      } else if (current.endsOn!.isBefore(current.startsOn!) ||
          !next.startsOn!.isAfter(current.endsOn!) ||
          next.endsOn!.isBefore(next.startsOn!) ||
          next.courseSelectionEndsOn!.isBefore(next.courseSelectionStartsOn!)) {
        errors.add('Semester and course selection dates are out of order.');
      }
      if (next.courseNames.length > 12 ||
          next.courseNames.any(
            (name) => name.trim().isEmpty || _textLength(name.trim()) > 120,
          ) ||
          next.courseNames
                  .map((name) => name.trim().toLowerCase())
                  .toSet()
                  .length !=
              next.courseNames.length) {
        errors.add('Course names must be unique and limited to twelve.');
      }
    }
    for (final goal in draft.goals) {
      if (_textLength(goal.title) > 200) {
        errors.add('Goal titles must be 200 characters or fewer.');
        break;
      }
    }
    _validateUniqueKeys(
      draft.goals.map((goal) => goal.key),
      'goal',
      errors,
    );
    _validateUniqueKeys(
      draft.routines.map((habit) => habit.key),
      'routine',
      errors,
    );
    _validateUniqueKeys(
      draft.fixedCommitments.map((commitment) => commitment.key),
      'commitment',
      errors,
    );
    final allKeys = [
      ...draft.goals.map((goal) => goal.key),
      ...draft.routines.map((routine) => routine.key),
      ...draft.fixedCommitments.map((commitment) => commitment.key),
      ...?draft.studySetup?.focusRhythm?.preparationItems.map(
        (item) => item.key,
      ),
    ];
    if (allKeys.map((key) => key.toLowerCase()).toSet().length !=
        allKeys.length) {
      errors.add('Setup item keys must be unique across all item types.');
    }
    for (final routine in draft.routines) {
      if (_textLength(routine.title) > 200) {
        errors.add('Routine titles must be 200 characters or fewer.');
      }
      if (!routine.cadenceConfirmed &&
          (routine.frequency != null || routine.target != null)) {
        errors.add('An unconfirmed routine must not carry cadence values.');
      }
      if (routine.cadenceConfirmed &&
          (!const {'daily', 'weekly'}.contains(routine.frequency) ||
              routine.target == null ||
              routine.target! < 1)) {
        errors.add(
          'A confirmed routine requires a daily or weekly cadence and target.',
        );
      }
      if (routine.status.requiresCadence &&
          (!routine.cadenceConfirmed ||
              !const {'daily', 'weekly'}.contains(routine.frequency) ||
              routine.target == null ||
              routine.target! < 1)) {
        errors.add(
          'Confirm a daily or weekly cadence before activating '
          '"${routine.title}".',
        );
      }
      if (routine.cadenceConfirmed &&
          routine.frequency == 'daily' &&
          routine.target != 1) {
        errors.add('A daily routine must have a target of 1.');
      }
      if (routine.cadenceConfirmed &&
          routine.frequency == 'weekly' &&
          (routine.target == null ||
              routine.target! < 1 ||
              routine.target! > 7)) {
        errors.add('A weekly routine target must be between 1 and 7.');
      }
    }
    for (final commitment in draft.fixedCommitments) {
      if (_textLength(commitment.title) > 120) {
        errors.add('Commitment titles must be 120 characters or fewer.');
      }
      if (commitment.location != null &&
          _textLength(commitment.location!) > 120) {
        errors.add('Commitment locations must be 120 characters or fewer.');
      }
      if (commitment.title.isEmpty ||
          commitment.weekday == null ||
          !_isTime(commitment.startsAt) ||
          !_isTime(commitment.endsAt) ||
          commitment.endsAt.compareTo(commitment.startsAt) <= 0) {
        errors.add(
          'Complete title, weekday, and valid start/end times for every '
          'fixed commitment.',
        );
        break;
      }
      if (commitment.validFrom != null &&
          commitment.validUntil != null &&
          commitment.validUntil!.isBefore(commitment.validFrom!)) {
        errors.add(
          'A fixed commitment end date cannot be before its start date.',
        );
        break;
      }
    }
    return errors;
  }

  IntakeResponseDraft copyWith({
    Object? displayName = _unset,
    List<String>? primaryFocusAreas,
    List<IntakeGoalDraft>? goals,
    List<String>? frictionPoints,
    Object? weekdayShape = _unset,
    Object? bestEnergyWindow = _unset,
    Object? coachingStyle = _unset,
    Object? reminderPreference = _unset,
    List<IntakeRoutineDraft>? routines,
    List<IntakeCommitmentDraft>? fixedCommitments,
    Object? contextNote = _unset,
    Object? calendarConnectionIntent = _unset,
    Object? studySetup = _unset,
  }) {
    return IntakeResponseDraft(
      displayName: identical(displayName, _unset)
          ? this.displayName
          : displayName as String?,
      primaryFocusAreas: primaryFocusAreas ?? this.primaryFocusAreas,
      goals: goals ?? this.goals,
      frictionPoints: frictionPoints ?? this.frictionPoints,
      weekdayShape: identical(weekdayShape, _unset)
          ? this.weekdayShape
          : weekdayShape as String?,
      bestEnergyWindow: identical(bestEnergyWindow, _unset)
          ? this.bestEnergyWindow
          : bestEnergyWindow as String?,
      coachingStyle: identical(coachingStyle, _unset)
          ? this.coachingStyle
          : coachingStyle as String?,
      reminderPreference: identical(reminderPreference, _unset)
          ? this.reminderPreference
          : reminderPreference as IntakeReminderPreference?,
      routines: routines ?? this.routines,
      fixedCommitments: fixedCommitments ?? this.fixedCommitments,
      contextNote: identical(contextNote, _unset)
          ? this.contextNote
          : contextNote as String?,
      calendarConnectionIntent: identical(calendarConnectionIntent, _unset)
          ? this.calendarConnectionIntent
          : calendarConnectionIntent as String?,
      studySetup: identical(studySetup, _unset)
          ? this.studySetup
          : studySetup as StudySetupDraft?,
    );
  }
}

class IntakeSetupSaveRequest {
  const IntakeSetupSaveRequest({
    required this.requestId,
    required this.baseRevision,
    required this.responses,
  });

  factory IntakeSetupSaveRequest.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 'intake-v1') {
      throw FormatException('Unsupported intake version: ${json['version']}');
    }
    final requestId = _requiredString(json, 'request_id');
    if (!isSetupUuid(requestId)) {
      throw const FormatException('Setup request_id must be a UUID.');
    }
    return IntakeSetupSaveRequest(
      requestId: requestId,
      baseRevision: _intValue(json['base_revision'], field: 'base_revision')!,
      responses: IntakeResponseDraft.fromJson(
        _requiredMap(json['responses'], 'responses'),
      ),
    );
  }

  final String requestId;
  final int baseRevision;
  final IntakeResponseDraft responses;

  Map<String, dynamic> toJson() {
    final normalizedRequestId = requestId.trim();
    if (!isSetupUuid(normalizedRequestId)) {
      throw StateError('Setup request_id must be a UUID.');
    }
    if (baseRevision < 0) {
      throw StateError('Setup base_revision must not be negative.');
    }
    return {
      'version': 'intake-v1',
      'request_id': normalizedRequestId,
      'base_revision': baseRevision,
      'responses': responses.normalized().toJson(),
    };
  }

  IntakeSetupSaveRequest copyWith({
    String? requestId,
    int? baseRevision,
    IntakeResponseDraft? responses,
  }) {
    return IntakeSetupSaveRequest(
      requestId: requestId ?? this.requestId,
      baseRevision: baseRevision ?? this.baseRevision,
      responses: responses ?? this.responses,
    );
  }
}

class IntakeSetupReadState {
  const IntakeSetupReadState({
    required this.exists,
    required this.revision,
    required this.baseRevision,
    required this.requestId,
    required this.status,
    required this.intakeResponseId,
    required this.snapshotId,
    required this.completedAt,
    required this.responses,
    required this.summary,
  });

  const IntakeSetupReadState.empty()
      : exists = false,
        revision = 0,
        baseRevision = 0,
        requestId = null,
        status = 'not_started',
        intakeResponseId = null,
        snapshotId = null,
        completedAt = null,
        responses = null,
        summary = const {};

  factory IntakeSetupReadState.fromJson(Map<String, dynamic> json) {
    final exists = _requiredBool(json, 'exists');
    final rawResponses = json['responses'];
    if (exists && rawResponses == null) {
      throw const FormatException('Existing setup is missing responses.');
    }
    final requestId = _optionalString(json['request_id']);
    if (requestId != null && !isSetupUuid(requestId)) {
      throw const FormatException('Setup request_id must be a UUID.');
    }
    return IntakeSetupReadState(
      exists: exists,
      revision: _intValue(json['revision'], field: 'revision') ?? 0,
      baseRevision:
          _intValue(json['base_revision'], field: 'base_revision') ?? 0,
      requestId: requestId,
      status: _optionalString(json['status']),
      intakeResponseId: _optionalString(json['intake_response_id']),
      snapshotId: _optionalString(json['snapshot_id']),
      completedAt: _optionalDateTime(json['completed_at']),
      responses: rawResponses == null
          ? null
          : IntakeResponseDraft.fromJson(
              _requiredMap(rawResponses, 'responses'),
            ),
      summary: _optionalMap(json['summary']) ?? const {},
    );
  }

  final bool exists;
  final int revision;
  final int baseRevision;
  final String? requestId;
  final String? status;
  final String? intakeResponseId;
  final String? snapshotId;
  final DateTime? completedAt;
  final IntakeResponseDraft? responses;
  final Map<String, dynamic> summary;

  Map<String, dynamic> toJson() => {
        'exists': exists,
        'revision': revision,
        'base_revision': baseRevision,
        'request_id': requestId,
        'status': status,
        'intake_response_id': intakeResponseId,
        'snapshot_id': snapshotId,
        'completed_at': completedAt?.toUtc().toIso8601String(),
        'responses': responses?.toJson(),
        'summary': summary,
      };

  IntakeSetupReadState copyWith({
    bool? exists,
    int? revision,
    int? baseRevision,
    Object? requestId = _unset,
    Object? status = _unset,
    Object? intakeResponseId = _unset,
    Object? snapshotId = _unset,
    Object? completedAt = _unset,
    Object? responses = _unset,
    Map<String, dynamic>? summary,
  }) {
    return IntakeSetupReadState(
      exists: exists ?? this.exists,
      revision: revision ?? this.revision,
      baseRevision: baseRevision ?? this.baseRevision,
      requestId:
          identical(requestId, _unset) ? this.requestId : requestId as String?,
      status: identical(status, _unset) ? this.status : status as String?,
      intakeResponseId: identical(intakeResponseId, _unset)
          ? this.intakeResponseId
          : intakeResponseId as String?,
      snapshotId: identical(snapshotId, _unset)
          ? this.snapshotId
          : snapshotId as String?,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as DateTime?,
      responses: identical(responses, _unset)
          ? this.responses
          : responses as IntakeResponseDraft?,
      summary: summary ?? this.summary,
    );
  }
}

String generateSetupUuid({Random? random}) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex =
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

IntakeResponseDraft repairSetupItemKeys(IntakeResponseDraft draft) {
  final seen = <String>{};

  String repairedKey(String key) {
    final trimmed = key.trim();
    if (isSetupUuid(trimmed) && seen.add(trimmed.toLowerCase())) {
      return trimmed;
    }
    late String generated;
    do {
      generated = generateSetupUuid();
    } while (!seen.add(generated));
    return generated;
  }

  String repairedStudyKey(String key) {
    final trimmed = key.trim();
    if (isCanonicalStudyUuid(trimmed) && seen.add(trimmed.toLowerCase())) {
      return trimmed;
    }
    late String generated;
    do {
      generated = generateSetupUuid();
    } while (!seen.add(generated));
    return generated;
  }

  return draft.copyWith(
    goals: draft.goals
        .map((goal) => goal.copyWith(key: repairedKey(goal.key)))
        .toList(growable: false),
    routines: draft.routines
        .map((routine) => routine.copyWith(key: repairedKey(routine.key)))
        .toList(growable: false),
    fixedCommitments: draft.fixedCommitments
        .map(
          (commitment) => commitment.copyWith(
            key: repairedKey(commitment.key),
          ),
        )
        .toList(growable: false),
    studySetup: draft.studySetup?.focusRhythm == null
        ? draft.studySetup
        : draft.studySetup!.copyWith(
            focusRhythm: draft.studySetup!.focusRhythm!.copyWith(
              preparationItems: draft.studySetup!.focusRhythm!.preparationItems
                  .map(
                    (item) => item.copyWith(key: repairedStudyKey(item.key)),
                  )
                  .toList(growable: false),
            ),
          ),
  );
}

StudySetupDraft? _normalizedStudySetup(StudySetupDraft? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final focus = value.focusRhythm;
  final semesters = value.semesterPlanning;
  return value.copyWith(
    focusRhythm: focus?.copyWith(
      preparationItems: focus.preparationItems
          .where((item) => item.label.trim().isNotEmpty)
          .map(
            (item) => item.copyWith(
              key: item.key.trim(),
              label: item.label.trim(),
            ),
          )
          .toList(growable: false),
    ),
    semesterPlanning: semesters?.copyWith(
      currentSemester: semesters.currentSemester.copyWith(
        name: semesters.currentSemester.name.trim(),
      ),
      nextSemester: semesters.nextSemester.copyWith(
        name: semesters.nextSemester.name.trim(),
        courseNames: _cleanStringList(semesters.nextSemester.courseNames),
      ),
    ),
  );
}

bool isSetupUuid(String value) {
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}

bool isCanonicalStudyUuid(String value) {
  return RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-'
    r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(value);
}

const Object _unset = Object();

String _requiredString(Map<String, dynamic> json, String field) {
  final value = _optionalString(json[field]);
  if (value == null) {
    throw FormatException('Missing non-empty $field.');
  }
  return value;
}

String _requiredTime(Map<String, dynamic> json, String field) {
  final value = _requiredString(json, field);
  return _normalizedTime(value) ?? value;
}

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Expected a string, got ${value.runtimeType}.');
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _optionalTime(Object? value) {
  final text = _optionalString(value);
  if (text == null) {
    return null;
  }
  return _normalizedTime(text) ?? text;
}

bool _requiredBool(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! bool) {
    throw FormatException('Expected a boolean $field.');
  }
  return value;
}

int? _intValue(Object? value, {required String field}) {
  if (value == null) {
    return null;
  }
  if (value is num && value.toInt() == value) {
    return value.toInt();
  }
  throw FormatException('Expected an integer $field.');
}

int _requiredExactInt(Object? value, String field) {
  if (value is! int) {
    throw FormatException('Expected an exact integer $field.');
  }
  return value;
}

String _requiredExactText(Object? value, String field, int maxLength) {
  if (value is! String ||
      value.isEmpty ||
      value != value.trim() ||
      _textLength(value) > maxLength) {
    throw FormatException('Invalid exact text $field.');
  }
  return value;
}

DateTime _requiredCalendarDate(Object? value, String field) {
  final parsed = _optionalCalendarDate(value);
  if (parsed == null) {
    throw FormatException('Missing calendar date $field.');
  }
  return parsed;
}

List<String> _exactTextList(
  Object? value,
  String field, {
  required int maxItems,
  required int maxLength,
}) {
  if (value is! List || value.length > maxItems) {
    throw FormatException('Invalid list $field.');
  }
  return value
      .map((item) => _requiredExactText(item, field, maxLength))
      .toList(growable: false);
}

void _expectExactKeys(
  Map<String, dynamic> json,
  Set<String> allowed,
  String label, {
  Set<String> optional = const {},
}) {
  final keys = json.keys.toSet();
  final required = allowed.difference(optional);
  if (!allowed.containsAll(keys) || !keys.containsAll(required)) {
    throw FormatException('$label has an invalid field set.');
  }
}

DateTime? _optionalDateTime(Object? value) {
  final text = _optionalString(value);
  if (text == null) {
    return null;
  }
  final date = DateTime.tryParse(text);
  if (date == null) {
    throw FormatException('Invalid date-time: $text');
  }
  return date;
}

DateTime? _optionalCalendarDate(Object? value) {
  final text = _optionalString(value);
  if (text == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    if (text == null) return null;
    throw FormatException('Invalid calendar date: $text');
  }
  final parsed = DateTime.tryParse('${text}T00:00:00Z');
  if (parsed == null || _calendarDate(parsed) != text) {
    throw FormatException('Invalid calendar date: $text');
  }
  return parsed;
}

String _calendarDate(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

Map<String, dynamic> _requiredMap(Object? value, String field) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw FormatException('Expected an object $field.');
}

Map<String, dynamic>? _optionalMap(Object? value) {
  if (value == null) {
    return null;
  }
  return _requiredMap(value, 'value');
}

List<String> _stringList(Object? value) {
  if (value == null) {
    return const [];
  }
  if (value is! List) {
    throw const FormatException('Expected a list of strings.');
  }
  return value.map((item) {
    if (item is! String || item.trim().isEmpty) {
      throw const FormatException('Expected non-empty list strings.');
    }
    return item.trim();
  }).toList(growable: false);
}

List<T> _modelList<T>(
  Object? value, {
  required String modelName,
  required T Function(Map<String, dynamic>) fromJson,
}) {
  if (value == null) {
    return const [];
  }
  if (value is! List) {
    throw FormatException('Expected a list of $modelName objects.');
  }
  return value
      .map((item) => fromJson(_requiredMap(item, modelName)))
      .toList(growable: false);
}

List<String> _cleanStringList(Iterable<String> values) {
  final result = <String>[];
  final seen = <String>{};
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty && seen.add(trimmed)) {
      result.add(trimmed);
    }
  }
  return List.unmodifiable(result);
}

bool _isTime(String? value) {
  if (value == null ||
      !RegExp(r'^\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?$').hasMatch(value)) {
    return false;
  }
  final parts = value.split(':');
  final hour = int.parse(parts[0]);
  final minute = int.parse(parts[1]);
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}

String? _normalizedTime(String value) {
  if (!_isTime(value)) {
    return null;
  }
  return value.substring(0, 5);
}

int _textLength(String value) => value.runes.length;

void _validateUniqueKeys(
  Iterable<String> keys,
  String kind,
  List<String> errors,
) {
  final seen = <String>{};
  for (final key in keys) {
    if (!isSetupUuid(key)) {
      errors.add('Every $kind requires a valid UUID key.');
      return;
    }
    if (!seen.add(key.toLowerCase())) {
      errors.add('Every $kind requires a unique stable key.');
      return;
    }
  }
}
