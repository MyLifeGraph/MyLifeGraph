import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/app_user_resolver.dart';
import '../../../../core/supabase/supabase_tables.dart';
import '../../domain/entities/dashboard_snapshot.dart';

class DashboardSupabaseDataSource {
  const DashboardSupabaseDataSource(this._client);

  final SupabaseClient _client;

  Future<DashboardSnapshot> getSnapshot() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final results = await Future.wait([
      _client
          .from(SupabaseTables.dailyLogs)
          .select(
            'entry_date,mood_score,energy_level,sleep_hours,stress_level,'
            'focus_minutes,steps,activity_level,screen_time_hours',
          )
          .eq('user_id', userId)
          .order('entry_date', ascending: false)
          .limit(60),
      _client
          .from(SupabaseTables.tasks)
          .select('id,title,deadline,priority,status')
          .eq('user_id', userId)
          .order('deadline', ascending: true)
          .limit(8),
      _client
          .from(SupabaseTables.scheduleItems)
          .select('title,weekday,starts_at,ends_at,location')
          .eq('user_id', userId)
          .order('weekday', ascending: true)
          .order('starts_at', ascending: true),
    ]);

    return const DashboardSnapshotMapper().map(
      dailyLogs: List<Map<String, dynamic>>.from(results[0] as List),
      taskRows: List<Map<String, dynamic>>.from(results[1] as List),
      scheduleRows: List<Map<String, dynamic>>.from(results[2] as List),
      loadedAt: DateTime.now(),
    );
  }
}

class DashboardSnapshotMapper {
  const DashboardSnapshotMapper();

  DashboardSnapshot map({
    required List<Map<String, dynamic>> dailyLogs,
    required List<Map<String, dynamic>> taskRows,
    required List<Map<String, dynamic>> scheduleRows,
    required DateTime loadedAt,
  }) {
    return DashboardSnapshot(
      origin: DashboardOrigin.account,
      loadedAt: loadedAt,
      latestCheckIn:
          dailyLogs.isEmpty ? null : _checkInFromRow(dailyLogs.first),
      checkInStreakDays: _streakDays(dailyLogs, loadedAt),
      todayPlan: taskRows
          .where((row) => _isVisibleTaskStatus('${row['status']}'))
          .map(_taskToPlanItem)
          .toList(),
      scheduleDays: _scheduleDays(scheduleRows, loadedAt),
    );
  }

  DashboardCheckIn? _checkInFromRow(Map<String, dynamic> row) {
    final entryDate = DateTime.tryParse('${row['entry_date'] ?? ''}');
    if (entryDate == null) {
      return null;
    }
    return DashboardCheckIn(
      entryDate: entryDate,
      mood: (row['mood_score'] as num?)?.toInt(),
      energy: (row['energy_level'] as num?)?.toInt(),
      sleepHours: (row['sleep_hours'] as num?)?.toDouble(),
      stress: (row['stress_level'] as num?)?.toInt(),
      focusMinutes: (row['focus_minutes'] as num?)?.toInt(),
      steps: (row['steps'] as num?)?.toInt(),
      activityLevel: (row['activity_level'] as num?)?.toInt(),
      screenTimeHours: (row['screen_time_hours'] as num?)?.toDouble(),
    );
  }

  int _streakDays(List<Map<String, dynamic>> rows, DateTime loadedAt) {
    var streak = 0;
    var expected = loadedAt;
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
    final status = '${row['status']}'.toLowerCase();
    final priority = '${row['priority'] ?? 'normal'}'.trim().toLowerCase();
    return PlanItem(
      id: '${row['id']}',
      title: '${row['title'] ?? 'Untitled task'}',
      deadline: DateTime.tryParse('${row['deadline'] ?? ''}'),
      priority: priority.isEmpty ? 'normal' : priority,
      isCompleted: status == 'done' || status == 'completed',
    );
  }

  bool _isVisibleTaskStatus(String status) {
    return switch (status.toLowerCase()) {
      'cancelled' || 'archived' => false,
      _ => true,
    };
  }

  List<ScheduleDay> _scheduleDays(
    List<Map<String, dynamic>> rows,
    DateTime loadedAt,
  ) {
    final monday = loadedAt.subtract(Duration(days: loadedAt.weekday - 1));

    return List.generate(7, (index) {
      final date = monday.add(Duration(days: index));
      final weekday = index + 1;
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
        events: events,
      );
    });
  }

  ScheduleEvent _scheduleEventFromRow(Map<String, dynamic> row) {
    final startsAt = '${row['starts_at'] ?? ''}'.trim();
    final endsAt = '${row['ends_at'] ?? ''}'.trim();
    final time = startsAt.isEmpty
        ? 'Time not set'
        : endsAt.isEmpty
            ? startsAt
            : '$startsAt-$endsAt';
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
