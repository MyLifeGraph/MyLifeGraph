import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/app_user_resolver.dart';
import '../../../core/supabase/supabase_tables.dart';

class CoachSupabaseService {
  const CoachSupabaseService(this._client);

  final SupabaseClient _client;

  Future<List<CoachChatMessage>> getMessages() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final rows = await _client
        .from(SupabaseTables.coachMessages)
        .select()
        .eq('user_id', userId)
        .order('created_at')
        .limit(40);

    return List<Map<String, dynamic>>.from(rows as List).map((row) {
      return CoachChatMessage(
        text: row['content'] as String,
        isUser: '${row['role']}'.toLowerCase() == 'user',
      );
    }).toList();
  }

  Future<void> addMessage({
    required String text,
    required bool isUser,
  }) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    await _client.from(SupabaseTables.coachMessages).insert({
      'user_id': userId,
      'role': isUser ? 'user' : 'assistant',
      'content': text,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}

class CoachChatMessage {
  const CoachChatMessage({
    required this.text,
    required this.isUser,
  });

  final String text;
  final bool isUser;
}
