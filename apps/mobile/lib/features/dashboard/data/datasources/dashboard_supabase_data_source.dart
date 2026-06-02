import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/app_user_resolver.dart';
import '../../../../core/supabase/supabase_tables.dart';
import '../../domain/entities/dashboard_snapshot.dart';

class DashboardSupabaseDataSource {
  const DashboardSupabaseDataSource(this._client);

  final SupabaseClient _client;

  Future<DashboardSnapshot> getSnapshot() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final logs = await _client
        .from(SupabaseTables.dailyLogs)
        .select()
        .eq('userId', userId)
        .order('date', ascending: false)
        .limit(7);
    final tasks = await _client
        .from(SupabaseTables.tasks)
        .select()
        .eq('userId', userId)
        .order('deadline', ascending: true)
        .limit(8);

    final dailyLogs = List<Map<String, dynamic>>.from(logs as List);
    final taskRows = List<Map<String, dynamic>>.from(tasks as List);
    final latest = dailyLogs.isEmpty ? <String, dynamic>{} : dailyLogs.first;
    final trend = dailyLogs.reversed.map((row) => _activityScore(row)).toList()
      ..removeWhere((score) => score == 0);

    return DashboardSnapshot(
      optimizationScore: _activityScore(latest).clamp(0, 100),
      streakDays: _streakDays(dailyLogs),
      focusMinutesToday: (latest['focusMinutes'] as num?)?.round() ?? 0,
      recoveryScore: _recoveryScore(latest).clamp(0, 100),
      energyTrend: trend.isEmpty ? [0, 0, 0, 0, 0, 0, 0] : trend,
      todayPlan: taskRows.map(_taskToPlanItem).toList(),
    );
  }

  int _activityScore(Map<String, dynamic> row) {
    if (row.isEmpty) {
      return 0;
    }
    final activity = (row['activityLevel'] as num?)?.toDouble() ?? 0;
    final energy = (row['energyLevel'] as num?)?.toDouble() ?? 0;
    final sleep = (row['sleepHours'] as num?)?.toDouble() ?? 0;
    final focus = (row['focusMinutes'] as num?)?.toDouble() ?? 0;
    final score =
        activity * 2.4 + energy * 2.4 + sleep * 7 + (focus / 120 * 20);
    return score.round().clamp(0, 100);
  }

  int _recoveryScore(Map<String, dynamic> row) {
    if (row.isEmpty) {
      return 0;
    }
    final sleep = (row['sleepHours'] as num?)?.toDouble() ?? 0;
    final energy = (row['energyLevel'] as num?)?.toDouble() ?? 0;
    return ((sleep / 8 * 70) + (energy / 10 * 30)).round();
  }

  int _streakDays(List<Map<String, dynamic>> rows) {
    var streak = 0;
    var expected = DateTime.now();
    final dates = rows
        .map((row) => DateTime.tryParse('${row['date']}'))
        .whereType<DateTime>()
        .map((date) => DateTime(date.year, date.month, date.day))
        .toSet();

    while (
        dates.contains(DateTime(expected.year, expected.month, expected.day))) {
      streak++;
      expected = expected.subtract(const Duration(days: 1));
    }
    return streak;
  }

  PlanItem _taskToPlanItem(Map<String, dynamic> row) {
    final deadline = DateTime.tryParse('${row['deadline'] ?? ''}');
    final status = '${row['status']}'.toUpperCase();
    final priority = '${row['priority']}'.toLowerCase();
    return PlanItem(
      id: row['id'] as String,
      title: '${row['title']}',
      time: deadline == null
          ? priority
          : '${deadline.month}/${deadline.day}/${deadline.year}',
      type: priority == 'high' ? 'focus' : 'task',
      isCompleted: status == 'DONE' || status == 'COMPLETED',
    );
  }
}
