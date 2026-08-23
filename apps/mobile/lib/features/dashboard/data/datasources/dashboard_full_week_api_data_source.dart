import '../../../../core/contracts/strict_contract.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/time/profile_timezone.dart';
import '../../domain/entities/dashboard_full_week.dart';

class DashboardFullWeekApiDataSource {
  const DashboardFullWeekApiDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<DashboardFullWeekProjection> getCurrentWeek({
    required String accessToken,
  }) async {
    final json = await _apiClient.getJson(
      '/v1/today/week-agenda',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return const DashboardFullWeekMapper().map(json);
  }
}

class DashboardFullWeekMapper {
  const DashboardFullWeekMapper();

  DashboardFullWeekProjection map(Map<String, dynamic> json) {
    _keys(
      json,
      const {
        'contract_version',
        'origin',
        'generated_at',
        'timezone',
        'local_today',
        'week_starts_on',
        'week_ends_on',
        'days',
        'source_states',
      },
      'Full week',
    );
    if (json['contract_version'] != todayWeekAgendaContractVersion ||
        json['origin'] != 'authenticated_backend') {
      throw const DashboardFullWeekException(
        'Full-week contract is unsupported.',
      );
    }
    final timezone = _string(json['timezone'], 'Full-week timezone', 100);
    final generatedAt = requireStrictAwareDateTime(
      json['generated_at'],
      exactSecondsFormat: true,
      validateDateAndTimeComponents: true,
      onFailure: () => _fail('Full-week generation time is invalid.'),
    );
    try {
      profileDateAt(instant: generatedAt, timezoneName: timezone);
    } on ProfileTimezoneException {
      throw const DashboardFullWeekException(
        'Full-week timezone is invalid.',
      );
    }
    final localToday = _date(json['local_today'], 'Full-week local today');
    if (!_sameDate(
      profileDateAt(instant: generatedAt, timezoneName: timezone),
      localToday,
    )) {
      throw const DashboardFullWeekException(
        'Full-week local today is invalid.',
      );
    }
    final weekStartsOn = _date(
      json['week_starts_on'],
      'Full-week start date',
    );
    final weekEndsOn = _date(json['week_ends_on'], 'Full-week end date');
    final sourceStates = _sourceStates(
      _map(json['source_states'], 'Full-week source states'),
    );
    final days = requireStrictMapList(
      json['days'],
      minItems: 7,
      maxItems: 7,
      onFailure: () => _fail('Full-week days are invalid.'),
    ).map((day) => _day(day, timezone)).toList(growable: false);
    return DashboardFullWeekProjection(
      generatedAt: generatedAt,
      timezone: timezone,
      localToday: localToday,
      weekStartsOn: weekStartsOn,
      weekEndsOn: weekEndsOn,
      days: days,
      sourceStates: sourceStates,
    );
  }

  DashboardFullWeekDay _day(Map<String, dynamic> json, String timezone) {
    _keys(json, const {'local_date', 'items'}, 'Full-week day');
    return DashboardFullWeekDay(
      localDate: _date(json['local_date'], 'Full-week day date'),
      items: requireStrictMapList(
        json['items'],
        maxItems: 4000,
        onFailure: () => _fail('Full-week day items are invalid.'),
      ).map((item) => _item(item, timezone)).toList(growable: false),
    );
  }

  DashboardFullWeekItem _item(
    Map<String, dynamic> json,
    String timezone,
  ) {
    _keys(
      json,
      const {
        'id',
        'category',
        'source_id',
        'plan_id',
        'habit_id',
        'local_date',
        'title',
        'detail',
        'status',
        'planned_minutes',
        'credited_tracked_minutes',
        'remaining_minutes',
        'all_day',
        'local_starts_at',
        'local_ends_at',
        'starts_at',
        'ends_at',
        'action',
      },
      'Full-week item',
    );
    final category = _category(json['category']);
    final itemId = _uuid(json['id'], 'Full-week item identity');
    final sourceId = _uuid(json['source_id'], 'Full-week source identity');
    final planId = _optionalUuid(json['plan_id'], 'Full-week plan identity');
    final habitId = _optionalUuid(json['habit_id'], 'Full-week Habit identity');
    final status = _status(category, json['status']);
    final plannedMinutes = _optionalInt(
      json['planned_minutes'],
      'Full-week planned minutes',
    );
    final creditedTrackedMinutes = _optionalInt(
      json['credited_tracked_minutes'],
      'Full-week credited minutes',
    );
    final remainingMinutes = _optionalInt(
      json['remaining_minutes'],
      'Full-week remaining minutes',
    );
    final allDay = requireStrictBool(
      json['all_day'],
      onFailure: () => _fail('Full-week all-day state is invalid.'),
    );
    final localDate = _date(json['local_date'], 'Full-week item date');
    final localStartsAt = _optionalLocalDateTime(
      json['local_starts_at'],
      'Full-week local start',
    );
    final localEndsAt = _optionalLocalDateTime(
      json['local_ends_at'],
      'Full-week local end',
    );
    final startsAt = _optionalAwareDateTime(
      json['starts_at'],
      'Full-week start',
    );
    final endsAt = _optionalAwareDateTime(json['ends_at'], 'Full-week end');
    if (allDay
        ? [localStartsAt, localEndsAt, startsAt, endsAt]
            .any((value) => value != null)
        : [localStartsAt, localEndsAt, startsAt, endsAt]
                .any((value) => value == null) ||
            !localStartsAt!.startsWith(_dateKey(localDate)) ||
            !localEndsAt!.startsWith(_dateKey(localDate)) &&
                !localEndsAt.startsWith(
                  _dateKey(localDate.add(const Duration(days: 1))),
                ) ||
            !endsAt!.isAfter(startsAt!) ||
            localStartsAt != _profileWall(startsAt, timezone) ||
            localEndsAt != _profileWall(endsAt, timezone)) {
      throw const DashboardFullWeekException(
        'Full-week item interval is invalid.',
      );
    }
    final actionJson = json['action'];
    final action = actionJson == null
        ? null
        : _action(_map(actionJson, 'Full-week action'));
    if (!_itemFactsMatch(
          category: category,
          planId: planId,
          habitId: habitId,
          plannedMinutes: plannedMinutes,
          creditedTrackedMinutes: creditedTrackedMinutes,
          remainingMinutes: remainingMinutes,
        ) ||
        action != null &&
            !_actionMatches(
              category: category,
              status: status,
              sourceId: sourceId,
              planId: planId,
              habitId: habitId,
              remainingMinutes: remainingMinutes,
              localDate: localDate,
              action: action,
            )) {
      throw const DashboardFullWeekException(
        'Full-week item action is invalid.',
      );
    }
    return DashboardFullWeekItem(
      id: itemId,
      category: category,
      sourceId: sourceId,
      planId: planId,
      habitId: habitId,
      localDate: localDate,
      title: _string(json['title'], 'Full-week title', 200),
      detail: _optionalString(json['detail'], 'Full-week detail', 300),
      status: status,
      plannedMinutes: plannedMinutes,
      creditedTrackedMinutes: creditedTrackedMinutes,
      remainingMinutes: remainingMinutes,
      allDay: allDay,
      localStartsAt: localStartsAt,
      localEndsAt: localEndsAt,
      startsAt: startsAt,
      endsAt: endsAt,
      action: action,
    );
  }

  DashboardFullWeekAction _action(Map<String, dynamic> json) {
    _keys(
      json,
      const {'kind', 'target_id', 'source_kind', 'local_date'},
      'Full-week action',
    );
    final kind = switch (json['kind']) {
      'start_preparation_focus' =>
        DashboardFullWeekActionKind.startPreparationFocus,
      'start_task_focus' => DashboardFullWeekActionKind.startTaskFocus,
      'resume_focus' => DashboardFullWeekActionKind.resumeFocus,
      'reflect_focus' => DashboardFullWeekActionKind.reflectFocus,
      'open_preparation_plan' =>
        DashboardFullWeekActionKind.openPreparationPlan,
      'open_habit' => DashboardFullWeekActionKind.openHabit,
      _ => _fail('Full-week action kind is invalid.'),
    };
    final sourceKind = _optionalEnum(
      json['source_kind'],
      'Full-week action source',
      const {'deadline_plan_block', 'planner_task_block'},
    );
    final localDate = json['local_date'] == null
        ? null
        : _date(json['local_date'], 'Full-week action date');
    final scheduled = const {
      DashboardFullWeekActionKind.startPreparationFocus,
      DashboardFullWeekActionKind.startTaskFocus,
    }.contains(kind);
    if (scheduled != (sourceKind != null) ||
        (kind == DashboardFullWeekActionKind.openHabit) !=
            (localDate != null)) {
      throw const DashboardFullWeekException(
        'Full-week action payload is invalid.',
      );
    }
    return DashboardFullWeekAction(
      kind: kind,
      targetId: _uuid(json['target_id'], 'Full-week action target'),
      sourceKind: sourceKind,
      localDate: localDate,
    );
  }

  DashboardFullWeekSourceStates _sourceStates(Map<String, dynamic> json) {
    _keys(
      json,
      const {
        'setup',
        'preparation',
        'calendar',
        'focus',
        'tasks',
        'habits',
        'fixed_commitments',
      },
      'Full-week source states',
    );
    return DashboardFullWeekSourceStates(
      setup: _source('setup', 'Setup', json['setup']),
      preparation: _source(
        'preparation',
        'Preparation',
        json['preparation'],
      ),
      calendar: _source('calendar', 'Calendar', json['calendar']),
      focus: _source('focus', 'Focus', json['focus']),
      tasks: _source('tasks', 'Planner Tasks', json['tasks']),
      habits: _source('habits', 'Habit slots', json['habits']),
      fixedCommitments: _source(
        'fixed_commitments',
        'Fixed commitments',
        json['fixed_commitments'],
      ),
    );
  }

  DashboardFullWeekSourceState _source(
    String name,
    String label,
    Object? value,
  ) {
    final json = _map(value, '$label source');
    _keys(json, const {'status', 'message'}, '$label source');
    final status = switch (json['status']) {
      'current' => DashboardFullWeekSourceStatus.current,
      'unavailable' => DashboardFullWeekSourceStatus.unavailable,
      _ => _fail('$label source status is invalid.'),
    };
    final message = _optionalString(json['message'], '$label message', 160);
    if ((status == DashboardFullWeekSourceStatus.unavailable) !=
        (message != null)) {
      throw DashboardFullWeekException('$label source state is invalid.');
    }
    return DashboardFullWeekSourceState(
      name: name,
      label: label,
      status: status,
      message: message,
    );
  }
}

bool _actionMatches({
  required DashboardFullWeekCategory category,
  required DashboardFullWeekItemStatus status,
  required String sourceId,
  required String? planId,
  required String? habitId,
  required int? remainingMinutes,
  required DateTime localDate,
  required DashboardFullWeekAction action,
}) =>
    switch (action.kind) {
      DashboardFullWeekActionKind.startPreparationFocus =>
        category == DashboardFullWeekCategory.preparation &&
            action.sourceKind == 'deadline_plan_block' &&
            action.targetId == sourceId &&
            action.localDate == null &&
            const {
              DashboardFullWeekItemStatus.upcoming,
              DashboardFullWeekItemStatus.partial,
              DashboardFullWeekItemStatus.missed,
            }.contains(status) &&
            remainingMinutes != null &&
            remainingMinutes >= 5,
      DashboardFullWeekActionKind.startTaskFocus =>
        category == DashboardFullWeekCategory.task &&
            action.sourceKind == 'planner_task_block' &&
            action.targetId == sourceId &&
            action.localDate == null &&
            const {
              DashboardFullWeekItemStatus.todo,
              DashboardFullWeekItemStatus.inProgress,
            }.contains(status),
      DashboardFullWeekActionKind.resumeFocus =>
        category == DashboardFullWeekCategory.focus &&
            action.sourceKind == null &&
            action.targetId == sourceId &&
            action.localDate == null &&
            status == DashboardFullWeekItemStatus.active,
      DashboardFullWeekActionKind.reflectFocus =>
        category == DashboardFullWeekCategory.focus &&
            action.sourceKind == null &&
            action.targetId == sourceId &&
            action.localDate == null &&
            const {
              DashboardFullWeekItemStatus.completed,
              DashboardFullWeekItemStatus.abandoned,
            }.contains(status),
      DashboardFullWeekActionKind.openPreparationPlan =>
        category == DashboardFullWeekCategory.preparation &&
            action.sourceKind == null &&
            action.targetId == planId &&
            action.localDate == null,
      DashboardFullWeekActionKind.openHabit =>
        category == DashboardFullWeekCategory.habit &&
            action.sourceKind == null &&
            action.targetId == habitId &&
            action.localDate != null &&
            _sameDate(action.localDate!, localDate),
    };

bool _itemFactsMatch({
  required DashboardFullWeekCategory category,
  required String? planId,
  required String? habitId,
  required int? plannedMinutes,
  required int? creditedTrackedMinutes,
  required int? remainingMinutes,
}) {
  final preparationFacts = [
    planId,
    plannedMinutes,
    creditedTrackedMinutes,
    remainingMinutes,
  ];
  if (category == DashboardFullWeekCategory.preparation) {
    if (preparationFacts.any((value) => value == null) ||
        plannedMinutes! < 5 ||
        plannedMinutes > 240 ||
        creditedTrackedMinutes! < 0 ||
        creditedTrackedMinutes > plannedMinutes ||
        remainingMinutes != plannedMinutes - creditedTrackedMinutes) {
      return false;
    }
  } else if (preparationFacts.any((value) => value != null)) {
    return false;
  }
  return (category == DashboardFullWeekCategory.habit) == (habitId != null);
}

DashboardFullWeekCategory _category(Object? value) => switch (value) {
      'setup' => DashboardFullWeekCategory.setup,
      'preparation' => DashboardFullWeekCategory.preparation,
      'calendar' => DashboardFullWeekCategory.calendar,
      'focus' => DashboardFullWeekCategory.focus,
      'task' => DashboardFullWeekCategory.task,
      'habit' => DashboardFullWeekCategory.habit,
      'fixed_commitment' => DashboardFullWeekCategory.fixedCommitment,
      _ => _fail('Full-week category is invalid.'),
    };

Map<String, dynamic> _map(Object? value, String label) => requireStrictMap(
      value,
      onFailure: () => _fail('$label is invalid.'),
    );

void _keys(Map<String, dynamic> value, Set<String> keys, String label) =>
    requireStrictKeys(
      value,
      requiredKeys: keys,
      onFailure: () => _fail('$label fields are invalid.'),
    );

String _string(Object? value, String label, int maximum) => requireStrictString(
      value,
      maxLength: maximum,
      onFailure: () => _fail('$label is invalid.'),
    );

String? _optionalString(Object? value, String label, int maximum) =>
    value == null ? null : _string(value, label, maximum);

String _uuid(Object? value, String label) => requireStrictUuid(
      value,
      onFailure: () => _fail('$label is invalid.'),
    );

String? _optionalUuid(Object? value, String label) =>
    value == null ? null : _uuid(value, label);

int? _optionalInt(Object? value, String label) {
  if (value == null) return null;
  if (value is! int || value is bool) _fail('$label is invalid.');
  return value;
}

DashboardFullWeekItemStatus _status(
  DashboardFullWeekCategory category,
  Object? value,
) {
  final result = switch (value) {
    'scheduled' => DashboardFullWeekItemStatus.scheduled,
    'upcoming' => DashboardFullWeekItemStatus.upcoming,
    'partial' => DashboardFullWeekItemStatus.partial,
    'completed' => DashboardFullWeekItemStatus.completed,
    'missed' => DashboardFullWeekItemStatus.missed,
    'confirmed' => DashboardFullWeekItemStatus.confirmed,
    'tentative' => DashboardFullWeekItemStatus.tentative,
    'active' => DashboardFullWeekItemStatus.active,
    'abandoned' => DashboardFullWeekItemStatus.abandoned,
    'todo' => DashboardFullWeekItemStatus.todo,
    'in_progress' => DashboardFullWeekItemStatus.inProgress,
    'done' => DashboardFullWeekItemStatus.done,
    'cancelled' => DashboardFullWeekItemStatus.cancelled,
    'open' => DashboardFullWeekItemStatus.open,
    'skipped' => DashboardFullWeekItemStatus.skipped,
    _ => _fail('Full-week status is invalid.'),
  };
  final valid = switch (category) {
    DashboardFullWeekCategory.setup ||
    DashboardFullWeekCategory.fixedCommitment =>
      result == DashboardFullWeekItemStatus.scheduled,
    DashboardFullWeekCategory.preparation => const {
        DashboardFullWeekItemStatus.upcoming,
        DashboardFullWeekItemStatus.partial,
        DashboardFullWeekItemStatus.completed,
        DashboardFullWeekItemStatus.missed,
      }.contains(result),
    DashboardFullWeekCategory.calendar => const {
        DashboardFullWeekItemStatus.confirmed,
        DashboardFullWeekItemStatus.tentative,
      }.contains(result),
    DashboardFullWeekCategory.focus => const {
        DashboardFullWeekItemStatus.active,
        DashboardFullWeekItemStatus.completed,
        DashboardFullWeekItemStatus.abandoned,
      }.contains(result),
    DashboardFullWeekCategory.task => const {
        DashboardFullWeekItemStatus.todo,
        DashboardFullWeekItemStatus.inProgress,
        DashboardFullWeekItemStatus.done,
        DashboardFullWeekItemStatus.cancelled,
      }.contains(result),
    DashboardFullWeekCategory.habit => const {
        DashboardFullWeekItemStatus.open,
        DashboardFullWeekItemStatus.completed,
        DashboardFullWeekItemStatus.skipped,
      }.contains(result),
  };
  if (!valid) _fail('Full-week status does not match its category.');
  return result;
}

DateTime _date(Object? value, String label) {
  final text = requireStrictLocalDate(
    value,
    minimumYear: 1,
    onFailure: () => _fail('$label is invalid.'),
  );
  return dashboardFullWeekDate(text);
}

String? _optionalLocalDateTime(Object? value, String label) {
  if (value == null) return null;
  if (value is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$').hasMatch(value) ||
      DateTime.tryParse(value) == null ||
      DateTime.parse(value).isUtc) {
    _fail('$label is invalid.');
  }
  return value;
}

DateTime? _optionalAwareDateTime(Object? value, String label) => value == null
    ? null
    : requireStrictAwareDateTime(
        value,
        exactSecondsFormat: true,
        validateDateAndTimeComponents: true,
        onFailure: () => _fail('$label is invalid.'),
      );

String? _optionalEnum(
  Object? value,
  String label,
  Set<String> allowed,
) {
  if (value == null) return null;
  final parsed = _string(value, label, 40);
  if (!allowed.contains(parsed)) _fail('$label is invalid.');
  return parsed;
}

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _profileWall(DateTime instant, String timezoneName) {
  final local = profileDateTimeAt(
    instant: instant,
    timezoneName: timezoneName,
  );
  return '${_dateKey(local)}T'
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

Never _fail(String message) => throw DashboardFullWeekException(message);
