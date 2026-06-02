import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/app_user_resolver.dart';
import '../../../../core/supabase/supabase_tables.dart';

class DailyCheckInSupabaseDataSource {
  const DailyCheckInSupabaseDataSource(this._client);

  final SupabaseClient _client;

  Future<void> saveDefaultCheckIn() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final now = DateTime.now();
    final id = 'daily_${now.microsecondsSinceEpoch}';
    final date = DateTime(now.year, now.month, now.day).toIso8601String();

    await _client.from(SupabaseTables.dailyLogs).upsert({
      'id': id,
      'userId': userId,
      'date': date,
      'sleepHours': 7.2,
      'steps': 8200,
      'activityLevel': 6,
      'screenTimeHours': 4.5,
      'focusMinutes': 90,
      'mood': 'GOOD',
      'energyLevel': 6,
      'nutrition': 'Balanced, late meals, high protein, skipped meal',
      'dayFocus': 'One thing that would make today successful',
      'reflection': 'Logged from the mobile Daily Check-In.',
      'updatedAt': now.toIso8601String(),
    });

    await _client.from(SupabaseTables.sleepLogs).insert({
      'id': 'sleep_${now.microsecondsSinceEpoch}',
      'userId': userId,
      'dailyLogId': id,
      'date': date,
      'hours': 7.2,
      'quality': 7,
    });

    await _client.from(SupabaseTables.activityLogs).insert({
      'id': 'activity_${now.microsecondsSinceEpoch}',
      'userId': userId,
      'dailyLogId': id,
      'date': date,
      'steps': 8200,
      'activityLevel': 6,
      'workoutMinutes': 25,
    });

    await _client.from(SupabaseTables.moodLogs).insert({
      'id': 'mood_${now.microsecondsSinceEpoch}',
      'userId': userId,
      'dailyLogId': id,
      'date': date,
      'mood': 'GOOD',
      'energyLevel': 6,
      'stressLevel': 4,
    });
  }
}
