import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/deadline_plans/data/deadline_plan_api_data_source.dart';
import 'package:my_life_graph/features/deadline_plans/data/deadline_plan_repository_impl.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_plan.dart';

import 'support/deadline_plan_fixtures.dart';

void main() {
  test('read and proposal use exact endpoints, bearer, and body', () async {
    final client = _TrackingApiClient(
      getResponses: {
        '/v1/deadline-plans': deadlinePlanFeed(),
        '/v1/deadline-plans/workload': preparationWorkloadEnvelope(),
        '/v1/deadline-plans/workload/2026-07-20':
            preparationWorkloadDetailEnvelope(),
      },
      postResponses: {
        '/v1/deadline-plans/proposals': deadlinePlanEnvelope(status: 'draft'),
      },
    );
    final repository = _repository(client);
    final draft = _draft();

    final feed = await repository.getPlans();
    final workload = await repository.getWorkload();
    final workloadDetail = await repository.getWorkloadDetail('2026-07-20');
    final proposed = await repository.propose(
      requestId: deadlineRequestId,
      draft: draft,
    );

    expect(feed.plans, hasLength(1));
    expect(workload.dailyPreparationBudgetMinutes, 120);
    expect(workloadDetail.contributions, hasLength(2));
    expect(proposed.isDraft, isTrue);
    expect(
      client.getCalls,
      [
        '/v1/deadline-plans',
        '/v1/deadline-plans/workload',
        '/v1/deadline-plans/workload/2026-07-20',
      ],
    );
    expect(client.postCalls, ['/v1/deadline-plans/proposals']);
    expect(client.headersByPath['/v1/deadline-plans'], {
      'Authorization': 'Bearer account-token',
    });
    expect(client.headersByPath['/v1/deadline-plans/workload'], {
      'Authorization': 'Bearer account-token',
    });
    expect(
      client.headersByPath['/v1/deadline-plans/workload/2026-07-20'],
      {'Authorization': 'Bearer account-token'},
    );
    expect(client.bodyByPath['/v1/deadline-plans/proposals'], {
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
      'use_calendar_availability': false,
    });
  });

  test('workload detail rejects an invalid or mismatched date', () async {
    final mismatched = preparationWorkloadDetailEnvelope()
      ..['local_date'] = '2026-07-21';
    final repository = _repository(
      _TrackingApiClient(
        getResponses: {
          '/v1/deadline-plans/workload/2026-07-20': mismatched,
        },
      ),
    );

    await expectLater(
      repository.getWorkloadDetail('not-a-date'),
      throwsA(isA<DeadlinePlanAccessException>()),
    );
    await expectLater(
      repository.getWorkloadDetail('2026-07-20'),
      throwsA(isA<DeadlinePlanContractException>()),
    );
  });

  test('lifecycle uses exact expected revision only', () async {
    final client = _TrackingApiClient(
      postResponses: {
        '/v1/deadline-plans/$deadlinePlanId/confirm': deadlinePlanEnvelope(),
        '/v1/deadline-plans/$deadlinePlanId/complete':
            deadlinePlanEnvelope(status: 'completed'),
        '/v1/deadline-plans/$deadlinePlanId/cancel':
            deadlinePlanEnvelope(status: 'cancelled'),
      },
    );
    final repository = _repository(client);

    await repository.confirm(
      planId: deadlinePlanId,
      requestId: deadlineRequestId,
      expectedRevision: 1,
    );
    await repository.complete(
      planId: deadlinePlanId,
      requestId: '44444444-4444-4444-8444-444444444444',
      expectedRevision: 1,
    );
    await repository.cancel(
      planId: deadlinePlanId,
      requestId: '55555555-5555-4555-8555-555555555555',
      expectedRevision: 1,
    );

    for (final path in client.postCalls) {
      expect(
        client.bodyByPath[path]!.keys,
        {'request_id', 'expected_revision'},
      );
      expect(client.bodyByPath[path]!['expected_revision'], 1);
    }
  });

  test('exact replay accepts a newer current plan projection', () async {
    final newerProjection = deadlinePlanEnvelope(status: 'completed');
    final identity = newerProjection['plan'] as Map<String, dynamic>;
    final active = newerProjection['active_revision'] as Map<String, dynamic>;
    identity
      ..['current_revision'] = 2
      ..['latest_revision'] = 2;
    active
      ..['revision'] = 2
      ..['base_revision'] = 1;
    final client = _TrackingApiClient(
      postResponses: {
        '/v1/deadline-plans/proposals': newerProjection,
        '/v1/deadline-plans/$deadlinePlanId/confirm': newerProjection,
      },
    );
    final repository = _repository(client);

    final proposalReplay = await repository.propose(
      requestId: deadlineRequestId,
      draft: _draft(),
    );
    final confirmReplay = await repository.confirm(
      planId: deadlinePlanId,
      requestId: '44444444-4444-4444-8444-444444444444',
      expectedRevision: 1,
    );

    expect(proposalReplay.status, DeadlinePlanStatus.completed);
    expect(proposalReplay.currentRevision, 2);
    expect(confirmReplay.status, DeadlinePlanStatus.completed);
    expect(confirmReplay.currentRevision, 2);
  });

  test('non-synced and missing token stay zero-call', () async {
    final client = _TrackingApiClient(throwOnRequest: true);
    final nonSynced = _repository(client, canUseSyncedPlanner: false);
    final noToken = _repository(client, token: ' ');

    await expectLater(
      nonSynced.getPlans(),
      throwsA(isA<DeadlinePlanAccessException>()),
    );
    await expectLater(
      nonSynced.getWorkload(),
      throwsA(isA<DeadlinePlanAccessException>()),
    );
    await expectLater(
      nonSynced.getWorkloadDetail('2026-07-20'),
      throwsA(isA<DeadlinePlanAccessException>()),
    );
    await expectLater(
      noToken.getPlans(),
      throwsA(isA<DeadlinePlanAccessException>()),
    );
    await expectLater(
      noToken.getWorkloadDetail('2026-07-20'),
      throwsA(isA<DeadlinePlanAccessException>()),
    );
    expect(client.totalCalls, 0);
  });
}

DeadlinePlanProposalDraft _draft() => DeadlinePlanProposalDraft(
      planId: deadlinePlanId,
      baseRevision: 0,
      kind: DeadlinePlanKind.exam,
      title: 'Algorithms exam',
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
      useCalendarAvailability: false,
    );

DeadlinePlanRepositoryImpl _repository(
  _TrackingApiClient client, {
  bool canUseSyncedPlanner = true,
  String? token = ' account-token ',
}) =>
    DeadlinePlanRepositoryImpl(
      config: const AppConfig(
        environment: 'test',
        supabaseUrl: 'http://127.0.0.1:54321',
        supabaseAnonKey: 'anon-key',
        aiServiceBaseUrl: 'http://127.0.0.1:8000',
        useMockData: false,
      ),
      apiDataSource: DeadlinePlanApiDataSource(client),
      accessTokenProvider: () => token,
      canUseSyncedPlanner: canUseSyncedPlanner,
    );

class _TrackingApiClient extends ApiClient {
  _TrackingApiClient({
    this.getResponses = const {},
    this.postResponses = const {},
    this.throwOnRequest = false,
  }) : super(Dio());

  final Map<String, Map<String, dynamic>> getResponses;
  final Map<String, Map<String, dynamic>> postResponses;
  final bool throwOnRequest;
  final List<String> getCalls = [];
  final List<String> postCalls = [];
  final Map<String, Map<String, dynamic>?> bodyByPath = {};
  final Map<String, Map<String, String>?> headersByPath = {};

  int get totalCalls => getCalls.length + postCalls.length;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    if (throwOnRequest) throw StateError('Network must not be used.');
    getCalls.add(path);
    headersByPath[path] = headers;
    return getResponses[path] ?? (throw StateError('Missing GET $path'));
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    if (throwOnRequest) throw StateError('Network must not be used.');
    postCalls.add(path);
    bodyByPath[path] = body;
    headersByPath[path] = headers;
    return postResponses[path] ?? (throw StateError('Missing POST $path'));
  }
}
