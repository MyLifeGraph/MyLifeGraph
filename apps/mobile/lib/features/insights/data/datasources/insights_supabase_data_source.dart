import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/app_user_resolver.dart';
import '../../../../core/supabase/supabase_tables.dart';
import '../../../quick_action/domain/habit_v1.dart';
import '../../domain/entities/correlation.dart';
import '../../domain/entities/insight.dart';

class InsightsSupabaseDataSource {
  const InsightsSupabaseDataSource(
    this._client, {
    InsightSupabaseRowMapper mapper = const InsightSupabaseRowMapper(),
    InsightsQueryPaginator paginator = const InsightsQueryPaginator(),
    InsightsLocalDatePolicy localDates = const InsightsLocalDatePolicy(),
  })  : _mapper = mapper,
        _paginator = paginator,
        _localDates = localDates;

  final SupabaseClient _client;
  final InsightSupabaseRowMapper _mapper;
  final InsightsQueryPaginator _paginator;
  final InsightsLocalDatePolicy _localDates;

  Future<List<Insight>> getInsights() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final rows = await _client
        .from(SupabaseTables.aiInsights)
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(20);

    return List<Map<String, dynamic>>.from(rows as List)
        .map(_mapper.fromRow)
        .toList(growable: false);
  }

  Future<List<CorrelationDataPoint>> getCorrelationDataPoints({
    required int windowDays,
  }) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final today = _localDates.now();
    final requestedDays = normalizeInsightsWindowDays(windowDays);
    final requestedStartDate =
        _dateOnly(habitAddCalendarDays(today, -(requestedDays - 1)));
    final endDate = _dateOnly(today);

    final typedDailyRows = await _fetchDailyRows(
      userId: userId,
      startDate: requestedStartDate,
      endDate: endDate,
    );
    final effectiveStartDate = requestedStartDate;
    final effectiveWindowDays = habitCalendarDayDifference(
          DateTime.parse(endDate),
          DateTime.parse(effectiveStartDate),
        ) +
        1;

    final relatedRows = await Future.wait([
      _fetchTaskRows(
        userId: userId,
        startDate: effectiveStartDate,
        endDate: endDate,
      ),
      _fetchScheduleRows(userId: userId),
      _fetchHabitRows(userId: userId),
      _fetchHabitLogRows(
        userId: userId,
        startDate: effectiveStartDate,
        endDate: endDate,
      ),
      _fetchFocusRows(
        userId: userId,
        startDate: effectiveStartDate,
        endDate: endDate,
      ),
    ]);
    final taskRows = relatedRows[0];
    final scheduleRows = relatedRows[1];
    final habitRows = relatedRows[2];
    final habitLogRows = relatedRows[3];
    final focusRows = relatedRows[4];

    final plannedMinutesByDate = _plannedMinutesByDate(
      taskRows: taskRows,
      scheduleRows: scheduleRows,
      startDate: DateTime.parse(effectiveStartDate),
      windowDays: effectiveWindowDays,
    );
    final focusMinutesByDate = _focusMinutesByDate(
      focusRows,
      startDate: effectiveStartDate,
      endDate: endDate,
    );
    final habitCompletionByDate = _habitCompletionByDate(
      habitRows: habitRows,
      habitLogRows: habitLogRows,
      startDate: DateTime.parse(effectiveStartDate),
      windowDays: effectiveWindowDays,
    );

    final dailyRowsByDate = {
      for (final row in typedDailyRows) '${row['entry_date']}': row,
    };
    final availableDates = <String>{
      ...dailyRowsByDate.keys,
      ...focusMinutesByDate.keys,
      ...habitCompletionByDate.keys,
      ...plannedMinutesByDate.keys,
    }.toList()
      ..sort();

    return availableDates.map((entryDate) {
      final row = dailyRowsByDate[entryDate];
      final values = <String, double>{};
      if (row != null) {
        _addNumeric(values, 'sleep_hours', row['sleep_hours']);
        _addNumeric(values, 'stress_level', row['stress_level']);
        _addNumeric(values, 'energy_level', row['energy_level']);
        _addNumeric(values, 'mood_score', row['mood_score']);
        _addNumeric(values, 'screen_time_hours', row['screen_time_hours']);
        _addNumeric(values, 'activity_level', row['activity_level']);
        _addNumeric(values, 'steps', row['steps']);
      }
      final focusMinutes = focusMinutesByDate[entryDate];
      if (focusMinutes != null) {
        values['focus_minutes'] = focusMinutes;
      }
      final plannedMinutes = plannedMinutesByDate[entryDate];
      if (plannedMinutes != null) {
        values['planned_minutes'] = plannedMinutes;
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

  Future<List<Map<String, dynamic>>> _fetchDailyRows({
    required String userId,
    required String startDate,
    required String endDate,
  }) {
    return _paginator.load((from, to) async {
      return _client
          .from(SupabaseTables.dailyLogs)
          .select()
          .eq('user_id', userId)
          .gte('entry_date', startDate)
          .lte('entry_date', endDate)
          .order('entry_date', ascending: true)
          .order('id', ascending: true)
          .range(from, to);
    });
  }

  Future<List<Map<String, dynamic>>> _fetchTaskRows({
    required String userId,
    required String startDate,
    required String endDate,
  }) {
    final deadlineRange = _localDates.taskDeadlineUtcRange(
      startDate: startDate,
      endDate: endDate,
    );
    return _paginator.load((from, to) async {
      return _client
          .from(SupabaseTables.tasks)
          .select('id,deadline,status,estimated_minutes')
          .eq('user_id', userId)
          .gte('deadline', deadlineRange.startInclusive.toIso8601String())
          .lt('deadline', deadlineRange.endExclusive.toIso8601String())
          .order('deadline', ascending: true)
          .order('id', ascending: true)
          .range(from, to);
    });
  }

  Future<List<Map<String, dynamic>>> _fetchScheduleRows({
    required String userId,
  }) {
    return _paginator.load((from, to) async {
      return _client
          .from(SupabaseTables.scheduleItems)
          .select('id,weekday,starts_at,ends_at')
          .eq('user_id', userId)
          .order('weekday', ascending: true)
          .order('id', ascending: true)
          .range(from, to);
    });
  }

  Future<List<Map<String, dynamic>>> _fetchHabitRows({
    required String userId,
  }) {
    return _paginator.load((from, to) async {
      return _client
          .from(SupabaseTables.habits)
          .select('id,frequency,target,active,metadata,created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: true)
          .order('id', ascending: true)
          .range(from, to);
    });
  }

  Future<List<Map<String, dynamic>>> _fetchHabitLogRows({
    required String userId,
    required String startDate,
    required String endDate,
  }) {
    return _paginator.load((from, to) async {
      return _client
          .from(SupabaseTables.habitLogs)
          .select('id,habit_id,entry_date,value,status')
          .eq('user_id', userId)
          .gte('entry_date', startDate)
          .lte('entry_date', endDate)
          .order('entry_date', ascending: true)
          .order('habit_id', ascending: true)
          .order('id', ascending: true)
          .range(from, to);
    });
  }

  Future<List<Map<String, dynamic>>> _fetchFocusRows({
    required String userId,
    required String startDate,
    required String endDate,
  }) {
    final start = DateTime.parse(startDate)
        .subtract(const Duration(days: 1))
        .toUtc()
        .toIso8601String();
    final end = DateTime.parse(endDate)
        .add(const Duration(days: 2))
        .toUtc()
        .toIso8601String();
    return _paginator.load((from, to) async {
      return _client
          .from(SupabaseTables.focusSessions)
          .select('id,status,started_at,actual_minutes,metadata')
          .eq('user_id', userId)
          .gte('started_at', start)
          .lt('started_at', end)
          .order('started_at', ascending: true)
          .order('id', ascending: true)
          .range(from, to);
    });
  }

  Map<String, double> _plannedMinutesByDate({
    required List<Map<String, dynamic>> taskRows,
    required List<Map<String, dynamic>> scheduleRows,
    required DateTime startDate,
    required int windowDays,
  }) {
    final scheduleMinutesByWeekday = <int, int>{};
    for (final row in scheduleRows) {
      final weekday = (row['weekday'] as num?)?.toInt();
      final minutes = _timeRangeMinutes(row['starts_at'], row['ends_at']);
      if (weekday != null && minutes != null) {
        scheduleMinutesByWeekday[weekday] =
            (scheduleMinutesByWeekday[weekday] ?? 0) + minutes;
      }
    }

    final planned = <String, double>{};
    for (var offset = 0; offset < windowDays; offset++) {
      final date = habitAddCalendarDays(startDate, offset);
      final scheduleMinutes = scheduleMinutesByWeekday[date.weekday] ?? 0;
      if (scheduleMinutes > 0) {
        planned[_dateOnly(date)] = scheduleMinutes.toDouble();
      }
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
      final estimate = row['estimated_minutes'];
      if (estimate is! num || estimate <= 0 || estimate != estimate.toInt()) {
        continue;
      }
      final key = _localDates.taskDeadlineDateKey(deadline);
      planned[key] = (planned[key] ?? 0) + estimate.toDouble();
    }

    return planned;
  }

  Map<String, double> _focusMinutesByDate(
    List<Map<String, dynamic>> rows, {
    required String startDate,
    required String endDate,
  }) {
    final totals = <String, double>{};
    for (final row in rows) {
      if (row['status'] != 'completed') continue;
      final actual = row['actual_minutes'];
      final metadata = row['metadata'];
      final entryDate = metadata is Map ? metadata['entry_date'] : null;
      if (actual is! num ||
          actual < 0 ||
          entryDate is! String ||
          entryDate.compareTo(startDate) < 0 ||
          entryDate.compareTo(endDate) > 0 ||
          !_isDateKey(entryDate)) {
        continue;
      }
      totals[entryDate] = (totals[entryDate] ?? 0) + actual.toDouble();
    }
    return totals;
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
    final local = _localDates.toLocal(created);
    return DateTime(local.year, local.month, local.day);
  }

  int? _timeRangeMinutes(Object? startsAt, Object? endsAt) {
    int? minutes(Object? value) {
      if (value is! String) return null;
      final parts = value.split(':');
      if (parts.length < 2) return null;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null ||
          minute == null ||
          hour < 0 ||
          hour > 23 ||
          minute < 0 ||
          minute > 59) {
        return null;
      }
      return hour * 60 + minute;
    }

    final start = minutes(startsAt);
    final end = minutes(endsAt);
    if (start == null || end == null || end <= start) return null;
    return end - start;
  }

  bool _isDateKey(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final parsed = DateTime.tryParse(value);
    return parsed != null && _dateOnly(parsed) == value;
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

typedef InsightsClock = DateTime Function();
typedef InsightsDateLocalizer = DateTime Function(DateTime timestamp);
typedef InsightsLocalMidnightToUtc = DateTime Function(DateTime localDate);

class InsightsUtcDateRange {
  const InsightsUtcDateRange({
    required this.startInclusive,
    required this.endExclusive,
  });

  final DateTime startInclusive;
  final DateTime endExclusive;
}

class InsightsLocalDatePolicy {
  const InsightsLocalDatePolicy({
    InsightsClock? clock,
    InsightsDateLocalizer? localizer,
    InsightsLocalMidnightToUtc? localMidnightToUtc,
  })  : _clock = clock,
        _localizer = localizer,
        _localMidnightToUtc = localMidnightToUtc;

  final InsightsClock? _clock;
  final InsightsDateLocalizer? _localizer;
  final InsightsLocalMidnightToUtc? _localMidnightToUtc;

  DateTime now() => toLocal(_clock?.call() ?? DateTime.now());

  DateTime toLocal(DateTime timestamp) {
    return _localizer?.call(timestamp) ?? timestamp.toLocal();
  }

  InsightsUtcDateRange taskDeadlineUtcRange({
    required String startDate,
    required String endDate,
  }) {
    final firstLocalDate = DateTime.parse(startDate);
    final lastLocalDate = DateTime.parse(endDate);
    final nextLocalDate = DateTime(
      lastLocalDate.year,
      lastLocalDate.month,
      lastLocalDate.day + 1,
    );
    return InsightsUtcDateRange(
      startInclusive: _localMidnightUtc(firstLocalDate),
      endExclusive: _localMidnightUtc(nextLocalDate),
    );
  }

  String taskDeadlineDateKey(DateTime deadline) {
    return _insightsDateOnly(toLocal(deadline));
  }

  DateTime _localMidnightUtc(DateTime localDate) {
    final override = _localMidnightToUtc;
    if (override != null) {
      return override(localDate).toUtc();
    }
    return DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
    ).toUtc();
  }
}

String _insightsDateOnly(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

class InsightSupabaseRowMapper {
  const InsightSupabaseRowMapper();

  Insight fromRow(Map<String, dynamic> row) {
    final rawConfidence = row['confidence'];
    if (rawConfidence != null && rawConfidence is! num) {
      throw const FormatException(
        'Insight confidence must be numeric or null.',
      );
    }
    final confidence = (rawConfidence as num?)?.toDouble();
    if (confidence != null &&
        (!confidence.isFinite || confidence < 0 || confidence > 1)) {
      throw const FormatException(
        'Insight confidence must be between 0 and 1.',
      );
    }

    return Insight(
      id: row['id'] as String,
      title: row['title'] as String,
      summary: row['description'] as String,
      confidence: confidence,
      tags: [
        '${row['category']}'.toLowerCase(),
        '${row['priority']}'.toLowerCase(),
      ],
    );
  }
}

typedef InsightsPageFetcher = Future<Object?> Function(int from, int to);

class InsightsQueryPaginator {
  const InsightsQueryPaginator({
    this.pageSize = 500,
    this.maxRows = 10000,
  })  : assert(pageSize > 0),
        assert(maxRows > 0);

  final int pageSize;
  final int maxRows;

  Future<List<Map<String, dynamic>>> load(
    InsightsPageFetcher fetchPage,
  ) async {
    final result = <Map<String, dynamic>>[];
    for (var offset = 0;;) {
      final remaining = maxRows - result.length;
      final requestedSize = remaining == 0
          ? 1
          : remaining < pageSize
              ? remaining
              : pageSize;
      final rows = await fetchPage(offset, offset + requestedSize - 1);
      final page = List<Map<String, dynamic>>.from(rows as List);
      if (page.length > requestedSize) {
        throw StateError('Insight source returned an oversized page.');
      }
      if (remaining == 0) {
        if (page.isEmpty) {
          return result;
        }
        throw StateError(
          'Insight source exceeds the $maxRows-row verification limit.',
        );
      }
      result.addAll(page);
      if (page.length < requestedSize) {
        return result;
      }
      offset += page.length;
    }
  }
}
