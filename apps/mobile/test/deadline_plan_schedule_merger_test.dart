import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/dashboard/domain/deadline_plan_schedule_merger.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/deadline_preparation_schedule_block.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_snapshot.dart';

import 'support/deadline_plan_fixtures.dart';

void main() {
  test('confirmed blocks appear in the matching account week with provenance',
      () {
    final snapshot = _snapshot(DashboardOrigin.account);

    final merged = DeadlinePlanScheduleMerger(
      toDeviceLocal: (value) => value.toUtc().add(const Duration(hours: 2)),
    ).merge(
      snapshot,
      [_block()],
    );
    final events = merged.scheduleDays.single.events;

    expect(events, hasLength(2));
    expect(events.first.title, 'Existing class');
    final preparation = events.last;
    expect(preparation.title, 'Preparation: Algorithms exam');
    expect(preparation.time, '10:00–10:50');
    expect(preparation.origin, ScheduleEventOrigin.deadlinePreparation);
    expect(preparation.deadlinePlanId, deadlinePlanId);
    expect(preparation.provenanceLabel, contains('MyLifeGraph reservation'));
  });

  test('guest schedule remains local and unchanged', () {
    final snapshot = _snapshot(DashboardOrigin.localDemo);

    final merged = DeadlinePlanScheduleMerger(
      toDeviceLocal: (value) => value.toUtc().add(const Duration(hours: 2)),
    ).merge(
      snapshot,
      [_block()],
    );

    expect(identical(merged, snapshot), isTrue);
    expect(merged.scheduleDays.single.events, hasLength(1));
  });

  test('device timezone conversion chooses the displayed day and time', () {
    final snapshot = DashboardSnapshot(
      origin: DashboardOrigin.account,
      loadedAt: DateTime(2026, 7, 20),
      latestCheckIn: null,
      checkInStreakDays: 0,
      todayPlan: const [],
      scheduleDays: [
        ScheduleDay(
          label: 'Sun',
          dateLabel: 'Jul 19',
          date: DateTime(2026, 7, 19),
          events: const [],
        ),
        ScheduleDay(
          label: 'Mon',
          dateLabel: 'Jul 20',
          date: DateTime(2026, 7, 20),
          events: const [],
        ),
      ],
    );
    final nearMidnight = DeadlinePreparationScheduleBlock(
      id: deadlineBlockId,
      planId: deadlinePlanId,
      planTitle: 'Algorithms exam',
      revision: 1,
      sequence: 1,
      startsAt: DateTime.parse('2026-07-20T01:00:00Z'),
      endsAt: DateTime.parse('2026-07-20T01:50:00Z'),
      plannedMinutes: 50,
    );

    final west = DeadlinePlanScheduleMerger(
      toDeviceLocal: (value) => value.toUtc().subtract(
            const Duration(hours: 10),
          ),
    ).merge(snapshot, [nearMidnight]);
    expect(west.scheduleDays.first.events.single.time, '15:00–15:50');
    expect(west.scheduleDays.last.events, isEmpty);

    final earlierInstant = DeadlinePreparationScheduleBlock(
      id: '44444444-4444-4444-8444-444444444444',
      planId: deadlinePlanId,
      planTitle: 'Algorithms exam',
      revision: 1,
      sequence: 2,
      startsAt: DateTime.parse('2026-07-19T12:00:00Z'),
      endsAt: DateTime.parse('2026-07-19T12:50:00Z'),
      plannedMinutes: 50,
    );
    final east = DeadlinePlanScheduleMerger(
      toDeviceLocal: (value) => value.toUtc().add(const Duration(hours: 14)),
    ).merge(snapshot, [earlierInstant]);
    expect(east.scheduleDays.first.events, isEmpty);
    expect(east.scheduleDays.last.events.single.time, '02:00–02:50');
    expect(
      east.scheduleDays.last.events.single.provenanceLabel,
      contains('Device time'),
    );
  });
}

DeadlinePreparationScheduleBlock _block() => DeadlinePreparationScheduleBlock(
      id: deadlineBlockId,
      planId: deadlinePlanId,
      planTitle: 'Algorithms exam',
      revision: 1,
      sequence: 1,
      startsAt: DateTime.parse('2026-07-20T08:00:00Z'),
      endsAt: DateTime.parse('2026-07-20T08:50:00Z'),
      plannedMinutes: 50,
    );

DashboardSnapshot _snapshot(DashboardOrigin origin) => DashboardSnapshot(
      origin: origin,
      loadedAt: DateTime(2026, 7, 20, 9),
      latestCheckIn: null,
      checkInStreakDays: 0,
      todayPlan: const [],
      scheduleDays: [
        ScheduleDay(
          label: 'Mon',
          dateLabel: 'Jul 20',
          date: DateTime(2026, 7, 20),
          events: const [
            ScheduleEvent(
              title: 'Existing class',
              time: '09:00-09:30',
              sortMinutes: 540,
            ),
          ],
        ),
      ],
    );
