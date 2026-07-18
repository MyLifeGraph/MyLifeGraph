import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_plan.dart';

import 'support/deadline_plan_fixtures.dart';

void main() {
  test('parses exact active detail and preserves honest progress fields', () {
    final plan = DeadlinePlanResponse.fromJson(deadlinePlanEnvelope()).plan;

    expect(plan.id, deadlinePlanId);
    expect(plan.status, DeadlinePlanStatus.active);
    expect(plan.activeRevision!.blocks.single.plannedMinutes, 50);
    expect(plan.progress.creditedPriorMinutes, 30);
    expect(plan.progress.trackedFocusMinutes, 25);
    expect(plan.progress.remainingMinutes, 245);
  });

  test('proposal payload has exact keys and permits explicit busy periods', () {
    final draft = DeadlinePlanProposalDraft(
      planId: deadlinePlanId,
      baseRevision: 0,
      kind: DeadlinePlanKind.exam,
      title: ' Algorithms exam ',
      deadlineAt: DateTime.parse('2026-07-25T15:00:00Z'),
      estimatedTotalMinutes: 300,
      creditedPriorMinutes: 0,
      preferredSessionMinutes: 50,
      maxDailyMinutes: 120,
      planningStartOn: '2026-07-18',
      bufferDays: 1,
      sourceKind: DeadlinePlanSourceKind.manual,
      sourceCalendarEventId: null,
      sourceCalendarEventFingerprint: null,
      useCalendarAvailability: true,
    );

    expect(draft.toJson(requestId: deadlineRequestId), {
      'request_id': deadlineRequestId,
      'plan_id': deadlinePlanId,
      'base_revision': 0,
      'kind': 'exam',
      'title': 'Algorithms exam',
      'deadline_at': '2026-07-25T15:00:00.000Z',
      'estimated_total_minutes': 300,
      'credited_prior_minutes': 0,
      'preferred_session_minutes': 50,
      'max_daily_minutes': 120,
      'planning_start_on': '2026-07-18',
      'buffer_days': 1,
      'source_kind': 'manual',
      'use_calendar_availability': true,
    });
  });

  test('rejects prior credit equal to estimate', () {
    final json = deadlinePlanEnvelope();
    final revision = json['active_revision'] as Map<String, dynamic>;
    revision['credited_prior_minutes'] = 300;
    revision['remaining_minutes_at_proposal'] = 0;
    revision['planned_minutes'] = 0;
    revision['unscheduled_minutes'] = 0;
    revision['blocks'] = <Map<String, dynamic>>[];

    expect(
      () => DeadlinePlanResponse.fromJson(json),
      throwsA(isA<DeadlinePlanContractException>()),
    );
  });

  test('feed rejects more than fifty plans', () {
    final detail = deadlinePlanDetail();
    final json = deadlinePlanFeed(
      plans: List.generate(51, (_) => Map<String, dynamic>.from(detail)),
    );

    expect(
      () => DeadlinePlanFeed.fromJson(json),
      throwsA(isA<DeadlinePlanContractException>()),
    );
  });

  test('revision rejects duplicate or non-contiguous block sequences', () {
    final duplicate = deadlineRevision(
      plannedMinutes: 100,
      unscheduledMinutes: 145,
      blocks: [
        deadlineBlock(),
        deadlineBlock(
          id: '44444444-4444-4444-8444-444444444444',
        ),
      ],
    );
    final gap = deadlineRevision(
      plannedMinutes: 100,
      unscheduledMinutes: 145,
      blocks: [
        deadlineBlock(),
        deadlineBlock(
          id: '44444444-4444-4444-8444-444444444444',
          sequence: 3,
        ),
      ],
    );

    expect(
      () => DeadlinePlanRevision.fromJson(duplicate),
      throwsA(isA<DeadlinePlanContractException>()),
    );
    expect(
      () => DeadlinePlanRevision.fromJson(gap),
      throwsA(isA<DeadlinePlanContractException>()),
    );
  });

  test('revision rejects a skipped revision and an inexact block duration', () {
    final skipped = deadlineRevision(revision: 3, baseRevision: 1);
    final wrongDuration = deadlineRevision(
      plannedMinutes: 40,
      unscheduledMinutes: 205,
      blocks: [deadlineBlock(plannedMinutes: 40)],
    );

    expect(
      () => DeadlinePlanRevision.fromJson(skipped),
      throwsA(isA<DeadlinePlanContractException>()),
    );
    expect(
      () => DeadlinePlanRevision.fromJson(wrongDuration),
      throwsA(isA<DeadlinePlanContractException>()),
    );
  });

  test('completed plan requires its active revision', () {
    final json = deadlinePlanEnvelope(status: 'completed')
      ..remove('active_revision');

    expect(
      () => DeadlinePlanResponse.fromJson(json),
      throwsA(isA<DeadlinePlanContractException>()),
    );
  });

  test('terminal plan rejects a pending revision', () {
    final json = deadlinePlanEnvelope(status: 'completed', pending: true);

    expect(
      () => DeadlinePlanResponse.fromJson(json),
      throwsA(isA<DeadlinePlanContractException>()),
    );
  });

  test('progress stays authoritative to active revision while replan is staged',
      () {
    final valid = DeadlinePlanResponse.fromJson(
      deadlinePlanEnvelope(pending: true),
    ).plan;
    expect(valid.progress.estimatedTotalMinutes, 300);
    expect(valid.pendingRevision!.estimatedTotalMinutes, 420);

    final mismatched = deadlinePlanEnvelope(pending: true);
    final progress = mismatched['progress'] as Map<String, dynamic>;
    progress
      ..['estimated_total_minutes'] = 420
      ..['credited_prior_minutes'] = 60
      ..['accounted_minutes'] = 85
      ..['remaining_minutes'] = 335;

    expect(
      () => DeadlinePlanResponse.fromJson(mismatched),
      throwsA(isA<DeadlinePlanContractException>()),
    );
  });

  test('cancelled unconfirmed draft has no task or revision', () {
    final detail = deadlinePlanDetail(status: 'draft');
    final identity = detail['plan'] as Map<String, dynamic>;
    identity['status'] = 'cancelled';
    identity['cancelled_at'] = '2026-07-18T12:00:00Z';
    detail.remove('pending_revision');
    final plan = DeadlinePlanResponse.fromJson({
      'contract_version': 'deadline-plan-v1',
      'origin': 'authenticated_backend',
      ...detail,
    }).plan;

    expect(plan.status, DeadlinePlanStatus.cancelled);
    expect(plan.currentRevision, 0);
    expect(plan.taskId, isNull);
    expect(plan.displayedRevision, isNull);
  });

  test('rejects mismatched revision identity and unsupported energy window',
      () {
    final mismatched = deadlinePlanEnvelope();
    (mismatched['active_revision'] as Map<String, dynamic>)['plan_id'] =
        '55555555-5555-4555-8555-555555555555';
    expect(
      () => DeadlinePlanResponse.fromJson(mismatched),
      throwsA(isA<DeadlinePlanContractException>()),
    );

    final unsupported = deadlinePlanEnvelope();
    (unsupported['active_revision']
        as Map<String, dynamic>)['best_energy_window'] = 'lunch';
    expect(
      () => DeadlinePlanResponse.fromJson(unsupported),
      throwsA(isA<DeadlinePlanContractException>()),
    );
  });
}
