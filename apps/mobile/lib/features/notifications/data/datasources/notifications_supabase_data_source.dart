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

  Future<List<AppNotification>> getPendingInAppNotifications({
    required List<String> enabledCategories,
  }) async {
    const supportedCategories = {
      'focus_prompt',
      'recovery_prompt',
      'weekly_summary',
    };
    if (enabledCategories.isEmpty) return const [];
    if (enabledCategories.toSet().length != enabledCategories.length ||
        enabledCategories.any(
          (category) => !supportedCategories.contains(category),
        )) {
      throw ArgumentError.value(
        enabledCategories,
        'enabledCategories',
        'Pending in-app categories must be known and unique.',
      );
    }
    final userId = await AppUserResolver(_client).resolveUserId();
    final nowUtc = clock().toUtc();
    final rows = await _client
        .from(SupabaseTables.notifications)
        .select(NotificationsSupabaseQueryIntent.columns)
        .eq('user_id', userId)
        .not('generation_key', 'is', null)
        .inFilter('generation_category', enabledCategories)
        .isFilter('in_app_delivered_at', null)
        .isFilter(NotificationsSupabaseQueryIntent.dismissedAtColumn, null)
        .lte('due_at', nowUtc.toIso8601String())
        .order('due_at')
        .order('id')
        .limit(3);

    return mapper.pendingInAppFromRows(
      List<Map<String, dynamic>>.from(rows as List),
      now: nowUtc,
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
      'is_read,read_at,dismissed_at,due_at,metadata,generation_key,'
      'generation_category,delivery_date,in_app_delivered_at';
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
        'metadata',
        'generation_key',
        'generation_category',
        'delivery_date',
        'in_app_delivered_at',
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
    final inAppDeliveredAt = optionalNotificationAwareDateTime(
      row['in_app_delivered_at'],
      'in_app_delivered_at',
    );
    final generation = _generationFromRow(row);
    if (updatedAt.isBefore(createdAt) ||
        isRead != (readAt != null) ||
        (dismissedAt != null && !isRead) ||
        (readAt?.isAfter(updatedAt) ?? false) ||
        (dismissedAt?.isAfter(updatedAt) ?? false) ||
        (inAppDeliveredAt?.isBefore(createdAt) ?? false) ||
        (generation != null && dueAt == null)) {
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
      generationKey: generation?.key,
      generationCategory: generation?.category,
      deliveryDate: generation?.deliveryDate,
      inAppDeliveredAt: inAppDeliveredAt,
      generationProvenance: generation?.provenance,
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

  List<AppNotification> pendingInAppFromRows(
    List<Map<String, dynamic>> rows, {
    required DateTime now,
  }) {
    final nowUtc = now.toUtc();
    return rows
        .map(fromRow)
        .where(
          (notification) =>
              notification.isDeterministicallyGenerated &&
              notification.inAppDeliveredAt == null &&
              notification.dismissedAt == null &&
              notification.dueAt != null &&
              !notification.dueAt!.isAfter(nowUtc),
        )
        .take(3)
        .toList(growable: false);
  }

  _GeneratedRow? _generationFromRow(Map<String, dynamic> row) {
    final key = row['generation_key'];
    final category = row['generation_category'];
    final deliveryDate = row['delivery_date'];
    final deliveredAt = row['in_app_delivered_at'];
    final metadata = row['metadata'];
    if (key == null &&
        category == null &&
        deliveryDate == null &&
        deliveredAt == null) {
      return null;
    }
    if (key is! String ||
        key.isEmpty ||
        key.length > 200 ||
        category is! String ||
        !const {
          'focus_prompt',
          'recovery_prompt',
          'weekly_summary',
        }.contains(category) ||
        deliveryDate is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(deliveryDate) ||
        metadata is! Map<String, dynamic>) {
      throw const NotificationLifecycleContractException(
        'Generated notification row is invalid.',
      );
    }
    requireNotificationExactKeys(
      metadata,
      const {
        'contract_version',
        'origin',
        'category',
        'reason_code',
        'delivery_date',
        'timezone',
        'source_kind',
        'source_id',
        'source_generated_at',
        'sensitive_copy_excluded',
        'llm_used',
      },
      'Notification generation provenance',
    );
    final reasonCode = metadata['reason_code'];
    final timezone = metadata['timezone'];
    final sourceKind = metadata['source_kind'];
    final sourceId = metadata['source_id'];
    if (metadata['contract_version'] != 'notification-generation-v1' ||
        metadata['origin'] != 'deterministic_backend' ||
        metadata['category'] != category ||
        metadata['delivery_date'] != deliveryDate ||
        metadata['sensitive_copy_excluded'] != true ||
        metadata['llm_used'] != false ||
        reasonCode is! String ||
        reasonCode.isEmpty ||
        timezone is! String ||
        timezone.isEmpty ||
        sourceKind is! String ||
        !const {
          'daily_briefing',
          'daily_state',
          'weekly_review',
        }.contains(sourceKind) ||
        sourceId is! String ||
        sourceId.isEmpty) {
      throw const NotificationLifecycleContractException(
        'Generated notification provenance is invalid.',
      );
    }
    return _GeneratedRow(
      key: key,
      category: category,
      deliveryDate: deliveryDate,
      provenance: NotificationGenerationProvenance(
        reasonCode: reasonCode,
        timezone: timezone,
        sourceKind: sourceKind,
        sourceId: sourceId,
        sourceGeneratedAt: requiredNotificationAwareDateTime(
          metadata['source_generated_at'],
          'source_generated_at',
        ),
      ),
    );
  }
}

class _GeneratedRow {
  const _GeneratedRow({
    required this.key,
    required this.category,
    required this.deliveryDate,
    required this.provenance,
  });

  final String key;
  final String category;
  final String deliveryDate;
  final NotificationGenerationProvenance provenance;
}
