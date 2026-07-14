import 'app_notification.dart';
import 'notification_lifecycle.dart';

const notificationSettingsContractVersion = 'notification-settings-v1';
const notificationConsentVersion = 'in-app-notification-consent-v1';
const notificationDeliveryContractVersion = 'in-app-notification-delivery-v1';

final _requestUuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _clockTimePattern = RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$');

class NotificationCategories {
  const NotificationCategories({
    required this.focusPrompt,
    required this.recoveryPrompt,
    required this.weeklySummary,
  });

  factory NotificationCategories.fromJson(Map<String, dynamic> json) {
    requireNotificationExactKeys(
      json,
      const {'focus_prompt', 'recovery_prompt', 'weekly_summary'},
      'Notification categories',
    );
    final focusPrompt = json['focus_prompt'];
    final recoveryPrompt = json['recovery_prompt'];
    final weeklySummary = json['weekly_summary'];
    if (focusPrompt is! bool ||
        recoveryPrompt is! bool ||
        weeklySummary is! bool) {
      throw const NotificationLifecycleContractException(
        'Notification categories are invalid.',
      );
    }
    return NotificationCategories(
      focusPrompt: focusPrompt,
      recoveryPrompt: recoveryPrompt,
      weeklySummary: weeklySummary,
    );
  }

  final bool focusPrompt;
  final bool recoveryPrompt;
  final bool weeklySummary;

  List<String> get enabledCategoryCodes => List.unmodifiable([
        if (focusPrompt) 'focus_prompt',
        if (recoveryPrompt) 'recovery_prompt',
        if (weeklySummary) 'weekly_summary',
      ]);

  bool allows(String? category) => switch (category) {
        'focus_prompt' => focusPrompt,
        'recovery_prompt' => recoveryPrompt,
        'weekly_summary' => weeklySummary,
        _ => false,
      };

  Map<String, dynamic> toJson() => {
        'focus_prompt': focusPrompt,
        'recovery_prompt': recoveryPrompt,
        'weekly_summary': weeklySummary,
      };
}

class NotificationQuietHours {
  NotificationQuietHours({required this.startsAt, required this.endsAt}) {
    if (!_clockTimePattern.hasMatch(startsAt) ||
        !_clockTimePattern.hasMatch(endsAt)) {
      throw const NotificationLifecycleContractException(
        'Notification quiet hours must use HH:mm.',
      );
    }
  }

  factory NotificationQuietHours.fromJson(Map<String, dynamic> json) {
    requireNotificationExactKeys(
      json,
      const {'starts_at', 'ends_at'},
      'Notification quiet hours',
    );
    final startsAt = json['starts_at'];
    final endsAt = json['ends_at'];
    if (startsAt is! String || endsAt is! String) {
      throw const NotificationLifecycleContractException(
        'Notification quiet hours are invalid.',
      );
    }
    return NotificationQuietHours(startsAt: startsAt, endsAt: endsAt);
  }

  final String startsAt;
  final String endsAt;

  Map<String, dynamic> toJson() => {
        'starts_at': startsAt,
        'ends_at': endsAt,
      };
}

class NotificationSettings {
  const NotificationSettings._({
    required this.inAppDeliveryEnabled,
    required this.consentVersion,
    required this.consentedAt,
    required this.disabledAt,
    required this.categories,
    required this.quietHours,
    required this.dailyLimit,
    required this.updatedAt,
    required this.replayed,
  });

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    requireNotificationExactKeys(
      json,
      const {
        'contract_version',
        'in_app_delivery_enabled',
        'consent_version',
        'consented_at',
        'disabled_at',
        'categories',
        'quiet_hours',
        'daily_limit',
        'updated_at',
        'replayed',
      },
      'Notification settings response',
    );
    if (json['contract_version'] != notificationSettingsContractVersion) {
      throw const NotificationLifecycleContractException(
        'Notification settings contract version is invalid.',
      );
    }
    final enabled = json['in_app_delivery_enabled'];
    final consentVersion = json['consent_version'];
    final categoriesJson = json['categories'];
    final quietHoursJson = json['quiet_hours'];
    final dailyLimit = json['daily_limit'];
    final replayed = json['replayed'];
    if (enabled is! bool ||
        (consentVersion != null && consentVersion is! String) ||
        categoriesJson is! Map<String, dynamic> ||
        (quietHoursJson != null && quietHoursJson is! Map<String, dynamic>) ||
        dailyLimit is! int ||
        dailyLimit < 1 ||
        dailyLimit > 5 ||
        replayed is! bool) {
      throw const NotificationLifecycleContractException(
        'Notification settings scalar fields are invalid.',
      );
    }
    final consentedAt = optionalNotificationAwareDateTime(
      json['consented_at'],
      'consented_at',
    );
    final disabledAt = optionalNotificationAwareDateTime(
      json['disabled_at'],
      'disabled_at',
    );
    final updatedAt = requiredNotificationAwareDateTime(
      json['updated_at'],
      'updated_at',
    );
    if (enabled) {
      if (consentVersion != notificationConsentVersion ||
          consentedAt == null ||
          disabledAt != null) {
        throw const NotificationLifecycleContractException(
          'Enabled notification settings lack active consent.',
        );
      }
    } else if (consentedAt == null) {
      if (consentVersion != null || disabledAt != null) {
        throw const NotificationLifecycleContractException(
          'Never-enabled notification consent is invalid.',
        );
      }
    } else if (consentVersion != notificationConsentVersion ||
        disabledAt == null ||
        disabledAt.isBefore(consentedAt)) {
      throw const NotificationLifecycleContractException(
        'Disabled notification consent is invalid.',
      );
    }
    if ((consentedAt?.isAfter(updatedAt) ?? false) ||
        (disabledAt?.isAfter(updatedAt) ?? false)) {
      throw const NotificationLifecycleContractException(
        'Notification consent timestamps exceed updated_at.',
      );
    }
    return NotificationSettings._(
      inAppDeliveryEnabled: enabled,
      consentVersion: consentVersion as String?,
      consentedAt: consentedAt,
      disabledAt: disabledAt,
      categories: NotificationCategories.fromJson(categoriesJson),
      quietHours: quietHoursJson == null
          ? null
          : NotificationQuietHours.fromJson(quietHoursJson),
      dailyLimit: dailyLimit,
      updatedAt: updatedAt,
      replayed: replayed,
    );
  }

  final bool inAppDeliveryEnabled;
  final String? consentVersion;
  final DateTime? consentedAt;
  final DateTime? disabledAt;
  final NotificationCategories categories;
  final NotificationQuietHours? quietHours;
  final int dailyLimit;
  final DateTime updatedAt;
  final bool replayed;
}

class NotificationSettingsUpdate {
  NotificationSettingsUpdate({
    required this.requestId,
    required this.expectedUpdatedAt,
    required this.inAppDeliveryEnabled,
    required this.categories,
    required this.quietHours,
    required this.dailyLimit,
  }) {
    if (!_requestUuidV4Pattern.hasMatch(requestId)) {
      throw const NotificationLifecycleContractException(
        'Notification settings request id is invalid.',
      );
    }
    if (!expectedUpdatedAt.isUtc || dailyLimit < 1 || dailyLimit > 5) {
      throw const NotificationLifecycleContractException(
        'Notification settings update is invalid.',
      );
    }
  }

  final String requestId;
  final DateTime expectedUpdatedAt;
  final bool inAppDeliveryEnabled;
  final NotificationCategories categories;
  final NotificationQuietHours? quietHours;
  final int dailyLimit;

  Map<String, dynamic> toJson() => {
        'contract_version': notificationSettingsContractVersion,
        'request_id': requestId,
        'expected_updated_at': expectedUpdatedAt.toIso8601String(),
        'in_app_delivery_enabled': inAppDeliveryEnabled,
        'consent_version': notificationConsentVersion,
        'categories': categories.toJson(),
        'quiet_hours': quietHours?.toJson(),
        'daily_limit': dailyLimit,
      };
}

class NotificationDeliveryReceipt {
  const NotificationDeliveryReceipt._({
    required this.notificationId,
    required this.deliveredAt,
    required this.replayed,
  });

  factory NotificationDeliveryReceipt.fromJson(Map<String, dynamic> json) {
    requireNotificationExactKeys(
      json,
      const {
        'contract_version',
        'notification_id',
        'channel',
        'delivered_at',
        'replayed',
      },
      'Notification delivery response',
    );
    final notificationId = json['notification_id'];
    final replayed = json['replayed'];
    if (json['contract_version'] != notificationDeliveryContractVersion ||
        json['channel'] != 'in_app' ||
        notificationId is! String ||
        !isNotificationUuid(notificationId) ||
        replayed is! bool) {
      throw const NotificationLifecycleContractException(
        'Notification delivery response is invalid.',
      );
    }
    return NotificationDeliveryReceipt._(
      notificationId: notificationId,
      deliveredAt: requiredNotificationAwareDateTime(
        json['delivered_at'],
        'delivered_at',
      ),
      replayed: replayed,
    );
  }

  final String notificationId;
  final DateTime deliveredAt;
  final bool replayed;

  void requireMatches(AppNotification notification) {
    if (notificationId != notification.id ||
        deliveredAt.isBefore(notification.createdAt)) {
      throw const NotificationLifecycleContractException(
        'Notification delivery response does not match its row.',
      );
    }
  }
}
