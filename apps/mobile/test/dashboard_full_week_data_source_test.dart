import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_life_graph/composition/dashboard_providers.dart';
import 'package:my_life_graph/composition/dashboard_guest_snapshot_adapter.dart';
import 'package:my_life_graph/composition/deadline_plan_providers.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/supabase/supabase_providers.dart';
import 'package:my_life_graph/features/dashboard/data/datasources/dashboard_full_week_supabase_data_source.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_full_week.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_plan.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_plan_repository.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/deadline_plan_fixtures.dart';

void main() {
  test('Setup read is owner-filtered, bounded, and chronologically mapped',
      () async {
    final requests = <Uri>[];
    final client = _client((request) async {
      requests.add(request.url);
      return _json(
        [
          {
            'id': 'setup-1',
            'title': 'Algorithms lecture',
            'weekday': 3,
            'starts_at': '09:15:00',
            'ends_at': '10:45:00',
            'location': 'Room 4',
            'metadata': {
              'managed_by': 'setup',
              'valid_from': '2026-08-01',
              'valid_until': '2026-12-20',
            },
          },
        ],
        request,
      );
    });
    addTearDown(client.dispose);
    final source = DashboardFullWeekSupabaseDataSource(
      client,
      resolveUserId: () async => 'owner-id',
    );

    final result = await source.getSetupCommitments();

    expect(result.single.id, 'setup-1');
    expect(result.single.startsAt, '09:15');
    expect(result.single.sortMinutes, 9 * 60 + 15);
    expect(result.single.validFrom, DateTime(2026, 8, 1));
    expect(result.single.validUntil, DateTime(2026, 12, 20));
    expect(requests.single.queryParameters['user_id'], 'eq.owner-id');
    expect(
      requests.single.queryParameters['metadata->>managed_by'],
      'eq.setup',
    );
    expect(
      requests.single.queryParameters['limit'],
      '${maxDashboardFullWeekCommitments + 1}',
    );
  });

  test('exact block associations combine every session and valid reflection',
      () async {
    final requests = <Uri>[];
    final client = _client((request) async {
      requests.add(request.url);
      if (request.url.path.endsWith('/focus_session_schedule_sources')) {
        return _json(
          const [
            {
              'focus_session_id': 'session-1',
              'source_kind': 'deadline_plan_block',
              'deadline_plan_block_id': 'block-a',
            },
            {
              'focus_session_id': 'session-2',
              'source_kind': 'deadline_plan_block',
              'deadline_plan_block_id': 'block-a',
            },
            {
              'focus_session_id': 'session-3',
              'source_kind': 'deadline_plan_block',
              'deadline_plan_block_id': 'block-b',
            },
          ],
          request,
        );
      }
      if (request.url.path.endsWith('/focus_sessions')) {
        return _json(
          const [
            {'id': 'session-1', 'status': 'completed'},
            {'id': 'session-2', 'status': 'abandoned'},
            {'id': 'session-3', 'status': 'active'},
          ],
          request,
        );
      }
      if (request.url.path.endsWith('/focus_session_reflections')) {
        return _json(
          const [
            {
              'focus_session_id': 'session-1',
              'contract_version': 'focus-reflection-v1',
              'focus_quality': 4,
              'useful_progress': 5,
            },
            {
              'focus_session_id': 'session-2',
              'contract_version': 'focus-reflection-v1',
              'focus_quality': 3,
              'useful_progress': 4,
            },
          ],
          request,
        );
      }
      throw StateError('Unexpected request ${request.url}');
    });
    addTearDown(client.dispose);
    final source = DashboardFullWeekSupabaseDataSource(
      client,
      resolveUserId: () async => 'owner-id',
    );

    final result = await source.getBlockFocusFacts(['block-a', 'block-b']);

    expect(result['block-a'], hasLength(2));
    expect(result['block-a']!.every((fact) => fact.terminal), isTrue);
    expect(
      result['block-a']!.every((fact) => fact.hasValidReflection),
      isTrue,
    );
    expect(result['block-b']!.single.terminal, isFalse);
    expect(result['block-b']!.single.hasValidReflection, isFalse);
    expect(
      requests.every(
        (uri) => uri.queryParameters['user_id'] == 'eq.owner-id',
      ),
      isTrue,
    );
    final sourceRequest = requests.first;
    expect(
      sourceRequest.queryParameters['source_kind'],
      'eq.deadline_plan_block',
    );
    expect(
      sourceRequest.queryParameters['deadline_plan_block_id'],
      contains('block-a'),
    );
    expect(
      sourceRequest.queryParameters['deadline_plan_block_id'],
      contains('block-b'),
    );
  });

  test('240 block ids use sorted owner-filtered association batches', () async {
    final requests = <Uri>[];
    final client = _client((request) async {
      requests.add(request.url);
      return _json(const [], request);
    });
    addTearDown(client.dispose);
    final source = DashboardFullWeekSupabaseDataSource(
      client,
      resolveUserId: () async => 'owner-id',
    );
    final requested = List.generate(
      maxDashboardFullWeekBlocks,
      (index) => _uuid(maxDashboardFullWeekBlocks - index),
    );

    final result = await source.getBlockFocusFacts(requested);

    expect(result, hasLength(maxDashboardFullWeekBlocks));
    expect(result.values.every((facts) => facts.isEmpty), isTrue);
    expect(requests, hasLength(3));
    expect(requests.map(_filteredIds).map((ids) => ids.length), [100, 100, 40]);
    expect(
      requests.expand(_filteredIds).toList(),
      [...requested]..sort(),
    );
    for (final request in requests) {
      expect(request.queryParameters['user_id'], 'eq.owner-id');
      expect(
        request.queryParameters['source_kind'],
        'eq.deadline_plan_block',
      );
      expect(
        request.queryParameters['limit'],
        '${maxDashboardFullWeekFocusAssociations + 1}',
      );
    }
  });

  test('association bound is global across block batches', () async {
    var batchIndex = 0;
    var sessionIndex = 0;
    final requestedLimits = <String?>[];
    final client = _client((request) async {
      requestedLimits.add(request.url.queryParameters['limit']);
      final blockIds = _filteredIds(request.url);
      final count = switch (batchIndex++) { 0 => 200, 1 => 200, _ => 101 };
      return _json(
        [
          for (var index = 0; index < count; index++)
            {
              'focus_session_id': 'session-${sessionIndex++}',
              'source_kind': 'deadline_plan_block',
              'deadline_plan_block_id': blockIds[index % blockIds.length],
            },
        ],
        request,
      );
    });
    addTearDown(client.dispose);
    final source = DashboardFullWeekSupabaseDataSource(
      client,
      resolveUserId: () async => 'owner-id',
    );

    await expectLater(
      source.getBlockFocusFacts(
        List.generate(maxDashboardFullWeekBlocks, _uuid),
      ),
      throwsA(isA<DashboardFullWeekDataException>()),
    );

    expect(batchIndex, 3);
    expect(requestedLimits, ['501', '301', '101']);
  });

  test('duplicate session association across block batches is invalid',
      () async {
    var associationBatch = 0;
    final client = _client((request) async {
      if (!request.url.path.endsWith('/focus_session_schedule_sources')) {
        throw StateError('Association validation must precede detail reads.');
      }
      final blockIds = _filteredIds(request.url);
      associationBatch += 1;
      return _json(
        [
          {
            'focus_session_id': 'duplicate-session',
            'source_kind': 'deadline_plan_block',
            'deadline_plan_block_id': blockIds.first,
          },
        ],
        request,
      );
    });
    addTearDown(client.dispose);
    final source = DashboardFullWeekSupabaseDataSource(
      client,
      resolveUserId: () async => 'owner-id',
    );

    await expectLater(
      source.getBlockFocusFacts(List.generate(101, _uuid)),
      throwsA(isA<DashboardFullWeekDataException>()),
    );
    expect(associationBatch, 2);
  });

  test('an invalid reflection row does not count as fully rated', () async {
    final client = _client((request) async {
      if (request.url.path.endsWith('/focus_session_schedule_sources')) {
        return _json(
          const [
            {
              'focus_session_id': 'session-1',
              'source_kind': 'deadline_plan_block',
              'deadline_plan_block_id': 'block-a',
            },
          ],
          request,
        );
      }
      if (request.url.path.endsWith('/focus_sessions')) {
        return _json(
          const [
            {'id': 'session-1', 'status': 'completed'},
          ],
          request,
        );
      }
      return _json(
        const [
          {
            'focus_session_id': 'session-1',
            'contract_version': 'focus-reflection-v1',
            'focus_quality': 0,
            'useful_progress': 5,
          },
        ],
        request,
      );
    });
    addTearDown(client.dispose);
    final source = DashboardFullWeekSupabaseDataSource(
      client,
      resolveUserId: () async => 'owner-id',
    );

    final result = await source.getBlockFocusFacts(['block-a']);

    expect(result['block-a']!.single.terminal, isTrue);
    expect(result['block-a']!.single.hasValidReflection, isFalse);
  });

  test('reflection transport failure is exposed for partial projection',
      () async {
    final client = _client((request) async {
      if (request.url.path.endsWith('/focus_session_schedule_sources')) {
        return _json(
          const [
            {
              'focus_session_id': 'session-1',
              'source_kind': 'deadline_plan_block',
              'deadline_plan_block_id': 'block-a',
            },
          ],
          request,
        );
      }
      if (request.url.path.endsWith('/focus_sessions')) {
        return _json(
          const [
            {'id': 'session-1', 'status': 'completed'},
          ],
          request,
        );
      }
      return http.Response(
        jsonEncode({'message': 'offline'}),
        503,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.dispose);
    final source = DashboardFullWeekSupabaseDataSource(
      client,
      resolveUserId: () async => 'owner-id',
    );

    await expectLater(
      source.getBlockFocusFacts(['block-a']),
      throwsA(anything),
    );
  });

  test('block request bound fails before any remote read', () async {
    var calls = 0;
    final client = _client((request) async {
      calls += 1;
      return _json(const [], request);
    });
    addTearDown(client.dispose);
    final source = DashboardFullWeekSupabaseDataSource(
      client,
      resolveUserId: () async => 'owner-id',
    );

    await expectLater(
      source.getBlockFocusFacts(
        List.generate(
          maxDashboardFullWeekBlocks + 1,
          (index) => 'block-$index',
        ),
      ),
      throwsA(isA<DashboardFullWeekDataException>()),
    );
    expect(calls, 0);
  });

  test('guest latest and full-week projections make zero Supabase calls',
      () async {
    var calls = 0;
    final client = _client((request) async {
      calls += 1;
      return _json(const [], request);
    });
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        appSurfaceCapabilitiesProvider.overrideWithValue(
          const AppSurfaceCapabilities(
            isLocalDemo: true,
            canUseSyncedHabits: false,
          ),
        ),
        dashboardMockDataSourceProvider.overrideWithValue(
          const DashboardGuestSnapshotAdapter(
            quickCheckInStore: _EmptyQuickCheckInStore(),
          ),
        ),
        supabaseClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    final displayedDate = DateTime(2026, 8, 5);

    final latest = await container.read(
      dashboardLatestCheckInProvider(displayedDate).future,
    );
    final fullWeek = await container.read(
      dashboardFullWeekProvider(displayedDate).future,
    );

    expect(latest, isNull);
    expect(fullWeek.days, hasLength(7));
    expect(calls, 0);
  });

  test('provider keeps official completion when rating reads fail', () async {
    final source = _PartialFullWeekSource();
    final repository = _DeadlineFeedRepository(
      DeadlinePlanFeed.fromJson(
        deadlinePlanFeed(
          plans: [deadlinePlanDetail(status: 'completed')],
        ),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appSurfaceCapabilitiesProvider.overrideWithValue(
          const AppSurfaceCapabilities(
            isLocalDemo: false,
            canUseSyncedHabits: true,
            canUseDeadlinePlanner: true,
          ),
        ),
        dashboardFullWeekDataSourceProvider.overrideWithValue(source),
        deadlinePlanRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      dashboardFullWeekProvider(DateTime(2026, 7, 20)).future,
    );
    final preparation = result.days.expand((day) => day.items).singleWhere(
          (item) => item.kind == DashboardFullWeekItemKind.preparation,
        );

    expect(preparation.status, DashboardAppointmentStatus.completed);
    expect(result.ratingStatusUnavailable, isTrue);
    expect(result.ratingLoadError, contains('Known completed blocks'));
  });

  test(
      'provider owns an early Preparation failure while Setup is still pending',
      () async {
    final commitments = Completer<List<DashboardSetupCommitmentFact>>();
    final container = _fullWeekContainer(
      source: _PendingCommitmentSource(commitments.future),
      repository: const _FailingDeadlineFeedRepository(),
    );
    addTearDown(container.dispose);

    final pending = container.read(
      dashboardFullWeekProvider(DateTime(2026, 8, 5)).future,
    );
    await Future<void>.delayed(Duration.zero);
    commitments.complete(const []);

    final result = await pending;
    expect(result.commitmentLoadError, isNull);
    expect(result.preparationLoadError, contains('could not be loaded'));
    expect(result.hasPartialSourceFailure, isTrue);
    expect(result.days, hasLength(7));
  });

  test('241 transformed blocks preserve a Setup-only partial projection',
      () async {
    final source = _CountingFullWeekSource();
    final repository = _DeadlineFeedRepository(
      DeadlinePlanFeed(
        plans: [
          _planWithBlocks(planIndex: 1, blockCount: 81),
          _planWithBlocks(planIndex: 2, blockCount: 80),
          _planWithBlocks(planIndex: 3, blockCount: 80),
        ],
      ),
    );
    final container = _fullWeekContainer(
      source: source,
      repository: repository,
    );
    addTearDown(container.dispose);

    final result = await container.read(
      dashboardFullWeekProvider(DateTime(2026, 7, 20)).future,
    );
    final items = result.days.expand((day) => day.items).toList();

    expect(items, hasLength(1));
    expect(items.single.kind, DashboardFullWeekItemKind.setupCommitment);
    expect(result.commitmentLoadError, isNull);
    expect(result.preparationLoadError, contains('could not be loaded'));
    expect(result.hasPartialSourceFailure, isTrue);
    expect(source.ratingCalls, 0);
  });

  test('provider fails the whole projection when both core sources fail',
      () async {
    final container = _fullWeekContainer(
      source: const _FailingFullWeekSource(),
      repository: const _FailingDeadlineFeedRepository(),
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(
        dashboardFullWeekProvider(DateTime(2026, 8, 5)).future,
      ),
      throwsA(isA<DashboardFullWeekDataException>()),
    );
  });
}

ProviderContainer _fullWeekContainer({
  required DashboardFullWeekDataSource source,
  required DeadlinePlanRepository repository,
}) =>
    ProviderContainer(
      overrides: [
        appSurfaceCapabilitiesProvider.overrideWithValue(
          const AppSurfaceCapabilities(
            isLocalDemo: false,
            canUseSyncedHabits: true,
            canUseDeadlinePlanner: true,
          ),
        ),
        dashboardFullWeekDataSourceProvider.overrideWithValue(source),
        deadlinePlanRepositoryProvider.overrideWithValue(repository),
      ],
    );

SupabaseClient _client(
  Future<http.Response> Function(http.Request request) handler,
) =>
    SupabaseClient(
      'http://localhost:54321',
      'test-anon-key',
      httpClient: MockClient(handler),
      accessToken: () async => 'test-access-token',
    );

http.Response _json(Object value, http.Request request) => http.Response(
      jsonEncode(value),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );

String _uuid(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

List<String> _filteredIds(Uri uri) => RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    )
        .allMatches(uri.queryParameters['deadline_plan_block_id'] ?? '')
        .map(
          (match) => match.group(0)!,
        )
        .toList(growable: false);

DeadlinePlan _planWithBlocks({
  required int planIndex,
  required int blockCount,
}) {
  final planId = _uuid(900000 + planIndex);
  final json = deadlinePlanDetail();
  final record = json['plan']! as Map<String, dynamic>;
  final revision = json['active_revision']! as Map<String, dynamic>;
  final progress = json['progress']! as Map<String, dynamic>;
  final estimated = blockCount * 50 + 30;
  record
    ..['id'] = planId
    ..['managed_task_id'] = planId
    ..['title'] = 'Preparation $planIndex'
    ..['original_estimated_total_minutes'] = estimated;
  revision
    ..['plan_id'] = planId
    ..['title'] = 'Preparation $planIndex'
    ..['estimated_total_minutes'] = estimated
    ..['tracked_focus_minutes_at_proposal'] = 0
    ..['remaining_minutes_at_proposal'] = blockCount * 50
    ..['planned_minutes'] = blockCount * 50
    ..['unscheduled_minutes'] = 0
    ..['blocks'] = [
      for (var index = 0; index < blockCount; index++)
        deadlineBlock(
          id: _uuid(planIndex * 1000 + index),
          sequence: index + 1,
        ),
    ];
  progress
    ..['estimated_total_minutes'] = estimated
    ..['tracked_focus_minutes'] = 0
    ..['accounted_minutes'] = 30
    ..['remaining_minutes'] = blockCount * 50;
  return DeadlinePlan.fromDetailJson(json);
}

class _PartialFullWeekSource implements DashboardFullWeekDataSource {
  @override
  Future<List<DashboardSetupCommitmentFact>> getSetupCommitments() async =>
      const [];

  @override
  Future<Map<String, List<DashboardBlockFocusFact>>> getBlockFocusFacts(
    Iterable<String> requestedBlockIds,
  ) =>
      throw StateError('reflections offline');
}

class _CountingFullWeekSource implements DashboardFullWeekDataSource {
  int ratingCalls = 0;

  @override
  Future<List<DashboardSetupCommitmentFact>> getSetupCommitments() async =>
      const [
        DashboardSetupCommitmentFact(
          id: 'setup-1',
          title: 'Algorithms lecture',
          weekday: DateTime.monday,
          startsAt: '09:00',
          endsAt: '10:00',
          sortMinutes: 540,
        ),
      ];

  @override
  Future<Map<String, List<DashboardBlockFocusFact>>> getBlockFocusFacts(
    Iterable<String> requestedBlockIds,
  ) async {
    ratingCalls += 1;
    return const {};
  }
}

class _DeadlineFeedRepository implements DeadlinePlanRepository {
  const _DeadlineFeedRepository(this.feed);

  final DeadlinePlanFeed feed;

  @override
  Future<DeadlinePlanFeed> getPlans() async => feed;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingCommitmentSource implements DashboardFullWeekDataSource {
  const _PendingCommitmentSource(this.commitments);

  final Future<List<DashboardSetupCommitmentFact>> commitments;

  @override
  Future<List<DashboardSetupCommitmentFact>> getSetupCommitments() =>
      commitments;

  @override
  Future<Map<String, List<DashboardBlockFocusFact>>> getBlockFocusFacts(
    Iterable<String> requestedBlockIds,
  ) async =>
      const {};
}

class _FailingFullWeekSource implements DashboardFullWeekDataSource {
  const _FailingFullWeekSource();

  @override
  Future<List<DashboardSetupCommitmentFact>> getSetupCommitments() async =>
      throw StateError('setup offline');

  @override
  Future<Map<String, List<DashboardBlockFocusFact>>> getBlockFocusFacts(
    Iterable<String> requestedBlockIds,
  ) async =>
      const {};
}

class _FailingDeadlineFeedRepository implements DeadlinePlanRepository {
  const _FailingDeadlineFeedRepository();

  @override
  Future<DeadlinePlanFeed> getPlans() async =>
      throw StateError('preparation offline');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyQuickCheckInStore implements QuickCheckInStore {
  const _EmptyQuickCheckInStore();

  @override
  QuickCheckInSaveTarget get target => QuickCheckInSaveTarget.guest;

  @override
  Future<DailyCaptureEntry?> loadToday(DateTime today) async => null;

  @override
  Future<EveningShutdownDraft?> loadLatestEvening() async => null;

  @override
  Future<void> saveEvening(EveningShutdownDraft draft) async {}

  @override
  Future<void> saveMorning(MorningCalibrationDraft draft) async {}
}
