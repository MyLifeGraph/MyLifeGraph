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
            'focus_minutes,steps,activity_level,screen_time_hours,metadata',
          )
          .eq('user_id', userId)
          .order('entry_date', ascending: false)
          .limit(60),
      _client
          .from(SupabaseTables.tasks)
          .select(
            'id,title,description,deadline,priority,status,estimated_minutes,'
            'source,metadata',
          )
          .eq('user_id', userId)
          .order('deadline', ascending: true, nullsFirst: true)
          .order('updated_at', ascending: false)
          .limit(100),
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
    final metadata = _stringMap(row['metadata']);
    final captures = _stringMap(metadata?['captures']);
    final evening = _stringMap(captures?['evening']);
    final morning = _stringMap(captures?['morning']);
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
      hasEveningCapture: evening != null,
      hasMorningCapture: morning != null,
      focusBand: _optionalString(evening?['focus_band']),
      stressSource: _optionalString(evening?['stress_source']),
      stressControllability:
          _optionalString(evening?['stress_controllability']),
      dayShape: _optionalString(morning?['day_shape']),
    );
  }

  Map<String, dynamic>? _stringMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(value);
  }

  String? _optionalString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
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
    final source = _optionalString(row['source']);
    final taskId = '${row['id']}';
    final deadlinePlanId = source == 'deadline-plan-v1' ? taskId : null;
    return PlanItem(
      id: taskId,
      title: '${row['title'] ?? 'Untitled task'}',
      deadline: DateTime.tryParse('${row['deadline'] ?? ''}')?.toLocal(),
      priority: priority.isEmpty ? 'normal' : priority,
      isCompleted: status == 'done' || status == 'completed',
      status: status,
      description: _optionalString(row['description']),
      estimatedMinutes: (row['estimated_minutes'] as num?)?.toInt(),
      source: source,
      deadlinePlanId: deadlinePlanId,
    );
  }

  bool _isVisibleTaskStatus(String status) {
    return switch (status.toLowerCase()) {
      'archived' => false,
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
        date: DateTime(date.year, date.month, date.day),
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
      sortMinutes: _timeSortMinutes(startsAt),
    );
  }

  int? _timeSortMinutes(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})').firstMatch(value);
    final hour = int.tryParse(match?.group(1) ?? '');
    final minute = int.tryParse(match?.group(2) ?? '');
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
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
