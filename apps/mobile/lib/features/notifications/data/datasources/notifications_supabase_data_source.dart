import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/app_user_resolver.dart';
import '../../../../core/supabase/supabase_tables.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/entities/notification_lifecycle.dart';

typedef NotificationsClock = DateTime Function();

class NotificationsSupabaseDataSource {
  const NotificationsSupabaseDataSource(
    this._client, {
    this.mapper = const NotificationsSupabaseRowMapper(),
    this.clock = DateTime.now,
  });

  final SupabaseClient _client;
  final NotificationsSupabaseRowMapper mapper;
  final NotificationsClock clock;

  Future<List<AppNotification>> getNotifications() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final intent = NotificationsSupabaseQueryIntent.at(clock());
    final rows = await _client
        .from(SupabaseTables.notifications)
        .select(NotificationsSupabaseQueryIntent.columns)
        .eq('user_id', userId)
        .isFilter(NotificationsSupabaseQueryIntent.dismissedAtColumn, null)
        .or(intent.dueAtFilter)
        .order('created_at', ascending: false)
        .limit(30);

    return mapper.visibleFromRows(
      List<Map<String, dynamic>>.from(rows as List),
      now: intent.nowUtc,
    );
  }
}

class NotificationsSupabaseQueryIntent {
  const NotificationsSupabaseQueryIntent._(this.nowUtc);

  factory NotificationsSupabaseQueryIntent.at(DateTime now) {
    return NotificationsSupabaseQueryIntent._(now.toUtc());
  }

  static const columns =
      'id,title,message,type,priority,action_url,created_at,updated_at,'
      'is_read,read_at,dismissed_at,due_at';
  static const dismissedAtColumn = 'dismissed_at';

  final DateTime nowUtc;

  String get dueAtFilter =>
      'due_at.is.null,due_at.lte.${nowUtc.toIso8601String()}';
}

class NotificationsSupabaseRowMapper {
  const NotificationsSupabaseRowMapper();

  AppNotification fromRow(Map<String, dynamic> row) {
    requireNotificationExactKeys(
      row,
      const {
        'id',
        'title',
        'message',
        'type',
        'priority',
        'action_url',
        'created_at',
        'updated_at',
        'is_read',
        'read_at',
        'dismissed_at',
        'due_at',
      },
      'Notification row',
    );
    final id = row['id'];
    final title = row['title'];
    final message = row['message'];
    final type = row['type'];
    final priority = row['priority'];
    final actionUrl = row['action_url'];
    final isRead = row['is_read'];
    if (id is! String || !isNotificationUuid(id)) {
      throw const NotificationLifecycleContractException(
        'Notification row id is invalid.',
      );
    }
    for (final value in [title, message, type, priority]) {
      if (value is! String || value.trim().isEmpty) {
        throw const NotificationLifecycleContractException(
          'Notification row text is invalid.',
        );
      }
    }
    if ((actionUrl != null && actionUrl is! String) || isRead is! bool) {
      throw const NotificationLifecycleContractException(
        'Notification row scalar fields are invalid.',
      );
    }
    final createdAt =
        requiredNotificationAwareDateTime(row['created_at'], 'created_at');
    final updatedAt =
        requiredNotificationAwareDateTime(row['updated_at'], 'updated_at');
    final readAt = optionalNotificationAwareDateTime(row['read_at'], 'read_at');
    final dismissedAt = optionalNotificationAwareDateTime(
      row['dismissed_at'],
      'dismissed_at',
    );
    final dueAt = optionalNotificationAwareDateTime(row['due_at'], 'due_at');
    if (updatedAt.isBefore(createdAt) ||
        isRead != (readAt != null) ||
        (dismissedAt != null && !isRead) ||
        (readAt?.isAfter(updatedAt) ?? false) ||
        (dismissedAt?.isAfter(updatedAt) ?? false)) {
      throw const NotificationLifecycleContractException(
        'Notification row lifecycle state is invalid.',
      );
    }

    return AppNotification(
      id: id,
      title: title as String,
      body: message as String,
      type: type as String,
      priority: priority as String,
      actionUrl: actionUrl as String?,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isRead: isRead,
      readAt: readAt,
      dismissedAt: dismissedAt,
      dueAt: dueAt,
    );
  }

  List<AppNotification> visibleFromRows(
    List<Map<String, dynamic>> rows, {
    required DateTime now,
  }) {
    final nowUtc = now.toUtc();
    return rows
        .map(fromRow)
        .where(
          (notification) =>
              notification.dismissedAt == null &&
              (notification.dueAt == null ||
                  !notification.dueAt!.isAfter(nowUtc)),
        )
        .toList(growable: false);
  }
}
