Map<String, dynamic> weeklyReviewResponseJson({
  String freshness = 'current',
  bool includeReview = true,
  String operation = 'shrink',
  String ownership = 'manual',
  String applicationMode = 'direct_habit',
  Map<String, dynamic>? before,
  Object? after = _defaultAfter,
}) {
  final beforeState = before ?? weeklyHabitState(weeklyTarget: 3);
  final afterState = identical(after, _defaultAfter)
      ? weeklyHabitState(weeklyTarget: 2)
      : after;
  return {
    'contract_version': 'weekly-review-v1',
    'period_key': '2026-W28',
    'starts_on': '2026-07-06',
    'ends_on': '2026-07-12',
    'timezone': 'Europe/Berlin',
    'freshness': freshness,
    'needs_generation': freshness == 'missing' || freshness == 'stale',
    'stale_reasons':
        freshness == 'stale' ? ['source_snapshot_changed'] : <String>[],
    'review': includeReview
        ? {
            'id': '11111111-1111-4111-8111-111111111111',
            'data_quality': 'sufficient',
            'narrative':
                'You completed planned work while keeping recovery visible.',
            'facts': {
              'tasks': {
                'completed': 4,
                'carried': 2,
                'overdue_carried': 1,
                'cancelled': 1,
                'goal_linked_completed': 2,
              },
              'habits': {
                'active': 2,
                'paused': 1,
                'archived': 0,
                'stable_definitions': 2,
                'changed_definitions': 1,
                'scheduled_opportunities': 7,
                'completed': 3,
                'skipped': 1,
                'missed': 1,
                'recovery_open': 1,
                'unknown': 1,
              },
              'focus': {
                'completed_sessions': 2,
                'abandoned_sessions': 1,
                'active_sessions': 0,
                'actual_minutes': 55,
              },
              'recovery': {
                'observed_days': 7,
                'recovery_days': 2,
              },
              'feedback': {
                'total': 5,
                'done': 1,
                'later': 1,
                'not_helpful': 1,
                'too_much': 1,
                'does_not_fit': 1,
              },
            },
            'proposals': [
              {
                'id': 'proposal:habit:one',
                'operation': operation,
                'target_kind': 'habit',
                'target_id': '22222222-2222-4222-8222-222222222222',
                'target_title': 'Walk after lunch',
                'ownership': ownership,
                'application_mode': applicationMode,
                'expected_updated_at': '2026-07-12T17:30:00Z',
                'reason_code': 'weekly_target_too_high',
                'reason': 'A smaller target may fit the observed week better.',
                'evidence_refs': [
                  {
                    'table': 'habit_logs',
                    'id': '22222222-2222-4222-8222-222222222222',
                    'field': 'status',
                  },
                ],
                'change': {'before': beforeState, 'after': afterState},
              },
            ],
            'evidence_refs': [
              {
                'table': 'user_state_snapshots',
                'id': '33333333-3333-4333-8333-333333333333',
                'field': 'summary',
              },
            ],
            'provenance': {
              'engine': 'deterministic',
              'contract_version': 'weekly-review-v1',
              'source_snapshot_id': '33333333-3333-4333-8333-333333333333',
              'source_snapshot_generated_at': '2026-07-12T17:00:00Z',
              'evidence_window': {
                'starts_on': '2026-07-06',
                'ends_on': '2026-07-12',
                'days': 7,
              },
              'source_fingerprint':
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              'baseline': 'none',
              'limitations': ['One completed week is a small evidence window.'],
              'llm_used': false,
            },
            'generated_at': '2026-07-12T18:00:00Z',
            'updated_at': '2026-07-12T18:00:00Z',
          }
        : null,
  };
}

Map<String, dynamic> weeklyHabitState({
  String lifecycle = 'active',
  String kind = 'weekly_target',
  int? weeklyTarget = 3,
  List<int> scheduledWeekdays = const [],
}) =>
    {
      'lifecycle': lifecycle,
      'cadence': {
        'kind': kind,
        'weekly_target': weeklyTarget,
        'scheduled_weekdays': scheduledWeekdays,
      },
    };

const Object _defaultAfter = Object();
