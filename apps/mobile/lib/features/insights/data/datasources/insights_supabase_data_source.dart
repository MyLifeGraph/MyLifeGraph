import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/app_user_resolver.dart';
import '../../../../core/supabase/supabase_tables.dart';
import '../../domain/entities/insight.dart';

class InsightsSupabaseDataSource {
  const InsightsSupabaseDataSource(this._client);

  final SupabaseClient _client;

  Future<List<Insight>> getInsights() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final rows = await _client
        .from(SupabaseTables.aiInsights)
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(20);

    return List<Map<String, dynamic>>.from(rows as List).map((row) {
      return Insight(
        id: row['id'] as String,
        title: row['title'] as String,
        summary: row['description'] as String,
        impact:
            '${((row['confidence'] as num?)?.toDouble() ?? 0.72) * 100 ~/ 1}%',
        tags: [
          '${row['category']}'.toLowerCase(),
          '${row['priority']}'.toLowerCase(),
        ],
      );
    }).toList();
  }
}
