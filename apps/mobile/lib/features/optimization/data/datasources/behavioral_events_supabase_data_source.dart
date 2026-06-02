import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_tables.dart';
import '../../domain/entities/behavioral_signal.dart';

class BehavioralEventsSupabaseDataSource {
  const BehavioralEventsSupabaseDataSource(this._client);

  final SupabaseClient _client;

  Future<void> createSignal({
    required String userId,
    required BehavioralSignal signal,
  }) async {
    await _client.from(SupabaseTables.behavioralEvents).insert({
      'user_id': userId,
      'event_type': signal.type,
      'value': signal.value,
      'occurred_at': signal.occurredAt.toIso8601String(),
      'metadata': signal.metadata,
    });
  }
}
