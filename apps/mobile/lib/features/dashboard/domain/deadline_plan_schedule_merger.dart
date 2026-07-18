import 'entities/deadline_preparation_schedule_block.dart';
import 'entities/dashboard_snapshot.dart';

class DeadlinePlanScheduleMerger {
  const DeadlinePlanScheduleMerger({this.toDeviceLocal = _toLocal});

  final DateTime Function(DateTime) toDeviceLocal;

  DashboardSnapshot merge(
    DashboardSnapshot snapshot,
    List<DeadlinePreparationScheduleBlock> blocks,
  ) {
    if (snapshot.origin != DashboardOrigin.account) return snapshot;

    final eventsByDate = <String, List<ScheduleEvent>>{};
    for (final block in blocks) {
      final startsAt = toDeviceLocal(block.startsAt);
      final endsAt = toDeviceLocal(block.endsAt);
      final deviceDate = _dateKey(startsAt);
      eventsByDate.putIfAbsent(deviceDate, () => []).add(
            ScheduleEvent(
              title: 'Preparation: ${block.planTitle}',
              time: '${_time(startsAt)}–${_time(endsAt)}',
              origin: ScheduleEventOrigin.deadlinePreparation,
              provenanceLabel: 'Device time · MyLifeGraph reservation',
              deadlinePlanId: block.planId,
              deadlinePlanBlockId: block.id,
              sortMinutes: startsAt.hour * 60 + startsAt.minute,
              endSortMinutes: endsAt.hour * 60 + endsAt.minute,
            ),
          );
    }

    final mergedDays = snapshot.scheduleDays.map((day) {
      final date = day.date;
      if (date == null) return day;
      final key = _dateKey(date);
      final preparation = eventsByDate[key] ?? const <ScheduleEvent>[];
      if (preparation.isEmpty) return day;
      final events = [...day.events, ...preparation]..sort((left, right) {
          final byTime = (left.sortMinutes ?? 24 * 60)
              .compareTo(right.sortMinutes ?? 24 * 60);
          if (byTime != 0) return byTime;
          return left.title.compareTo(right.title);
        });
      return ScheduleDay(
        label: day.label,
        dateLabel: day.dateLabel,
        events: List.unmodifiable(events),
        date: day.date,
      );
    }).toList(growable: false);

    return DashboardSnapshot(
      origin: snapshot.origin,
      loadedAt: snapshot.loadedAt,
      latestCheckIn: snapshot.latestCheckIn,
      checkInStreakDays: snapshot.checkInStreakDays,
      todayPlan: snapshot.todayPlan,
      scheduleDays: mergedDays,
      preparationScheduleError: null,
    );
  }

  DashboardSnapshot withUnavailablePreparationSchedule(
    DashboardSnapshot snapshot,
  ) {
    if (snapshot.origin != DashboardOrigin.account) return snapshot;
    return DashboardSnapshot(
      origin: snapshot.origin,
      loadedAt: snapshot.loadedAt,
      latestCheckIn: snapshot.latestCheckIn,
      checkInStreakDays: snapshot.checkInStreakDays,
      todayPlan: snapshot.todayPlan,
      scheduleDays: snapshot.scheduleDays,
      preparationScheduleError:
          'Preparation reservations could not be loaded. Existing commitments are still shown.',
    );
  }

  String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _time(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

DateTime _toLocal(DateTime value) => value.toLocal();
