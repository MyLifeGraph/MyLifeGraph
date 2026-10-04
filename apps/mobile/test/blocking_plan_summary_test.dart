import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:my_life_graph/features/focus_protection/domain/blocking_plan.dart';
import 'package:my_life_graph/features/focus_protection/presentation/widgets/blocking_plan_summary.dart';

void main() {
  tzdata.initializeTimeZones();
  final monday = DateTime(2026, 10, 5, 16);
  String summary(BlockingPlan p, {DateTime? now, bool access = true}) =>
      blockingPlanTiming(p, now: now ?? monday, usageGranted: access);
  test(
    'budgets distinguish missing access, remaining allowance and exhausted',
    () {
      const plan = BlockingPlan(
        id: 'b',
        name: 'Games',
        budget: 45,
        usedMs: 600001,
      );
      expect(summary(plan), 'All day · 35m left');
      expect(summary(plan, access: false), 'Usage unavailable');
      expect(
        summary(
          const BlockingPlan(
            id: 'b',
            name: 'G',
            budget: 45,
            usedMs: 99999999,
            active: true,
          ),
        ),
        'All day · 0m left',
      );
      expect(
        summary(
          const BlockingPlan(id: 'b', name: 'G', budget: 45, enabled: false),
        ),
        'Paused',
      );
    },
  );
  test('native inactive status and mixed OR rules never claim a false end', () {
    const window = BlockingWindow();
    expect(
      summary(const BlockingPlan(id: 'w', name: 'Study', windows: [window])),
      'Scheduled',
    );
    expect(
      summary(
        const BlockingPlan(
          id: 'w',
          name: 'Study',
          active: true,
          focus: true,
          windows: [window],
        ),
      ),
      'Active',
    );
    expect(
      summary(
        const BlockingPlan(
          id: 'w',
          name: 'Study',
          active: true,
          always: true,
          windows: [window],
        ),
      ),
      'All day',
    );
  });
  test(
    'weekly overlaps merge, exclusive ends and overnight retain device date',
    () {
      const plan = BlockingPlan(
        id: 'w',
        name: 'Study',
        active: true,
        windows: [
          BlockingWindow(days: {1}, start: 900, end: 1020),
          BlockingWindow(days: {1}, start: 990, end: 1080),
        ],
      );
      expect(summary(plan), 'Active until 18:00');
      expect(summary(plan, now: DateTime(2026, 10, 5, 18)), 'Active');
      expect(
        summary(
          const BlockingPlan(
            id: 'w',
            name: 'Night',
            active: true,
            windows: [
              BlockingWindow(days: {1}, start: 1320, end: 420),
            ],
          ),
          now: DateTime(2026, 10, 5, 23),
        ),
        'Active until 6/10 · 07:00',
      );
    },
  );
  test(
    'DST forward and repeated hours follow actual local minute boundaries',
    () {
      final berlin = tz.getLocation('Europe/Berlin');
      const plan = BlockingPlan(
        id: 'w',
        name: 'Night',
        active: true,
        windows: [
          BlockingWindow(days: {7}, start: 60, end: 210),
        ],
      );
      expect(
        summary(plan, now: tz.TZDateTime(berlin, 2026, 3, 29, 1, 30)),
        'Active until 03:30',
      );
      expect(
        summary(plan, now: tz.TZDateTime(berlin, 2026, 10, 25, 1, 30)),
        'Active until 03:30',
      );
    },
  );
  test('timer and expired timer use real supplied instant', () {
    expect(
      summary(
        BlockingPlan(
          id: 't',
          name: 'Timer',
          active: true,
          until: DateTime(2026, 10, 5, 18).millisecondsSinceEpoch,
        ),
      ),
      'Active until 18:00',
    );
    expect(
      summary(const BlockingPlan(id: 't', name: 'Timer', until: 1)),
      'Expired',
    );
  });
}
