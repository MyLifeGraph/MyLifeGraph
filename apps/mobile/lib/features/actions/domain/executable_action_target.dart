enum ExecutableActionKind {
  task('task'),
  habit('habit'),
  focus('focus'),
  planning('planning'),
  recovery('recovery'),
  capture('capture');

  const ExecutableActionKind(this.code);

  final String code;

  static ExecutableActionKind? fromCode(Object? value) {
    for (final kind in values) {
      if (kind.code == value) {
        return kind;
      }
    }
    return null;
  }
}

enum ExecutableActionCommand {
  openTask('open_task'),
  completeTask('complete_task'),
  logHabit('log_habit'),
  startFocus('start_focus'),
  reviewPlan('review_plan'),
  openCapture('open_capture');

  const ExecutableActionCommand(this.code);

  final String code;

  static ExecutableActionCommand? fromCode(Object? value) {
    for (final command in values) {
      if (command.code == value) {
        return command;
      }
    }
    return null;
  }
}

class ExecutableActionTarget {
  ExecutableActionTarget({
    required this.id,
    required this.kind,
    required this.command,
    this.targetId,
    this.estimatedMinutes,
    Map<String, Object> metadata = const {},
  }) : metadata = Map.unmodifiable(metadata) {
    _validate();
  }

  factory ExecutableActionTarget.fromJson(Map<String, dynamic> json) {
    const allowedKeys = {
      'contract_version',
      'id',
      'kind',
      'command',
      'target_id',
      'estimated_minutes',
      'metadata',
    };
    if (json.keys.any((key) => !allowedKeys.contains(key))) {
      throw const UnsupportedActionTargetException(
        'Executable action contains unknown fields.',
      );
    }
    if (json['contract_version'] != contractVersion) {
      throw const UnsupportedActionTargetException(
        'Unsupported executable action contract.',
      );
    }
    if (json['id'] is! String ||
        json['target_id'] != null && json['target_id'] is! String) {
      throw const UnsupportedActionTargetException(
        'Executable action identity must be text.',
      );
    }
    final kind = ExecutableActionKind.fromCode(json['kind']);
    final command = ExecutableActionCommand.fromCode(json['command']);
    if (kind == null || command == null) {
      throw const UnsupportedActionTargetException(
        'Unknown executable action kind or command.',
      );
    }
    final rawMetadata = json['metadata'];
    if (json.containsKey('metadata') && rawMetadata is! Map) {
      throw const UnsupportedActionTargetException(
        'Executable action metadata must be an object.',
      );
    }
    final metadata = <String, Object>{};
    if (rawMetadata is Map) {
      for (final entry in rawMetadata.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! Object) {
          throw const UnsupportedActionTargetException(
            'Executable action metadata is invalid.',
          );
        }
        metadata[key] = value;
      }
    }
    final estimate = json['estimated_minutes'];
    if (estimate != null && estimate is! int) {
      throw const UnsupportedActionTargetException(
        'Executable action estimate must be a whole number.',
      );
    }
    return ExecutableActionTarget(
      id: json['id'] as String,
      kind: kind,
      command: command,
      targetId: json['target_id'] as String?,
      estimatedMinutes: estimate as int?,
      metadata: metadata,
    );
  }

  static const contractVersion = 'executable-action-v1';
  static const allowedMetadataKeys = {
    'entry_date',
    'focus_minutes',
    'habit_outcome',
    'route',
    'source',
    'target_kind',
  };
  static const allowedCaptureRoutes = {
    '/quick-mood-check-in',
    '/morning-calibration',
  };

  final String id;
  final ExecutableActionKind kind;
  final ExecutableActionCommand command;
  final String? targetId;
  final int? estimatedMinutes;
  final Map<String, Object> metadata;

  static final _identifierPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._:-]*$',
  );
  static final _sourcePattern = RegExp(r'^[a-z0-9][a-z0-9._:-]*$');
  static final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  Map<String, dynamic> toJson() => {
        'contract_version': contractVersion,
        'id': id,
        'kind': kind.code,
        'command': command.code,
        'target_id': targetId,
        'estimated_minutes': estimatedMinutes,
        'metadata': metadata,
      };

  ExecutableActionAvailability availability({
    required bool canUseSyncedExecution,
    bool canUseWeeklyReview = false,
  }) {
    if (command == ExecutableActionCommand.reviewPlan) {
      return canUseSyncedExecution && canUseWeeklyReview
          ? const ExecutableActionAvailability.available()
          : const ExecutableActionAvailability.unavailable(
              'Weekly review requires a synced account.',
            );
    }
    if (command == ExecutableActionCommand.openCapture) {
      return const ExecutableActionAvailability.available();
    }
    if (!canUseSyncedExecution) {
      return const ExecutableActionAvailability.unavailable(
        'This action requires a synced account.',
      );
    }
    return const ExecutableActionAvailability.available();
  }

  void _validate() {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty ||
        normalizedId.length > 200 ||
        normalizedId != id ||
        !_identifierPattern.hasMatch(id)) {
      throw const UnsupportedActionTargetException(
        'Executable action id is invalid.',
      );
    }
    if (targetId != null &&
        (targetId!.trim().isEmpty ||
            targetId!.length > 200 ||
            targetId!.trim() != targetId ||
            !_identifierPattern.hasMatch(targetId!))) {
      throw const UnsupportedActionTargetException(
        'Executable action target id is invalid.',
      );
    }
    if (estimatedMinutes != null &&
        (estimatedMinutes! < 1 || estimatedMinutes! > 480)) {
      throw const UnsupportedActionTargetException(
        'Executable action estimate is out of range.',
      );
    }
    for (final entry in metadata.entries) {
      if (!allowedMetadataKeys.contains(entry.key) ||
          entry.value is! String &&
              entry.value is! int &&
              entry.value is! bool) {
        throw const UnsupportedActionTargetException(
          'Executable action metadata is unsupported.',
        );
      }
      _validateMetadataValue(entry.key, entry.value);
    }

    final allowedForCommand = switch (command) {
      ExecutableActionCommand.openTask ||
      ExecutableActionCommand.completeTask =>
        const {'source'},
      ExecutableActionCommand.logHabit => const {
          'entry_date',
          'habit_outcome',
          'source',
        },
      ExecutableActionCommand.startFocus => const {
          'focus_minutes',
          'source',
          'target_kind',
        },
      ExecutableActionCommand.reviewPlan => const {'source'},
      ExecutableActionCommand.openCapture => const {
          'entry_date',
          'route',
          'source',
        },
    };
    if (metadata.keys.any((key) => !allowedForCommand.contains(key))) {
      throw const UnsupportedActionTargetException(
        'Executable action metadata does not match its command.',
      );
    }

    switch (command) {
      case ExecutableActionCommand.openTask:
      case ExecutableActionCommand.completeTask:
        _requireKindAndTarget(ExecutableActionKind.task);
      case ExecutableActionCommand.logHabit:
        _requireKindAndTarget(ExecutableActionKind.habit);
      case ExecutableActionCommand.startFocus:
        if (kind != ExecutableActionKind.focus) {
          throw const UnsupportedActionTargetException(
            'Focus commands require a focus action.',
          );
        }
        final targetKind = metadata['target_kind'];
        if (targetId != null && targetKind != 'task' && targetKind != 'habit') {
          throw const UnsupportedActionTargetException(
            'A linked focus action requires task or habit target_kind.',
          );
        }
        if (targetId == null && targetKind != null) {
          throw const UnsupportedActionTargetException(
            'Focus target_kind requires a linked target.',
          );
        }
        if (estimatedMinutes != null &&
            (estimatedMinutes! < 5 || estimatedMinutes! > 240)) {
          throw const UnsupportedActionTargetException(
            'Focus estimates cannot exceed 240 minutes.',
          );
        }
        final focusMinutes = metadata['focus_minutes'];
        if (focusMinutes is int &&
            estimatedMinutes != null &&
            focusMinutes != estimatedMinutes) {
          throw const UnsupportedActionTargetException(
            'Focus duration fields must agree.',
          );
        }
      case ExecutableActionCommand.reviewPlan:
        if (kind != ExecutableActionKind.planning) {
          throw const UnsupportedActionTargetException(
            'Plan commands require a planning action.',
          );
        }
      case ExecutableActionCommand.openCapture:
        if (kind != ExecutableActionKind.capture ||
            targetId != null ||
            !allowedCaptureRoutes.contains(metadata['route'])) {
          throw const UnsupportedActionTargetException(
            'Capture commands require an implemented capture route.',
          );
        }
    }
  }

  static void _validateMetadataValue(String key, Object value) {
    switch (key) {
      case 'entry_date':
        if (value is! String || !_isCalendarDate(value)) {
          throw const UnsupportedActionTargetException(
            'Executable action entry date is invalid.',
          );
        }
      case 'focus_minutes':
        if (value is! int || value < 5 || value > 240) {
          throw const UnsupportedActionTargetException(
            'Executable focus minutes are invalid.',
          );
        }
      case 'habit_outcome':
        if (value != 'completed' && value != 'skipped') {
          throw const UnsupportedActionTargetException(
            'Executable habit outcome is invalid.',
          );
        }
      case 'route':
        if (value is! String || !allowedCaptureRoutes.contains(value)) {
          throw const UnsupportedActionTargetException(
            'Executable action route is invalid.',
          );
        }
      case 'source':
        if (value is! String ||
            value.length > 64 ||
            !_sourcePattern.hasMatch(value)) {
          throw const UnsupportedActionTargetException(
            'Executable action source is invalid.',
          );
        }
      case 'target_kind':
        if (value != 'task' && value != 'habit') {
          throw const UnsupportedActionTargetException(
            'Executable focus target kind is invalid.',
          );
        }
    }
  }

  static bool _isCalendarDate(String value) {
    if (!_datePattern.hasMatch(value)) {
      return false;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return false;
    }
    final parts = value.split('-').map(int.parse).toList();
    return parsed.year == parts[0] &&
        parsed.month == parts[1] &&
        parsed.day == parts[2];
  }

  void _requireKindAndTarget(ExecutableActionKind requiredKind) {
    if (kind != requiredKind || targetId == null) {
      throw const UnsupportedActionTargetException(
        'Executable action kind and target do not match its command.',
      );
    }
  }
}

class ExecutableActionAvailability {
  const ExecutableActionAvailability.available()
      : isAvailable = true,
        reason = null;

  const ExecutableActionAvailability.unavailable(this.reason)
      : isAvailable = false;

  final bool isAvailable;
  final String? reason;
}

class UnsupportedActionTargetException implements Exception {
  const UnsupportedActionTargetException(this.message);

  final String message;

  @override
  String toString() => message;
}
