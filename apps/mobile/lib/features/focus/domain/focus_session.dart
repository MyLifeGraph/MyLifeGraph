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

class FocusSession {
  const FocusSession({
    required this.id,
    required this.status,
    required this.startedAt,
    required this.plannedMinutes,
    required this.updatedAt,
    this.entryDate,
    this.endedAt,
    this.actualMinutes,
    this.label,
    this.targetKind,
    this.targetId,
  });

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
    );
  }

  final String id;
  final FocusSessionStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int plannedMinutes;
  final int? actualMinutes;
  final String? label;
  final FocusTargetKind? targetKind;
  final String? targetId;
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
    if ((targetKind == null) != (this.targetId == null)) {
      throw const FocusCommandException('Focus target is invalid.');
    }
  }

  final int plannedMinutes;
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

class FocusCommandException implements Exception {
  const FocusCommandException(this.message);

  final String message;

  @override
  String toString() => message;
}
