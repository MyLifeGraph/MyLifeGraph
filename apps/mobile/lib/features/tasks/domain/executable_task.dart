enum ExecutableTaskStatus {
  todo('todo'),
  inProgress('in_progress'),
  done('done'),
  cancelled('cancelled'),
  archived('archived');

  const ExecutableTaskStatus(this.code);

  final String code;

  static ExecutableTaskStatus? fromCode(Object? value) {
    for (final status in values) {
      if (status.code == value) {
        return status;
      }
    }
    return null;
  }
}

enum ExecutableTaskPriority {
  low('low'),
  medium('medium'),
  high('high'),
  critical('critical');

  const ExecutableTaskPriority(this.code);

  final String code;

  static ExecutableTaskPriority? fromCode(Object? value) {
    for (final priority in values) {
      if (priority.code == value) {
        return priority;
      }
    }
    return null;
  }
}

class ExecutableTask {
  const ExecutableTask({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    required this.updatedAt,
    this.description,
    this.deadline,
    this.estimatedMinutes,
    this.completedAt,
    this.cancelledAt,
  });

  factory ExecutableTask.fromRow(Map<String, dynamic> row) {
    if (row['id'] is! String || row['title'] is! String) {
      throw const TaskCommandException('Task response is invalid.');
    }
    final id = (row['id'] as String).trim();
    final title = (row['title'] as String).trim();
    final status = ExecutableTaskStatus.fromCode(row['status']);
    final priority = ExecutableTaskPriority.fromCode(row['priority']);
    if (id.isEmpty || title.isEmpty || status == null || priority == null) {
      throw const TaskCommandException('Task response is invalid.');
    }
    return ExecutableTask(
      id: id,
      title: title,
      description: _optionalString(row['description']),
      status: status,
      priority: priority,
      deadline: _optionalDateTime(row['deadline']),
      estimatedMinutes: _optionalInt(row['estimated_minutes']),
      completedAt: _optionalDateTime(row['completed_at']),
      cancelledAt: _optionalDateTime(row['cancelled_at']),
      updatedAt: _requiredDateTime(row['updated_at']),
    );
  }

  final String id;
  final String title;
  final String? description;
  final ExecutableTaskStatus status;
  final ExecutableTaskPriority priority;
  final DateTime? deadline;
  final int? estimatedMinutes;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final DateTime updatedAt;

  bool get isOpen =>
      status == ExecutableTaskStatus.todo ||
      status == ExecutableTaskStatus.inProgress;

  bool get isTerminal =>
      status == ExecutableTaskStatus.done ||
      status == ExecutableTaskStatus.cancelled ||
      status == ExecutableTaskStatus.archived;

  static String? _optionalString(Object? value) {
    if (value != null && value is! String) {
      throw const TaskCommandException('Task text is invalid.');
    }
    final text = (value as String?)?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static DateTime? _optionalDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String || value.isEmpty) {
      throw const TaskCommandException('Task timestamp is invalid.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw const TaskCommandException('Task timestamp is invalid.');
    }
    return parsed;
  }

  static DateTime _requiredDateTime(Object? value) {
    final parsed = _optionalDateTime(value);
    if (parsed == null) {
      throw const TaskCommandException('Task timestamp is invalid.');
    }
    return parsed;
  }

  static int? _optionalInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num && value == value.toInt()) {
      return value.toInt();
    }
    throw const TaskCommandException('Task estimate is invalid.');
  }
}

class ExecutableTaskDraft {
  ExecutableTaskDraft({
    required String title,
    String? description,
    this.priority = ExecutableTaskPriority.medium,
    this.deadline,
    this.estimatedMinutes,
  })  : title = title.trim(),
        description = _normalizeDescription(description) {
    validate();
  }

  final String title;
  final String? description;
  final ExecutableTaskPriority priority;
  final DateTime? deadline;
  final int? estimatedMinutes;

  void validate() {
    if (title.isEmpty || title.length > 160) {
      throw const TaskCommandException(
        'Task title must contain 1 to 160 characters.',
      );
    }
    if (description != null && description!.length > 2000) {
      throw const TaskCommandException(
        'Task description must be at most 2000 characters.',
      );
    }
    if (estimatedMinutes != null &&
        (estimatedMinutes! < 5 || estimatedMinutes! > 480)) {
      throw const TaskCommandException(
        'Task estimate must be between 5 and 480 minutes.',
      );
    }
  }

  static String? _normalizeDescription(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class TaskUndoToken {
  const TaskUndoToken({
    required this.taskId,
    required this.status,
    required this.deadline,
    required this.completedAt,
    required this.cancelledAt,
    required this.expectedUpdatedAt,
  });

  factory TaskUndoToken.fromTask(ExecutableTask task) => TaskUndoToken(
        taskId: task.id,
        status: task.status,
        deadline: task.deadline,
        completedAt: task.completedAt,
        cancelledAt: task.cancelledAt,
        expectedUpdatedAt: task.updatedAt,
      );

  factory TaskUndoToken.forTransition({
    required ExecutableTask previous,
    required ExecutableTask current,
  }) =>
      TaskUndoToken(
        taskId: previous.id,
        status: previous.status,
        deadline: previous.deadline,
        completedAt: previous.completedAt,
        cancelledAt: previous.cancelledAt,
        expectedUpdatedAt: current.updatedAt,
      );

  final String taskId;
  final ExecutableTaskStatus status;
  final DateTime? deadline;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final DateTime expectedUpdatedAt;
}

void validateTaskPostpone({
  required DateTime? currentDeadline,
  required DateTime newDeadline,
  required DateTime now,
}) {
  if (!newDeadline.isAfter(now)) {
    throw const TaskCommandException(
      'A postponed deadline must be in the future.',
    );
  }
  if (currentDeadline != null && !newDeadline.isAfter(currentDeadline)) {
    throw const TaskCommandException(
      'A postponed deadline must be later than the current deadline.',
    );
  }
}

class TaskCommandException implements Exception {
  const TaskCommandException(this.message);

  final String message;

  @override
  String toString() => message;
}
