const assignmentSeriesId = '22222222-2222-4222-8222-222222222222';
const assignmentSeriesRequestId = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> assignmentSeriesEnvelope({
  String status = 'draft',
}) {
  final active = status == 'active' || status == 'cancelled';
  final identity = <String, dynamic>{
    'id': assignmentSeriesId,
    'status': status,
    'title': 'Weekly algorithms sheet',
    'current_revision': active ? 1 : 0,
    'latest_revision': 1,
    'created_at': '2026-08-10T08:00:00Z',
    'updated_at': '2026-08-10T08:00:00Z',
    if (active) 'first_activated_at': '2026-08-10T08:00:00Z',
    if (status == 'cancelled') 'cancelled_at': '2026-08-10T09:00:00Z',
  };
  final revision = <String, dynamic>{
    'series_id': assignmentSeriesId,
    'revision': 1,
    'base_revision': 0,
    'state': active ? 'active' : 'proposed',
    'title': 'Weekly algorithms sheet',
    'next_deadline_at': '2026-08-17T15:00:00Z',
    'remaining_occurrences': 2,
    'estimated_total_minutes': 90,
    'preferred_session_minutes': 30,
    'max_daily_minutes': 60,
    'buffer_days': 1,
    'use_calendar_availability': false,
    'timezone': 'Europe/Berlin',
    'planned_minutes': 180,
    'unscheduled_minutes': 0,
    'created_at': '2026-08-10T08:00:00Z',
    if (active) 'activated_at': '2026-08-10T08:00:00Z',
    'occurrences': [
      {
        'position': 1,
        'action': 'upsert',
        'plan_id': '40000000-0000-4000-8000-000000000001',
        'plan_revision': 1,
        'deadline_at': '2026-08-17T15:00:00Z',
      },
      {
        'position': 2,
        'action': 'upsert',
        'plan_id': '40000000-0000-4000-8000-000000000002',
        'plan_revision': 1,
        'deadline_at': '2026-08-24T15:00:00Z',
      },
    ],
  };
  return {
    'contract_version': 'assignment-series-v1',
    'origin': 'authenticated_backend',
    'assignment_series': {
      'series': identity,
      if (active) 'active_revision': revision else 'pending_revision': revision,
    },
  };
}

Map<String, dynamic> assignmentSeriesFeed() => {
      'contract_version': 'assignment-series-v1',
      'origin': 'authenticated_backend',
      'assignment_series': [
        assignmentSeriesEnvelope()['assignment_series'],
      ],
    };
