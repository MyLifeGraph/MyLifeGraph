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
    this.recoveryMinutes = 0,
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
    this.timeWindowLabel,
  });

  final int durationMinutes;
  final int evidenceSessions;
  final String? timeWindowLabel;

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

    final windows = <String, int>{};
    for (final session in completed) {
      final hour = session.startedAt.toLocal().hour;
      final label = switch (hour) {
        >= 5 && < 12 => 'in the morning',
        >= 12 && < 17 => 'in the afternoon',
        >= 17 && < 22 => 'in the evening',
        _ => 'late at night',
      };
      windows[label] = (windows[label] ?? 0) + 1;
    }
    final rankedWindows = windows.entries.toList()
      ..sort((left, right) {
        final count = right.value.compareTo(left.value);
        return count != 0 ? count : left.key.compareTo(right.key);
      });
    final strongestWindow = rankedWindows.first;
    final hasUsefulWindow = strongestWindow.value >= 3 &&
        strongestWindow.value / completed.length >= 0.4;

    return FocusPreferenceSuggestion(
      durationMinutes: roundedDuration,
      evidenceSessions: completed.length,
      timeWindowLabel: hasUsefulWindow ? strongestWindow.key : null,
    );
  }
}

class FocusCommandException implements Exception {
  const FocusCommandException(this.message);

  final String message;

  @override
  String toString() => message;
}
