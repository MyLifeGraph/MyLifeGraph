import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/dashboard/data/datasources/today_overview_api_data_source.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_snapshot.dart';

void main() {
  const mapper = TodayOverviewMapper();

  test('maps the strict v2 overview with Planner agenda sources', () {
    final snapshot = mapper.map(_overview());

    expect(snapshot.isTodayOverview, isTrue);
    expect(snapshot.localDate, DateTime(2026, 7, 21));
    expect(snapshot.checkIns?.completedDaysStreak, 6);
    expect(snapshot.progress?.completed, 3);
    expect(snapshot.progress?.total, 5);
    expect(
      snapshot.timeline.map((item) => item.kind),
      [
        TodayTimelineKind.calendarEvent,
        TodayTimelineKind.setupCommitment,
        TodayTimelineKind.preparation,
        TodayTimelineKind.focusSession,
        TodayTimelineKind.taskBlock,
        TodayTimelineKind.habitSlot,
        TodayTimelineKind.manualCommitment,
      ],
    );
    expect(snapshot.todayTasks.single.todayReason, 'completed_today');
    expect(snapshot.todayTasks.single.scheduledToday, isTrue);
    expect(snapshot.todayHabits.single.outcome, 'skipped');
    expect(snapshot.todayHabits.single.scheduledToday, isTrue);
    expect(
      snapshot.progress?.total,
      5,
      reason: 'blocks do not duplicate targets',
    );
  });

  test('rejects a partial total that does not match counted projections', () {
    final json = _overview();
    json['progress'] = {'completed': 4, 'total': 5};

    expect(
      () => mapper.map(json),
      throwsA(isA<TodayOverviewContractException>()),
    );
  });

  test('accepts unavailable progress only with the matching source state', () {
    final json = _overview();
    json['progress'] = null;
    json['progress_unavailable_sources'] = ['tasks'];
    final states = Map<String, dynamic>.from(json['source_states'] as Map);
    states['tasks'] = {
      'status': 'unavailable',
      'message': 'Tasks could not be loaded.',
    };
    json['source_states'] = states;
    json['tasks'] = {'today': <dynamic>[], 'all': <dynamic>[]};
    json['timeline'] = (json['timeline'] as List<dynamic>)
        .where((item) => (item as Map<String, dynamic>)['kind'] != 'task_block')
        .toList();

    final snapshot = mapper.map(json);

    expect(snapshot.progress, isNull);
    expect(snapshot.sourceStates?.tasks.status, TodaySourceStatus.unavailable);
  });

  test('rejects Planner flags without matching agenda targets', () {
    final json = _overview();
    final tasks = Map<String, dynamic>.from(json['tasks'] as Map);
    tasks['today'] = [
      {
        ...Map<String, dynamic>.from((tasks['today'] as List).single as Map),
        'scheduled_today': false,
      },
    ];
    tasks['all'] = [
      {
        ...Map<String, dynamic>.from((tasks['all'] as List).single as Map),
        'scheduled_today': false,
      },
    ];
    json['tasks'] = tasks;

    expect(
      () => mapper.map(json),
      throwsA(isA<TodayOverviewContractException>()),
    );
  });

  test('rejects a Planner duration that differs from its interval', () {
    final json = _overview();
    final timeline = List<dynamic>.from(json['timeline'] as List);
    final block = Map<String, dynamic>.from(timeline[4] as Map);
    block['planned_minutes'] = 20;
    timeline[4] = block;
    json['timeline'] = timeline;

    expect(
      () => mapper.map(json),
      throwsA(isA<TodayOverviewContractException>()),
    );
  });
}

Map<String, dynamic> _overview() {
  final task = {
    'id': '10000000-0000-4000-8000-000000000001',
    'title': 'Submit essay',
    'description': null,
    'status': 'done',
    'priority': 'high',
    'deadline': '2026-07-21T12:00:00Z',
    'estimated_minutes': 30,
    'completed_at': '2026-07-21T08:00:00Z',
    'source': 'manual',
    'deadline_plan_id': null,
    'today_reason': 'completed_today',
    'scheduled_today': true,
  };
  return {
    'contract_version': 'today-overview-v2',
    'origin': 'authenticated_backend',
    'local_date': '2026-07-21',
    'timezone': 'Europe/Berlin',
    'generated_at': '2026-07-21T08:00:00Z',
    'check_ins': {
      'morning_saved': true,
      'evening_saved': true,
      'completed_days_streak': 6,
    },
    'progress': {'completed': 3, 'total': 5},
    'progress_unavailable_sources': <dynamic>[],
    'timeline': [
      {
        'kind': 'calendar_event',
        'id': '20000000-0000-4000-8000-000000000001',
        'title': 'Campus closed',
        'location': null,
        'source_label': 'Studies',
        'all_day': true,
        'starts_at': null,
        'ends_at': null,
        'starts_on': '2026-07-21',
        'ends_on': '2026-07-22',
      },
      {
        'kind': 'setup_commitment',
        'id': '30000000-0000-5000-8000-000000000001',
        'title': 'Lecture',
        'location': 'Hall A',
        'all_day': false,
        'starts_at': '2026-07-21T08:00:00Z',
        'ends_at': '2026-07-21T09:00:00Z',
      },
      {
        'kind': 'preparation',
        'id': '40000000-0000-4000-8000-000000000001',
        'title': 'Mathematics',
        'location': null,
        'all_day': false,
        'starts_at': '2026-07-21T09:00:00Z',
        'ends_at': '2026-07-21T09:50:00Z',
        'plan_id': '50000000-0000-4000-8000-000000000001',
        'block_id': '40000000-0000-4000-8000-000000000001',
        'managed_task_id': '50000000-0000-4000-8000-000000000001',
        'state': 'partial',
        'planned_minutes': 50,
        'credited_tracked_minutes': 20,
      },
      {
        'kind': 'focus_session',
        'id': '60000000-0000-4000-8000-000000000001',
        'title': 'Essay focus',
        'location': null,
        'all_day': false,
        'starts_at': '2026-07-21T10:00:00Z',
        'ends_at': '2026-07-21T10:30:00Z',
        'status': 'completed',
        'actual_minutes': 30,
      },
      {
        'kind': 'task_block',
        'id': '80000000-0000-4000-8000-000000000001',
        'title': 'Submit essay',
        'location': null,
        'all_day': false,
        'starts_at': '2026-07-21T11:00:00Z',
        'ends_at': '2026-07-21T11:25:00Z',
        'task_id': '10000000-0000-4000-8000-000000000001',
        'planned_minutes': 25,
      },
      {
        'kind': 'habit_slot',
        'id': '90000000-0000-4000-8000-000000000001',
        'title': 'Read',
        'location': null,
        'all_day': false,
        'starts_at': '2026-07-21T12:00:00Z',
        'ends_at': '2026-07-21T12:20:00Z',
        'habit_id': '70000000-0000-4000-8000-000000000001',
        'planned_minutes': 20,
      },
      {
        'kind': 'manual_commitment',
        'id': 'a0000000-0000-4000-8000-000000000001',
        'title': 'Tutoring',
        'location': 'Library',
        'all_day': false,
        'starts_at': '2026-07-21T13:00:00Z',
        'ends_at': '2026-07-21T14:00:00Z',
        'commitment_id': 'a0000000-0000-4000-8000-000000000001',
      },
    ],
    'tasks': {
      'today': [task],
      'all': [task],
    },
    'habits': [
      {
        'id': '70000000-0000-4000-8000-000000000001',
        'title': 'Read',
        'description': null,
        'cadence': 'daily',
        'cadence_label': 'Daily',
        'outcome': 'skipped',
        'weekly_completed': 0,
        'weekly_target': 1,
        'setup_managed': false,
        'scheduled_today': true,
      },
    ],
    'source_states': {
      for (final key in [
        'check_ins',
        'tasks',
        'habits',
        'setup_commitments',
        'preparation',
        'calendar_events',
        'focus_sessions',
        'planner',
      ])
        key: {'status': 'current', 'message': null},
    },
  };
}
