import '../../../../core/network/api_client.dart';
import '../../domain/entities/dashboard_snapshot.dart';

const todayOverviewContractVersion = 'today-overview-v2';

class TodayOverviewApiDataSource {
  const TodayOverviewApiDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<DashboardSnapshot> getOverview({required String accessToken}) async {
    final json = await _apiClient.getJson(
      '/v1/today/overview-v2',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return const TodayOverviewMapper().map(json);
  }
}

class TodayOverviewMapper {
  const TodayOverviewMapper();

  DashboardSnapshot map(Map<String, dynamic> json) {
    _exactKeys(
      json,
      const {
        'contract_version',
        'origin',
        'local_date',
        'timezone',
        'generated_at',
        'check_ins',
        'progress',
        'progress_unavailable_sources',
        'timeline',
        'tasks',
        'habits',
        'source_states',
      },
      'Today overview',
    );
    if (json['contract_version'] != todayOverviewContractVersion ||
        json['origin'] != 'authenticated_backend') {
      throw const TodayOverviewContractException(
        'Today overview contract is unsupported.',
      );
    }
    final localDate = _date(json['local_date'], 'Today local date');
    final timezone = _string(json['timezone'], 'Today timezone', 100);
    final generatedAt = _awareDateTime(
      json['generated_at'],
      'Today generated time',
    );
    final rawCheckIns = json['check_ins'];
    if (rawCheckIns != null && rawCheckIns is! Map) {
      throw const TodayOverviewContractException(
        'Today check-ins are invalid.',
      );
    }
    final checkIns = rawCheckIns == null
        ? null
        : _checkIns(Map<String, dynamic>.from(rawCheckIns));
    final rawProgress = json['progress'];
    if (rawProgress != null && rawProgress is! Map) {
      throw const TodayOverviewContractException('Today progress is invalid.');
    }
    final progress = rawProgress == null
        ? null
        : _progress(Map<String, dynamic>.from(rawProgress));
    final rawUnavailable = _list(
      json['progress_unavailable_sources'],
      'Today unavailable progress sources',
      5,
    );
    final unavailable = rawUnavailable
        .map(
          (value) => _enumString(
            value,
            'Today unavailable progress source',
            const {'check_ins', 'tasks', 'habits', 'preparation', 'planner'},
          ),
        )
        .toList(growable: false);
    if (unavailable.toSet().length != unavailable.length ||
        unavailable.isEmpty != (progress != null)) {
      throw const TodayOverviewContractException(
        'Today progress availability is inconsistent.',
      );
    }

    final rawTasks = _map(json['tasks'], 'Today tasks');
    _exactKeys(rawTasks, const {'today', 'all'}, 'Today tasks');
    final todayTasks = _list(rawTasks['today'], 'Today task list', 1000)
        .map((value) => _task(_map(value, 'Today task')))
        .toList(growable: false);
    final allTasks = _list(rawTasks['all'], 'All task list', 1000)
        .map((value) => _task(_map(value, 'All task')))
        .toList(growable: false);
    final allIds = allTasks.map((task) => task.id).toSet();
    if (allIds.length != allTasks.length ||
        todayTasks.map((task) => task.id).toSet().length != todayTasks.length ||
        todayTasks.any(
          (task) => !allIds.contains(task.id) || task.todayReason == null,
        )) {
      throw const TodayOverviewContractException(
        'Today task projections are inconsistent.',
      );
    }

    final timeline = _list(json['timeline'], 'Today timeline', 2000)
        .map((value) => _timelineItem(_map(value, 'Today timeline item')))
        .toList(growable: false);
    final habits = _list(json['habits'], 'Today habits', 500)
        .map((value) => _habit(_map(value, 'Today habit')))
        .toList(growable: false);
    final sourceStates = _sourceStates(
      _map(json['source_states'], 'Today source states'),
    );
    final scheduledTaskIds = timeline
        .where((item) => item.kind == TodayTimelineKind.taskBlock)
        .map((item) => item.taskId!)
        .toSet();
    final scheduledHabitIds = timeline
        .where((item) => item.kind == TodayTimelineKind.habitSlot)
        .map((item) => item.habitId!)
        .toSet();
    if (!_sameStringSet(
          scheduledTaskIds,
          allTasks
              .where((task) => task.scheduledToday)
              .map((task) => task.id)
              .toSet(),
        ) ||
        !_sameStringSet(
          scheduledTaskIds,
          todayTasks
              .where((task) => task.scheduledToday)
              .map((task) => task.id)
              .toSet(),
        ) ||
        !_sameStringSet(
          scheduledHabitIds,
          habits
              .where((habit) => habit.scheduledToday)
              .map((habit) => habit.id)
              .toSet(),
        )) {
      throw const TodayOverviewContractException(
        'Today Planner target projections are inconsistent.',
      );
    }
    for (final item in timeline.where(
      (value) =>
          value.kind == TodayTimelineKind.taskBlock ||
          value.kind == TodayTimelineKind.habitSlot,
    )) {
      if (item.endsAt!.difference(item.startsAt!).inMinutes !=
          item.plannedMinutes) {
        throw const TodayOverviewContractException(
          'Today Planner block duration is inconsistent.',
        );
      }
    }
    final expectedUnavailable = <String>[
      if (sourceStates.checkIns.status == TodaySourceStatus.unavailable)
        'check_ins',
      if (sourceStates.tasks.status == TodaySourceStatus.unavailable) 'tasks',
      if (sourceStates.habits.status == TodaySourceStatus.unavailable) 'habits',
      if (sourceStates.preparation.status == TodaySourceStatus.unavailable)
        'preparation',
      if (sourceStates.planner?.status == TodaySourceStatus.unavailable)
        'planner',
    ];
    if (!_sameStrings(unavailable, expectedUnavailable) ||
        (sourceStates.checkIns.status == TodaySourceStatus.current) !=
            (checkIns != null)) {
      throw const TodayOverviewContractException(
        'Today source availability is inconsistent.',
      );
    }

    if (progress != null) {
      final preparation = timeline.where(
        (item) => item.kind == TodayTimelineKind.preparation,
      );
      final expectedTotal =
          2 + todayTasks.length + habits.length + preparation.length;
      final expectedCompleted = (checkIns!.morningSaved ? 1 : 0) +
          (checkIns.eveningSaved ? 1 : 0) +
          todayTasks.where((task) => task.status == 'done').length +
          habits.where((habit) => habit.outcome == 'completed').length +
          preparation.where((item) => item.state == 'completed').length;
      if (progress.total != expectedTotal ||
          progress.completed != expectedCompleted) {
        throw const TodayOverviewContractException(
          'Today progress arithmetic is inconsistent.',
        );
      }
    }

    return DashboardSnapshot(
      origin: DashboardOrigin.account,
      loadedAt: generatedAt.toLocal(),
      latestCheckIn: null,
      checkInStreakDays: checkIns?.completedDaysStreak ?? 0,
      todayPlan: List.unmodifiable(allTasks),
      scheduleDays: const [],
      localDate: localDate,
      timezone: timezone,
      checkIns: checkIns,
      progress: progress,
      todayTasks: List.unmodifiable(todayTasks),
      timeline: List.unmodifiable(timeline),
      todayHabits: List.unmodifiable(habits),
      sourceStates: sourceStates,
      isTodayOverview: true,
    );
  }

  TodayCheckIns _checkIns(Map<String, dynamic> json) {
    _exactKeys(
      json,
      const {'morning_saved', 'evening_saved', 'completed_days_streak'},
      'Today check-ins',
    );
    return TodayCheckIns(
      morningSaved: _boolean(json['morning_saved'], 'Morning check-in'),
      eveningSaved: _boolean(json['evening_saved'], 'Evening check-in'),
      completedDaysStreak: _integer(
        json['completed_days_streak'],
        'Check-in streak',
        minimum: 0,
      ),
    );
  }

  TodayProgress _progress(Map<String, dynamic> json) {
    _exactKeys(json, const {'completed', 'total'}, 'Today progress');
    final completed = _integer(
      json['completed'],
      'Today completed count',
      minimum: 0,
    );
    final total = _integer(
      json['total'],
      'Today total count',
      minimum: 2,
    );
    if (completed > total) {
      throw const TodayOverviewContractException(
        'Today completed count exceeds its total.',
      );
    }
    return TodayProgress(completed: completed, total: total);
  }

  PlanItem _task(Map<String, dynamic> json) {
    _exactKeys(
      json,
      const {
        'id',
        'title',
        'description',
        'status',
        'priority',
        'deadline',
        'estimated_minutes',
        'completed_at',
        'source',
        'deadline_plan_id',
        'today_reason',
        'scheduled_today',
      },
      'Today task',
    );
    final id = _uuid(json['id'], 'Today task identity');
    final status = _enumString(
      json['status'],
      'Today task status',
      const {'todo', 'in_progress', 'done', 'cancelled'},
    );
    final source = _string(json['source'], 'Today task source', 100);
    final deadlinePlanId = _optionalUuid(
      json['deadline_plan_id'],
      'Today task plan identity',
    );
    final completedAt = _optionalAwareDateTime(
      json['completed_at'],
      'Today task completion time',
    );
    if ((source == 'deadline-plan-v1') != (deadlinePlanId == id) ||
        (status == 'done') != (completedAt != null)) {
      throw const TodayOverviewContractException(
        'Today task lifecycle is inconsistent.',
      );
    }
    return PlanItem(
      id: id,
      title: _string(json['title'], 'Today task title', 160),
      description: _optionalString(
        json['description'],
        'Today task description',
        2000,
      ),
      status: status,
      priority: _enumString(
        json['priority'],
        'Today task priority',
        const {'low', 'medium', 'high', 'critical'},
      ),
      deadline: _optionalAwareDateTime(
        json['deadline'],
        'Today task deadline',
      )?.toLocal(),
      estimatedMinutes: _optionalInteger(
        json['estimated_minutes'],
        'Today task estimate',
        minimum: 5,
        maximum: 480,
      ),
      completedAt: completedAt?.toLocal(),
      source: source,
      deadlinePlanId: deadlinePlanId,
      todayReason: _optionalEnumString(
        json['today_reason'],
        'Today task reason',
        const {
          'overdue',
          'due_today',
          'in_progress',
          'completed_today',
          'scheduled_today',
        },
      ),
      scheduledToday: _boolean(
        json['scheduled_today'],
        'Today task scheduled state',
      ),
      isCompleted: status == 'done',
    );
  }

  TodayHabit _habit(Map<String, dynamic> json) {
    _exactKeys(
      json,
      const {
        'id',
        'title',
        'description',
        'cadence',
        'cadence_label',
        'outcome',
        'weekly_completed',
        'weekly_target',
        'setup_managed',
        'scheduled_today',
      },
      'Today habit',
    );
    final cadence = _enumString(
      json['cadence'],
      'Today habit cadence',
      const {'daily', 'weekdays', 'weekly_target'},
    );
    final target = _integer(
      json['weekly_target'],
      'Today habit target',
      minimum: 1,
      maximum: 7,
    );
    if (cadence != 'weekly_target' && target != 1) {
      throw const TodayOverviewContractException(
        'Today habit target is inconsistent.',
      );
    }
    return TodayHabit(
      id: _uuid(json['id'], 'Today habit identity'),
      title: _string(json['title'], 'Today habit title', 160),
      description: _optionalString(
        json['description'],
        'Today habit description',
        2000,
      ),
      cadence: cadence,
      cadenceLabel: _string(
        json['cadence_label'],
        'Today habit cadence label',
        80,
      ),
      outcome: _optionalEnumString(
        json['outcome'],
        'Today habit outcome',
        const {'completed', 'skipped'},
      ),
      weeklyCompleted: _integer(
        json['weekly_completed'],
        'Today habit completion count',
        minimum: 0,
        maximum: 7,
      ),
      weeklyTarget: target,
      setupManaged: _boolean(json['setup_managed'], 'Today habit ownership'),
      scheduledToday: _boolean(
        json['scheduled_today'],
        'Today habit scheduled state',
      ),
    );
  }

  TodayTimelineItem _timelineItem(Map<String, dynamic> json) {
    final kind = json['kind'];
    switch (kind) {
      case 'setup_commitment':
        _exactKeys(
          json,
          const {
            'kind',
            'id',
            'title',
            'location',
            'all_day',
            'starts_at',
            'ends_at',
          },
          'Today setup commitment',
        );
        return _timedTimeline(
          json,
          kind: TodayTimelineKind.setupCommitment,
        );
      case 'preparation':
        _exactKeys(
          json,
          const {
            'kind',
            'id',
            'title',
            'location',
            'all_day',
            'starts_at',
            'ends_at',
            'plan_id',
            'block_id',
            'managed_task_id',
            'state',
            'planned_minutes',
            'credited_tracked_minutes',
          },
          'Today preparation block',
        );
        final item = _timedTimeline(
          json,
          kind: TodayTimelineKind.preparation,
          planId: _uuid(json['plan_id'], 'Today preparation plan'),
          blockId: _uuid(json['block_id'], 'Today preparation block'),
          managedTaskId: _uuid(
            json['managed_task_id'],
            'Today preparation task',
          ),
          state: _enumString(
            json['state'],
            'Today preparation state',
            const {'upcoming', 'partial', 'completed', 'missed'},
          ),
          plannedMinutes: _integer(
            json['planned_minutes'],
            'Today preparation minutes',
            minimum: 5,
            maximum: 240,
          ),
          creditedTrackedMinutes: _integer(
            json['credited_tracked_minutes'],
            'Today preparation credit',
            minimum: 0,
            maximum: 240,
          ),
        );
        if (item.id != item.blockId ||
            item.planId != item.managedTaskId ||
            item.creditedTrackedMinutes! > item.plannedMinutes!) {
          throw const TodayOverviewContractException(
            'Today preparation identity is inconsistent.',
          );
        }
        return item;
      case 'focus_session':
        _exactKeys(
          json,
          const {
            'kind',
            'id',
            'title',
            'location',
            'all_day',
            'starts_at',
            'ends_at',
            'status',
            'actual_minutes',
          },
          'Today focus session',
        );
        final status = _enumString(
          json['status'],
          'Today focus status',
          const {'active', 'completed', 'abandoned'},
        );
        final actualMinutes = _optionalInteger(
          json['actual_minutes'],
          'Today focus duration',
          minimum: 0,
        );
        if ((status == 'active') != (actualMinutes == null)) {
          throw const TodayOverviewContractException(
            'Today focus lifecycle is inconsistent.',
          );
        }
        return _timedTimeline(
          json,
          kind: TodayTimelineKind.focusSession,
          state: status,
          actualMinutes: actualMinutes,
        );
      case 'task_block':
        _exactKeys(
          json,
          const {
            'kind',
            'id',
            'title',
            'location',
            'all_day',
            'starts_at',
            'ends_at',
            'task_id',
            'planned_minutes',
          },
          'Today Task block',
        );
        return _timedTimeline(
          json,
          kind: TodayTimelineKind.taskBlock,
          taskId: _uuid(json['task_id'], 'Today Task block target'),
          plannedMinutes: _integer(
            json['planned_minutes'],
            'Today Task block minutes',
            minimum: 5,
            maximum: 240,
          ),
        );
      case 'habit_slot':
        _exactKeys(
          json,
          const {
            'kind',
            'id',
            'title',
            'location',
            'all_day',
            'starts_at',
            'ends_at',
            'habit_id',
            'planned_minutes',
          },
          'Today Habit slot',
        );
        return _timedTimeline(
          json,
          kind: TodayTimelineKind.habitSlot,
          habitId: _uuid(json['habit_id'], 'Today Habit slot target'),
          plannedMinutes: _integer(
            json['planned_minutes'],
            'Today Habit slot minutes',
            minimum: 5,
            maximum: 240,
          ),
        );
      case 'manual_commitment':
        _exactKeys(
          json,
          const {
            'kind',
            'id',
            'title',
            'location',
            'all_day',
            'starts_at',
            'ends_at',
            'commitment_id',
          },
          'Today fixed commitment',
        );
        return _timedTimeline(
          json,
          kind: TodayTimelineKind.manualCommitment,
          commitmentId: _uuid(
            json['commitment_id'],
            'Today fixed commitment identity',
          ),
        );
      case 'calendar_event':
        _exactKeys(
          json,
          const {
            'kind',
            'id',
            'title',
            'location',
            'source_label',
            'all_day',
            'starts_at',
            'ends_at',
            'starts_on',
            'ends_on',
          },
          'Today calendar event',
        );
        final allDay = _boolean(json['all_day'], 'Today all-day state');
        final startsAt = _optionalAwareDateTime(
          json['starts_at'],
          'Today calendar start',
        );
        final endsAt = _optionalAwareDateTime(
          json['ends_at'],
          'Today calendar end',
        );
        final startsOn = _optionalDate(json['starts_on'], 'Today start date');
        final endsOn = _optionalDate(json['ends_on'], 'Today end date');
        if (allDay
            ? startsOn == null ||
                endsOn == null ||
                !endsOn.isAfter(startsOn) ||
                startsAt != null ||
                endsAt != null
            : startsAt == null ||
                endsAt == null ||
                !endsAt.isAfter(startsAt) ||
                startsOn != null ||
                endsOn != null) {
          throw const TodayOverviewContractException(
            'Today calendar interval is inconsistent.',
          );
        }
        return TodayTimelineItem(
          kind: TodayTimelineKind.calendarEvent,
          id: _uuid(json['id'], 'Today calendar identity'),
          title: _string(json['title'], 'Today calendar title', 200),
          location: _optionalString(
            json['location'],
            'Today calendar location',
            300,
          ),
          sourceLabel: _string(
            json['source_label'],
            'Today calendar source',
            80,
          ),
          allDay: allDay,
          startsAt: startsAt?.toLocal(),
          endsAt: endsAt?.toLocal(),
          startsOn: startsOn,
          endsOn: endsOn,
        );
      default:
        throw const TodayOverviewContractException(
          'Today timeline kind is unsupported.',
        );
    }
  }

  TodayTimelineItem _timedTimeline(
    Map<String, dynamic> json, {
    required TodayTimelineKind kind,
    String? planId,
    String? blockId,
    String? managedTaskId,
    String? state,
    int? plannedMinutes,
    int? creditedTrackedMinutes,
    int? actualMinutes,
    String? taskId,
    String? habitId,
    String? commitmentId,
  }) {
    if (_boolean(json['all_day'], 'Today timed all-day state')) {
      throw const TodayOverviewContractException(
        'Today timed item cannot be all-day.',
      );
    }
    final startsAt = _awareDateTime(json['starts_at'], 'Today item start');
    final endsAt = _awareDateTime(json['ends_at'], 'Today item end');
    if (!endsAt.isAfter(startsAt)) {
      throw const TodayOverviewContractException(
        'Today timeline interval is invalid.',
      );
    }
    return TodayTimelineItem(
      kind: kind,
      id: _uuid(json['id'], 'Today timeline identity'),
      title: _string(json['title'], 'Today timeline title', 200),
      location: _optionalString(
        json['location'],
        'Today timeline location',
        300,
      ),
      allDay: false,
      startsAt: startsAt.toLocal(),
      endsAt: endsAt.toLocal(),
      planId: planId,
      blockId: blockId,
      managedTaskId: managedTaskId,
      state: state,
      plannedMinutes: plannedMinutes,
      creditedTrackedMinutes: creditedTrackedMinutes,
      actualMinutes: actualMinutes,
      taskId: taskId,
      habitId: habitId,
      commitmentId: commitmentId,
    );
  }

  TodaySourceStates _sourceStates(Map<String, dynamic> json) {
    _exactKeys(
      json,
      const {
        'check_ins',
        'tasks',
        'habits',
        'setup_commitments',
        'preparation',
        'calendar_events',
        'focus_sessions',
        'planner',
      },
      'Today source states',
    );
    return TodaySourceStates(
      checkIns: _sourceState(_map(json['check_ins'], 'Check-in source')),
      tasks: _sourceState(_map(json['tasks'], 'Task source')),
      habits: _sourceState(_map(json['habits'], 'Habit source')),
      setupCommitments: _sourceState(
        _map(json['setup_commitments'], 'Setup source'),
      ),
      preparation: _sourceState(
        _map(json['preparation'], 'Preparation source'),
      ),
      calendarEvents: _sourceState(
        _map(json['calendar_events'], 'Calendar source'),
      ),
      focusSessions: _sourceState(
        _map(json['focus_sessions'], 'Focus source'),
      ),
      planner: _sourceState(_map(json['planner'], 'Planner source')),
    );
  }

  TodaySourceState _sourceState(Map<String, dynamic> json) {
    _exactKeys(json, const {'status', 'message'}, 'Today source state');
    final statusCode = _enumString(
      json['status'],
      'Today source status',
      const {'current', 'unavailable'},
    );
    final message = _optionalString(
      json['message'],
      'Today source message',
      160,
    );
    if ((statusCode == 'unavailable') != (message != null)) {
      throw const TodayOverviewContractException(
        'Today source message is inconsistent.',
      );
    }
    return TodaySourceState(
      status: statusCode == 'current'
          ? TodaySourceStatus.current
          : TodaySourceStatus.unavailable,
      message: message,
    );
  }
}

class TodayOverviewContractException implements Exception {
  const TodayOverviewContractException(this.message);

  final String message;

  @override
  String toString() => message;
}

void _exactKeys(
  Map<String, dynamic> json,
  Set<String> expected,
  String label,
) {
  if (json.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(json.keys.toSet()).isNotEmpty) {
    throw TodayOverviewContractException('$label has an invalid shape.');
  }
}

Map<String, dynamic> _map(Object? value, String label) {
  if (value is! Map) {
    throw TodayOverviewContractException('$label must be an object.');
  }
  return Map<String, dynamic>.from(value);
}

List<dynamic> _list(Object? value, String label, int maximum) {
  if (value is! List || value.length > maximum) {
    throw TodayOverviewContractException('$label is invalid.');
  }
  return value;
}

String _string(Object? value, String label, int maximum) {
  if (value is! String ||
      value.isEmpty ||
      value != value.trim() ||
      value.length > maximum) {
    throw TodayOverviewContractException('$label is invalid.');
  }
  return value;
}

String? _optionalString(Object? value, String label, int maximum) =>
    value == null ? null : _string(value, label, maximum);

String _enumString(
  Object? value,
  String label,
  Set<String> allowed,
) {
  final text = _string(value, label, 100);
  if (!allowed.contains(text)) {
    throw TodayOverviewContractException('$label is invalid.');
  }
  return text;
}

String? _optionalEnumString(
  Object? value,
  String label,
  Set<String> allowed,
) =>
    value == null ? null : _enumString(value, label, allowed);

bool _boolean(Object? value, String label) {
  if (value is! bool) {
    throw TodayOverviewContractException('$label is invalid.');
  }
  return value;
}

int _integer(
  Object? value,
  String label, {
  required int minimum,
  int? maximum,
}) {
  if (value is! int || value < minimum || maximum != null && value > maximum) {
    throw TodayOverviewContractException('$label is invalid.');
  }
  return value;
}

int? _optionalInteger(
  Object? value,
  String label, {
  required int minimum,
  int? maximum,
}) =>
    value == null
        ? null
        : _integer(value, label, minimum: minimum, maximum: maximum);

DateTime _awareDateTime(Object? value, String label) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
      ).hasMatch(value)) {
    throw TodayOverviewContractException('$label is invalid.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      !parsed.isUtc && !value.contains(RegExp(r'[+-]\d{2}:\d{2}$'))) {
    throw TodayOverviewContractException('$label is invalid.');
  }
  return parsed;
}

DateTime? _optionalAwareDateTime(Object? value, String label) =>
    value == null ? null : _awareDateTime(value, label);

DateTime _date(Object? value, String label) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw TodayOverviewContractException('$label is invalid.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      '${parsed.year.toString().padLeft(4, '0')}-'
              '${parsed.month.toString().padLeft(2, '0')}-'
              '${parsed.day.toString().padLeft(2, '0')}' !=
          value) {
    throw TodayOverviewContractException('$label is invalid.');
  }
  return parsed;
}

DateTime? _optionalDate(Object? value, String label) =>
    value == null ? null : _date(value, label);

String _uuid(Object? value, String label) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(value)) {
    throw TodayOverviewContractException('$label is invalid.');
  }
  return value;
}

String? _optionalUuid(Object? value, String label) =>
    value == null ? null : _uuid(value, label);

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameStringSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
