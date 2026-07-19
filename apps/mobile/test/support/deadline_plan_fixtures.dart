const deadlinePlanId = '11111111-1111-4111-8111-111111111111';
const deadlineBlockId = '22222222-2222-4222-8222-222222222222';
const deadlineRequestId = '33333333-3333-4333-8333-333333333333';
const deadlineFingerprint =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> preparationWorkloadEnvelope({
  int? budget = 120,
  int firstDayReservedMinutes = 50,
}) =>
    {
      'contract_version': 'preparation-workload-v1',
      'origin': 'authenticated_backend',
      'generated_at': '2026-07-20T08:00:00Z',
      'timezone': 'Europe/Berlin',
      'daily_preparation_budget_minutes': budget,
      'days': [
        for (var offset = 0; offset < 7; offset++)
          {
            'local_date': DateTime(2026, 7, 20 + offset)
                .toIso8601String()
                .split('T')
                .first,
            'reserved_preparation_minutes':
                offset == 0 ? firstDayReservedMinutes : 0,
            'remaining_budget_minutes': budget == null
                ? null
                : (budget - (offset == 0 ? firstDayReservedMinutes : 0))
                    .clamp(0, budget),
            'over_budget_minutes': budget == null
                ? 0
                : ((offset == 0 ? firstDayReservedMinutes : 0) - budget)
                    .clamp(0, 30000),
            'active_plan_count': offset == 0 ? 1 : 0,
            'fixed_commitment_minutes': offset == 0 ? 90 : 0,
          },
      ],
    };

Map<String, dynamic> deadlinePlanEnvelope({
  String status = 'active',
  bool pending = false,
  String activeTitle = 'Algorithms exam',
  String pendingTitle = 'Revised algorithms exam',
}) {
  final detail = deadlinePlanDetail(
    status: status,
    pending: pending,
    activeTitle: activeTitle,
    pendingTitle: pendingTitle,
  );
  return {
    'contract_version': 'deadline-plan-v1',
    'origin': 'authenticated_backend',
    ...detail,
  };
}

Map<String, dynamic> deadlinePlanFeed({
  List<Map<String, dynamic>>? plans,
}) =>
    {
      'contract_version': 'deadline-plan-v1',
      'origin': 'authenticated_backend',
      'plans': plans ?? [deadlinePlanDetail()],
    };

Map<String, dynamic> deadlinePlanDetail({
  String status = 'active',
  bool pending = false,
  String activeTitle = 'Algorithms exam',
  String pendingTitle = 'Revised algorithms exam',
}) {
  final draft = status == 'draft';
  final terminal = status == 'completed' || status == 'cancelled';
  final activeRevision = draft
      ? null
      : deadlineRevision(
          title: activeTitle,
          state: 'active',
          revision: 1,
          baseRevision: 0,
          activatedAt: '2026-07-18T10:01:00Z',
          blockState: terminal ? 'completed' : 'upcoming',
        );
  final pendingRevision = draft
      ? deadlineRevision(
          title: pendingTitle,
          state: 'proposed',
          revision: 1,
          baseRevision: 0,
        )
      : pending
          ? deadlineRevision(
              title: pendingTitle,
              state: 'proposed',
              revision: 2,
              baseRevision: 1,
              estimatedTotalMinutes: 420,
              creditedPriorMinutes: 60,
              trackedFocusMinutes: 25,
              plannedMinutes: 50,
              unscheduledMinutes: 285,
            )
          : null;
  return {
    'plan': {
      'id': deadlinePlanId,
      'status': status,
      'kind': 'exam',
      'title': activeTitle,
      if (!draft) 'managed_task_id': deadlinePlanId,
      'original_estimated_total_minutes': 300,
      'original_credited_prior_minutes': 30,
      'current_revision': draft ? 0 : 1,
      'latest_revision': pending ? 2 : 1,
      'created_at': '2026-07-18T10:00:00Z',
      'updated_at': '2026-07-18T10:01:00Z',
      if (status == 'completed') 'completed_at': '2026-07-18T12:00:00Z',
      if (status == 'cancelled') 'cancelled_at': '2026-07-18T12:00:00Z',
    },
    if (activeRevision != null) 'active_revision': activeRevision,
    if (pendingRevision != null) 'pending_revision': pendingRevision,
    'progress': {
      'estimated_total_minutes': 300,
      'credited_prior_minutes': 30,
      'tracked_focus_minutes': 25,
      'accounted_minutes': 55,
      'remaining_minutes': 245,
      'completion_suggested': false,
    },
  };
}

Map<String, dynamic> deadlineRevision({
  String title = 'Algorithms exam',
  String state = 'active',
  int revision = 1,
  int baseRevision = 0,
  String? activatedAt,
  String? supersededAt,
  int estimatedTotalMinutes = 300,
  int creditedPriorMinutes = 30,
  int trackedFocusMinutes = 25,
  int plannedMinutes = 50,
  int unscheduledMinutes = 195,
  String blockState = 'upcoming',
  List<Map<String, dynamic>>? blocks,
}) {
  final remaining =
      estimatedTotalMinutes - creditedPriorMinutes - trackedFocusMinutes;
  return {
    'plan_id': deadlinePlanId,
    'revision': revision,
    'base_revision': baseRevision,
    'state': state,
    'kind': 'exam',
    'title': title,
    'deadline_at': '2026-07-25T15:00:00Z',
    'estimated_total_minutes': estimatedTotalMinutes,
    'credited_prior_minutes': creditedPriorMinutes,
    'preferred_session_minutes': 50,
    'max_daily_minutes': 120,
    'planning_start_on': '2026-07-18',
    'buffer_days': 1,
    'source_kind': 'manual',
    'source_status': 'not_applicable',
    'use_calendar_availability': true,
    'availability_connection_id': '66666666-6666-4666-8666-666666666666',
    'availability_import_id': '77777777-7777-4777-8777-777777777777',
    'timezone': 'Europe/Berlin',
    'best_energy_window': 'morning',
    'planning_fingerprint': deadlineFingerprint,
    'tracked_focus_minutes_at_proposal': trackedFocusMinutes,
    'remaining_minutes_at_proposal': remaining,
    'planned_minutes': plannedMinutes,
    'unscheduled_minutes': unscheduledMinutes,
    'created_at': '2026-07-18T10:00:00Z',
    if (activatedAt != null) 'activated_at': activatedAt,
    if (supersededAt != null) 'superseded_at': supersededAt,
    'blocks': blocks ??
        [
          deadlineBlock(state: blockState, plannedMinutes: plannedMinutes),
        ],
  };
}

Map<String, dynamic> deadlineBlock({
  String id = deadlineBlockId,
  int sequence = 1,
  int plannedMinutes = 50,
  int creditedTrackedMinutes = 0,
  String state = 'upcoming',
}) =>
    {
      'id': id,
      'sequence': sequence,
      'starts_at': '2026-07-20T08:00:00Z',
      'ends_at': '2026-07-20T08:50:00Z',
      'local_date': '2026-07-20',
      'local_start_time': '10:00:00',
      'local_end_time': '10:50:00',
      'planned_minutes': plannedMinutes,
      'credited_tracked_minutes': creditedTrackedMinutes,
      'state': state,
    };
