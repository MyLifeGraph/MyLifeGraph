import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/app_user_resolver.dart';
import '../../../core/supabase/supabase_tables.dart';

class HabitCompletionSupabaseDataSource {
  const HabitCompletionSupabaseDataSource(this._client);

  final SupabaseClient _client;

  Future<List<HabitCompletionOption>> fetchActiveHabits() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final today = _dateOnly(DateTime.now());

    final habitRows = await _client
        .from(SupabaseTables.habits)
        .select('id,title,description,frequency,target,updated_at')
        .eq('user_id', userId)
        .eq('active', true)
        .order('updated_at', ascending: false);

    final logRows = await _client
        .from(SupabaseTables.habitLogs)
        .select('habit_id,value')
        .eq('user_id', userId)
        .eq('entry_date', today);

    final completedHabitIds = {
      for (final row in List<Map<String, dynamic>>.from(logRows as List))
        if ((row['value'] as num? ?? 0) > 0) row['habit_id'] as String,
    };

    return List<Map<String, dynamic>>.from(habitRows as List).map((row) {
      final id = row['id'] as String;
      return HabitCompletionOption(
        id: id,
        title: row['title'] as String? ?? 'Habit',
        description: row['description'] as String?,
        frequency: row['frequency'] as String? ?? 'daily',
        target: row['target'] as int? ?? 1,
        completedToday: completedHabitIds.contains(id),
      );
    }).toList();
  }

  Future<void> completeHabit({
    required String habitId,
    String? notes,
  }) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final now = DateTime.now();
    final entryDate = _dateOnly(now);

    await _client.from(SupabaseTables.habitLogs).upsert(
      {
        'user_id': userId,
        'habit_id': habitId,
        'entry_date': entryDate,
        'value': 1,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
      onConflict: 'habit_id,entry_date',
    );

    await _client
        .from(SupabaseTables.habits)
        .update({
          'updated_at': now.toIso8601String(),
        })
        .eq('id', habitId)
        .eq('user_id', userId);
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class HabitCompletionOption {
  const HabitCompletionOption({
    required this.id,
    required this.title,
    required this.frequency,
    required this.target,
    required this.completedToday,
    this.description,
  });

  final String id;
  final String title;
  final String frequency;
  final int target;
  final bool completedToday;
  final String? description;
}
