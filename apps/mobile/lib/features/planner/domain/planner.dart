class PlannerContractException implements Exception {
  const PlannerContractException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PlannerAccessException implements Exception {
  const PlannerAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PlannerPreferences {
  const PlannerPreferences({
    required this.useCalendarBusyTime,
    required this.updatedAt,
    required this.currentCalendarImportId,
    required this.calendarAvailable,
  });

  factory PlannerPreferences.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      const {
        'contract_version',
        'origin',
        'use_calendar_busy_time',
        'updated_at',
        'current_calendar_import_id',
        'calendar_available',
      },
      'Planner preferences',
    );
    _expectEnvelope(
      json,
      contractVersion: 'planner-preferences-v1',
      label: 'Planner preferences',
    );
    final calendarAvailable =
        _bool(json['calendar_available'], 'calendar_available');
    final importId = _optionalUuid(
      json['current_calendar_import_id'],
      'current_calendar_import_id',
    );
    if (calendarAvailable != (importId != null)) {
      throw const PlannerContractException(
        'Planner calendar availability is inconsistent.',
      );
    }
    return PlannerPreferences(
      useCalendarBusyTime: _bool(
        json['use_calendar_busy_time'],
        'use_calendar_busy_time',
      ),
      updatedAt: _optionalDateTime(json['updated_at'], 'updated_at'),
      currentCalendarImportId: importId,
      calendarAvailable: calendarAvailable,
    );
  }

  final bool useCalendarBusyTime;
  final DateTime? updatedAt;
  final String? currentCalendarImportId;
  final bool calendarAvailable;
}

class PlannerAttention {
  const PlannerAttention({
    required this.id,
    required this.kind,
    required this.title,
    required this.detail,
    required this.planId,
    required this.unplacedMinutes,
  });

  factory PlannerAttention.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      const {
        'id',
        'kind',
        'title',
        'detail',
        'plan_id',
        'unplaced_minutes',
      },
      'Planner attention',
    );
    return PlannerAttention(
      id: _text(json['id'], 'attention.id', max: 200),
      kind: _enumText(
        json['kind'],
        'attention.kind',
        const {'conflict', 'unscheduled', 'stale_preview'},
      ),
      title: _text(json['title'], 'attention.title', max: 160),
      detail: _text(json['detail'], 'attention.detail', max: 240),
      planId: _optionalUuid(json['plan_id'], 'attention.plan_id'),
      unplacedMinutes: _int(
        json['unplaced_minutes'],
        'attention.unplaced_minutes',
        min: 0,
      ),
    );
  }

  final String id;
  final String kind;
  final String title;
  final String detail;
  final String? planId;
  final int unplacedMinutes;
}

class PlannerDayItem {
  const PlannerDayItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.sourceId,
    required this.startsAt,
    required this.endsAt,
    required this.allDay,
    required this.state,
  });

  factory PlannerDayItem.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      const {
        'id',
        'kind',
        'title',
        'source_id',
        'starts_at',
        'ends_at',
        'all_day',
        'state',
      },
      'Planner day item',
    );
    final allDay = _bool(json['all_day'], 'day item all_day');
    final starts = _optionalDateTime(json['starts_at'], 'day item starts_at');
    final ends = _optionalDateTime(json['ends_at'], 'day item ends_at');
    if (allDay
        ? starts != null || ends != null
        : starts == null || ends == null) {
      throw const PlannerContractException(
        'Planner day item interval is inconsistent.',
      );
    }
    if (!allDay && !ends!.isAfter(starts!)) {
      throw const PlannerContractException(
        'Planner day item interval is invalid.',
      );
    }
    return PlannerDayItem(
      id: _uuid(json['id'], 'day item id'),
      kind: _enumText(json['kind'], 'day item kind', const {
        'setup_commitment',
        'manual_commitment',
        'task_block',
        'habit_slot',
        'preparation',
        'calendar_event',
      }),
      title: _text(json['title'], 'day item title', max: 200),
      sourceId: _uuid(json['source_id'], 'day item source_id'),
      startsAt: starts,
      endsAt: ends,
      allDay: allDay,
      state: _optionalText(json['state'], 'day item state', max: 40),
    );
  }

  final String id;
  final String kind;
  final String title;
  final String sourceId;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool allDay;
  final String? state;
}

class PlannerDay {
  const PlannerDay({required this.localDate, required this.items});

  factory PlannerDay.fromJson(Map<String, dynamic> json) {
    _expectKeys(json, const {'local_date', 'items'}, 'Planner day');
    final items = _objects(json['items'], 'Planner day items')
        .map(PlannerDayItem.fromJson)
        .toList(growable: false);
    if (items.length > 1500) {
      throw const PlannerContractException('Planner day is too large.');
    }
    return PlannerDay(
      localDate: _date(json['local_date'], 'day local_date'),
      items: items,
    );
  }

  final DateTime localDate;
  final List<PlannerDayItem> items;
}

class PlannerPreparation {
  const PlannerPreparation({
    required this.planId,
    required this.title,
    required this.status,
    required this.remainingMinutes,
    required this.nextBlockStartsAt,
    required this.hasPendingPreview,
  });

  factory PlannerPreparation.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      const {
        'plan_id',
        'title',
        'status',
        'remaining_minutes',
        'next_block_starts_at',
        'has_pending_preview',
      },
      'Planner preparation',
    );
    return PlannerPreparation(
      planId: _uuid(json['plan_id'], 'preparation plan_id'),
      title: _text(json['title'], 'preparation title', max: 160),
      status: _enumText(
        json['status'],
        'preparation status',
        const {'draft', 'active', 'completed', 'cancelled'},
      ),
      remainingMinutes: _int(
        json['remaining_minutes'],
        'preparation remaining_minutes',
        min: 0,
      ),
      nextBlockStartsAt: _optionalDateTime(
        json['next_block_starts_at'],
        'preparation next_block_starts_at',
      ),
      hasPendingPreview: _bool(
        json['has_pending_preview'],
        'preparation has_pending_preview',
      ),
    );
  }

  final String planId;
  final String title;
  final String status;
  final int remainingMinutes;
  final DateTime? nextBlockStartsAt;
  final bool hasPendingPreview;
}

class PlannerUnscheduled {
  const PlannerUnscheduled({
    required this.id,
    required this.kind,
    required this.title,
    required this.reason,
    required this.expectedUpdatedAt,
    required this.description,
    required this.priority,
    required this.estimatedMinutes,
    required this.deadlineAt,
    required this.preferredSessionMinutes,
    required this.cadenceKind,
    required this.scheduledWeekdays,
    required this.weeklyTarget,
    required this.durationMinutes,
  });

  factory PlannerUnscheduled.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      const {
        'id',
        'kind',
        'title',
        'reason',
        'expected_updated_at',
        'description',
        'priority',
        'estimated_minutes',
        'deadline_at',
        'preferred_session_minutes',
        'cadence',
        'duration_minutes',
      },
      'Unscheduled item',
    );
    final kind =
        _enumText(json['kind'], 'unscheduled kind', const {'task', 'habit'});
    final priority = json['priority'] == null
        ? null
        : _enumText(
            json['priority'],
            'unscheduled priority',
            const {'low', 'medium', 'high', 'critical'},
          );
    final estimated = _optionalInt(
      json['estimated_minutes'],
      'unscheduled estimated_minutes',
      min: 5,
      max: 480,
    );
    final deadline = _optionalDateTime(
      json['deadline_at'],
      'unscheduled deadline_at',
    );
    final session = _optionalInt(
      json['preferred_session_minutes'],
      'unscheduled preferred_session_minutes',
      min: 5,
      max: 240,
    );
    final duration = _optionalInt(
      json['duration_minutes'],
      'unscheduled duration_minutes',
      min: 5,
      max: 240,
    );
    String? cadenceKind;
    var scheduledWeekdays = const <int>[];
    int? weeklyTarget;
    final rawCadence = json['cadence'];
    if (rawCadence != null) {
      final cadence = _object(rawCadence, 'unscheduled cadence');
      _expectKeys(
        cadence,
        const {'kind', 'scheduled_weekdays', 'weekly_target'},
        'unscheduled cadence',
      );
      cadenceKind = _enumText(
        cadence['kind'],
        'unscheduled cadence kind',
        const {'daily', 'weekdays', 'weekly_target'},
      );
      scheduledWeekdays = _integers(
        cadence['scheduled_weekdays'],
        'unscheduled cadence weekdays',
        min: 1,
        max: 7,
      );
      weeklyTarget = _int(
        cadence['weekly_target'],
        'unscheduled cadence target',
        min: 1,
        max: 7,
      );
      if (scheduledWeekdays.toSet().length != scheduledWeekdays.length ||
          (cadenceKind == 'daily' &&
              (scheduledWeekdays.isNotEmpty || weeklyTarget != 1)) ||
          (cadenceKind == 'weekdays' &&
              (scheduledWeekdays.isEmpty || weeklyTarget != 1)) ||
          (cadenceKind == 'weekly_target' && scheduledWeekdays.isNotEmpty)) {
        throw const PlannerContractException(
          'Unscheduled Habit cadence is invalid.',
        );
      }
    }
    if (session != null && session % 5 != 0 ||
        duration != null && duration % 5 != 0 ||
        kind == 'task' &&
            (priority == null || cadenceKind != null || duration != null) ||
        kind == 'habit' &&
            (priority != null ||
                estimated != null ||
                deadline != null ||
                session != null ||
                cadenceKind == null)) {
      throw const PlannerContractException(
        'Unscheduled target projection is inconsistent.',
      );
    }
    return PlannerUnscheduled(
      id: _uuid(json['id'], 'unscheduled id'),
      kind: kind,
      title: _text(json['title'], 'unscheduled title', max: 160),
      reason: _enumText(json['reason'], 'unscheduled reason', const {
        'not_planned',
        'released',
        'missing_scheduling_inputs',
      }),
      expectedUpdatedAt: _optionalDateTime(
        json['expected_updated_at'],
        'unscheduled expected_updated_at',
      ),
      description: _optionalText(
        json['description'],
        'unscheduled description',
        max: 2000,
      ),
      priority: priority,
      estimatedMinutes: estimated,
      deadlineAt: deadline,
      preferredSessionMinutes: session,
      cadenceKind: cadenceKind,
      scheduledWeekdays: scheduledWeekdays,
      weeklyTarget: weeklyTarget,
      durationMinutes: duration,
    );
  }

  final String id;
  final String kind;
  final String title;
  final String reason;
  final DateTime? expectedUpdatedAt;
  final String? description;
  final String? priority;
  final int? estimatedMinutes;
  final DateTime? deadlineAt;
  final int? preferredSessionMinutes;
  final String? cadenceKind;
  final List<int> scheduledWeekdays;
  final int? weeklyTarget;
  final int? durationMinutes;
}

class PlannerTaskBlock {
  const PlannerTaskBlock({
    required this.id,
    required this.sequence,
    required this.startsAt,
    required this.endsAt,
    required this.localDate,
    required this.plannedMinutes,
    required this.state,
  });

  factory PlannerTaskBlock.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      const {
        'id',
        'sequence',
        'starts_at',
        'ends_at',
        'local_date',
        'planned_minutes',
        'state',
      },
      'Planner Task block',
    );
    final starts = _dateTime(json['starts_at'], 'Task block starts_at');
    final ends = _dateTime(json['ends_at'], 'Task block ends_at');
    final plannedMinutes = _int(
      json['planned_minutes'],
      'Task block planned_minutes',
      min: 5,
      max: 240,
    );
    if (!ends.isAfter(starts) ||
        plannedMinutes % 5 != 0 ||
        ends.difference(starts) != Duration(minutes: plannedMinutes)) {
      throw const PlannerContractException('Planner Task block is invalid.');
    }
    return PlannerTaskBlock(
      id: _uuid(json['id'], 'Task block id'),
      sequence: _int(json['sequence'], 'Task block sequence', min: 1),
      startsAt: starts,
      endsAt: ends,
      localDate: _date(json['local_date'], 'Task block local_date'),
      plannedMinutes: plannedMinutes,
      state: _enumText(json['state'], 'Task block state', const {
        'proposed',
        'active',
        'released',
        'superseded',
      }),
    );
  }

  final String id;
  final int sequence;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime localDate;
  final int plannedMinutes;
  final String state;
}

class PlannerHabitSlot {
  const PlannerHabitSlot({
    required this.id,
    required this.weekday,
    required this.startsAt,
    required this.endsAt,
    required this.durationMinutes,
    required this.state,
  });

  factory PlannerHabitSlot.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      const {
        'id',
        'weekday',
        'starts_at',
        'ends_at',
        'duration_minutes',
        'state',
      },
      'Planner Habit slot',
    );
    final starts = _time(json['starts_at'], 'Habit slot starts_at');
    final ends = _time(json['ends_at'], 'Habit slot ends_at');
    final duration = _int(
      json['duration_minutes'],
      'Habit slot duration_minutes',
      min: 5,
      max: 240,
    );
    if (duration % 5 != 0 ||
        _timeMinutes(ends) - _timeMinutes(starts) != duration) {
      throw const PlannerContractException('Planner Habit slot is invalid.');
    }
    return PlannerHabitSlot(
      id: _uuid(json['id'], 'Habit slot id'),
      weekday: _int(json['weekday'], 'Habit slot weekday', min: 1, max: 7),
      startsAt: starts,
      endsAt: ends,
      durationMinutes: duration,
      state: _enumText(json['state'], 'Habit slot state', const {
        'proposed',
        'active',
        'released',
        'superseded',
      }),
    );
  }

  final String id;
  final int weekday;
  final String startsAt;
  final String endsAt;
  final int durationMinutes;
  final String state;
}

class PlannerRevision {
  const PlannerRevision({
    required this.revision,
    required this.state,
    required this.targetKind,
    required this.targetOperation,
    required this.targetId,
    required this.targetTitle,
    required this.plannedMinutes,
    required this.unscheduledMinutes,
    required this.calendarImportId,
    required this.taskBlocks,
    required this.habitSlots,
  });

  factory PlannerRevision.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      const {
        'revision',
        'base_revision',
        'state',
        'target',
        'timezone',
        'best_energy_window',
        'planning_start_on',
        'planning_fingerprint',
        'calendar_import_id',
        'planned_minutes',
        'unscheduled_minutes',
        'task_blocks',
        'habit_slots',
        'created_at',
        'activated_at',
        'superseded_at',
      },
      'Planner revision',
    );
    final target = _plannerTarget(_object(json['target'], 'Planner target'));
    final revision = _int(json['revision'], 'revision', min: 1, max: 500);
    final baseRevision = _int(
      json['base_revision'],
      'base_revision',
      min: 0,
      max: 499,
    );
    final state = _enumText(
      json['state'],
      'revision state',
      const {'proposed', 'active', 'superseded'},
    );
    final createdAt = _dateTime(json['created_at'], 'created_at');
    final activatedAt = _optionalDateTime(
      json['activated_at'],
      'activated_at',
    );
    final supersededAt = _optionalDateTime(
      json['superseded_at'],
      'superseded_at',
    );
    final blocks = _objects(json['task_blocks'], 'Planner Task blocks')
        .map(PlannerTaskBlock.fromJson)
        .toList(growable: false);
    final slots = _objects(json['habit_slots'], 'Planner Habit slots')
        .map(PlannerHabitSlot.fromJson)
        .toList(growable: false);
    final plannedMinutes = _int(
      json['planned_minutes'],
      'planned_minutes',
      min: 0,
    );
    final expectedMinutes = target.kind == 'task'
        ? blocks.fold(0, (sum, value) => sum + value.plannedMinutes)
        : slots.fold(0, (sum, value) => sum + value.durationMinutes);
    final childStates = [
      ...blocks.map((value) => value.state),
      ...slots.map((value) => value.state),
    ];
    final expectedChildState = state == 'proposed' ? 'proposed' : state;
    if (revision != baseRevision + 1 ||
        blocks.length > 1500 ||
        slots.length > 7 ||
        (target.kind == 'task' ? slots.isNotEmpty : blocks.isNotEmpty) ||
        blocks.map((value) => value.id).toSet().length != blocks.length ||
        blocks.map((value) => value.sequence).toSet().length != blocks.length ||
        slots.map((value) => value.id).toSet().length != slots.length ||
        slots.map((value) => value.weekday).toSet().length != slots.length ||
        plannedMinutes != expectedMinutes ||
        childStates.any((value) => value != expectedChildState) ||
        (state == 'proposed' &&
            (activatedAt != null || supersededAt != null)) ||
        (state == 'active' && (activatedAt == null || supersededAt != null)) ||
        (state == 'superseded' && supersededAt == null)) {
      throw const PlannerContractException(
        'Planner revision target is inconsistent.',
      );
    }
    _text(json['timezone'], 'timezone', max: 100);
    _enumText(
      json['best_energy_window'],
      'best_energy_window',
      const {
        'early_morning',
        'morning',
        'afternoon',
        'evening',
        'variable',
      },
    );
    _date(json['planning_start_on'], 'planning_start_on');
    final fingerprint = _text(
      json['planning_fingerprint'],
      'planning_fingerprint',
      max: 64,
    );
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint)) {
      throw const PlannerContractException(
        'Planner revision fingerprint is invalid.',
      );
    }
    if (activatedAt != null && activatedAt.isBefore(createdAt) ||
        supersededAt != null && supersededAt.isBefore(createdAt)) {
      throw const PlannerContractException(
        'Planner revision timestamps are invalid.',
      );
    }
    return PlannerRevision(
      revision: revision,
      state: state,
      targetKind: target.kind,
      targetOperation: target.operation,
      targetId: target.id,
      targetTitle: target.title,
      plannedMinutes: plannedMinutes,
      unscheduledMinutes: _int(
        json['unscheduled_minutes'],
        'unscheduled_minutes',
        min: 0,
      ),
      calendarImportId: _optionalUuid(
        json['calendar_import_id'],
        'calendar_import_id',
      ),
      taskBlocks: blocks,
      habitSlots: slots,
    );
  }

  final int revision;
  final String state;
  final String targetKind;
  final String targetOperation;
  final String targetId;
  final String targetTitle;
  final int plannedMinutes;
  final int unscheduledMinutes;
  final String? calendarImportId;
  final List<PlannerTaskBlock> taskBlocks;
  final List<PlannerHabitSlot> habitSlots;
}

class PlannerActionPlan {
  const PlannerActionPlan({
    required this.id,
    required this.targetKind,
    required this.targetId,
    required this.status,
    required this.currentRevision,
    required this.latestRevision,
    required this.needsAttention,
    required this.attentionReasons,
    required this.activeRevision,
    required this.pendingRevision,
  });

  factory PlannerActionPlan.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      const {
        'id',
        'target_kind',
        'target_id',
        'status',
        'current_revision',
        'latest_revision',
        'needs_attention',
        'attention_reasons',
        'active_revision',
        'pending_revision',
      },
      'Planner action plan',
    );
    final reasons = _strings(json['attention_reasons'], 'attention_reasons');
    final needsAttention = _bool(json['needs_attention'], 'needs_attention');
    final targetKind = _enumText(
      json['target_kind'],
      'target_kind',
      const {'task', 'habit'},
    );
    final targetId = _uuid(json['target_id'], 'target_id');
    final currentRevision = _int(
      json['current_revision'],
      'current_revision',
      min: 0,
      max: 500,
    );
    final latestRevision = _int(
      json['latest_revision'],
      'latest_revision',
      min: 1,
      max: 500,
    );
    final active = _optionalObject(json['active_revision'], 'active_revision')
        ?.let(PlannerRevision.fromJson);
    final pending =
        _optionalObject(json['pending_revision'], 'pending_revision')
            ?.let(PlannerRevision.fromJson);
    if (needsAttention != reasons.isNotEmpty ||
        reasons.length > 12 ||
        latestRevision < currentRevision ||
        (currentRevision == 0) != (active == null) ||
        active != null &&
            (active.revision != currentRevision ||
                active.state != 'active' ||
                active.targetKind != targetKind ||
                active.targetId != targetId) ||
        pending != null &&
            (pending.revision != latestRevision ||
                pending.state != 'proposed' ||
                pending.targetKind != targetKind ||
                pending.targetId != targetId)) {
      throw const PlannerContractException(
        'Planner attention state is invalid.',
      );
    }
    return PlannerActionPlan(
      id: _uuid(json['id'], 'plan id'),
      targetKind: targetKind,
      targetId: targetId,
      status: _enumText(json['status'], 'plan status', const {
        'draft',
        'active',
        'unscheduled',
        'cancelled',
      }),
      currentRevision: currentRevision,
      latestRevision: latestRevision,
      needsAttention: needsAttention,
      attentionReasons: reasons,
      activeRevision: active,
      pendingRevision: pending,
    );
  }

  final String id;
  final String targetKind;
  final String targetId;
  final String status;
  final int currentRevision;
  final int latestRevision;
  final bool needsAttention;
  final List<String> attentionReasons;
  final PlannerRevision? activeRevision;
  final PlannerRevision? pendingRevision;
}

PlannerActionPlan plannerActionPlanFromResponse(Map<String, dynamic> json) {
  _expectKeys(
    json,
    const {'contract_version', 'origin', 'plan'},
    'Planner action plan response',
  );
  _expectEnvelope(
    json,
    contractVersion: 'planner-v1',
    label: 'Planner action plan response',
  );
  return PlannerActionPlan.fromJson(_object(json['plan'], 'plan'));
}

class PlannerCommitment {
  const PlannerCommitment({
    required this.id,
    required this.title,
    required this.location,
    required this.recurrence,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    required this.weekday,
    required this.localStartsAt,
    required this.localEndsAt,
    required this.updatedAt,
  });

  factory PlannerCommitment.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      const {
        'id',
        'title',
        'location',
        'recurrence',
        'status',
        'starts_at',
        'ends_at',
        'weekday',
        'local_starts_at',
        'local_ends_at',
        'created_at',
        'updated_at',
        'archived_at',
      },
      'Planner commitment',
    );
    final recurrence = _enumText(
      json['recurrence'],
      'commitment recurrence',
      const {'one_off', 'weekly'},
    );
    final status = _enumText(
      json['status'],
      'commitment status',
      const {'active', 'archived'},
    );
    final startsAt = _optionalDateTime(
      json['starts_at'],
      'commitment starts_at',
    );
    final endsAt = _optionalDateTime(json['ends_at'], 'commitment ends_at');
    final weekday = json['weekday'] == null
        ? null
        : _int(json['weekday'], 'commitment weekday', min: 1, max: 7);
    final localStartsAt = json['local_starts_at'] == null
        ? null
        : _time(json['local_starts_at'], 'commitment local_starts_at');
    final localEndsAt = json['local_ends_at'] == null
        ? null
        : _time(json['local_ends_at'], 'commitment local_ends_at');
    final createdAt = _dateTime(json['created_at'], 'commitment created_at');
    final updatedAt = _dateTime(json['updated_at'], 'commitment updated_at');
    final archivedAt = _optionalDateTime(
      json['archived_at'],
      'commitment archived_at',
    );
    final oneOffValid = startsAt != null &&
        endsAt != null &&
        endsAt.isAfter(startsAt) &&
        weekday == null &&
        localStartsAt == null &&
        localEndsAt == null;
    final weeklyValid = startsAt == null &&
        endsAt == null &&
        weekday != null &&
        localStartsAt != null &&
        localEndsAt != null &&
        _timeMinutes(localEndsAt) > _timeMinutes(localStartsAt);
    if ((recurrence == 'one_off' ? !oneOffValid : !weeklyValid) ||
        (status == 'archived') != (archivedAt != null) ||
        updatedAt.isBefore(createdAt) ||
        archivedAt != null && archivedAt.isBefore(createdAt)) {
      throw const PlannerContractException(
        'Planner commitment lifecycle is invalid.',
      );
    }
    return PlannerCommitment(
      id: _uuid(json['id'], 'commitment id'),
      title: _text(json['title'], 'commitment title', max: 160),
      location:
          _optionalText(json['location'], 'commitment location', max: 300),
      recurrence: recurrence,
      status: status,
      startsAt: startsAt,
      endsAt: endsAt,
      weekday: weekday,
      localStartsAt: localStartsAt,
      localEndsAt: localEndsAt,
      updatedAt: updatedAt,
    );
  }

  final String id;
  final String title;
  final String? location;
  final String recurrence;
  final String status;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? weekday;
  final String? localStartsAt;
  final String? localEndsAt;
  final DateTime updatedAt;
}

PlannerCommitment plannerCommitmentFromResponse(Map<String, dynamic> json) {
  _expectKeys(
    json,
    const {
      'contract_version',
      'origin',
      'commitment',
      'affected_plan_ids',
      'replayed',
    },
    'Planner commitment response',
  );
  _expectEnvelope(
    json,
    contractVersion: 'planner-v1',
    label: 'Planner commitment response',
  );
  _bool(json['replayed'], 'commitment replayed');
  final affected = json['affected_plan_ids'];
  if (affected is! List ||
      affected.any((value) {
        try {
          _uuid(value, 'affected plan id');
          return false;
        } on PlannerContractException {
          return true;
        }
      })) {
    throw const PlannerContractException('Affected Planner plans are invalid.');
  }
  return PlannerCommitment.fromJson(
    _object(json['commitment'], 'commitment'),
  );
}

class PlannerOverview {
  const PlannerOverview({
    required this.generatedAt,
    required this.timezone,
    required this.localDate,
    required this.preferences,
    required this.actionPlans,
    required this.commitments,
    required this.needsAttention,
    required this.days,
    required this.ongoingPreparation,
    required this.unscheduled,
    required this.history,
  });

  factory PlannerOverview.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      const {
        'contract_version',
        'origin',
        'generated_at',
        'timezone',
        'local_date',
        'preferences',
        'action_plans',
        'commitments',
        'needs_attention',
        'days',
        'ongoing_preparation',
        'unscheduled',
        'history',
      },
      'Planner overview',
    );
    _expectEnvelope(
      json,
      contractVersion: 'planner-v1',
      label: 'Planner overview',
    );
    final days = _objects(json['days'], 'Planner days')
        .map(PlannerDay.fromJson)
        .toList(growable: false);
    final localDate = _date(json['local_date'], 'local_date');
    final actionPlans = _objects(json['action_plans'], 'action_plans')
        .map(PlannerActionPlan.fromJson)
        .toList(growable: false);
    final commitments = _objects(json['commitments'], 'commitments')
        .map(PlannerCommitment.fromJson)
        .toList(growable: false);
    final needsAttention = _objects(
      json['needs_attention'],
      'needs_attention',
    ).map(PlannerAttention.fromJson).toList(growable: false);
    final ongoing = _objects(
      json['ongoing_preparation'],
      'ongoing_preparation',
    ).map(PlannerPreparation.fromJson).toList(growable: false);
    final unscheduled = _objects(json['unscheduled'], 'unscheduled')
        .map(PlannerUnscheduled.fromJson)
        .toList(growable: false);
    final history = _objects(json['history'], 'history')
        .map(PlannerUnscheduled.fromJson)
        .toList(growable: false);
    final expectedDays = [
      for (var offset = 0; offset < 7; offset++)
        DateTime.utc(localDate.year, localDate.month, localDate.day + offset),
    ];
    if (days.length != 7 ||
        [for (final day in days) day.localDate]
            .asMap()
            .entries
            .any((entry) => entry.value != expectedDays[entry.key]) ||
        actionPlans.length > 1000 ||
        commitments.length > 1000 ||
        needsAttention.length > 500 ||
        ongoing.length > 50 ||
        unscheduled.length > 1000 ||
        history.length > 1000 ||
        !_unique(actionPlans.map((value) => value.id)) ||
        !_unique(commitments.map((value) => value.id)) ||
        !_unique(needsAttention.map((value) => value.id)) ||
        !_unique(ongoing.map((value) => value.planId)) ||
        !_unique(unscheduled.map((value) => '${value.kind}:${value.id}')) ||
        !_unique(history.map((value) => '${value.kind}:${value.id}'))) {
      throw const PlannerContractException(
        'Planner overview projection is inconsistent.',
      );
    }
    return PlannerOverview(
      generatedAt: _dateTime(json['generated_at'], 'generated_at'),
      timezone: _text(json['timezone'], 'timezone', max: 100),
      localDate: localDate,
      preferences: PlannerPreferences.fromJson(
        _object(json['preferences'], 'preferences'),
      ),
      actionPlans: actionPlans,
      commitments: commitments,
      needsAttention: needsAttention,
      days: days,
      ongoingPreparation: ongoing,
      unscheduled: unscheduled,
      history: history,
    );
  }

  final DateTime generatedAt;
  final String timezone;
  final DateTime localDate;
  final PlannerPreferences preferences;
  final List<PlannerActionPlan> actionPlans;
  final List<PlannerCommitment> commitments;
  final List<PlannerAttention> needsAttention;
  final List<PlannerDay> days;
  final List<PlannerPreparation> ongoingPreparation;
  final List<PlannerUnscheduled> unscheduled;
  final List<PlannerUnscheduled> history;
}

class PlannerTaskDraft {
  const PlannerTaskDraft({
    required this.title,
    required this.description,
    required this.priority,
    required this.estimatedMinutes,
    required this.deadlineAt,
    required this.preferredSessionMinutes,
    this.targetId,
    this.expectedUpdatedAt,
  });

  final String title;
  final String? description;
  final String priority;
  final int? estimatedMinutes;
  final DateTime? deadlineAt;
  final int? preferredSessionMinutes;
  final String? targetId;
  final DateTime? expectedUpdatedAt;

  Map<String, dynamic> proposalJson({
    required String requestId,
    required String planId,
    required String newTargetId,
    required int baseRevision,
    required String planningStartOn,
  }) {
    if ((targetId == null) != (expectedUpdatedAt == null)) {
      throw const PlannerContractException(
        'Planner Task draft target identity is inconsistent.',
      );
    }
    return {
      'request_id': requestId,
      'plan_id': planId,
      'base_revision': baseRevision,
      'planning_start_on': planningStartOn,
      'target': {
        'kind': 'task',
        'operation': targetId == null ? 'create' : 'update',
        'target_id': targetId ?? newTargetId,
        'expected_updated_at': expectedUpdatedAt?.toUtc().toIso8601String(),
        'title': title,
        'description': description,
        'priority': priority,
        'estimated_minutes': estimatedMinutes,
        'deadline_at': deadlineAt?.toUtc().toIso8601String(),
        'preferred_session_minutes': preferredSessionMinutes,
      },
    };
  }
}

class PlannerHabitDraft {
  const PlannerHabitDraft({
    required this.title,
    required this.description,
    required this.cadenceKind,
    required this.scheduledWeekdays,
    required this.weeklyTarget,
    required this.durationMinutes,
    this.targetId,
    this.expectedUpdatedAt,
  });

  final String title;
  final String? description;
  final String cadenceKind;
  final List<int> scheduledWeekdays;
  final int weeklyTarget;
  final int? durationMinutes;
  final String? targetId;
  final DateTime? expectedUpdatedAt;

  Map<String, dynamic> proposalJson({
    required String requestId,
    required String planId,
    required String newTargetId,
    required int baseRevision,
    required String planningStartOn,
  }) {
    if (durationMinutes == null ||
        (targetId == null) != (expectedUpdatedAt == null)) {
      throw const PlannerContractException(
        'Planner Habit draft target identity is inconsistent.',
      );
    }
    return {
      'request_id': requestId,
      'plan_id': planId,
      'base_revision': baseRevision,
      'planning_start_on': planningStartOn,
      'target': {
        'kind': 'habit',
        'operation': targetId == null ? 'create' : 'update',
        'target_id': targetId ?? newTargetId,
        'expected_updated_at': expectedUpdatedAt?.toUtc().toIso8601String(),
        'title': title,
        'description': description,
        'cadence': {
          'kind': cadenceKind,
          'scheduled_weekdays': scheduledWeekdays,
          'weekly_target': weeklyTarget,
        },
        'duration_minutes': durationMinutes,
      },
    };
  }
}

class PlannerCommitmentDraft {
  const PlannerCommitmentDraft({
    required this.title,
    required this.location,
    required this.recurrence,
    required this.startsAt,
    required this.endsAt,
    required this.weekday,
    required this.localStartsAt,
    required this.localEndsAt,
  });

  final String title;
  final String? location;
  final String recurrence;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? weekday;
  final String? localStartsAt;
  final String? localEndsAt;

  Map<String, dynamic> createJson({
    required String requestId,
    required String commitmentId,
  }) =>
      {
        'request_id': requestId,
        'commitment_id': commitmentId,
        'title': title,
        'location': location,
        'recurrence': recurrence,
        'starts_at': startsAt?.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'weekday': weekday,
        'local_starts_at': localStartsAt,
        'local_ends_at': localEndsAt,
      };

  Map<String, dynamic> updateJson({
    required String requestId,
    required PlannerCommitment commitment,
  }) =>
      {
        ...createJson(requestId: requestId, commitmentId: commitment.id),
        'expected_updated_at': commitment.updatedAt.toUtc().toIso8601String(),
      };
}

extension _NullableMapLet on Map<String, dynamic> {
  T let<T>(T Function(Map<String, dynamic>) convert) => convert(this);
}

({String kind, String operation, String id, String title}) _plannerTarget(
  Map<String, dynamic> target,
) {
  final kind = _enumText(
    target['kind'],
    'Planner target kind',
    const {'task', 'habit'},
  );
  if (kind == 'task') {
    _expectKeys(
      target,
      const {
        'kind',
        'operation',
        'target_id',
        'expected_updated_at',
        'title',
        'description',
        'priority',
        'estimated_minutes',
        'deadline_at',
        'preferred_session_minutes',
      },
      'Planner Task target',
    );
    _optionalText(target['description'], 'Task description', max: 2000);
    _enumText(
      target['priority'],
      'Task priority',
      const {'low', 'medium', 'high', 'critical'},
    );
    _optionalInt(
      target['estimated_minutes'],
      'Task estimated_minutes',
      min: 5,
      max: 480,
    );
    _optionalDateTime(target['deadline_at'], 'Task deadline_at');
    final session = _optionalInt(
      target['preferred_session_minutes'],
      'Task preferred_session_minutes',
      min: 5,
      max: 240,
    );
    if (session != null && session % 5 != 0) {
      throw const PlannerContractException(
        'Planner Task session length is invalid.',
      );
    }
  } else {
    _expectKeys(
      target,
      const {
        'kind',
        'operation',
        'target_id',
        'expected_updated_at',
        'title',
        'description',
        'cadence',
        'duration_minutes',
      },
      'Planner Habit target',
    );
    _optionalText(target['description'], 'Habit description', max: 2000);
    final cadence = _object(target['cadence'], 'Habit cadence');
    _expectKeys(
      cadence,
      const {'kind', 'scheduled_weekdays', 'weekly_target'},
      'Habit cadence',
    );
    final cadenceKind = _enumText(
      cadence['kind'],
      'Habit cadence kind',
      const {'daily', 'weekdays', 'weekly_target'},
    );
    final weekdays = _integers(
      cadence['scheduled_weekdays'],
      'Habit weekdays',
      min: 1,
      max: 7,
    );
    final weeklyTarget = _int(
      cadence['weekly_target'],
      'Habit weekly target',
      min: 1,
      max: 7,
    );
    final duration = _int(
      target['duration_minutes'],
      'Habit duration_minutes',
      min: 5,
      max: 240,
    );
    if (duration % 5 != 0 ||
        (cadenceKind == 'daily' &&
            (weekdays.isNotEmpty || weeklyTarget != 1)) ||
        (cadenceKind == 'weekdays' &&
            (weekdays.isEmpty || weeklyTarget != 1)) ||
        (cadenceKind == 'weekly_target' && weekdays.isNotEmpty)) {
      throw const PlannerContractException('Planner Habit target is invalid.');
    }
  }
  final operation = _enumText(
    target['operation'],
    'Planner target operation',
    const {'create', 'update'},
  );
  final expected = _optionalDateTime(
    target['expected_updated_at'],
    'Planner target expected_updated_at',
  );
  if ((operation == 'create') != (expected == null)) {
    throw const PlannerContractException(
      'Planner target version is inconsistent.',
    );
  }
  return (
    kind: kind,
    operation: operation,
    id: _uuid(target['target_id'], 'Planner target id'),
    title: _text(target['title'], 'Planner target title', max: 160),
  );
}

void _expectEnvelope(
  Map<String, dynamic> json, {
  required String contractVersion,
  required String label,
}) {
  if (json['contract_version'] != contractVersion ||
      json['origin'] != 'authenticated_backend') {
    throw PlannerContractException('$label contract is unsupported.');
  }
}

void _expectKeys(Map<String, dynamic> json, Set<String> keys, String label) {
  if (json.length != keys.length ||
      json.keys.any((key) => !keys.contains(key))) {
    throw PlannerContractException('$label has an unexpected shape.');
  }
}

Map<String, dynamic> _object(Object? value, String label) {
  if (value is! Map) {
    throw PlannerContractException('$label must be an object.');
  }
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic>? _optionalObject(Object? value, String label) =>
    value == null ? null : _object(value, label);

List<Map<String, dynamic>> _objects(Object? value, String label) {
  if (value is! List) throw PlannerContractException('$label must be a list.');
  return value.map((item) => _object(item, label)).toList(growable: false);
}

List<String> _strings(Object? value, String label) {
  if (value is! List || value.any((item) => item is! String)) {
    throw PlannerContractException('$label must contain text only.');
  }
  final result = value.cast<String>();
  if (result.length != result.toSet().length) {
    throw PlannerContractException('$label contains duplicates.');
  }
  return List.unmodifiable(result);
}

List<int> _integers(
  Object? value,
  String label, {
  required int min,
  required int max,
}) {
  if (value is! List) {
    throw PlannerContractException('$label must be a list.');
  }
  final result = value
      .map((item) => _int(item, label, min: min, max: max))
      .toList(growable: false);
  if (!_unique(result)) {
    throw PlannerContractException('$label contains duplicates.');
  }
  return result;
}

String _text(Object? value, String label, {required int max}) {
  if (value is! String ||
      value.isEmpty ||
      value.trim() != value ||
      value.length > max) {
    throw PlannerContractException('$label is invalid.');
  }
  return value;
}

String? _optionalText(Object? value, String label, {required int max}) =>
    value == null ? null : _text(value, label, max: max);

String _enumText(Object? value, String label, Set<String> values) {
  final result = _text(value, label, max: 80);
  if (!values.contains(result)) {
    throw PlannerContractException('$label is unsupported.');
  }
  return result;
}

bool _bool(Object? value, String label) {
  if (value is! bool) throw PlannerContractException('$label must be boolean.');
  return value;
}

int _int(Object? value, String label, {required int min, int? max}) {
  if (value is! int || value < min || max != null && value > max) {
    throw PlannerContractException('$label is invalid.');
  }
  return value;
}

int? _optionalInt(
  Object? value,
  String label, {
  required int min,
  int? max,
}) =>
    value == null ? null : _int(value, label, min: min, max: max);

DateTime _dateTime(Object? value, String label) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$',
      ).hasMatch(value)) {
    throw PlannerContractException('$label is invalid.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      !parsed.isUtc && !value.contains(RegExp(r'[+-]\d\d:\d\d$'))) {
    throw PlannerContractException('$label must include a timezone.');
  }
  return parsed;
}

DateTime? _optionalDateTime(Object? value, String label) =>
    value == null ? null : _dateTime(value, label);

DateTime _date(Object? value, String label) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw PlannerContractException('$label is invalid.');
  }
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  if (parsed == null ||
      '${parsed.year.toString().padLeft(4, '0')}-'
              '${parsed.month.toString().padLeft(2, '0')}-'
              '${parsed.day.toString().padLeft(2, '0')}' !=
          value) {
    throw PlannerContractException('$label is invalid.');
  }
  return parsed;
}

String _time(Object? value, String label) {
  if (value is! String ||
      !RegExp(r'^([01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+)?$').hasMatch(value)) {
    throw PlannerContractException('$label is invalid.');
  }
  return value;
}

String _uuid(Object? value, String label) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(value)) {
    throw PlannerContractException('$label is invalid.');
  }
  return value;
}

String? _optionalUuid(Object? value, String label) =>
    value == null ? null : _uuid(value, label);

int _timeMinutes(String value) {
  final parts = value.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

bool _unique<T>(Iterable<T> values) {
  final list = values.toList(growable: false);
  return list.length == list.toSet().length;
}
