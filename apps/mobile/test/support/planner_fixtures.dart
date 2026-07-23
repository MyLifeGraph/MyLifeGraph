Map<String, dynamic> plannerOverviewEnvelope() {
  final firstDay = DateTime.utc(2026, 7, 21);
  return {
    'contract_version': 'planner-v1',
    'origin': 'authenticated_backend',
    'generated_at': '2026-07-21T08:00:00Z',
    'timezone': 'Europe/Berlin',
    'local_date': '2026-07-21',
    'preferences': plannerPreferencesEnvelope(),
    'action_plans': <dynamic>[],
    'commitments': [plannerCommitment()],
    'needs_attention': [
      {
        'id': 'plan:conflict',
        'kind': 'conflict',
        'target': 'plan',
        'title': 'Write report',
        'detail': 'A fixed commitment overlaps this plan.',
        'plan_id': '10000000-0000-4000-8000-000000000001',
        'unplaced_minutes': 0,
      },
    ],
    'days': [
      for (var offset = 0; offset < 7; offset++)
        {
          'local_date': _date(firstDay.add(Duration(days: offset))),
          'items': offset == 0
              ? [
                  {
                    'id': '20000000-0000-4000-8000-000000000001',
                    'kind': 'setup_commitment',
                    'title': 'Lecture',
                    'source_id': '20000000-0000-4000-8000-000000000002',
                    'starts_at': '2026-07-21T08:00:00Z',
                    'ends_at': '2026-07-21T09:00:00Z',
                    'recovery_minutes': 0,
                    'reserved_ends_at': '2026-07-21T09:00:00Z',
                    'all_day': false,
                    'state': null,
                  },
                  {
                    'id': '30000000-0000-4000-8000-000000000001',
                    'kind': 'task_block',
                    'title': 'Write report',
                    'source_id': '30000000-0000-4000-8000-000000000002',
                    'starts_at': '2026-07-21T09:00:00Z',
                    'ends_at': '2026-07-21T09:30:00Z',
                    'recovery_minutes': 0,
                    'reserved_ends_at': '2026-07-21T09:30:00Z',
                    'all_day': false,
                    'state': 'active',
                  },
                  {
                    'id': '40000000-0000-4000-8000-000000000001',
                    'kind': 'habit_slot',
                    'title': 'Read',
                    'source_id': '40000000-0000-4000-8000-000000000002',
                    'starts_at': '2026-07-21T10:00:00Z',
                    'ends_at': '2026-07-21T10:20:00Z',
                    'recovery_minutes': 0,
                    'reserved_ends_at': '2026-07-21T10:20:00Z',
                    'all_day': false,
                    'state': 'active',
                  },
                  {
                    'id': '50000000-0000-4000-8000-000000000001',
                    'kind': 'manual_commitment',
                    'title': 'Tutoring',
                    'source_id': '50000000-0000-4000-8000-000000000001',
                    'starts_at': '2026-07-21T11:00:00Z',
                    'ends_at': '2026-07-21T12:00:00Z',
                    'recovery_minutes': 0,
                    'reserved_ends_at': '2026-07-21T12:00:00Z',
                    'all_day': false,
                    'state': 'active',
                  },
                  {
                    'id': '60000000-0000-4000-8000-000000000001',
                    'kind': 'preparation',
                    'title': 'Mathematics',
                    'source_id': '60000000-0000-4000-8000-000000000002',
                    'starts_at': '2026-07-21T13:00:00Z',
                    'ends_at': '2026-07-21T13:50:00Z',
                    'recovery_minutes': 0,
                    'reserved_ends_at': '2026-07-21T13:50:00Z',
                    'all_day': false,
                    'state': 'active',
                  },
                  {
                    'id': '70000000-0000-4000-8000-000000000001',
                    'kind': 'calendar_event',
                    'title': 'Imported seminar',
                    'source_id': '70000000-0000-4000-8000-000000000001',
                    'starts_at': '2026-07-21T14:00:00Z',
                    'ends_at': '2026-07-21T15:00:00Z',
                    'recovery_minutes': 0,
                    'reserved_ends_at': '2026-07-21T15:00:00Z',
                    'all_day': false,
                    'state': 'busy',
                  },
                ]
              : <dynamic>[],
        },
    ],
    'ongoing_preparation': [
      {
        'plan_id': '60000000-0000-4000-8000-000000000002',
        'title': 'Mathematics',
        'status': 'active',
        'remaining_minutes': 150,
        'next_block_starts_at': '2026-07-21T13:00:00Z',
        'has_pending_preview': false,
      },
    ],
    'unscheduled': [
      {
        'id': '80000000-0000-4000-8000-000000000001',
        'kind': 'task',
        'title': 'Undated reading',
        'reason': 'not_planned',
        'expected_updated_at': '2026-07-20T08:00:00Z',
        'description': null,
        'priority': 'medium',
        'estimated_minutes': null,
        'deadline_at': null,
        'preferred_session_minutes': null,
        'use_study_rhythm': false,
        'cadence': null,
        'duration_minutes': null,
      },
    ],
    'history': [
      {
        'id': '90000000-0000-4000-8000-000000000001',
        'kind': 'habit',
        'title': 'Archived walk',
        'reason': 'released',
        'expected_updated_at': '2026-07-20T08:00:00Z',
        'description': null,
        'priority': null,
        'estimated_minutes': null,
        'deadline_at': null,
        'preferred_session_minutes': null,
        'use_study_rhythm': false,
        'cadence': {
          'kind': 'daily',
          'scheduled_weekdays': <dynamic>[],
          'weekly_target': 1,
        },
        'duration_minutes': null,
      },
    ],
  };
}

Map<String, dynamic> plannerPreferencesEnvelope() => {
      'contract_version': 'planner-preferences-v1',
      'origin': 'authenticated_backend',
      'use_calendar_busy_time': true,
      'updated_at': '2026-07-21T07:00:00Z',
      'current_calendar_import_id': 'a0000000-0000-4000-8000-000000000001',
      'calendar_available': true,
    };

Map<String, dynamic> plannerActionPlanEnvelope({String state = 'proposed'}) {
  final plan = plannerActionPlan(state: state);
  return {
    'contract_version': 'planner-v1',
    'origin': 'authenticated_backend',
    'plan': plan,
  };
}

Map<String, dynamic> plannerActionPlan({String state = 'proposed'}) {
  final active = state == 'active';
  final revision = {
    'revision': 1,
    'base_revision': 0,
    'state': state,
    'target': {
      'kind': 'task',
      'operation': 'create',
      'target_id': 'b0000000-0000-4000-8000-000000000001',
      'expected_updated_at': null,
      'title': 'Prepare presentation',
      'description': null,
      'priority': 'high',
      'estimated_minutes': 60,
      'deadline_at': '2026-07-24T12:00:00Z',
      'preferred_session_minutes': 30,
      'use_study_rhythm': false,
    },
    'timezone': 'Europe/Berlin',
    'best_energy_window': 'morning',
    'planning_start_on': '2026-07-21',
    'planning_fingerprint': List.filled(64, 'a').join(),
    'calendar_import_id': 'a0000000-0000-4000-8000-000000000001',
    'study_setup_revision': null,
    'recovery_minutes': 0,
    'planned_minutes': 60,
    'unscheduled_minutes': 0,
    'task_blocks': [
      {
        'id': 'c0000000-0000-4000-8000-000000000001',
        'sequence': 1,
        'starts_at': '2026-07-21T08:00:00Z',
        'ends_at': '2026-07-21T08:30:00Z',
        'local_date': '2026-07-21',
        'planned_minutes': 30,
        'recovery_minutes': 0,
        'reserved_ends_at': '2026-07-21T08:30:00Z',
        'state': state,
      },
      {
        'id': 'c0000000-0000-4000-8000-000000000002',
        'sequence': 2,
        'starts_at': '2026-07-22T08:00:00Z',
        'ends_at': '2026-07-22T08:30:00Z',
        'local_date': '2026-07-22',
        'planned_minutes': 30,
        'recovery_minutes': 0,
        'reserved_ends_at': '2026-07-22T08:30:00Z',
        'state': state,
      },
    ],
    'habit_slots': <dynamic>[],
    'created_at': '2026-07-21T07:30:00Z',
    'activated_at': active ? '2026-07-21T07:45:00Z' : null,
    'superseded_at': null,
  };
  return {
    'id': 'd0000000-0000-4000-8000-000000000001',
    'target_kind': 'task',
    'target_id': 'b0000000-0000-4000-8000-000000000001',
    'status': active ? 'active' : 'draft',
    'current_revision': active ? 1 : 0,
    'latest_revision': 1,
    'needs_attention': false,
    'attention_reasons': <dynamic>[],
    'active_revision': active ? revision : null,
    'pending_revision': active ? null : revision,
  };
}

Map<String, dynamic> plannerCommitment() => {
      'id': '50000000-0000-4000-8000-000000000001',
      'title': 'Tutoring',
      'location': 'Library',
      'recurrence': 'one_off',
      'status': 'active',
      'starts_at': '2026-07-21T11:00:00Z',
      'ends_at': '2026-07-21T12:00:00Z',
      'weekday': null,
      'local_starts_at': null,
      'local_ends_at': null,
      'created_at': '2026-07-20T08:00:00Z',
      'updated_at': '2026-07-20T08:00:00Z',
      'archived_at': null,
    };

Map<String, dynamic> plannerCommitmentEnvelope() => {
      'contract_version': 'planner-v1',
      'origin': 'authenticated_backend',
      'commitment': plannerCommitment(),
      'affected_plan_ids': <dynamic>[],
      'replayed': false,
    };

String _date(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
