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
      status: IntakeCommitmentStatus.fromJson(json['status']),
    );
  }

  final String key;
  final String title;
  final String? location;
  final int? weekday;
  final String startsAt;
  final String endsAt;
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
        calendarConnectionIntent = null;

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
  );
}

bool isSetupUuid(String value) {
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
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
