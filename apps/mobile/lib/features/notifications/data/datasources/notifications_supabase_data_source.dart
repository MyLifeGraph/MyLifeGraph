import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/app_user_resolver.dart';
import '../../../../core/supabase/supabase_tables.dart';
import '../../domain/entities/app_notification.dart';

class NotificationsSupabaseDataSource {
  const NotificationsSupabaseDataSource(
    this._client, {
    this.mapper = const NotificationsSupabaseRowMapper(),
  });

  final SupabaseClient _client;
  final NotificationsSupabaseRowMapper mapper;

  Future<List<AppNotification>> getNotifications() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final rows = await _client
        .from(SupabaseTables.notifications)
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(30);

    return List<Map<String, dynamic>>.from(rows as List)
        .map(mapper.fromRow)
        .toList();
  }
}

class NotificationsSupabaseRowMapper {
  const NotificationsSupabaseRowMapper();

  AppNotification fromRow(Map<String, dynamic> row) {
    final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');
    if (createdAt == null) {
      throw const FormatException('Notification created_at is invalid.');
    }

    return AppNotification(
      id: row['id'] as String,
      title: row['title'] as String,
      body: row['message'] as String,
      type: row['type'] as String,
      priority: row['priority'] as String,
      actionUrl: row['action_url'] as String?,
      createdAt: createdAt,
      isRead: row['is_read'] == true,
    );
  }
}
