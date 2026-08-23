import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_full_week.dart';

DashboardFullWeekProjection dashboardFullWeekFixture({
  DateTime? localToday,
  List<DashboardFullWeekItem> items = const [],
  DashboardFullWeekSourceStates sourceStates = dashboardFullWeekCurrentSources,
}) {
  final today = localToday ?? DateTime.utc(2026, 8, 5);
  final normalized = DateTime.utc(today.year, today.month, today.day);
  final monday = normalized.subtract(
    Duration(days: normalized.weekday - DateTime.monday),
  );
  return DashboardFullWeekProjection(
    generatedAt: DateTime.utc(2026, 8, 5, 8),
    timezone: 'Europe/Berlin',
    localToday: normalized,
    weekStartsOn: monday,
    weekEndsOn: monday.add(const Duration(days: 6)),
    days: List.generate(7, (offset) {
      final date = monday.add(Duration(days: offset));
      return DashboardFullWeekDay(
        localDate: date,
        items: items
            .where(
              (item) =>
                  item.localDate.year == date.year &&
                  item.localDate.month == date.month &&
                  item.localDate.day == date.day,
            )
            .toList(),
      );
    }),
    sourceStates: sourceStates,
  );
}

const dashboardFullWeekCurrentSources = DashboardFullWeekSourceStates(
  setup: DashboardFullWeekSourceState(
    name: 'setup',
    label: 'Setup',
    status: DashboardFullWeekSourceStatus.current,
  ),
  preparation: DashboardFullWeekSourceState(
    name: 'preparation',
    label: 'Preparation',
    status: DashboardFullWeekSourceStatus.current,
  ),
  calendar: DashboardFullWeekSourceState(
    name: 'calendar',
    label: 'Calendar',
    status: DashboardFullWeekSourceStatus.current,
  ),
  focus: DashboardFullWeekSourceState(
    name: 'focus',
    label: 'Focus',
    status: DashboardFullWeekSourceStatus.current,
  ),
  tasks: DashboardFullWeekSourceState(
    name: 'tasks',
    label: 'Planner Tasks',
    status: DashboardFullWeekSourceStatus.current,
  ),
  habits: DashboardFullWeekSourceState(
    name: 'habits',
    label: 'Habit slots',
    status: DashboardFullWeekSourceStatus.current,
  ),
  fixedCommitments: DashboardFullWeekSourceState(
    name: 'fixed_commitments',
    label: 'Fixed commitments',
    status: DashboardFullWeekSourceStatus.current,
  ),
);

DashboardFullWeekItem dashboardFullWeekTimedItem({
  required String id,
  required DashboardFullWeekCategory category,
  required DateTime localDate,
  required String title,
  DashboardFullWeekAction? action,
  DashboardFullWeekItemStatus? status,
  String? detail,
  String start = '09:00:00',
  String end = '10:00:00',
}) {
  final date = _date(localDate);
  final resolvedStatus = status ??
      (action?.kind == DashboardFullWeekActionKind.resumeFocus
          ? DashboardFullWeekItemStatus.active
          : _defaultStatus(category));
  final isPreparation = category == DashboardFullWeekCategory.preparation;
  final isHabit = category == DashboardFullWeekCategory.habit;
  return DashboardFullWeekItem(
    id: id,
    category: category,
    sourceId: id,
    planId: isPreparation ? action?.targetId ?? 'plan-$id' : null,
    habitId: isHabit ? action?.targetId ?? 'habit-$id' : null,
    localDate: DateTime.utc(localDate.year, localDate.month, localDate.day),
    title: title,
    detail: detail,
    status: resolvedStatus,
    plannedMinutes: isPreparation ? 60 : null,
    creditedTrackedMinutes: isPreparation ? 0 : null,
    remainingMinutes: isPreparation ? 60 : null,
    allDay: false,
    localStartsAt: '${_dateKey(date)}T$start',
    localEndsAt: '${_dateKey(date)}T$end',
    startsAt: DateTime.utc(date.year, date.month, date.day, 7),
    endsAt: DateTime.utc(date.year, date.month, date.day, 8),
    action: action,
  );
}

DashboardFullWeekItemStatus _defaultStatus(
  DashboardFullWeekCategory category,
) =>
    switch (category) {
      DashboardFullWeekCategory.setup ||
      DashboardFullWeekCategory.fixedCommitment =>
        DashboardFullWeekItemStatus.scheduled,
      DashboardFullWeekCategory.preparation =>
        DashboardFullWeekItemStatus.upcoming,
      DashboardFullWeekCategory.calendar =>
        DashboardFullWeekItemStatus.confirmed,
      DashboardFullWeekCategory.focus => DashboardFullWeekItemStatus.completed,
      DashboardFullWeekCategory.task => DashboardFullWeekItemStatus.todo,
      DashboardFullWeekCategory.habit => DashboardFullWeekItemStatus.open,
    };

DateTime _date(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
