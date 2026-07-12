import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/app_user_resolver.dart';
import '../../../../core/supabase/supabase_tables.dart';
import '../../../quick_action/domain/habit_v1.dart';
import '../../domain/entities/correlation.dart';
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

  Future<List<CorrelationDataPoint>> getCorrelationDataPoints({
    required int windowDays,
  }) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final today = DateTime.now();
    final useAllTime = windowDays < 0;
    final requestedDays = useAllTime ? 1 : windowDays;
    final requestedStartDate =
        _dateOnly(habitAddCalendarDays(today, -(requestedDays - 1)));
    final endDate = _dateOnly(today);

    final dailyRows = useAllTime
        ? await _client
            .from(SupabaseTables.dailyLogs)
            .select()
            .eq('user_id', userId)
            .lte('entry_date', endDate)
            .order('entry_date', ascending: true)
        : await _client
            .from(SupabaseTables.dailyLogs)
            .select()
            .eq('user_id', userId)
            .gte('entry_date', requestedStartDate)
            .lte('entry_date', endDate)
            .order('entry_date', ascending: true);
    final typedDailyRows = List<Map<String, dynamic>>.from(dailyRows as List);
    if (typedDailyRows.isEmpty) {
      return const [];
    }

    final effectiveStartDate = useAllTime
        ? '${typedDailyRows.first['entry_date']}'
        : requestedStartDate;
    final effectiveWindowDays = habitCalendarDayDifference(
          DateTime.parse(endDate),
          DateTime.parse(effectiveStartDate),
        ) +
        1;

    final taskRows = useAllTime
        ? await _client
            .from(SupabaseTables.tasks)
            .select('deadline,status,priority')
            .eq('user_id', userId)
            .lte('deadline', '${endDate}T23:59:59.999Z')
        : await _client
            .from(SupabaseTables.tasks)
            .select('deadline,status,priority')
            .eq('user_id', userId)
            .gte('deadline', '${effectiveStartDate}T00:00:00.000Z')
            .lte('deadline', '${endDate}T23:59:59.999Z');
    final scheduleRows = await _client
        .from(SupabaseTables.scheduleItems)
        .select('weekday')
        .eq('user_id', userId);
    final habitRows = await _client
        .from(SupabaseTables.habits)
        .select('id,frequency,target,active,metadata,created_at')
        .eq('user_id', userId);
    final habitLogRows = useAllTime
        ? await _client
            .from(SupabaseTables.habitLogs)
            .select('habit_id,entry_date,value,status')
            .eq('user_id', userId)
            .lte('entry_date', endDate)
        : await _client
            .from(SupabaseTables.habitLogs)
            .select('habit_id,entry_date,value,status')
            .eq('user_id', userId)
            .gte('entry_date', effectiveStartDate)
            .lte('entry_date', endDate);

    final workloadByDate = _workloadByDate(
      taskRows: List<Map<String, dynamic>>.from(taskRows as List),
      scheduleRows: List<Map<String, dynamic>>.from(scheduleRows as List),
      startDate: DateTime.parse(effectiveStartDate),
      windowDays: effectiveWindowDays,
    );
    final habitCompletionByDate = _habitCompletionByDate(
      habitRows: List<Map<String, dynamic>>.from(habitRows as List),
      habitLogRows: List<Map<String, dynamic>>.from(habitLogRows as List),
      startDate: DateTime.parse(effectiveStartDate),
      windowDays: effectiveWindowDays,
    );

    return typedDailyRows.map((row) {
      final entryDate = '${row['entry_date']}';
      final values = <String, double>{};
      _addNumeric(values, 'sleep_hours', row['sleep_hours']);
      _addNumeric(values, 'focus_minutes', row['focus_minutes']);
      _addNumeric(values, 'stress_level', row['stress_level']);
      _addNumeric(values, 'energy_level', row['energy_level']);
      _addNumeric(values, 'mood_score', row['mood_score']);
      _addNumeric(values, 'screen_time_hours', row['screen_time_hours']);
      _addNumeric(values, 'activity_level', row['activity_level']);
      _addNumeric(values, 'steps', row['steps']);

      final sleep = values['sleep_hours'];
      final energy = values['energy_level'];
      if (sleep != null && energy != null) {
        values['recovery_score'] = ((sleep / 8 * 70) + (energy / 10 * 30))
            .roundToDouble()
            .clamp(0, 100);
      }
      final workload = workloadByDate[entryDate];
      if (workload != null) {
        values['workload_score'] = workload;
      }
      final habitCompletion = habitCompletionByDate[entryDate];
      if (habitCompletion != null) {
        values['habit_completion_rate'] = habitCompletion;
      }

      return CorrelationDataPoint(
        date: DateTime.parse(entryDate),
        values: values,
      );
    }).toList(growable: false);
  }

  Map<String, double> _workloadByDate({
    required List<Map<String, dynamic>> taskRows,
    required List<Map<String, dynamic>> scheduleRows,
    required DateTime startDate,
    required int windowDays,
  }) {
    final scheduleCountByWeekday = <int, int>{};
    for (final row in scheduleRows) {
      final weekday = (row['weekday'] as num?)?.toInt();
      if (weekday != null) {
        scheduleCountByWeekday[weekday] =
            (scheduleCountByWeekday[weekday] ?? 0) + 1;
      }
    }

    final workload = <String, double>{};
    for (var offset = 0; offset < windowDays; offset++) {
      final date = habitAddCalendarDays(startDate, offset);
      final scheduleLoad = (scheduleCountByWeekday[date.weekday] ?? 0) * 8.0;
      workload[_dateOnly(date)] = scheduleLoad.clamp(0, 45);
    }

    for (final row in taskRows) {
      final deadline = DateTime.tryParse('${row['deadline'] ?? ''}');
      if (deadline == null) {
        continue;
      }
      final status = '${row['status']}'.toLowerCase();
      if (status == 'archived' || status == 'cancelled') {
        continue;
      }
      final priority = '${row['priority']}'.toLowerCase();
      final weight = switch (priority) {
        'critical' => 32.0,
        'high' => 24.0,
        'medium' => 16.0,
        _ => 10.0,
      };
      final statusMultiplier = status == 'done' ? 0.4 : 1.0;
      final key = _dateOnly(deadline);
      workload[key] =
          ((workload[key] ?? 0) + weight * statusMultiplier).clamp(0, 100);
    }

    return workload;
  }

  Map<String, double> _habitCompletionByDate({
    required List<Map<String, dynamic>> habitRows,
    required List<Map<String, dynamic>> habitLogRows,
    required DateTime startDate,
    required int windowDays,
  }) {
    final scheduledHabits =
        <String, ({HabitCadence cadence, DateTime created})>{};
    for (final row in habitRows) {
      final id = row['id'];
      final started = _habitStartedDate(row);
      if (id is! String || started == null || row['active'] == false) {
        continue;
      }
      final metadata = row['metadata'];
      if (metadata is Map &&
          const ['candidate', 'archived'].contains(metadata['setup_state'])) {
        continue;
      }
      final cadence = HabitCadence.fromPersistence(
        frequency: row['frequency'],
        target: row['target'],
        metadata: metadata,
      );
      if (cadence.kind != HabitCadenceKind.weeklyTarget) {
        scheduledHabits[id] = (cadence: cadence, created: started);
      }
    }
    if (scheduledHabits.isEmpty) {
      return const {};
    }

    final completedHabitIdsByDate = <String, Set<String>>{};
    for (final row in habitLogRows) {
      final entryDate = row['entry_date'] as String?;
      final habitId = row['habit_id'] as String?;
      final completed = row['status'] == HabitOutcome.completed.code ||
          row['status'] == null && (row['value'] as num? ?? 0) > 0;
      if (entryDate == null ||
          habitId == null ||
          !completed ||
          !scheduledHabits.containsKey(habitId)) {
        continue;
      }
      completedHabitIdsByDate.putIfAbsent(entryDate, () => {}).add(habitId);
    }

    final ratesByDate = <String, double>{};
    for (var offset = 0; offset < windowDays; offset++) {
      final date = habitAddCalendarDays(startDate, offset);
      final dateKey = _dateOnly(date);
      final opportunities = scheduledHabits.entries
          .where((entry) {
            return !DateTime(
                  entry.value.created.year,
                  entry.value.created.month,
                  entry.value.created.day,
                ).isAfter(date) &&
                entry.value.cadence.isScheduledOn(date);
          })
          .map((entry) => entry.key)
          .toSet();
      if (opportunities.isEmpty) {
        continue;
      }
      final completed = completedHabitIdsByDate[dateKey]
              ?.where(opportunities.contains)
              .length ??
          0;
      ratesByDate[dateKey] =
          (completed / opportunities.length * 100).clamp(0, 100);
    }
    return ratesByDate;
  }

  DateTime? _habitStartedDate(Map<String, dynamic> row) {
    final metadata = row['metadata'];
    final startedOn = metadata is Map ? metadata['started_on'] : null;
    if (startedOn is String &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(startedOn)) {
      final parsed = DateTime.tryParse(startedOn);
      if (parsed != null && _dateOnly(parsed) == startedOn) {
        return DateTime(parsed.year, parsed.month, parsed.day);
      }
    }
    final created = DateTime.tryParse(row['created_at']?.toString() ?? '');
    if (created == null) {
      return null;
    }
    final local = created.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  void _addNumeric(Map<String, double> values, String key, Object? raw) {
    final value = (raw as num?)?.toDouble();
    if (value != null && value.isFinite) {
      values[key] = value;
    }
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
