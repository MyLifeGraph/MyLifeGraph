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
        .eq('user_id', userId)
        .order('entry_date', ascending: false)
        .limit(7);
    final tasks = await _client
        .from(SupabaseTables.tasks)
        .select()
        .eq('user_id', userId)
        .order('deadline', ascending: true)
        .limit(8);
    final scheduleItems = await _client
        .from(SupabaseTables.scheduleItems)
        .select()
        .eq('user_id', userId)
        .order('weekday', ascending: true)
        .order('starts_at', ascending: true);

    final dailyLogs = List<Map<String, dynamic>>.from(logs as List);
    final taskRows = List<Map<String, dynamic>>.from(tasks as List);
    final scheduleRows = List<Map<String, dynamic>>.from(scheduleItems as List);
    final latest = dailyLogs.isEmpty ? <String, dynamic>{} : dailyLogs.first;
    final trend = dailyLogs.reversed.map((row) => _activityScore(row)).toList()
      ..removeWhere((score) => score == 0);

    return DashboardSnapshot(
      optimizationScore: _activityScore(latest).clamp(0, 100),
      streakDays: _streakDays(dailyLogs),
      focusMinutesToday: (latest['focus_minutes'] as num?)?.round() ?? 0,
      recoveryScore: _recoveryScore(latest).clamp(0, 100),
      energyTrend: trend.isEmpty ? [0, 0, 0, 0, 0, 0, 0] : trend,
      todayPlan: taskRows.map(_taskToPlanItem).toList(),
      scheduleDays: _scheduleDays(scheduleRows, trend),
    );
  }

  int _activityScore(Map<String, dynamic> row) {
    if (row.isEmpty) {
      return 0;
    }
    final activity = (row['activity_level'] as num?)?.toDouble() ?? 0;
    final energy = (row['energy_level'] as num?)?.toDouble() ?? 0;
    final sleep = (row['sleep_hours'] as num?)?.toDouble() ?? 0;
    final focus = (row['focus_minutes'] as num?)?.toDouble() ?? 0;
    final score =
        activity * 2.4 + energy * 2.4 + sleep * 7 + (focus / 120 * 20);
    return score.round().clamp(0, 100);
  }

  int _recoveryScore(Map<String, dynamic> row) {
    if (row.isEmpty) {
      return 0;
    }
    final sleep = (row['sleep_hours'] as num?)?.toDouble() ?? 0;
    final energy = (row['energy_level'] as num?)?.toDouble() ?? 0;
    return ((sleep / 8 * 70) + (energy / 10 * 30)).round();
  }

  int _streakDays(List<Map<String, dynamic>> rows) {
    var streak = 0;
    var expected = DateTime.now();
    final dates = rows
        .map((row) => DateTime.tryParse('${row['entry_date']}'))
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
    final status = '${row['status']}'.toLowerCase();
    final priority = '${row['priority']}'.toLowerCase();
    return PlanItem(
      id: row['id'] as String,
      title: '${row['title']}',
      time: deadline == null
          ? priority
          : '${deadline.month}/${deadline.day}/${deadline.year}',
      type: priority == 'high' || priority == 'critical' ? 'focus' : 'task',
      isCompleted: status == 'done' || status == 'completed',
    );
  }

  List<ScheduleDay> _scheduleDays(
    List<Map<String, dynamic>> rows,
    List<int> trend,
  ) {
    final today = DateTime.now();
    final monday = today.subtract(Duration(days: today.weekday - 1));

    return List.generate(7, (index) {
      final date = monday.add(Duration(days: index));
      final weekday = index + 1;
      final activity = index < trend.length ? trend[index] : 0;
      final seen = <String>{};
      final events = rows
          .where((row) => (row['weekday'] as num?)?.toInt() == weekday)
          .where((row) {
            final key = [
              row['title'],
              row['starts_at'],
              row['ends_at'],
              row['location'],
            ].join('|');
            return seen.add(key);
          })
          .map(_scheduleEventFromRow)
          .toList();

      return ScheduleDay(
        label: _weekdayLabel(weekday),
        dateLabel: '${_monthLabel(date.month)} ${date.day}',
        energy: (activity / 100).clamp(0.08, 1),
        movement: activity == 0 ? 0.08 : (activity / 100).clamp(0.08, 1),
        activity: activity,
        events: events,
      );
    });
  }

  ScheduleEvent _scheduleEventFromRow(Map<String, dynamic> row) {
    final startsAt = '${row['starts_at'] ?? ''}'.trim();
    final endsAt = '${row['ends_at'] ?? ''}'.trim();
    final time =
        startsAt.isEmpty || endsAt.isEmpty ? '--:--' : '$startsAt-$endsAt';
    return ScheduleEvent(
      title: '${row['title'] ?? 'Schedule block'}',
      time: time,
    );
  }

  String _weekdayLabel(int weekday) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[(weekday - 1).clamp(0, labels.length - 1)];
  }

  String _monthLabel(int month) {
    const labels = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return labels[(month - 1).clamp(0, labels.length - 1)];
  }
}
