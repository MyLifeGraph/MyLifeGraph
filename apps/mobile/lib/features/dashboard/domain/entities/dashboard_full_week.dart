const todayWeekAgendaContractVersion = 'today-week-agenda-v1';

enum DashboardFullWeekCategory {
  setup,
  preparation,
  calendar,
  focus,
  task,
  habit,
  fixedCommitment,
}

enum DashboardFullWeekSourceStatus { current, unavailable }

enum DashboardFullWeekItemStatus {
  scheduled,
  upcoming,
  partial,
  completed,
  missed,
  confirmed,
  tentative,
  active,
  abandoned,
  todo,
  inProgress,
  done,
  cancelled,
  open,
  skipped,
}

enum DashboardFullWeekActionKind {
  startPreparationFocus,
  startTaskFocus,
  resumeFocus,
  reflectFocus,
  openPreparationPlan,
  openHabit,
}

class DashboardFullWeekProjection {
  DashboardFullWeekProjection({
    required this.generatedAt,
    required this.timezone,
    required this.localToday,
    required this.weekStartsOn,
    required this.weekEndsOn,
    required List<DashboardFullWeekDay> days,
    required this.sourceStates,
  }) : days = List.unmodifiable(days) {
    if (days.length != 7 ||
        weekStartsOn.weekday != DateTime.monday ||
        !_sameDate(weekEndsOn, _datePlusDays(weekStartsOn, 6)) ||
        days.asMap().entries.any(
              (entry) => !_sameDate(
                entry.value.localDate,
                _datePlusDays(weekStartsOn, entry.key),
              ),
            ) ||
        !_dateWithin(localToday, weekStartsOn, weekEndsOn)) {
      throw const DashboardFullWeekException(
        'Full week must contain one ordered profile-local Monday-to-Sunday week.',
      );
    }
    for (final day in days) {
      final ids = <String>{};
      for (final item in day.items) {
        if (!_sameDate(item.localDate, day.localDate) || !ids.add(item.id)) {
          throw const DashboardFullWeekException(
            'Full-week day items are inconsistent.',
          );
        }
        if (sourceStates.forCategory(item.category).status !=
            DashboardFullWeekSourceStatus.current) {
          throw const DashboardFullWeekException(
            'Unavailable Full-week sources cannot expose items.',
          );
        }
        if (!_statusMatches(item.category, item.status) ||
            !_identityAndActionMatch(item)) {
          throw const DashboardFullWeekException(
            'Full-week item authority is inconsistent.',
          );
        }
        if (item.action?.kind == DashboardFullWeekActionKind.openHabit &&
            !_sameDate(item.action!.localDate!, localToday)) {
          throw const DashboardFullWeekException(
            'Full-week Habit action is not for profile-local Today.',
          );
        }
      }
    }
  }

  final DateTime generatedAt;
  final String timezone;
  final DateTime localToday;
  final DateTime weekStartsOn;
  final DateTime weekEndsOn;
  final List<DashboardFullWeekDay> days;
  final DashboardFullWeekSourceStates sourceStates;

  factory DashboardFullWeekProjection.empty(DateTime displayedLocalDate) {
    final localToday = DateTime.utc(
      displayedLocalDate.year,
      displayedLocalDate.month,
      displayedLocalDate.day,
    );
    final weekStartsOn = localToday.subtract(
      Duration(days: localToday.weekday - DateTime.monday),
    );
    const current = DashboardFullWeekSourceStatus.current;
    return DashboardFullWeekProjection(
      generatedAt: DateTime.now().toUtc(),
      timezone: 'UTC',
      localToday: localToday,
      weekStartsOn: weekStartsOn,
      weekEndsOn: weekStartsOn.add(const Duration(days: 6)),
      days: List.generate(
        7,
        (offset) => DashboardFullWeekDay(
          localDate: weekStartsOn.add(Duration(days: offset)),
          items: const [],
        ),
      ),
      sourceStates: const DashboardFullWeekSourceStates(
        setup: DashboardFullWeekSourceState(
          name: 'setup',
          label: 'Setup',
          status: current,
        ),
        preparation: DashboardFullWeekSourceState(
          name: 'preparation',
          label: 'Preparation',
          status: current,
        ),
        calendar: DashboardFullWeekSourceState(
          name: 'calendar',
          label: 'Calendar',
          status: current,
        ),
        focus: DashboardFullWeekSourceState(
          name: 'focus',
          label: 'Focus',
          status: current,
        ),
        tasks: DashboardFullWeekSourceState(
          name: 'tasks',
          label: 'Planner Tasks',
          status: current,
        ),
        habits: DashboardFullWeekSourceState(
          name: 'habits',
          label: 'Habit slots',
          status: current,
        ),
        fixedCommitments: DashboardFullWeekSourceState(
          name: 'fixed_commitments',
          label: 'Fixed commitments',
          status: current,
        ),
      ),
    );
  }

  List<DashboardFullWeekSourceState> get unavailableSources => sourceStates.all
      .where(
        (source) => source.status == DashboardFullWeekSourceStatus.unavailable,
      )
      .toList(growable: false);
}

class DashboardFullWeekDay {
  DashboardFullWeekDay({
    required this.localDate,
    required List<DashboardFullWeekItem> items,
  }) : items = List.unmodifiable(items);

  final DateTime localDate;
  final List<DashboardFullWeekItem> items;
}

class DashboardFullWeekItem {
  const DashboardFullWeekItem({
    required this.id,
    required this.category,
    required this.sourceId,
    required this.localDate,
    required this.title,
    required this.status,
    required this.allDay,
    this.planId,
    this.habitId,
    this.plannedMinutes,
    this.creditedTrackedMinutes,
    this.remainingMinutes,
    this.detail,
    this.localStartsAt,
    this.localEndsAt,
    this.startsAt,
    this.endsAt,
    this.action,
  });

  final String id;
  final DashboardFullWeekCategory category;
  final String sourceId;
  final String? planId;
  final String? habitId;
  final DateTime localDate;
  final String title;
  final String? detail;
  final DashboardFullWeekItemStatus status;
  final int? plannedMinutes;
  final int? creditedTrackedMinutes;
  final int? remainingMinutes;
  final bool allDay;
  final String? localStartsAt;
  final String? localEndsAt;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DashboardFullWeekAction? action;

  String get timeLabel {
    if (allDay) return 'All day';
    return '${localStartsAt!.substring(11, 16)}–'
        '${localEndsAt!.substring(11, 16)}';
  }
}

class DashboardFullWeekAction {
  const DashboardFullWeekAction({
    required this.kind,
    required this.targetId,
    this.sourceKind,
    this.localDate,
  });

  final DashboardFullWeekActionKind kind;
  final String targetId;
  final String? sourceKind;
  final DateTime? localDate;
}

class DashboardFullWeekSourceStates {
  const DashboardFullWeekSourceStates({
    required this.setup,
    required this.preparation,
    required this.calendar,
    required this.focus,
    required this.tasks,
    required this.habits,
    required this.fixedCommitments,
  });

  final DashboardFullWeekSourceState setup;
  final DashboardFullWeekSourceState preparation;
  final DashboardFullWeekSourceState calendar;
  final DashboardFullWeekSourceState focus;
  final DashboardFullWeekSourceState tasks;
  final DashboardFullWeekSourceState habits;
  final DashboardFullWeekSourceState fixedCommitments;

  List<DashboardFullWeekSourceState> get all => [
        setup,
        preparation,
        calendar,
        focus,
        tasks,
        habits,
        fixedCommitments,
      ];

  DashboardFullWeekSourceState forCategory(
    DashboardFullWeekCategory category,
  ) =>
      switch (category) {
        DashboardFullWeekCategory.setup => setup,
        DashboardFullWeekCategory.preparation => preparation,
        DashboardFullWeekCategory.calendar => calendar,
        DashboardFullWeekCategory.focus => focus,
        DashboardFullWeekCategory.task => tasks,
        DashboardFullWeekCategory.habit => habits,
        DashboardFullWeekCategory.fixedCommitment => fixedCommitments,
      };
}

class DashboardFullWeekSourceState {
  const DashboardFullWeekSourceState({
    required this.name,
    required this.label,
    required this.status,
    this.message,
  });

  final String name;
  final String label;
  final DashboardFullWeekSourceStatus status;
  final String? message;
}

class DashboardFullWeekException implements Exception {
  const DashboardFullWeekException(this.message);

  final String message;

  @override
  String toString() => message;
}

DateTime dashboardFullWeekDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    throw const DashboardFullWeekException('Full-week date is invalid.');
  }
  final result = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  if (_dateKey(result) != value) {
    throw const DashboardFullWeekException('Full-week date is invalid.');
  }
  return result;
}

DateTime _datePlusDays(DateTime value, int days) =>
    DateTime.utc(value.year, value.month, value.day).add(Duration(days: days));

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

bool _dateWithin(DateTime value, DateTime start, DateTime end) =>
    !value.isBefore(start) && !value.isAfter(end);

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

bool _statusMatches(
  DashboardFullWeekCategory category,
  DashboardFullWeekItemStatus status,
) =>
    switch (category) {
      DashboardFullWeekCategory.setup ||
      DashboardFullWeekCategory.fixedCommitment =>
        status == DashboardFullWeekItemStatus.scheduled,
      DashboardFullWeekCategory.preparation => const {
          DashboardFullWeekItemStatus.upcoming,
          DashboardFullWeekItemStatus.partial,
          DashboardFullWeekItemStatus.completed,
          DashboardFullWeekItemStatus.missed,
        }.contains(status),
      DashboardFullWeekCategory.calendar => const {
          DashboardFullWeekItemStatus.confirmed,
          DashboardFullWeekItemStatus.tentative,
        }.contains(status),
      DashboardFullWeekCategory.focus => const {
          DashboardFullWeekItemStatus.active,
          DashboardFullWeekItemStatus.completed,
          DashboardFullWeekItemStatus.abandoned,
        }.contains(status),
      DashboardFullWeekCategory.task => const {
          DashboardFullWeekItemStatus.todo,
          DashboardFullWeekItemStatus.inProgress,
          DashboardFullWeekItemStatus.done,
          DashboardFullWeekItemStatus.cancelled,
        }.contains(status),
      DashboardFullWeekCategory.habit => const {
          DashboardFullWeekItemStatus.open,
          DashboardFullWeekItemStatus.completed,
          DashboardFullWeekItemStatus.skipped,
        }.contains(status),
    };

bool _identityAndActionMatch(DashboardFullWeekItem item) {
  final isPreparation = item.category == DashboardFullWeekCategory.preparation;
  if (isPreparation !=
      (item.planId != null &&
          item.plannedMinutes != null &&
          item.creditedTrackedMinutes != null &&
          item.remainingMinutes != null)) {
    return false;
  }
  if (isPreparation &&
      (item.plannedMinutes! < 5 ||
          item.plannedMinutes! > 240 ||
          item.creditedTrackedMinutes! < 0 ||
          item.creditedTrackedMinutes! > item.plannedMinutes! ||
          item.remainingMinutes !=
              item.plannedMinutes! - item.creditedTrackedMinutes!)) {
    return false;
  }
  if ((item.category == DashboardFullWeekCategory.habit) !=
      (item.habitId != null)) {
    return false;
  }
  final action = item.action;
  if (action == null) return true;
  return switch (action.kind) {
    DashboardFullWeekActionKind.startPreparationFocus =>
      item.category == DashboardFullWeekCategory.preparation &&
          action.sourceKind == 'deadline_plan_block' &&
          action.localDate == null &&
          action.targetId == item.sourceId &&
          const {
            DashboardFullWeekItemStatus.upcoming,
            DashboardFullWeekItemStatus.partial,
            DashboardFullWeekItemStatus.missed,
          }.contains(item.status) &&
          item.remainingMinutes! >= 5,
    DashboardFullWeekActionKind.startTaskFocus =>
      item.category == DashboardFullWeekCategory.task &&
          action.sourceKind == 'planner_task_block' &&
          action.localDate == null &&
          action.targetId == item.sourceId &&
          const {
            DashboardFullWeekItemStatus.todo,
            DashboardFullWeekItemStatus.inProgress,
          }.contains(item.status),
    DashboardFullWeekActionKind.resumeFocus =>
      item.category == DashboardFullWeekCategory.focus &&
          action.sourceKind == null &&
          action.localDate == null &&
          action.targetId == item.sourceId &&
          item.status == DashboardFullWeekItemStatus.active,
    DashboardFullWeekActionKind.reflectFocus =>
      item.category == DashboardFullWeekCategory.focus &&
          action.sourceKind == null &&
          action.localDate == null &&
          action.targetId == item.sourceId &&
          const {
            DashboardFullWeekItemStatus.completed,
            DashboardFullWeekItemStatus.abandoned,
          }.contains(item.status),
    DashboardFullWeekActionKind.openPreparationPlan =>
      item.category == DashboardFullWeekCategory.preparation &&
          action.sourceKind == null &&
          action.localDate == null &&
          action.targetId == item.planId,
    DashboardFullWeekActionKind.openHabit =>
      item.category == DashboardFullWeekCategory.habit &&
          action.sourceKind == null &&
          action.targetId == item.habitId &&
          action.localDate != null &&
          _sameDate(action.localDate!, item.localDate),
  };
}
