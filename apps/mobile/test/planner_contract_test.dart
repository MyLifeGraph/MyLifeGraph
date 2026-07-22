import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/planner/domain/planner.dart';

import 'support/planner_fixtures.dart';

void main() {
  test('maps the exact seven-day Planner overview in product order', () {
    final overview = PlannerOverview.fromJson(plannerOverviewEnvelope());

    expect(overview.days, hasLength(7));
    expect(overview.days.first.items.map((item) => item.kind), [
      'setup_commitment',
      'task_block',
      'habit_slot',
      'manual_commitment',
      'preparation',
      'calendar_event',
    ]);
    expect(overview.needsAttention.single.kind, 'conflict');
    expect(overview.ongoingPreparation.single.remainingMinutes, 150);
    expect(overview.unscheduled.single.title, 'Undated reading');
    expect(overview.history.single.title, 'Archived walk');
  });

  test('maps a strict staged Task preview with split blocks', () {
    final plan = plannerActionPlanFromResponse(plannerActionPlanEnvelope());

    expect(plan.status, 'draft');
    expect(plan.pendingRevision?.targetKind, 'task');
    expect(plan.pendingRevision?.targetOperation, 'create');
    expect(plan.pendingRevision?.plannedMinutes, 60);
    expect(
      plan.pendingRevision?.taskBlocks.map((block) => block.plannedMinutes),
      [30, 30],
    );
  });

  test('rejects unknown fields, nonconsecutive days, and bad minute sums', () {
    final unknown = plannerOverviewEnvelope()..['unexpected'] = true;
    expect(
      () => PlannerOverview.fromJson(unknown),
      throwsA(isA<PlannerContractException>()),
    );

    final days = plannerOverviewEnvelope();
    final rawDays = List<dynamic>.from(days['days'] as List);
    rawDays[3] = {
      ...Map<String, dynamic>.from(rawDays[3] as Map),
      'local_date': '2026-07-30',
    };
    days['days'] = rawDays;
    expect(
      () => PlannerOverview.fromJson(days),
      throwsA(isA<PlannerContractException>()),
    );

    final badPlan = plannerActionPlanEnvelope();
    final plan = Map<String, dynamic>.from(badPlan['plan'] as Map);
    final revision = Map<String, dynamic>.from(plan['pending_revision'] as Map);
    revision['planned_minutes'] = 55;
    plan['pending_revision'] = revision;
    badPlan['plan'] = plan;
    expect(
      () => plannerActionPlanFromResponse(badPlan),
      throwsA(isA<PlannerContractException>()),
    );
  });

  test('drafts preserve explicit missing Task scheduling inputs as null', () {
    const draft = PlannerTaskDraft(
      title: 'Undated Task',
      description: null,
      priority: 'medium',
      estimatedMinutes: null,
      deadlineAt: null,
      preferredSessionMinutes: null,
    );

    final body = draft.proposalJson(
      requestId: '10000000-0000-4000-8000-000000000001',
      planId: '20000000-0000-4000-8000-000000000001',
      newTargetId: '30000000-0000-4000-8000-000000000001',
      baseRevision: 0,
      planningStartOn: '2026-07-21',
    );
    final target = body['target'] as Map<String, dynamic>;

    expect(target['estimated_minutes'], isNull);
    expect(target['deadline_at'], isNull);
    expect(target['preferred_session_minutes'], isNull);
    expect(target['operation'], 'create');
  });
}
