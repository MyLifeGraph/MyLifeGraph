import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/app_user_resolver.dart';
import '../../../../core/supabase/supabase_tables.dart';
import '../../domain/entities/app_notification.dart';

class NotificationsSupabaseDataSource {
  const NotificationsSupabaseDataSource(this._client);

  final SupabaseClient _client;

  Future<List<AppNotification>> getNotifications() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final rows = await _client
        .from(SupabaseTables.notifications)
        .select()
        .eq('userId', userId)
        .order('createdAt', ascending: false)
        .limit(30);

    return List<Map<String, dynamic>>.from(rows as List).map((row) {
      return AppNotification(
        id: row['id'] as String,
        title: row['title'] as String,
        body: row['message'] as String,
        createdAt: DateTime.tryParse('${row['createdAt']}') ?? DateTime.now(),
        isRead: row['read'] == true,
      );
    }).toList();
  }
}
