import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/deadline_plans/data/assignment_series_api_data_source.dart';
import 'package:my_life_graph/features/deadline_plans/data/assignment_series_repository_impl.dart';
import 'package:my_life_graph/features/deadline_plans/domain/assignment_series.dart';

import 'support/assignment_series_fixtures.dart';

void main() {
  test('series repository uses exact owner endpoints, bearer, and bodies',
      () async {
    final client = _TrackingApiClient(
      getResponses: {
        '/v1/deadline-plans/assignment-series': assignmentSeriesFeed(),
      },
      postResponses: {
        '/v1/deadline-plans/assignment-series/proposals':
            assignmentSeriesEnvelope(),
        '/v1/deadline-plans/assignment-series/$assignmentSeriesId/confirm':
            assignmentSeriesEnvelope(status: 'active'),
        '/v1/deadline-plans/assignment-series/$assignmentSeriesId/cancel-future':
            assignmentSeriesEnvelope(status: 'cancelled'),
      },
    );
    final repository = _repository(client);
    final draft = _draft();

    final feed = await repository.getSeries();
    final proposed = await repository.propose(
      requestId: assignmentSeriesRequestId,
      draft: draft,
    );
    final confirmed = await repository.confirm(
      seriesId: assignmentSeriesId,
      requestId: '33333333-3333-4333-8333-333333333333',
      expectedRevision: 1,
    );
    final cancelled = await repository.cancelFuture(
      seriesId: assignmentSeriesId,
      requestId: '44444444-4444-4444-8444-444444444444',
      expectedRevision: 1,
    );

    expect(feed.series, hasLength(1));
    expect(proposed.hasPendingPreview, isTrue);
    expect(confirmed.isActive, isTrue);
    expect(cancelled.isCancelled, isTrue);
    expect(client.getCalls, ['/v1/deadline-plans/assignment-series']);
    expect(client.postCalls, [
      '/v1/deadline-plans/assignment-series/proposals',
      '/v1/deadline-plans/assignment-series/$assignmentSeriesId/confirm',
      '/v1/deadline-plans/assignment-series/$assignmentSeriesId/cancel-future',
    ]);
    expect(
      client.bodyByPath['/v1/deadline-plans/assignment-series/proposals'],
      draft.toJson(requestId: assignmentSeriesRequestId),
    );
    for (final path in client.getCalls.followedBy(client.postCalls)) {
      expect(client.headersByPath[path], {
        'Authorization': 'Bearer account-token',
      });
    }
  });

  test('non-synced and missing-token series stay zero-call', () async {
    final client = _TrackingApiClient(throwOnRequest: true);
    final local = _repository(client, canUseSyncedPlanner: false);
    final missingToken = _repository(client, token: ' ');

    await expectLater(
      local.getSeries(),
      throwsA(isA<AssignmentSeriesAccessException>()),
    );
    await expectLater(
      missingToken.propose(
        requestId: assignmentSeriesRequestId,
        draft: _draft(),
      ),
      throwsA(isA<AssignmentSeriesAccessException>()),
    );
    expect(client.totalCalls, 0);
  });
}

AssignmentSeriesProposalDraft _draft() => AssignmentSeriesProposalDraft(
      seriesId: assignmentSeriesId,
      baseRevision: 0,
      title: 'Weekly algorithms sheet',
      nextDeadlineAt: DateTime.parse('2026-08-17T17:00:00+02:00'),
      remainingOccurrences: 12,
      estimatedTotalMinutes: 90,
      preferredSessionMinutes: 30,
      maxDailyMinutes: 60,
      bufferDays: 1,
      useCalendarAvailability: false,
    );

AssignmentSeriesRepositoryImpl _repository(
  _TrackingApiClient client, {
  bool canUseSyncedPlanner = true,
  String? token = ' account-token ',
}) =>
    AssignmentSeriesRepositoryImpl(
      config: const AppConfig(
        environment: 'test',
        supabaseUrl: 'http://127.0.0.1:54321',
        supabaseAnonKey: 'anon-key',
        aiServiceBaseUrl: 'http://127.0.0.1:8000',
        useMockData: false,
      ),
      apiDataSource: AssignmentSeriesApiDataSource(client),
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
