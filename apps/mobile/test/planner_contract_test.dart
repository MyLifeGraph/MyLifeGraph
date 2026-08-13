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
    expect(overview.needsAttention.single.conflictSource, 'fixed_commitment');
    expect(overview.ongoingPreparation.single.remainingMinutes, 150);
    expect(overview.habits, hasLength(2));
    expect(overview.habits.first.ownership, 'setup');
    expect(overview.taskTargets.single.title, 'Undated reading');
    expect(overview.unscheduledTasks.single.title, 'Undated reading');
    expect(overview.history.single.title, 'Archived walk');
  });

  test('keeps released Tasks truthful even when scheduling inputs are absent',
      () {
    final envelope = plannerOverviewEnvelope();
    final tasks = List<dynamic>.from(envelope['unscheduled_tasks'] as List);
    tasks[0] = {
      ...Map<String, dynamic>.from(tasks[0] as Map),
      'reason': 'released',
    };
    envelope['unscheduled_tasks'] = tasks;
    final targetId = tasks[0]['id'] as String;
    envelope['action_plans'] = [_releasedTaskPlanForTarget(targetId)];

    expect(
      PlannerOverview.fromJson(envelope).unscheduledTasks.single.reason,
      'released',
    );

    tasks[0] = {
      ...Map<String, dynamic>.from(tasks[0] as Map),
      'reason': 'no_time_available',
    };
    expect(
      () => PlannerOverview.fromJson(envelope),
      throwsA(isA<PlannerContractException>()),
    );
  });

  test('maps a strict staged Task preview with split blocks', () {
    final plan = plannerActionPlanFromResponse(plannerActionPlanEnvelope());

    expect(plan.status, 'draft');
    expect(plan.pendingRevision?.targetKind, 'task');
    expect(plan.pendingRevision?.targetOperation, 'create');
    expect(plan.pendingRevision?.plannedMinutes, 60);
    expect(
      plan.pendingRevision?.targetTaskDraft?.title,
      'Prepare presentation',
    );
    expect(plan.pendingRevision?.targetTaskDraft?.priority, 'high');
    expect(plan.pendingRevision?.targetTaskDraft?.targetId, isNull);
    expect(plan.pendingRevision?.targetTaskDraft?.expectedUpdatedAt, isNull);
    expect(plan.pendingRevision?.targetHabitDraft, isNull);
    expect(
      plan.pendingRevision?.taskBlocks.map((block) => block.plannedMinutes),
      [30, 30],
    );
  });

  test('enforces SQL revision bounds and active child states', () {
    for (final fieldAndValue in const [
      ('revision', 501),
      ('base_revision', 500),
    ]) {
      final envelope = plannerActionPlanEnvelope();
      final plan = Map<String, dynamic>.from(envelope['plan'] as Map);
      final revision = Map<String, dynamic>.from(
        plan['pending_revision'] as Map,
      );
      revision[fieldAndValue.$1] = fieldAndValue.$2;
      plan['pending_revision'] = revision;
      envelope['plan'] = plan;

      expect(
        () => plannerActionPlanFromResponse(envelope),
        throwsA(isA<PlannerContractException>()),
      );
    }

    final wrongRevisionState = plannerActionPlanEnvelope(state: 'active');
    final wrongRevisionPlan = Map<String, dynamic>.from(
      wrongRevisionState['plan'] as Map,
    );
    final proposedRevision = Map<String, dynamic>.from(
      wrongRevisionPlan['active_revision'] as Map,
    )
      ..['state'] = 'proposed'
      ..['activated_at'] = null;
    proposedRevision['task_blocks'] = [
      for (final raw in proposedRevision['task_blocks'] as List<dynamic>)
        {...Map<String, dynamic>.from(raw as Map), 'state': 'proposed'},
    ];
    wrongRevisionPlan['active_revision'] = proposedRevision;
    wrongRevisionState['plan'] = wrongRevisionPlan;
    expect(
      () => plannerActionPlanFromResponse(wrongRevisionState),
      throwsA(isA<PlannerContractException>()),
    );

    final wrongTaskChild = plannerActionPlanEnvelope(state: 'active');
    final wrongTaskPlan =
        Map<String, dynamic>.from(wrongTaskChild['plan'] as Map);
    final activeTaskRevision = Map<String, dynamic>.from(
      wrongTaskPlan['active_revision'] as Map,
    );
    final taskBlocks = List<dynamic>.from(
      activeTaskRevision['task_blocks'] as List,
    );
    taskBlocks[0] = {
      ...Map<String, dynamic>.from(taskBlocks[0] as Map),
      'state': 'proposed',
    };
    activeTaskRevision['task_blocks'] = taskBlocks;
    wrongTaskPlan['active_revision'] = activeTaskRevision;
    wrongTaskChild['plan'] = wrongTaskPlan;
    expect(
      () => plannerActionPlanFromResponse(wrongTaskChild),
      throwsA(isA<PlannerContractException>()),
    );

    final wrongHabitChild = plannerOverviewEnvelope();
    final habit = Map<String, dynamic>.from(
      (wrongHabitChild['habits'] as List<dynamic>).first as Map,
    );
    final habitPlan = _pendingHabitPlanForTarget(
      habit['id'] as String,
      operation: 'update',
      expectedUpdatedAt: habit['expected_updated_at'] as String,
    );
    final activeHabitRevision = Map<String, dynamic>.from(
      habitPlan['pending_revision'] as Map,
    )
      ..['state'] = 'active'
      ..['planned_minutes'] = 20
      ..['activated_at'] = '2026-07-21T07:45:00Z'
      ..['habit_slots'] = <dynamic>[
        {
          'id': 'c0000000-0000-4000-8000-000000000099',
          'weekday': 1,
          'starts_at': '08:00:00',
          'ends_at': '08:20:00',
          'duration_minutes': 20,
          'state': 'proposed',
        },
      ];
    habitPlan
      ..['status'] = 'active'
      ..['current_revision'] = 1
      ..['active_revision'] = activeHabitRevision
      ..['pending_revision'] = null;
    habit
      ..['planning_status'] = 'scheduled'
      ..['plan_id'] = habitPlan['id']
      ..['has_pending_preview'] = false;
    (wrongHabitChild['habits'] as List<dynamic>)[0] = habit;
    wrongHabitChild['action_plans'] = [habitPlan];
    expect(
      () => PlannerOverview.fromJson(wrongHabitChild),
      throwsA(isA<PlannerContractException>()),
    );
  });

  test('rejects a pending revision whose target identity changed', () {
    final envelope = plannerActionPlanEnvelope();
    final plan = Map<String, dynamic>.from(envelope['plan'] as Map);
    final revision = Map<String, dynamic>.from(plan['pending_revision'] as Map);
    revision['target'] = {
      ...Map<String, dynamic>.from(revision['target'] as Map),
      'target_id': 'b0000000-0000-4000-8000-000000000099',
    };
    plan['pending_revision'] = revision;
    envelope['plan'] = plan;

    expect(
      () => plannerActionPlanFromResponse(envelope),
      throwsA(isA<PlannerContractException>()),
    );
  });

  test('rejects a pending revision whose target kind changed', () {
    final envelope = plannerActionPlanEnvelope();
    final plan = Map<String, dynamic>.from(envelope['plan'] as Map);
    final revision = Map<String, dynamic>.from(plan['pending_revision'] as Map);
    revision['target'] = {
      ...Map<String, dynamic>.from(revision['target'] as Map),
      'kind': 'habit',
    };
    plan['pending_revision'] = revision;
    envelope['plan'] = plan;

    expect(
      () => plannerActionPlanFromResponse(envelope),
      throwsA(isA<PlannerContractException>()),
    );
  });

  test('rejects corrupt Overview relations for Tasks and Habits', () {
    final noTime = plannerOverviewEnvelope();
    final tasks = List<dynamic>.from(noTime['unscheduled_tasks'] as List);
    tasks[0] = {
      ...Map<String, dynamic>.from(tasks[0] as Map),
      'reason': 'no_time_available',
      'estimated_minutes': 60,
      'deadline_at': '2026-07-24T12:00:00Z',
      'preferred_session_minutes': 30,
    };
    noTime['unscheduled_tasks'] = tasks;
    expect(
      () => PlannerOverview.fromJson(noTime),
      throwsA(isA<PlannerContractException>()),
    );

    final scheduledHabit = plannerOverviewEnvelope();
    final habits = List<dynamic>.from(scheduledHabit['habits'] as List);
    habits[0] = {
      ...Map<String, dynamic>.from(habits[0] as Map),
      'planning_status': 'scheduled',
      'plan_id': 'd0000000-0000-4000-8000-000000000001',
    };
    scheduledHabit['habits'] = habits;
    expect(
      () => PlannerOverview.fromJson(scheduledHabit),
      throwsA(isA<PlannerContractException>()),
    );
  });

  test('requires every unreserved open Task exactly under Unscheduled Tasks',
      () {
    final omitted = plannerOverviewEnvelope()
      ..['unscheduled_tasks'] = <dynamic>[];

    expect(
      () => PlannerOverview.fromJson(omitted),
      throwsA(isA<PlannerContractException>()),
    );

    final wrongReason = plannerOverviewEnvelope();
    final tasks = List<dynamic>.from(
      wrongReason['unscheduled_tasks'] as List<dynamic>,
    );
    tasks[0] = {
      ...Map<String, dynamic>.from(tasks.single as Map),
      'reason': 'released',
    };
    wrongReason['unscheduled_tasks'] = tasks;

    expect(
      () => PlannerOverview.fromJson(wrongReason),
      throwsA(isA<PlannerContractException>()),
    );
  });

  test('rejects a persisted Task plan without current or history snapshot', () {
    final envelope = plannerOverviewEnvelope();
    final target = Map<String, dynamic>.from(
      (envelope['task_targets'] as List<dynamic>).single as Map,
    );
    envelope
      ..['task_targets'] = <dynamic>[]
      ..['unscheduled_tasks'] = <dynamic>[]
      ..['action_plans'] = [
        _pendingTaskPlanForTarget(
          target['id'] as String,
          operation: 'update',
          expectedUpdatedAt: target['expected_updated_at'] as String,
        ),
      ];

    expect(
      () => PlannerOverview.fromJson(envelope),
      throwsA(isA<PlannerContractException>()),
    );
  });

  test('rejects an active Task plan bound only to Task history', () {
    final envelope = plannerOverviewEnvelope();
    const targetId = '80000000-0000-4000-8000-000000000001';
    final plan = plannerActionPlan(state: 'active');
    final active = plan['active_revision'] as Map<String, dynamic>;
    final target = active['target'] as Map<String, dynamic>;
    plan
      ..['target_id'] = targetId
      ..['status'] = 'active';
    target['target_id'] = targetId;
    envelope
      ..['task_targets'] = <dynamic>[]
      ..['unscheduled_tasks'] = <dynamic>[]
      ..['history'] = <dynamic>[
        {'id': targetId, 'kind': 'task', 'title': 'Historical Task'},
      ]
      ..['action_plans'] = <dynamic>[plan];

    expect(
      () => PlannerOverview.fromJson(envelope),
      throwsA(isA<PlannerContractException>()),
    );
  });

  test('keeps a pending Task create outside persisted target projections', () {
    final envelope = plannerOverviewEnvelope()
      ..['task_targets'] = <dynamic>[]
      ..['unscheduled_tasks'] = <dynamic>[]
      ..['action_plans'] = [plannerActionPlan()];

    final overview = PlannerOverview.fromJson(envelope);

    expect(
      overview.actionPlans.single.pendingRevision?.targetOperation,
      'create',
    );
    expect(overview.taskTargets, isEmpty);
    expect(overview.unscheduledTasks, isEmpty);
  });

  test('allows exact bounded cancelled tombstones without target snapshots',
      () {
    for (final kind in const ['task', 'habit']) {
      final targetId = kind == 'task'
          ? '80000000-0000-4000-8000-000000000081'
          : '80000000-0000-4000-8000-000000000082';
      final tombstone = <String, dynamic>{
        'id': kind == 'task'
            ? 'd0000000-0000-4000-8000-000000000081'
            : 'd0000000-0000-4000-8000-000000000082',
        'target_kind': kind,
        'target_id': targetId,
        'status': 'cancelled',
        'current_revision': 0,
        'latest_revision': 1,
        'needs_attention': false,
        'attention_reasons': <dynamic>[],
        'active_revision': null,
        'pending_revision': null,
      };
      for (final latestRevision in const [1, 2, 500]) {
        final accepted = plannerOverviewEnvelope()
          ..['action_plans'] = [
            {...tombstone, 'latest_revision': latestRevision},
          ];

        expect(
          PlannerOverview.fromJson(accepted).actionPlans.single.targetKind,
          kind,
        );
      }

      final malformed = plannerOverviewEnvelope()
        ..['action_plans'] = [
          {...tombstone, 'status': 'unscheduled'},
        ];
      expect(
        () => PlannerOverview.fromJson(malformed),
        throwsA(isA<PlannerContractException>()),
        reason: kind,
      );

      final outOfBounds = plannerOverviewEnvelope()
        ..['action_plans'] = [
          {...tombstone, 'latest_revision': 501},
        ];
      expect(
        () => PlannerOverview.fromJson(outOfBounds),
        throwsA(isA<PlannerContractException>()),
        reason: kind,
      );
    }
  });

  test('enforces SQL-shaped create, cancelled, and history lifecycles', () {
    for (final kind in const ['task', 'habit']) {
      final targetId = kind == 'task'
          ? '80000000-0000-4000-8000-000000000091'
          : '80000000-0000-4000-8000-000000000092';
      final pending = kind == 'task'
          ? _pendingTaskPlanForTarget(
              targetId,
              operation: 'create',
              expectedUpdatedAt: null,
            )
          : _pendingHabitPlanForTarget(
              targetId,
              operation: 'create',
              expectedUpdatedAt: null,
            );
      for (final malformed in <Map<String, dynamic>>[
        {...pending, 'status': 'cancelled'},
        {
          ...pending,
          'status': 'cancelled',
          'pending_revision': null,
          'needs_attention': true,
          'attention_reasons': ['target_changed'],
        },
        {...pending, 'status': 'unscheduled'},
      ]) {
        final envelope = plannerOverviewEnvelope()
          ..['action_plans'] = [malformed];
        expect(
          () => PlannerOverview.fromJson(envelope),
          throwsA(isA<PlannerContractException>()),
          reason: '$kind ${malformed['status']}',
        );
      }

      final formerlyActive = <String, dynamic>{
        'id': kind == 'task'
            ? 'd0000000-0000-4000-8000-000000000091'
            : 'd0000000-0000-4000-8000-000000000092',
        'target_kind': kind,
        'target_id': targetId,
        'status': 'cancelled',
        'current_revision': 0,
        'latest_revision': 2,
        'needs_attention': false,
        'attention_reasons': <dynamic>[],
        'active_revision': null,
        'pending_revision': null,
      };
      final accepted = plannerOverviewEnvelope()
        ..['task_targets'] = <dynamic>[]
        ..['unscheduled_tasks'] = <dynamic>[]
        ..['habits'] = <dynamic>[]
        ..['history'] = <dynamic>[
          {'id': targetId, 'kind': kind, 'title': 'Former target'},
        ]
        ..['action_plans'] = [formerlyActive];
      expect(
        PlannerOverview.fromJson(accepted).history.single.kind,
        kind,
      );
    }
  });

  test('rejects an active Habit plan bound only to Habit history', () {
    final envelope = plannerOverviewEnvelope();
    const targetId = '80000000-0000-4000-8000-000000000093';
    final plan = _pendingHabitPlanForTarget(
      targetId,
      operation: 'update',
      expectedUpdatedAt: '2026-07-20T08:00:00Z',
    );
    final active = Map<String, dynamic>.from(
      plan['pending_revision'] as Map,
    )
      ..['state'] = 'active'
      ..['activated_at'] = '2026-07-21T07:45:00Z';
    plan
      ..['status'] = 'unscheduled'
      ..['current_revision'] = 1
      ..['active_revision'] = active
      ..['pending_revision'] = null;
    envelope
      ..['habits'] = <dynamic>[]
      ..['history'] = <dynamic>[
        {'id': targetId, 'kind': 'habit', 'title': 'Archived Habit'},
      ]
      ..['action_plans'] = [plan];

    expect(
      () => PlannerOverview.fromJson(envelope),
      throwsA(isA<PlannerContractException>()),
    );
  });

  test('rejects create previews bound to persisted Overview targets', () {
    for (final projection in const ['habit', 'unscheduled_task', 'history']) {
      final envelope = plannerOverviewEnvelope();
      late final Map<String, dynamic> plan;
      if (projection == 'habit') {
        final habit = Map<String, dynamic>.from(
          (envelope['habits'] as List<dynamic>).first as Map,
        );
        plan = _pendingHabitPlanForTarget(
          habit['id'] as String,
          operation: 'create',
          expectedUpdatedAt: null,
        );
        envelope['habits'] = [
          {
            ...habit,
            'plan_id': plan['id'],
            'has_pending_preview': true,
          },
          ...(envelope['habits'] as List<dynamic>).skip(1),
        ];
      } else {
        final targetId = projection == 'history'
            ? ((envelope['history'] as List<dynamic>).first
                as Map<String, dynamic>)['id'] as String
            : ((envelope['unscheduled_tasks'] as List<dynamic>).first
                as Map<String, dynamic>)['id'] as String;
        plan = _pendingTaskPlanForTarget(
          targetId,
          operation: 'create',
          expectedUpdatedAt: null,
        );
        if (projection == 'history') {
          final history = Map<String, dynamic>.from(
            (envelope['history'] as List<dynamic>).first as Map,
          );
          envelope['history'] = [
            {...history, 'kind': 'task'},
          ];
        }
      }
      envelope['action_plans'] = [plan];

      expect(
        () => PlannerOverview.fromJson(envelope),
        throwsA(isA<PlannerContractException>()),
        reason: projection,
      );
    }
  });

  test('allows a persisted Habit with its matching pending update', () {
    final envelope = plannerOverviewEnvelope();
    final habits = List<dynamic>.from(envelope['habits'] as List);
    final habit = Map<String, dynamic>.from(habits.first as Map);
    final plan = _pendingHabitPlanForTarget(
      habit['id'] as String,
      operation: 'update',
      expectedUpdatedAt: habit['expected_updated_at'] as String,
    );
    habits[0] = {
      ...habit,
      'plan_id': plan['id'],
      'has_pending_preview': true,
    };
    envelope['habits'] = habits;
    envelope['action_plans'] = [plan];

    final overview = PlannerOverview.fromJson(envelope);

    expect(overview.habits.first.hasPendingPreview, isTrue);
    expect(
      overview.actionPlans.single.pendingRevision?.targetOperation,
      'update',
    );
    expect(
      overview.actionPlans.single.pendingRevision?.targetHabitDraft?.targetId,
      habit['id'],
    );
  });

  test('rejects persisted identities repeated in same-kind history', () {
    for (final kind in const ['task', 'habit']) {
      final envelope = plannerOverviewEnvelope();
      final targetId = kind == 'task'
          ? ((envelope['unscheduled_tasks'] as List<dynamic>).first
              as Map<String, dynamic>)['id'] as String
          : ((envelope['habits'] as List<dynamic>).first
              as Map<String, dynamic>)['id'] as String;
      envelope['history'] = [
        {'id': targetId, 'kind': kind, 'title': 'Archived target'},
      ];

      expect(
        () => PlannerOverview.fromJson(envelope),
        throwsA(isA<PlannerContractException>()),
        reason: kind,
      );
    }
  });

  test('allows Task and Habit persisted projections to share one UUID', () {
    final envelope = plannerOverviewEnvelope();
    final habits = envelope['habits'] as List<dynamic>;
    final sharedId = (habits.first as Map<String, dynamic>)['id'] as String;
    final tasks = List<dynamic>.from(envelope['unscheduled_tasks'] as List);
    final targets = List<dynamic>.from(envelope['task_targets'] as List);
    tasks[0] = {
      ...Map<String, dynamic>.from(tasks.first as Map),
      'id': sharedId,
    };
    targets[0] = {
      ...Map<String, dynamic>.from(targets.first as Map),
      'id': sharedId,
    };
    envelope['unscheduled_tasks'] = tasks;
    envelope['task_targets'] = targets;

    final overview = PlannerOverview.fromJson(envelope);

    expect(overview.unscheduledTasks.single.id, overview.habits.first.id);
  });

  test('keeps scheduled Task target facts outside Unscheduled Tasks', () {
    final envelope = plannerOverviewEnvelope();
    envelope['unscheduled_tasks'] = <dynamic>[];
    final target = Map<String, dynamic>.from(
      (envelope['task_targets'] as List<dynamic>).single as Map,
    );
    target
      ..['title'] = 'Current scheduled Task'
      ..['description'] = 'Fresh description'
      ..['priority'] = 'critical'
      ..['estimated_minutes'] = 90
      ..['deadline_at'] = '2026-07-25T12:00:00Z'
      ..['preferred_session_minutes'] = 30;
    envelope['task_targets'] = [target];
    envelope['action_plans'] = [
      _activeTaskPlanForTarget(
        target['id'] as String,
        expectedUpdatedAt: target['expected_updated_at'] as String,
      ),
    ];

    final overview = PlannerOverview.fromJson(envelope);

    expect(overview.unscheduledTasks, isEmpty);
    expect(overview.taskTargets.single.title, 'Current scheduled Task');
    expect(overview.taskTargets.single.description, 'Fresh description');
    expect(overview.taskTargets.single.priority, 'critical');
  });

  test('maps source-specific invalid DST recurrence attention copy', () {
    final envelope = plannerOverviewEnvelope();
    envelope['needs_attention'] = [
      {
        'id': 'plan:local-time-invalid:1',
        'kind': 'stale_preview',
        'target': 'plan',
        'title': 'Review notes',
        'detail':
            'Saved Habit: 2026-10-25 02:30 (ambiguous); Weekly Setup: 2026-10-25 02:30 (ambiguous) cannot be resolved in Europe/Berlin. Only those occurrences were omitted; nothing moved automatically.',
        'plan_id': '10000000-0000-4000-8000-000000000001',
        'unplaced_minutes': 0,
        'conflict_source': null,
      },
    ];

    final attention = PlannerOverview.fromJson(envelope).needsAttention.single;

    expect(attention.kind, 'stale_preview');
    expect(attention.conflictSource, isNull);
    expect(attention.detail, contains('Only those occurrences were omitted'));
    expect(attention.detail, contains('nothing moved automatically'));
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

Map<String, dynamic> _pendingTaskPlanForTarget(
  String targetId, {
  required String operation,
  required String? expectedUpdatedAt,
}) {
  final plan = Map<String, dynamic>.from(plannerActionPlan());
  final revision = Map<String, dynamic>.from(
    plan['pending_revision'] as Map,
  );
  final target = Map<String, dynamic>.from(revision['target'] as Map);
  target
    ..['operation'] = operation
    ..['target_id'] = targetId
    ..['expected_updated_at'] = expectedUpdatedAt;
  revision['target'] = target;
  plan
    ..['target_kind'] = 'task'
    ..['target_id'] = targetId
    ..['pending_revision'] = revision;
  return plan;
}

Map<String, dynamic> _pendingHabitPlanForTarget(
  String targetId, {
  required String operation,
  required String? expectedUpdatedAt,
}) {
  final plan = Map<String, dynamic>.from(plannerActionPlan());
  final revision = Map<String, dynamic>.from(
    plan['pending_revision'] as Map,
  );
  revision
    ..['target'] = {
      'kind': 'habit',
      'operation': operation,
      'target_id': targetId,
      'expected_updated_at': expectedUpdatedAt,
      'title': 'Read',
      'description': 'Keep up with the course reader.',
      'cadence': {
        'kind': 'daily',
        'scheduled_weekdays': <dynamic>[],
        'weekly_target': 1,
      },
      'duration_minutes': 20,
    }
    ..['planned_minutes'] = 0
    ..['unscheduled_minutes'] = 0
    ..['task_blocks'] = <dynamic>[]
    ..['habit_slots'] = <dynamic>[];
  plan
    ..['target_kind'] = 'habit'
    ..['target_id'] = targetId
    ..['pending_revision'] = revision;
  return plan;
}

Map<String, dynamic> _activeTaskPlanForTarget(
  String targetId, {
  required String expectedUpdatedAt,
}) {
  final plan = Map<String, dynamic>.from(plannerActionPlan(state: 'active'));
  final revision = Map<String, dynamic>.from(plan['active_revision'] as Map);
  final target = Map<String, dynamic>.from(revision['target'] as Map);
  target
    ..['operation'] = 'update'
    ..['target_id'] = targetId
    ..['expected_updated_at'] = expectedUpdatedAt;
  revision['target'] = target;
  plan
    ..['target_id'] = targetId
    ..['active_revision'] = revision;
  return plan;
}

Map<String, dynamic> _releasedTaskPlanForTarget(String targetId) => {
      'id': 'd0000000-0000-4000-8000-000000000001',
      'target_kind': 'task',
      'target_id': targetId,
      'status': 'unscheduled',
      'current_revision': 0,
      'latest_revision': 1,
      'needs_attention': true,
      'attention_reasons': ['target_released'],
      'active_revision': null,
      'pending_revision': null,
    };
