import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/app_user_resolver.dart';
import '../../../../core/supabase/supabase_tables.dart';

class DailyCheckInSupabaseDataSource {
  const DailyCheckInSupabaseDataSource(this._client);

  final SupabaseClient _client;

  Future<void> saveDefaultCheckIn() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, now.day);

    await _client.from(SupabaseTables.dailyLogs).upsert(
      {
        'user_id': userId,
        'entry_date': _dateOnly(date),
        'sleep_hours': 7.2,
        'steps': 8200,
        'activity_level': 6,
        'screen_time_hours': 4.5,
        'focus_minutes': 90,
        'mood_score': 7,
        'mood_label': 'good',
        'energy_level': 6,
        'stress_level': 4,
        'nutrition_notes': 'Balanced, late meals, high protein, skipped meal',
        'day_focus': 'One thing that would make today successful',
        'reflection': 'Logged from the mobile Daily Check-In.',
        'source': 'daily_check_in',
        'updated_at': now.toIso8601String(),
      },
      onConflict: 'user_id,entry_date',
    );

    await _client.from(SupabaseTables.behavioralEvents).insert([
      _event(userId, 'sleep', 7.2, 'hours', now, {'quality': 7}),
      _event(userId, 'activity_steps', 8200, 'steps', now),
      _event(userId, 'activity_level', 6, 'score_0_10', now),
      _event(userId, 'focus', 90, 'minutes', now),
      _event(userId, 'mood', 7, 'score_0_10', now),
      _event(userId, 'energy', 6, 'score_0_10', now),
      _event(userId, 'stress', 4, 'score_0_10', now),
    ]);
  }

  Map<String, dynamic> _event(
    String userId,
    String type,
    num value,
    String unit,
    DateTime occurredAt, [
    Map<String, Object?> metadata = const {},
  ]) {
    return {
      'user_id': userId,
      'event_type': type,
      'value': value,
      'unit': unit,
      'occurred_at': occurredAt.toIso8601String(),
      'source': 'daily_check_in',
      'metadata': metadata,
    };
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
