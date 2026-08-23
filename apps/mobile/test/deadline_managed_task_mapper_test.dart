import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/dashboard/data/datasources/dashboard_supabase_data_source.dart';

import 'support/deadline_plan_fixtures.dart';

void main() {
  test('retains exact managed preparation task provenance', () {
    final snapshot = const DashboardSnapshotMapper().map(
      dailyLogs: const [],
      taskRows: [
        {
          'id': deadlinePlanId,
          'title': 'Prepare for Algorithms exam',
          'priority': 'high',
          'status': 'todo',
          'source': 'deadline-plan-v1',
          'metadata': {
            'contract_version': 'deadline-plan-v1',
            'managed_by': 'deadline-planner',
            'plan_id': deadlinePlanId,
          },
        },
      ],
      scheduleRows: const [],
      loadedAt: DateTime(2026, 7, 20),
    );

    final task = snapshot.todayPlan.single;
    expect(task.isDeadlinePlanManaged, isTrue);
    expect(task.deadlinePlanId, deadlinePlanId);
  });

  test('deadline source fails closed to planner routing', () {
    final snapshot = const DashboardSnapshotMapper().map(
      dailyLogs: const [],
      taskRows: [
        {
          'id': deadlinePlanId,
          'title': 'Ordinary task',
          'priority': 'normal',
          'status': 'todo',
          'source': 'deadline-plan-v1',
          'metadata': {
            'contract_version': 'deadline-plan-v1',
            'deadline_plan_id': deadlinePlanId,
            'managed': false,
          },
        },
      ],
      scheduleRows: const [],
      loadedAt: DateTime(2026, 7, 20),
    );

    expect(snapshot.todayPlan.single.isDeadlinePlanManaged, isTrue);
    expect(snapshot.todayPlan.single.deadlinePlanId, deadlinePlanId);
  });
}
