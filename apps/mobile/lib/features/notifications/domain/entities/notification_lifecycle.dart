const notificationLifecycleContractVersion = 'notification-lifecycle-v1';

final _notificationUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _requestUuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

enum NotificationLifecycleCommand {
  markRead('mark_read'),
  markUnread('mark_unread'),
  dismiss('dismiss');

  const NotificationLifecycleCommand(this.wireValue);

  final String wireValue;

  static NotificationLifecycleCommand parse(Object? value) {
    for (final command in values) {
      if (value == command.wireValue) return command;
    }
    throw const NotificationLifecycleContractException(
      'Notification lifecycle command is invalid.',
    );
  }
}

class NotificationLifecycleRequest {
  NotificationLifecycleRequest({
    required this.notificationId,
    required this.requestId,
    required this.command,
    required this.expectedUpdatedAt,
  }) {
    if (!_notificationUuidPattern.hasMatch(notificationId)) {
      throw const NotificationLifecycleContractException(
        'Notification id is invalid.',
      );
    }
    if (!_requestUuidV4Pattern.hasMatch(requestId)) {
      throw const NotificationLifecycleContractException(
        'Notification lifecycle request id is invalid.',
      );
    }
    if (!expectedUpdatedAt.isUtc) {
      throw const NotificationLifecycleContractException(
        'Expected notification update time must be timezone-aware.',
      );
    }
  }

  final String notificationId;
  final String requestId;
  final NotificationLifecycleCommand command;
  final DateTime expectedUpdatedAt;

  Map<String, dynamic> toJson() => {
        'contract_version': notificationLifecycleContractVersion,
        'request_id': requestId,
        'command': command.wireValue,
        'expected_updated_at': expectedUpdatedAt.toIso8601String(),
      };
}

class NotificationLifecycleResult {
  const NotificationLifecycleResult._({
    required this.notificationId,
    required this.command,
    required this.isRead,
    required this.readAt,
    required this.dismissedAt,
    required this.updatedAt,
    required this.replayed,
  });

  factory NotificationLifecycleResult.fromJson(Map<String, dynamic> json) {
    _requireExactKeys(
      json,
      const {
        'contract_version',
        'notification_id',
        'command',
        'is_read',
        'read_at',
        'dismissed_at',
        'updated_at',
        'replayed',
      },
      'Notification lifecycle response',
    );
    if (json['contract_version'] != notificationLifecycleContractVersion) {
      throw const NotificationLifecycleContractException(
        'Notification lifecycle contract version is invalid.',
      );
    }
    final notificationId = json['notification_id'];
    if (notificationId is! String ||
        !_notificationUuidPattern.hasMatch(notificationId)) {
      throw const NotificationLifecycleContractException(
        'Notification lifecycle response id is invalid.',
      );
    }
    final command = NotificationLifecycleCommand.parse(json['command']);
    final isRead = json['is_read'];
    final replayed = json['replayed'];
    if (isRead is! bool || replayed is! bool) {
      throw const NotificationLifecycleContractException(
        'Notification lifecycle response booleans are invalid.',
      );
    }
    final readAt = _optionalAwareDateTime(json['read_at'], 'read_at');
    final dismissedAt =
        _optionalAwareDateTime(json['dismissed_at'], 'dismissed_at');
    final updatedAt = _requiredAwareDateTime(json['updated_at'], 'updated_at');
    if (isRead != (readAt != null)) {
      throw const NotificationLifecycleContractException(
        'Notification read state and timestamp do not match.',
      );
    }
    if ((readAt?.isAfter(updatedAt) ?? false) ||
        (dismissedAt?.isAfter(updatedAt) ?? false)) {
      throw const NotificationLifecycleContractException(
        'Notification lifecycle timestamps exceed updated_at.',
      );
    }
    switch (command) {
      case NotificationLifecycleCommand.markRead:
        if (!isRead || dismissedAt != null) {
          throw const NotificationLifecycleContractException(
            'Mark-read response state is invalid.',
          );
        }
      case NotificationLifecycleCommand.markUnread:
        if (isRead || dismissedAt != null) {
          throw const NotificationLifecycleContractException(
            'Mark-unread response state is invalid.',
          );
        }
      case NotificationLifecycleCommand.dismiss:
        if (!isRead || readAt == null || dismissedAt == null) {
          throw const NotificationLifecycleContractException(
            'Dismiss response lifecycle state is invalid.',
          );
        }
    }
    return NotificationLifecycleResult._(
      notificationId: notificationId,
      command: command,
      isRead: isRead,
      readAt: readAt,
      dismissedAt: dismissedAt,
      updatedAt: updatedAt,
      replayed: replayed,
    );
  }

  final String notificationId;
  final NotificationLifecycleCommand command;
  final bool isRead;
  final DateTime? readAt;
  final DateTime? dismissedAt;
  final DateTime updatedAt;
  final bool replayed;

  void requireMatches(NotificationLifecycleRequest request) {
    if (notificationId != request.notificationId ||
        command != request.command ||
        updatedAt.isBefore(request.expectedUpdatedAt)) {
      throw const NotificationLifecycleContractException(
        'Notification lifecycle response does not match its request.',
      );
    }
  }
}

DateTime requiredNotificationAwareDateTime(Object? value, String field) {
  return _requiredAwareDateTime(value, field);
}

DateTime? optionalNotificationAwareDateTime(Object? value, String field) {
  return _optionalAwareDateTime(value, field);
}

bool isNotificationUuid(String value) =>
    _notificationUuidPattern.hasMatch(value);

void requireNotificationExactKeys(
  Map<String, dynamic> json,
  Set<String> expected,
  String label,
) {
  _requireExactKeys(json, expected, label);
}

DateTime _requiredAwareDateTime(Object? value, String field) {
  if (value is! String) {
    throw NotificationLifecycleContractException(
      'Notification $field must be a timezone-aware timestamp.',
    );
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw NotificationLifecycleContractException(
      'Notification $field must be a timezone-aware timestamp.',
    );
  }
  return parsed;
}

DateTime? _optionalAwareDateTime(Object? value, String field) {
  if (value == null) return null;
  return _requiredAwareDateTime(value, field);
}

void _requireExactKeys(
  Map<String, dynamic> json,
  Set<String> expected,
  String label,
) {
  final keys = json.keys.toSet();
  if (keys.length != expected.length ||
      keys.difference(expected).isNotEmpty ||
      expected.difference(keys).isNotEmpty) {
    throw NotificationLifecycleContractException('$label shape is invalid.');
  }
}

class NotificationLifecycleContractException implements Exception {
  const NotificationLifecycleContractException(this.message);

  final String message;

  @override
  String toString() => 'NotificationLifecycleContractException: $message';
}
