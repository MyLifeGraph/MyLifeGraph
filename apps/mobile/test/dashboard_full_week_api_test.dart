import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/dashboard_providers.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/dashboard/data/datasources/dashboard_full_week_api_data_source.dart';
import 'package:my_life_graph/features/dashboard/data/repositories/dashboard_full_week_repository_impl.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_full_week.dart';
import 'package:my_life_graph/features/dashboard/domain/repositories/dashboard_full_week_repository.dart';

void main() {
  const mapper = DashboardFullWeekMapper();

  test('strict mapper accepts all seven sources and profile-local wire times',
      () {
    final projection = mapper.map(_agenda());

    expect(projection.days, hasLength(7));
    expect(projection.localToday, DateTime.utc(2026, 7, 21));
    expect(projection.timezone, 'Europe/Berlin');
    expect(
      projection.days[1].items.map((item) => item.category).toSet(),
      DashboardFullWeekCategory.values.toSet(),
    );
    final preparation = projection.days[1].items.firstWhere(
      (item) => item.category == DashboardFullWeekCategory.preparation,
    );
    expect(preparation.localStartsAt, '2026-07-21T09:00:00');
    expect(preparation.timeLabel, '09:00–09:50');
    expect(preparation.remainingMinutes, 50);
    expect(
      preparation.action?.kind,
      DashboardFullWeekActionKind.startPreparationFocus,
    );
    final habit = projection.days[1].items.firstWhere(
      (item) => item.category == DashboardFullWeekCategory.habit,
    );
    expect(habit.action?.localDate, DateTime.utc(2026, 7, 21));
  });

  test('strict mapper preserves partial-source state and rejects its items',
      () {
    final partial = _agenda();
    final states = Map<String, dynamic>.from(
      partial['source_states'] as Map<String, dynamic>,
    );
    states['calendar'] = {
      'status': 'unavailable',
      'message': 'Calendar is unavailable.',
    };
    partial['source_states'] = states;
    final day = Map<String, dynamic>.from(
      (partial['days'] as List<dynamic>)[1] as Map<String, dynamic>,
    );
    day['items'] = (day['items'] as List<dynamic>)
        .where(
          (item) => (item as Map<String, dynamic>)['category'] != 'calendar',
        )
        .toList();
    (partial['days'] as List<dynamic>)[1] = day;

    final projection = mapper.map(partial);
    expect(projection.unavailableSources.single.name, 'calendar');

    final invalid = _agenda();
    final invalidStates = Map<String, dynamic>.from(
      invalid['source_states'] as Map<String, dynamic>,
    );
    invalidStates['calendar'] = {
      'status': 'unavailable',
      'message': 'Calendar is unavailable.',
    };
    invalid['source_states'] = invalidStates;
    expect(
      () => mapper.map(invalid),
      throwsA(isA<DashboardFullWeekException>()),
    );
  });

  test('strict mapper rejects extra fields, incomplete weeks, and bad actions',
      () {
    final extra = _agenda()..['unexpected'] = true;
    expect(
      () => mapper.map(extra),
      throwsA(isA<DashboardFullWeekException>()),
    );

    final incomplete = _agenda();
    (incomplete['days'] as List<dynamic>).removeLast();
    expect(
      () => mapper.map(incomplete),
      throwsA(isA<DashboardFullWeekException>()),
    );

    final badAction = _agenda();
    final items = ((badAction['days'] as List<dynamic>)[1]
        as Map<String, dynamic>)['items'] as List<dynamic>;
    final preparation = Map<String, dynamic>.from(
      items[1] as Map<String, dynamic>,
    );
    preparation['action'] = {
      'kind': 'open_habit',
      'target_id': _id(90),
      'source_kind': null,
      'local_date': '2026-07-21',
    };
    items[1] = preparation;
    expect(
      () => mapper.map(badAction),
      throwsA(isA<DashboardFullWeekException>()),
    );
  });

  test('strict mapper rejects invalid status, identity, and source relations',
      () {
    final badStatus = _agenda();
    final badStatusItems = ((badStatus['days'] as List<dynamic>)[1]
        as Map<String, dynamic>)['items'] as List<dynamic>;
    (badStatusItems[1] as Map<String, dynamic>)['status'] = 'scheduled';
    expect(
      () => mapper.map(badStatus),
      throwsA(isA<DashboardFullWeekException>()),
    );

    final wrongTarget = _agenda();
    final wrongTargetItems = ((wrongTarget['days'] as List<dynamic>)[1]
        as Map<String, dynamic>)['items'] as List<dynamic>;
    final action = Map<String, dynamic>.from(
      (wrongTargetItems[1] as Map<String, dynamic>)['action']
          as Map<String, dynamic>,
    )..['target_id'] = _id(99);
    (wrongTargetItems[1] as Map<String, dynamic>)['action'] = action;
    expect(
      () => mapper.map(wrongTarget),
      throwsA(isA<DashboardFullWeekException>()),
    );

    final doneTaskAction = _agenda();
    final doneItems = ((doneTaskAction['days'] as List<dynamic>)[1]
        as Map<String, dynamic>)['items'] as List<dynamic>;
    (doneItems[4] as Map<String, dynamic>)['status'] = 'done';
    expect(
      () => mapper.map(doneTaskAction),
      throwsA(isA<DashboardFullWeekException>()),
    );
  });

  test('strict mapper rejects timezone, local-today, and wall-time mismatch',
      () {
    final invalidTimezone = _agenda()..['timezone'] = 'Mars/Olympus';
    expect(
      () => mapper.map(invalidTimezone),
      throwsA(isA<DashboardFullWeekException>()),
    );

    final wrongToday = _agenda()..['local_today'] = '2026-07-22';
    expect(
      () => mapper.map(wrongToday),
      throwsA(isA<DashboardFullWeekException>()),
    );

    final wrongWall = _agenda();
    final wallItems = ((wrongWall['days'] as List<dynamic>)[1]
        as Map<String, dynamic>)['items'] as List<dynamic>;
    (wallItems[0] as Map<String, dynamic>)['local_starts_at'] =
        '2026-07-21T09:00:00';
    expect(
      () => mapper.map(wrongWall),
      throwsA(isA<DashboardFullWeekException>()),
    );
  });

  test('strict mapper rejects normalized timestamp overflow components', () {
    final badGenerated = _agenda()..['generated_at'] = '2026-07-21T25:00:00Z';
    expect(
      () => mapper.map(badGenerated),
      throwsA(isA<DashboardFullWeekException>()),
    );

    final badItem = _agenda();
    final items = ((badItem['days'] as List<dynamic>)[1]
        as Map<String, dynamic>)['items'] as List<dynamic>;
    (items.first as Map<String, dynamic>)['starts_at'] = '2026-07-21T30:00:00Z';
    expect(
      () => mapper.map(badItem),
      throwsA(isA<DashboardFullWeekException>()),
    );
  });

  test('strict mapper accepts server fractions and explicit offsets', () {
    final agenda = _agenda()
      ..['generated_at'] = '2026-07-21T10:00:00.123456+02:00';
    final items = ((agenda['days'] as List<dynamic>)[1]
        as Map<String, dynamic>)['items'] as List<dynamic>;
    (items.first as Map<String, dynamic>)
      ..['starts_at'] = '2026-07-21T08:00:00.123456+02:00'
      ..['ends_at'] = '2026-07-21T09:00:00.500000+02:00';

    final projection = mapper.map(agenda);

    expect(
      projection.generatedAt,
      DateTime.parse('2026-07-21T10:00:00.123456+02:00'),
    );
    expect(
      projection.days[1].items.first.startsAt,
      DateTime.parse('2026-07-21T08:00:00.123456+02:00'),
    );
  });

  test('strict mapper rejects a Habit action outside profile-local Today', () {
    final agenda = _agenda()
      ..['generated_at'] = '2026-07-20T08:00:00Z'
      ..['local_today'] = '2026-07-20';

    expect(
      () => mapper.map(agenda),
      throwsA(isA<DashboardFullWeekException>()),
    );
  });

  test('strict mapper accepts both real Europe/Berlin fold instants', () {
    final agenda = _agenda();
    agenda['generated_at'] = '2026-10-25T12:00:00Z';
    agenda['local_today'] = '2026-10-25';
    agenda['week_starts_on'] = '2026-10-19';
    agenda['week_ends_on'] = '2026-10-25';
    agenda['days'] = List.generate(7, (offset) {
      final day = DateTime.utc(2026, 10, 19).add(Duration(days: offset));
      return <String, dynamic>{
        'local_date': _date(day),
        'items': offset == 6
            ? [
                {
                  ..._item(70, 'calendar', '02:30:00', '02:30:00'),
                  'local_date': '2026-10-25',
                  'local_starts_at': '2026-10-25T02:30:00',
                  'local_ends_at': '2026-10-25T02:30:00',
                  'starts_at': '2026-10-25T00:30:00Z',
                  'ends_at': '2026-10-25T01:30:00Z',
                },
              ]
            : <dynamic>[],
      };
    });

    final projection = mapper.map(agenda);
    expect(projection.days.last.items.single.timeLabel, '02:30–02:30');
  });

  test('strict mapper rejects a nonexistent Europe/Berlin gap wall time', () {
    final agenda = _agenda();
    agenda['generated_at'] = '2026-03-29T12:00:00Z';
    agenda['local_today'] = '2026-03-29';
    agenda['week_starts_on'] = '2026-03-23';
    agenda['week_ends_on'] = '2026-03-29';
    agenda['days'] = List.generate(7, (offset) {
      final day = DateTime.utc(2026, 3, 23).add(Duration(days: offset));
      return <String, dynamic>{
        'local_date': _date(day),
        'items': offset == 6
            ? [
                {
                  ..._item(71, 'calendar', '02:30:00', '03:30:00'),
                  'local_date': '2026-03-29',
                  'local_starts_at': '2026-03-29T02:30:00',
                  'local_ends_at': '2026-03-29T03:30:00',
                  'starts_at': '2026-03-29T01:30:00Z',
                  'ends_at': '2026-03-29T02:30:00Z',
                },
              ]
            : <dynamic>[],
      };
    });

    expect(
      () => mapper.map(agenda),
      throwsA(isA<DashboardFullWeekException>()),
    );
  });

  test('repository uses one Bearer GET and missing token makes zero calls',
      () async {
    final client = _TrackingApiClient(_agenda());
    final repository = DashboardFullWeekRepositoryImpl(
      dataSource: DashboardFullWeekApiDataSource(client),
      accessTokenProvider: () async => ' account-token ',
    );

    await repository.getCurrentWeek();
    expect(client.calls, ['/v1/today/week-agenda']);
    expect(client.headers.single, {
      'Authorization': 'Bearer account-token',
    });

    final noCallClient = _TrackingApiClient(_agenda());
    final noTokenRepository = DashboardFullWeekRepositoryImpl(
      dataSource: DashboardFullWeekApiDataSource(noCallClient),
      accessTokenProvider: () async => ' ',
    );
    await expectLater(
      noTokenRepository.getCurrentWeek(),
      throwsA(isA<DashboardFullWeekUnavailableException>()),
    );
    expect(noCallClient.calls, isEmpty);
  });

  test('guest provider returns seven local days with zero product calls',
      () async {
    final repository = _CountingRepository(
      dashboardFullWeekFixtureForProvider(),
    );
    final container = ProviderContainer(
      overrides: [
        appSurfaceCapabilitiesProvider.overrideWithValue(
          const AppSurfaceCapabilities(
            isLocalDemo: true,
            canUseSyncedHabits: false,
          ),
        ),
        dashboardFullWeekRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final projection = await container.read(
      dashboardFullWeekProvider(DateTime(2026, 7, 21)).future,
    );

    expect(repository.calls, 0);
    expect(projection.days, hasLength(7));
    expect(projection.localToday, DateTime.utc(2026, 7, 21));
  });
}

class _CountingRepository implements DashboardFullWeekRepository {
  _CountingRepository(this.projection);

  final DashboardFullWeekProjection projection;
  int calls = 0;

  @override
  Future<DashboardFullWeekProjection> getCurrentWeek() async {
    calls += 1;
    return projection;
  }
}

DashboardFullWeekProjection dashboardFullWeekFixtureForProvider() =>
    DashboardFullWeekProjection.empty(DateTime.utc(2026, 7, 21));

class _TrackingApiClient extends ApiClient {
  _TrackingApiClient(this.response) : super(Dio());

  final Map<String, dynamic> response;
  final List<String> calls = [];
  final List<Map<String, String>?> headers = [];

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    calls.add(path);
    this.headers.add(headers);
    return response;
  }
}

Map<String, dynamic> _agenda() {
  final days = List.generate(7, (offset) {
    final day = DateTime.utc(2026, 7, 20).add(Duration(days: offset));
    return <String, dynamic>{
      'local_date': _date(day),
      'items': <dynamic>[],
    };
  });
  final timed = <Map<String, dynamic>>[
    _item(1, 'setup', '08:00:00', '09:00:00'),
    _item(
      2,
      'preparation',
      '09:00:00',
      '09:50:00',
      action: {
        'kind': 'start_preparation_focus',
        'target_id': _id(2),
        'source_kind': 'deadline_plan_block',
        'local_date': null,
      },
    ),
    _item(
      4,
      'focus',
      '10:00:00',
      '10:30:00',
      action: {
        'kind': 'reflect_focus',
        'target_id': _id(4),
        'source_kind': null,
        'local_date': null,
      },
    ),
    _item(
      5,
      'task',
      '11:00:00',
      '11:25:00',
      action: {
        'kind': 'start_task_focus',
        'target_id': _id(5),
        'source_kind': 'planner_task_block',
        'local_date': null,
      },
    ),
    _item(
      6,
      'habit',
      '12:00:00',
      '12:20:00',
      action: {
        'kind': 'open_habit',
        'target_id': _id(6),
        'source_kind': null,
        'local_date': '2026-07-21',
      },
    ),
    _item(7, 'fixed_commitment', '13:00:00', '14:00:00'),
  ];
  timed.insert(2, {
    'id': _id(3),
    'category': 'calendar',
    'source_id': _id(3),
    'plan_id': null,
    'habit_id': null,
    'local_date': '2026-07-21',
    'title': 'Campus closed',
    'detail': null,
    'status': 'confirmed',
    'planned_minutes': null,
    'credited_tracked_minutes': null,
    'remaining_minutes': null,
    'all_day': true,
    'local_starts_at': null,
    'local_ends_at': null,
    'starts_at': null,
    'ends_at': null,
    'action': null,
  });
  days[1]['items'] = timed;
  return {
    'contract_version': todayWeekAgendaContractVersion,
    'origin': 'authenticated_backend',
    'generated_at': '2026-07-21T08:00:00Z',
    'timezone': 'Europe/Berlin',
    'local_today': '2026-07-21',
    'week_starts_on': '2026-07-20',
    'week_ends_on': '2026-07-26',
    'days': days,
    'source_states': {
      for (final source in [
        'setup',
        'preparation',
        'calendar',
        'focus',
        'tasks',
        'habits',
        'fixed_commitments',
      ])
        source: {'status': 'current', 'message': null},
    },
  };
}

Map<String, dynamic> _item(
  int identity,
  String category,
  String start,
  String end, {
  Map<String, dynamic>? action,
}) =>
    {
      'id': _id(identity),
      'category': category,
      'source_id': _id(identity),
      'plan_id': category == 'preparation' ? _id(80 + identity) : null,
      'habit_id': category == 'habit' ? _id(identity) : null,
      'local_date': '2026-07-21',
      'title': '${category[0].toUpperCase()}${category.substring(1)}',
      'detail': null,
      'status': switch (category) {
        'setup' || 'fixed_commitment' => 'scheduled',
        'preparation' => 'upcoming',
        'calendar' => 'confirmed',
        'focus' => 'completed',
        'task' => 'todo',
        'habit' => 'open',
        _ => throw StateError('unsupported category'),
      },
      'planned_minutes': category == 'preparation' ? 50 : null,
      'credited_tracked_minutes': category == 'preparation' ? 0 : null,
      'remaining_minutes': category == 'preparation' ? 50 : null,
      'all_day': false,
      'local_starts_at': '2026-07-21T$start',
      'local_ends_at': '2026-07-21T$end',
      'starts_at': '2026-07-21T${_utc(start)}Z',
      'ends_at': '2026-07-21T${_utc(end)}Z',
      'action': action,
    };

String _utc(String local) {
  final hour = int.parse(local.substring(0, 2)) - 2;
  return '${hour.toString().padLeft(2, '0')}${local.substring(2)}';
}

String _date(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _id(int value) =>
    '10000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
