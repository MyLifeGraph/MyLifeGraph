import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/app_user_resolver.dart';
import '../../../core/supabase/supabase_tables.dart';

class HabitCompletionSupabaseDataSource {
  const HabitCompletionSupabaseDataSource(this._client);

  final SupabaseClient _client;

  Future<List<HabitCompletionOption>> fetchActiveHabits() async {
    return fetchHabits(activeOnly: true);
  }

  Future<List<HabitCompletionOption>> fetchHabits({
    bool activeOnly = false,
  }) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final now = DateTime.now();
    final today = _dateOnly(now);
    final windowStart = _dateOnly(now.subtract(const Duration(days: 6)));

    var query = _client
        .from(SupabaseTables.habits)
        .select('id,title,description,frequency,target,active,updated_at')
        .eq('user_id', userId);
    if (activeOnly) {
      query = query.eq('active', true);
    }
    final habitRows = await query.order('updated_at', ascending: false);

    final logRows = await _client
        .from(SupabaseTables.habitLogs)
        .select('habit_id,entry_date,value')
        .eq('user_id', userId)
        .gte('entry_date', windowStart)
        .lte('entry_date', today);

    final completionDatesByHabit = <String, Set<String>>{};
    for (final row in List<Map<String, dynamic>>.from(logRows as List)) {
      if ((row['value'] as num? ?? 0) <= 0) {
        continue;
      }
      final habitId = row['habit_id'] as String?;
      final entryDate = row['entry_date'] as String?;
      if (habitId == null || entryDate == null) {
        continue;
      }
      completionDatesByHabit.putIfAbsent(habitId, () => {}).add(entryDate);
    }

    return List<Map<String, dynamic>>.from(habitRows as List).map((row) {
      final id = row['id'] as String;
      final completionDates = completionDatesByHabit[id] ?? const <String>{};
      return HabitCompletionOption(
        id: id,
        title: row['title'] as String? ?? 'Habit',
        description: row['description'] as String?,
        frequency: row['frequency'] as String? ?? 'daily',
        target: _intValue(row['target'], fallback: 1),
        active: row['active'] as bool? ?? true,
        completedToday: completionDates.contains(today),
        completionsLast7Days: completionDates.length,
        currentStreakDays: _currentStreakDays(completionDates, now),
        recentCompletionDates: completionDates,
      );
    }).toList();
  }

  Future<void> createHabit({
    required String title,
    String? description,
    required String frequency,
    required int target,
  }) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final now = DateTime.now().toIso8601String();

    await _client.from(SupabaseTables.habits).insert({
      'user_id': userId,
      'title': title.trim(),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      'frequency': frequency,
      'target': target,
      'active': true,
      'metadata': {'source': 'flutter-habit-management-v1'},
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateHabit({
    required String habitId,
    required String title,
    String? description,
    required String frequency,
    required int target,
  }) async {
    final userId = await AppUserResolver(_client).resolveUserId();

    await _client
        .from(SupabaseTables.habits)
        .update({
          'title': title.trim(),
          'description':
              description?.trim().isEmpty ?? true ? null : description!.trim(),
          'frequency': frequency,
          'target': target,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', habitId)
        .eq('user_id', userId);
  }

  Future<void> setHabitActive({
    required String habitId,
    required bool active,
  }) async {
    final userId = await AppUserResolver(_client).resolveUserId();

    await _client
        .from(SupabaseTables.habits)
        .update({
          'active': active,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', habitId)
        .eq('user_id', userId);
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

  int _currentStreakDays(Set<String> completionDates, DateTime today) {
    var streak = 0;
    for (var offset = 0; offset < 7; offset++) {
      final date = _dateOnly(today.subtract(Duration(days: offset)));
      if (!completionDates.contains(date)) {
        break;
      }
      streak += 1;
    }
    return streak;
  }

  int _intValue(Object? value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return fallback;
  }
}

class HabitCompletionOption {
  const HabitCompletionOption({
    required this.id,
    required this.title,
    required this.frequency,
    required this.target,
    required this.active,
    required this.completedToday,
    required this.completionsLast7Days,
    required this.currentStreakDays,
    required this.recentCompletionDates,
    this.description,
  });

  final String id;
  final String title;
  final String frequency;
  final int target;
  final bool active;
  final bool completedToday;
  final int completionsLast7Days;
  final int currentStreakDays;
  final Set<String> recentCompletionDates;
  final String? description;
}
