import 'deadline_plan_fixtures.dart';

const multiExamTargetId = deadlinePlanId;
const multiExamOtherId = '20000000-0000-4000-8000-000000000002';
const multiExamBalanceId = '30000000-0000-4000-8000-000000000003';
const multiExamRequestId = '40000000-0000-4000-8000-000000000004';

Map<String, dynamic> multiExamBlock({
  required String id,
  required String startsAt,
  int sequence = 1,
  int plannedMinutes = 30,
  int creditedMinutes = 0,
}) {
  final start = DateTime.parse(startsAt);
  final end = start.add(Duration(minutes: plannedMinutes));
  return {
    'id': id,
    'sequence': sequence,
    'starts_at': start.toUtc().toIso8601String(),
    'ends_at': end.toUtc().toIso8601String(),
    'reserved_ends_at': end.toUtc().toIso8601String(),
    'local_date':
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
    'planned_minutes': plannedMinutes,
    'recovery_minutes': 0,
    'credited_minutes': creditedMinutes,
  };
}

Map<String, dynamic> multiExamItem({
  required String planId,
  required int position,
  required String title,
  required String currentStart,
  required String proposedStart,
  int activeRevision = 1,
  int baseRevision = 1,
}) =>
    {
      'position': position,
      'plan_id': planId,
      'title': title,
      'deadline_at':
          '2026-09-${(10 + position).toString().padLeft(2, '0')}T12:00:00Z',
      'remaining_minutes': 120,
      'active_revision': activeRevision,
      'base_revision': baseRevision,
      'proposed_revision': baseRevision + 1,
      'current_blocks': [
        multiExamBlock(
          id: '${position}1000000-0000-4000-8000-000000000001',
          startsAt: currentStart,
        ),
      ],
      'proposed_blocks': [
        multiExamBlock(
          id: '${position}2000000-0000-4000-8000-000000000002',
          startsAt: proposedStart,
        ),
      ],
      'retained_minutes': 0,
      'added_minutes': 0,
      'shifted_minutes': 30,
      'removed_minutes': 0,
      'retained_block_count': 0,
      'added_block_count': 0,
      'shifted_block_count': 1,
      'removed_block_count': 0,
    };

Map<String, dynamic> multiExamBatch({String status = 'proposed'}) {
  final items = [
    multiExamItem(
      planId: multiExamTargetId,
      position: 1,
      title: 'Algorithms exam',
      currentStart: '2026-08-20T09:00:00Z',
      proposedStart: '2026-08-21T09:00:00Z',
    ),
    multiExamItem(
      planId: multiExamOtherId,
      position: 2,
      title: 'Physics exam',
      currentStart: '2026-08-20T10:00:00Z',
      proposedStart: '2026-08-21T10:00:00Z',
    ),
  ];
  return {
    'id': multiExamBalanceId,
    'status': status,
    'revision': 1,
    'target_plan_id': multiExamTargetId,
    'context_fingerprint':
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'confirmation_fingerprint':
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    'timezone': 'Europe/Berlin',
    'created_at': '2026-08-13T09:00:00Z',
    'updated_at':
        status == 'proposed' ? '2026-08-13T09:00:00Z' : '2026-08-13T10:00:00Z',
    'confirmed_at': status == 'confirmed' ? '2026-08-13T10:00:00Z' : null,
    'cancelled_at': status == 'cancelled' ? '2026-08-13T10:00:00Z' : null,
    'retained_minutes': 0,
    'added_minutes': 0,
    'shifted_minutes': 60,
    'removed_minutes': 0,
    'items': items,
    'child_links': [
      for (final item in items)
        {
          'plan_id': item['plan_id'],
          'proposed_revision': item['proposed_revision'],
          'balance_id': multiExamBalanceId,
          'balance_revision': 1,
          'status': status,
        },
    ],
  };
}

Map<String, dynamic> multiExamBatchEnvelope({String status = 'proposed'}) => {
      'contract_version': 'multi-exam-plan-v1',
      'origin': 'authenticated_backend',
      'balance': multiExamBatch(status: status),
    };

Map<String, dynamic> multiExamFeedEnvelope() {
  final batch = multiExamBatch();
  return {
    'contract_version': 'multi-exam-plan-v1',
    'origin': 'authenticated_backend',
    'balances': [
      {
        'id': batch['id'],
        'status': batch['status'],
        'revision': batch['revision'],
        'target_plan_id': batch['target_plan_id'],
        'affected_plan_count': 2,
        'shifted_minutes': batch['shifted_minutes'],
        'created_at': batch['created_at'],
        'updated_at': batch['updated_at'],
      },
    ],
  };
}

Map<String, dynamic> multiExamProposalEnvelope({
  String outcome = 'multi_exam_batch',
}) =>
    switch (outcome) {
      'no_change' => {
          'contract_version': 'multi-exam-plan-v1',
          'origin': 'authenticated_backend',
          'outcome': 'no_change',
          'target_plan_id': multiExamTargetId,
          'reason': 'already_balanced',
        },
      'single_plan' => {
          'contract_version': 'multi-exam-plan-v1',
          'origin': 'authenticated_backend',
          'outcome': 'single_plan',
          'plan': deadlinePlanEnvelope(status: 'draft'),
        },
      _ => {
          'contract_version': 'multi-exam-plan-v1',
          'origin': 'authenticated_backend',
          'outcome': 'multi_exam_batch',
          'balance': multiExamBatch(),
        },
    };
