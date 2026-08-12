enum FocusSessionStatus {
  active('active'),
  completed('completed'),
  abandoned('abandoned');

  const FocusSessionStatus(this.code);

  final String code;

  static FocusSessionStatus? fromCode(Object? value) {
    for (final status in values) {
      if (status.code == value) {
        return status;
      }
    }
    return null;
  }
}

enum FocusTargetKind {
  task('task'),
  habit('habit');

  const FocusTargetKind(this.code);

  final String code;

  static FocusTargetKind? fromCode(Object? value) {
    for (final kind in values) {
      if (kind.code == value) {
        return kind;
      }
    }
    return null;
  }
}

enum FocusScheduleSourceKind {
  deadlinePlanBlock('deadline_plan_block'),
  plannerTaskBlock('planner_task_block');

  const FocusScheduleSourceKind(this.code);

  final String code;

  static FocusScheduleSourceKind? fromCode(Object? value) {
    for (final kind in values) {
      if (kind.code == value) return kind;
    }
    return null;
  }
}

enum FocusObstacle {
  tired('tired', 'Tired'),
  distracted('distracted', 'Distracted'),
  interrupted('interrupted', 'Interrupted'),
  unclearGoal('unclear_goal', 'Unclear goal'),
  materialTooDifficult('material_too_difficult', 'Material too difficult'),
  sessionTooLong('session_too_long', 'Session too long'),
  environment('environment', 'Environment'),
  other('other', 'Other');

  const FocusObstacle(this.code, this.label);

  final String code;
  final String label;

  static FocusObstacle? fromCode(Object? value) {
    for (final obstacle in values) {
      if (obstacle.code == value) return obstacle;
    }
    return null;
  }
}

class FocusReflection {
  const FocusReflection({
    required this.focusSessionId,
    required this.focusQuality,
    required this.usefulProgress,
    required this.obstacles,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FocusReflection.fromRow(Map<String, dynamic> row) {
    final focusSessionId = row['focus_session_id'];
    final focusQuality = row['focus_quality'];
    final usefulProgress = row['useful_progress'];
    final rawObstacles = row['obstacles'];
    final createdAt = row['created_at'];
    final updatedAt = row['updated_at'];
    if (row['contract_version'] != 'focus-reflection-v1' ||
        focusSessionId is! String ||
        focusSessionId.trim().isEmpty ||
        focusQuality is! int ||
        focusQuality < 1 ||
        focusQuality > 5 ||
        usefulProgress is! int ||
        usefulProgress < 1 ||
        usefulProgress > 5 ||
        rawObstacles is! List ||
        rawObstacles.length > 2 ||
        createdAt is! String ||
        updatedAt is! String) {
      throw const FocusCommandException(
        'Focus reflection response is invalid.',
      );
    }
    final obstacles = <FocusObstacle>[];
    for (final raw in rawObstacles) {
      final obstacle = FocusObstacle.fromCode(raw);
      if (obstacle == null || obstacles.contains(obstacle)) {
        throw const FocusCommandException(
          'Focus reflection response is invalid.',
        );
      }
      obstacles.add(obstacle);
    }
    final parsedCreatedAt = DateTime.tryParse(createdAt);
    final parsedUpdatedAt = DateTime.tryParse(updatedAt);
    if (parsedCreatedAt == null ||
        parsedUpdatedAt == null ||
        parsedUpdatedAt.isBefore(parsedCreatedAt)) {
      throw const FocusCommandException(
        'Focus reflection response is invalid.',
      );
    }
    return FocusReflection(
      focusSessionId: focusSessionId.trim(),
      focusQuality: focusQuality,
      usefulProgress: usefulProgress,
      obstacles: List.unmodifiable(obstacles),
      createdAt: parsedCreatedAt,
      updatedAt: parsedUpdatedAt,
    );
  }

  final String focusSessionId;
  final int focusQuality;
  final int usefulProgress;
  final List<FocusObstacle> obstacles;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool matches(FocusReflectionDraft draft) =>
      focusQuality == draft.focusQuality &&
      usefulProgress == draft.usefulProgress &&
      obstacles.length == draft.obstacles.length &&
      obstacles.toSet().containsAll(draft.obstacles);
}

class FocusReflectionDraft {
  FocusReflectionDraft({
    required this.focusQuality,
    required this.usefulProgress,
    Iterable<FocusObstacle> obstacles = const [],
  }) : obstacles = List.unmodifiable(obstacles) {
    if (focusQuality < 1 ||
        focusQuality > 5 ||
        usefulProgress < 1 ||
        usefulProgress > 5 ||
        this.obstacles.length > 2 ||
        this.obstacles.toSet().length != this.obstacles.length) {
      throw const FocusCommandException('Focus reflection is invalid.');
    }
  }

  final int focusQuality;
  final int usefulProgress;
  final List<FocusObstacle> obstacles;
}

class FocusSession {
  const FocusSession({
    required this.id,
    required this.status,
    required this.startedAt,
    required this.plannedMinutes,
    this.recoveryMinutes = 0,
    required this.updatedAt,
    this.entryDate,
    this.endedAt,
    this.actualMinutes,
    this.label,
    this.targetKind,
    this.targetId,
    this.scheduleSource,
    this.requiresBackendLifecycle = false,
  });

  factory FocusSession.fromV2Json(Map<String, dynamic> json) {
    _exactKeys(
      json,
      const {
        'contract_version',
        'origin',
        'replayed',
        'id',
        'status',
        'started_at',
        'ended_at',
        'planned_minutes',
        'actual_minutes',
        'label',
        'task_id',
        'habit_id',
        'entry_date',
        'recovery_minutes',
        'updated_at',
        'schedule_source',
      },
      'Focus session V2',
    );
    if (json['contract_version'] != 'focus-session-v2' ||
        json['origin'] != 'authenticated_backend' ||
        json['replayed'] is! bool ||
        json['entry_date'] is! String ||
        json['recovery_minutes'] is! int) {
      throw const FocusCommandException('Focus session response is invalid.');
    }
    final recoveryMinutes = json['recovery_minutes'] as int;
    final scheduleSource = json['schedule_source'] == null
        ? null
        : FocusScheduleSource.fromJson(
            _stringMap(json['schedule_source'], 'Focus schedule source'),
          );
    final base = FocusSession.fromRow({
      'id': json['id'],
      'status': json['status'],
      'started_at': json['started_at'],
      'ended_at': json['ended_at'],
      'planned_minutes': json['planned_minutes'],
      'actual_minutes': json['actual_minutes'],
      'label': json['label'],
      'task_id': json['task_id'],
      'habit_id': json['habit_id'],
      'metadata': {
        'entry_date': json['entry_date'],
        if (recoveryMinutes > 0) 'recovery_minutes': recoveryMinutes,
      },
      'updated_at': json['updated_at'],
    });
    if (scheduleSource != null &&
        (base.targetKind != FocusTargetKind.task ||
            scheduleSource.originalRecoveryMinutes != base.recoveryMinutes)) {
      throw const FocusCommandException(
        'Scheduled Focus session response is inconsistent.',
      );
    }
    return FocusSession(
      id: base.id,
      status: base.status,
      startedAt: base.startedAt,
      endedAt: base.endedAt,
      plannedMinutes: base.plannedMinutes,
      recoveryMinutes: base.recoveryMinutes,
      actualMinutes: base.actualMinutes,
      label: base.label,
      targetKind: base.targetKind,
      targetId: base.targetId,
      updatedAt: base.updatedAt,
      entryDate: base.entryDate,
      scheduleSource: scheduleSource,
      requiresBackendLifecycle: true,
    );
  }

  factory FocusSession.fromRow(Map<String, dynamic> row) {
    if (row['id'] is! String ||
        row['started_at'] is! String ||
        row['updated_at'] is! String) {
      throw const FocusCommandException('Focus session response is invalid.');
    }
    final status = FocusSessionStatus.fromCode(row['status']);
    final startedAt = DateTime.tryParse(row['started_at'] as String);
    final updatedAt = DateTime.tryParse(row['updated_at'] as String);
    final entryDate = _optionalEntryDate(row['metadata']);
    final recoveryMinutes = _optionalRecoveryMinutes(row['metadata']);
    final plannedMinutes = _integer(row['planned_minutes']);
    final endedAt = _optionalTimestamp(row['ended_at']);
    final actualMinutes = _optionalInteger(row['actual_minutes']);
    final taskId = _optionalTargetId(row['task_id']);
    final habitId = _optionalTargetId(row['habit_id']);
    if ((row['id'] as String).trim().isEmpty ||
        status == null ||
        startedAt == null ||
        updatedAt == null ||
        plannedMinutes == null ||
        plannedMinutes < 5 ||
        plannedMinutes > 240 ||
        taskId != null && habitId != null) {
      throw const FocusCommandException('Focus session response is invalid.');
    }
    if (status == FocusSessionStatus.active &&
            (endedAt != null || actualMinutes != null) ||
        status != FocusSessionStatus.active &&
            (endedAt == null || actualMinutes == null)) {
      throw const FocusCommandException('Focus session lifecycle is invalid.');
    }
    if (endedAt != null &&
        (endedAt.isBefore(startedAt) ||
            actualMinutes !=
                measuredFocusMinutes(
                  startedAt: startedAt,
                  endedAt: endedAt,
                ))) {
      throw const FocusCommandException('Focus session duration is invalid.');
    }
    return FocusSession(
      id: (row['id'] as String).trim(),
      status: status,
      startedAt: startedAt,
      endedAt: endedAt,
      plannedMinutes: plannedMinutes,
      recoveryMinutes: recoveryMinutes,
      actualMinutes: actualMinutes,
      label: _optionalText(row['label']),
      targetKind: taskId != null
          ? FocusTargetKind.task
          : habitId != null
              ? FocusTargetKind.habit
              : null,
      targetId: taskId ?? habitId,
      updatedAt: updatedAt,
      entryDate: entryDate,
      requiresBackendLifecycle: _requiresBackendLifecycle(row['metadata']),
    );
  }

  final String id;
  final FocusSessionStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int plannedMinutes;
  final int recoveryMinutes;
  final int? actualMinutes;
  final String? label;
  final FocusTargetKind? targetKind;
  final String? targetId;
  final FocusScheduleSource? scheduleSource;
  final bool requiresBackendLifecycle;
  final DateTime updatedAt;
  final String? entryDate;

  bool get isActive => status == FocusSessionStatus.active;

  String get snapshotEntryDate {
    final explicitEntryDate = entryDate;
    if (explicitEntryDate != null) {
      return explicitEntryDate;
    }
    final utcStart = startedAt.toUtc();
    final month = utcStart.month.toString().padLeft(2, '0');
    final day = utcStart.day.toString().padLeft(2, '0');
    return '${utcStart.year}-$month-$day';
  }

  static int? _integer(Object? value) {
    if (value is num && value == value.toInt()) {
      return value.toInt();
    }
    return null;
  }

  static int? _optionalInteger(Object? value) {
    if (value == null) {
      return null;
    }
    final parsed = _integer(value);
    if (parsed == null || parsed < 0) {
      throw const FocusCommandException('Focus duration is invalid.');
    }
    return parsed;
  }

  static DateTime? _optionalTimestamp(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw const FocusCommandException('Focus timestamp is invalid.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw const FocusCommandException('Focus timestamp is invalid.');
    }
    return parsed;
  }

  static String? _optionalEntryDate(Object? metadata) {
    if (metadata is! Map) {
      return null;
    }
    final value = metadata['entry_date'];
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        parsed.year.toString().padLeft(4, '0') != value.substring(0, 4) ||
        parsed.month.toString().padLeft(2, '0') != value.substring(5, 7) ||
        parsed.day.toString().padLeft(2, '0') != value.substring(8, 10)) {
      return null;
    }
    return value;
  }

  static int _optionalRecoveryMinutes(Object? metadata) {
    if (metadata is! Map || !metadata.containsKey('recovery_minutes')) {
      return 0;
    }
    final rawValue = metadata['recovery_minutes'];
    if (rawValue is! int ||
        rawValue < 5 ||
        rawValue > 60 ||
        rawValue.remainder(5) != 0) {
      throw const FocusCommandException(
        'Focus recovery duration is invalid.',
      );
    }
    return rawValue;
  }

  static bool _requiresBackendLifecycle(Object? metadata) {
    if (metadata is! Map) return false;
    return metadata['contract_version'] == 'focus-session-v2';
  }

  static String? _optionalText(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw const FocusCommandException('Focus text is invalid.');
    }
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static String? _optionalTargetId(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String || value.trim().isEmpty) {
      throw const FocusCommandException('Focus target id is invalid.');
    }
    return value.trim();
  }
}

class FocusScheduleSource {
  const FocusScheduleSource({
    required this.kind,
    required this.blockId,
    required this.originalStartsAt,
    required this.originalEndsAt,
    required this.originalRecoveryMinutes,
  });

  factory FocusScheduleSource.fromJson(Map<String, dynamic> json) {
    _exactKeys(
      json,
      const {
        'source_kind',
        'block_id',
        'original_starts_at',
        'original_ends_at',
        'original_recovery_minutes',
      },
      'Focus schedule source',
    );
    final kind = FocusScheduleSourceKind.fromCode(json['source_kind']);
    final blockId = json['block_id'];
    final startsAt = json['original_starts_at'] is String
        ? DateTime.tryParse(json['original_starts_at'] as String)
        : null;
    final endsAt = json['original_ends_at'] is String
        ? DateTime.tryParse(json['original_ends_at'] as String)
        : null;
    final recovery = json['original_recovery_minutes'];
    if (kind == null ||
        blockId is! String ||
        !_uuidPattern.hasMatch(blockId) ||
        startsAt == null ||
        endsAt == null ||
        !endsAt.isAfter(startsAt) ||
        recovery is! int ||
        recovery < 0 ||
        recovery > 60 ||
        recovery.remainder(5) != 0) {
      throw const FocusCommandException(
        'Focus schedule source response is invalid.',
      );
    }
    return FocusScheduleSource(
      kind: kind,
      blockId: blockId,
      originalStartsAt: startsAt,
      originalEndsAt: endsAt,
      originalRecoveryMinutes: recovery,
    );
  }

  final FocusScheduleSourceKind kind;
  final String blockId;
  final DateTime originalStartsAt;
  final DateTime originalEndsAt;
  final int originalRecoveryMinutes;
}

class FocusStartContext {
  const FocusStartContext({
    required this.sourceKind,
    required this.blockId,
    required this.target,
    required this.originalStartsAt,
    required this.originalEndsAt,
    required this.recoveryMinutes,
    required this.remainingMinutes,
    required this.sourceState,
    required this.canStart,
    required this.blockingReason,
  });

  factory FocusStartContext.fromJson(Map<String, dynamic> json) {
    _exactKeys(
      json,
      const {
        'contract_version',
        'origin',
        'source_kind',
        'block_id',
        'target',
        'original_starts_at',
        'original_ends_at',
        'recovery_minutes',
        'remaining_minutes',
        'source_state',
        'can_start',
        'blocking_reason',
      },
      'Focus start context',
    );
    final sourceKind = FocusScheduleSourceKind.fromCode(json['source_kind']);
    final blockId = json['block_id'];
    final targetJson = _stringMap(json['target'], 'Focus start target');
    _exactKeys(targetJson, const {'kind', 'id', 'title'}, 'Focus start target');
    final targetId = targetJson['id'];
    final targetTitle = targetJson['title'];
    final starts = json['original_starts_at'] is String
        ? DateTime.tryParse(json['original_starts_at'] as String)
        : null;
    final ends = json['original_ends_at'] is String
        ? DateTime.tryParse(json['original_ends_at'] as String)
        : null;
    final recovery = json['recovery_minutes'];
    final remaining = json['remaining_minutes'];
    final sourceState = json['source_state'];
    final canStart = json['can_start'];
    final blockingReason = json['blocking_reason'];
    const states = {'upcoming', 'partial', 'completed', 'missed'};
    const reasons = {
      'source_fully_credited',
      'source_remaining_too_short',
      'active_focus_session',
      'deadline_plan_block',
      'planner_task_block',
      'fixed_commitment',
      'recurring_commitment',
      'availability_unavailable',
      'calendar_availability_unavailable',
      'calendar_busy',
    };
    if (json['contract_version'] != 'focus-start-context-v2' ||
        json['origin'] != 'authenticated_backend' ||
        sourceKind == null ||
        blockId is! String ||
        !_uuidPattern.hasMatch(blockId) ||
        targetJson['kind'] != 'task' ||
        targetId is! String ||
        !_uuidPattern.hasMatch(targetId) ||
        targetTitle is! String ||
        targetTitle.trim().isEmpty ||
        targetTitle != targetTitle.trim() ||
        starts == null ||
        ends == null ||
        !ends.isAfter(starts) ||
        recovery is! int ||
        recovery < 0 ||
        recovery > 60 ||
        recovery.remainder(5) != 0 ||
        remaining is! int ||
        remaining < 0 ||
        remaining > 240 ||
        sourceState is! String ||
        !states.contains(sourceState) ||
        canStart is! bool ||
        blockingReason != null && !reasons.contains(blockingReason) ||
        canStart != (blockingReason == null) ||
        (remaining == 0) != (sourceState == 'completed') ||
        remaining == 0 && blockingReason != 'source_fully_credited' ||
        remaining > 0 &&
            remaining < 5 &&
            blockingReason != 'source_remaining_too_short' ||
        remaining >= 5 &&
            (blockingReason == 'source_fully_credited' ||
                blockingReason == 'source_remaining_too_short')) {
      throw const FocusCommandException(
        'Focus start context response is invalid.',
      );
    }
    return FocusStartContext(
      sourceKind: sourceKind,
      blockId: blockId,
      target: FocusTargetOption(
        kind: FocusTargetKind.task,
        id: targetId,
        title: targetTitle,
      ),
      originalStartsAt: starts,
      originalEndsAt: ends,
      recoveryMinutes: recovery,
      remainingMinutes: remaining,
      sourceState: sourceState,
      canStart: canStart,
      blockingReason: blockingReason as String?,
    );
  }

  final FocusScheduleSourceKind sourceKind;
  final String blockId;
  final FocusTargetOption target;
  final DateTime originalStartsAt;
  final DateTime originalEndsAt;
  final int recoveryMinutes;
  final int remainingMinutes;
  final String sourceState;
  final bool canStart;
  final String? blockingReason;
}

class FocusTargetOption {
  const FocusTargetOption({
    required this.kind,
    required this.id,
    required this.title,
  });

  final FocusTargetKind kind;
  final String id;
  final String title;

  String get value => '${kind.code}:$id';
}

class FocusStartDraft {
  FocusStartDraft({
    required this.plannedMinutes,
    this.recoveryMinutes = 0,
    this.targetKind,
    String? targetId,
    String? label,
  })  : targetId = _normalizedTargetId(targetId),
        label = _normalizedLabel(label) {
    if (plannedMinutes < 5 || plannedMinutes > 240) {
      throw const FocusCommandException(
        'Focus duration must be between 5 and 240 minutes.',
      );
    }
    if (recoveryMinutes != 0 &&
        (recoveryMinutes < 5 ||
            recoveryMinutes > 60 ||
            recoveryMinutes.remainder(5) != 0)) {
      throw const FocusCommandException(
        'Recovery duration must be zero or 5–60 minutes in five-minute steps.',
      );
    }
    if ((targetKind == null) != (this.targetId == null)) {
      throw const FocusCommandException('Focus target is invalid.');
    }
  }

  final int plannedMinutes;
  final int recoveryMinutes;
  final FocusTargetKind? targetKind;
  final String? targetId;
  final String? label;

  static String? _normalizedLabel(String? value) {
    final label = value?.trim();
    if (label == null || label.isEmpty) {
      return null;
    }
    if (label.length > 160) {
      throw const FocusCommandException(
        'Focus label must be at most 160 characters.',
      );
    }
    return label;
  }

  static String? _normalizedTargetId(String? value) {
    if (value == null) {
      return null;
    }
    final id = value.trim();
    if (id.isEmpty || id.length > 200) {
      throw const FocusCommandException('Focus target is invalid.');
    }
    return id;
  }
}

class FocusPreparationItem {
  const FocusPreparationItem({
    required this.key,
    required this.label,
    required this.active,
  });

  factory FocusPreparationItem.fromJson(Map<String, dynamic> json) {
    if (json.keys
            .toSet()
            .difference(const {'key', 'label', 'active'}).isNotEmpty ||
        !json.keys.toSet().containsAll(const {'key', 'label', 'active'})) {
      throw const FocusCommandException(
        'Study preparation item response is invalid.',
      );
    }
    final key = json['key'];
    final label = json['label'];
    final active = json['active'];
    if (key is! String ||
        !_uuidPattern.hasMatch(key) ||
        label is! String ||
        label.trim().isEmpty ||
        label != label.trim() ||
        label.length > 120 ||
        active is! bool) {
      throw const FocusCommandException(
        'Study preparation item response is invalid.',
      );
    }
    return FocusPreparationItem(
      key: key,
      label: label,
      active: active,
    );
  }

  final String key;
  final String label;
  final bool active;
}

class StudyFocusSettings {
  StudyFocusSettings({
    required this.focusMinutes,
    required this.recoveryMinutes,
    required List<FocusPreparationItem> preparationItems,
    required this.setupRevision,
  }) : preparationItems = List.unmodifiable(preparationItems) {
    if (focusMinutes < 25 ||
        focusMinutes > 180 ||
        focusMinutes.remainder(5) != 0 ||
        recoveryMinutes < 5 ||
        recoveryMinutes > 60 ||
        recoveryMinutes.remainder(5) != 0 ||
        setupRevision < 1 ||
        preparationItems.length > 12 ||
        preparationItems.map((item) => item.key).toSet().length !=
            preparationItems.length ||
        preparationItems
                .map((item) => item.label.toLowerCase())
                .toSet()
                .length !=
            preparationItems.length) {
      throw const FocusCommandException(
        'Study focus settings response is invalid.',
      );
    }
  }

  factory StudyFocusSettings.fromRow(Map<String, dynamic> row) {
    final focusMinutes =
        row['focus_minutes'] is int ? row['focus_minutes'] as int : null;
    final recoveryMinutes =
        row['recovery_minutes'] is int ? row['recovery_minutes'] as int : null;
    final setupRevision =
        row['setup_revision'] is int ? row['setup_revision'] as int : null;
    final rawItems = row['preparation_items'];
    if (focusMinutes == null ||
        recoveryMinutes == null ||
        setupRevision == null ||
        rawItems is! List) {
      throw const FocusCommandException(
        'Study focus settings response is invalid.',
      );
    }
    return StudyFocusSettings(
      focusMinutes: focusMinutes,
      recoveryMinutes: recoveryMinutes,
      setupRevision: setupRevision,
      preparationItems: rawItems.map((item) {
        if (item is! Map) {
          throw const FocusCommandException(
            'Study preparation item response is invalid.',
          );
        }
        return FocusPreparationItem.fromJson(
          Map<String, dynamic>.from(item),
        );
      }).toList(growable: false),
    );
  }

  final int focusMinutes;
  final int recoveryMinutes;
  final List<FocusPreparationItem> preparationItems;
  final int setupRevision;
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-'
  r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void _exactKeys(
  Map<String, dynamic> json,
  Set<String> expected,
  String label,
) {
  if (json.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(json.keys.toSet()).isNotEmpty) {
    throw FocusCommandException('$label response is invalid.');
  }
}

Map<String, dynamic> _stringMap(Object? value, String label) {
  if (value is! Map) {
    throw FocusCommandException('$label response is invalid.');
  }
  return Map<String, dynamic>.from(value);
}

int measuredFocusMinutes({
  required DateTime startedAt,
  required DateTime endedAt,
}) {
  if (endedAt.isBefore(startedAt)) {
    throw const FocusCommandException(
      'Focus end time cannot precede its start time.',
    );
  }
  return endedAt.difference(startedAt).inMinutes;
}

class FocusPreferenceSuggestion {
  const FocusPreferenceSuggestion({
    required this.durationMinutes,
    required this.evidenceSessions,
  });

  final int durationMinutes;
  final int evidenceSessions;

  static FocusPreferenceSuggestion? fromSessions(
    Iterable<FocusSession> sessions,
  ) {
    final completed = sessions
        .where(
          (session) =>
              session.status == FocusSessionStatus.completed &&
              (session.actualMinutes ?? 0) >= 5,
        )
        .toList(growable: false);
    if (completed.length < 5) return null;

    final durations =
        completed.map((session) => session.actualMinutes!).toList()..sort();
    final middle = durations.length ~/ 2;
    final median = durations.length.isOdd
        ? durations[middle].toDouble()
        : (durations[middle - 1] + durations[middle]) / 2;
    final roundedDuration = ((median / 5).round() * 5).clamp(5, 240);

    return FocusPreferenceSuggestion(
      durationMinutes: roundedDuration,
      evidenceSessions: completed.length,
    );
  }
}

class FocusCommandException implements Exception {
  const FocusCommandException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FocusReflectionConflictException extends FocusCommandException {
  const FocusReflectionConflictException(super.message);
}
