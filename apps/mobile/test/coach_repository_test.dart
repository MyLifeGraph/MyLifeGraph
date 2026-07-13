import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/coach/data/coach_api_data_source.dart';
import 'package:my_life_graph/features/coach/data/coach_repository_impl.dart';
import 'package:my_life_graph/features/coach/domain/coach.dart';
import 'package:my_life_graph/features/coach/domain/coach_repository.dart';

import 'support/coach_fixtures.dart';

void main() {
  const config = AppConfig(
    environment: 'test',
    supabaseUrl: 'http://127.0.0.1:54321',
    supabaseAnonKey: 'anon-key',
    aiServiceBaseUrl: 'http://127.0.0.1:8000',
    useMockData: false,
  );

  test('reads are GET-only and response sends exact bearer/body/timeout',
      () async {
    final client = _TrackingApiClient(
      getResponses: {
        '/v1/coach/capabilities': coachCapabilitiesJson(),
        '/v1/coach/history': coachHistoryJson(),
        '/v1/coach/memories': coachMemoriesJson(),
      },
      timedPostResponses: {
        '/v1/coach/respond': coachResponseJson(),
      },
    );
    final repository = _repository(client, config: config);

    final capability = await repository.getCapabilities();
    final history = await repository.getHistory();
    final memories = await repository.getMemories();
    final response = await repository.respond(
      requestId: coachRequestId,
      message: '  What matters today?  ',
      receiveTimeout: const Duration(seconds: 55),
    );

    expect(capability.state, CoachCapabilityState.ready);
    expect(history.turns, hasLength(1));
    expect(memories.memories, hasLength(2));
    expect(response.requestId, coachRequestId);
    expect(client.getCalls, [
      '/v1/coach/capabilities',
      '/v1/coach/history',
      '/v1/coach/memories',
    ]);
    expect(client.timedPostCalls, ['/v1/coach/respond']);
    expect(client.headersByPath['/v1/coach/respond'], {
      'Authorization': 'Bearer account-token',
    });
    expect(client.bodyByPath['/v1/coach/respond'], {
      'contract_version': 'coach-request-v1',
      'request_id': coachRequestId,
      'message': 'What matters today?',
      'context_scope': 'today',
    });
    expect(
      client.timeoutByPath['/v1/coach/respond'],
      const Duration(seconds: 55),
    );
    expect(client.cancelTokenByPath['/v1/coach/respond'], isNotNull);
  });

  test('history deletion and memory selection use only exact endpoints',
      () async {
    final selectionPath = '/v1/coach/memories/$coachMemoryId/selection';
    final client = _TrackingApiClient(
      postResponses: {
        selectionPath: coachMemoriesJson(),
      },
      deleteResponses: {
        '/v1/coach/history': coachHistoryDeleteJson(),
        selectionPath: coachMemoriesJson(
          memories: [
            coachMemoryJson(selected: false),
            coachMemoryJson(
              id: coachManualMemoryId,
              type: 'pattern',
              title: 'Afternoon energy dip',
              content: 'Energy often drops later.',
              ownership: 'manual',
              selected: false,
            ),
          ],
        ),
      },
    );
    final repository = _repository(client, config: config);

    await repository.selectMemory(coachMemoryId);
    await repository.deselectMemory(coachMemoryId);
    final deletion = await repository.deleteHistory();

    expect(deletion.deleted, isTrue);
    expect(client.postCalls, [selectionPath]);
    expect(client.bodyByPath[selectionPath], {'selected': true});
    expect(client.deleteCalls, [selectionPath, '/v1/coach/history']);
    expect(
      client.headersByPath.values,
      everyElement({'Authorization': 'Bearer account-token'}),
    );
  });

  test('guest and mock source returns local truth with zero HTTP calls',
      () async {
    final client = _TrackingApiClient(throwOnRequest: true);
    final repository = _repository(
      client,
      config: config,
      isLocalDemo: true,
      canAccessCoachBackend: false,
      token: null,
    );

    final capability = await repository.getCapabilities();
    final history = await repository.getHistory();
    final memories = await repository.getMemories();

    expect(capability.state, CoachCapabilityState.disabled);
    expect(capability.reasonCode, 'local_demo');
    expect(history.turns, isEmpty);
    expect(memories.memories, isEmpty);
    await expectLater(
      repository.respond(
        requestId: coachRequestId,
        message: 'Hello',
        receiveTimeout: const Duration(seconds: 55),
      ),
      throwsA(isA<CoachAccessException>()),
    );
    await expectLater(
      repository.deleteHistory(),
      throwsA(isA<CoachAccessException>()),
    );
    expect(client.totalCalls, 0);
  });

  test('missing config, token, or synced capability fails before HTTP',
      () async {
    final client = _TrackingApiClient(throwOnRequest: true);
    final noConfig = _repository(
      client,
      config: const AppConfig(
        environment: 'test',
        supabaseUrl: '',
        supabaseAnonKey: '',
        aiServiceBaseUrl: 'http://127.0.0.1:8000',
        useMockData: false,
      ),
    );
    final noToken = _repository(client, config: config, token: ' ');
    final noCapability = _repository(
      client,
      config: config,
      canAccessCoachBackend: false,
    );

    await expectLater(
      noConfig.getCapabilities(),
      throwsA(isA<CoachAccessException>()),
    );
    await expectLater(
      noToken.getHistory(),
      throwsA(isA<CoachAccessException>()),
    );
    await expectLater(
      noCapability.getMemories(),
      throwsA(isA<CoachAccessException>()),
    );
    expect(client.totalCalls, 0);
  });

  test('exact backend error detail is typed and sanitized', () async {
    final request = RequestOptions(path: '/v1/coach/respond');
    final client = _TrackingApiClient(
      timedPostError: AppException(
        'Network request failed',
        cause: DioException(
          requestOptions: request,
          type: DioExceptionType.badResponse,
          response: Response<Map<String, dynamic>>(
            requestOptions: request,
            statusCode: 409,
            data: {
              'detail': {
                'code': 'in_progress',
                'message': 'This Coach request is still in progress.',
                'retryable': true,
              },
            },
          ),
        ),
      ),
    );
    final repository = _repository(client, config: config);

    await expectLater(
      repository.respond(
        requestId: coachRequestId,
        message: 'Hello',
        receiveTimeout: const Duration(seconds: 55),
      ),
      throwsA(
        isA<CoachRemoteException>()
            .having((error) => error.code, 'code', 'in_progress')
            .having(
              (error) => error.preservesRequestIdentity,
              'preserves request identity',
              isTrue,
            ),
      ),
    );
  });

  test('response id mismatch is rejected as invalid success', () async {
    final client = _TrackingApiClient(
      timedPostResponses: {
        '/v1/coach/respond': coachResponseJson(
          requestId: coachSecondRequestId,
        ),
      },
    );
    final repository = _repository(client, config: config);

    await expectLater(
      repository.respond(
        requestId: coachRequestId,
        message: 'Hello',
        receiveTimeout: const Duration(seconds: 55),
      ),
      throwsA(isA<CoachContractException>()),
    );
  });

  test('active response exposes cancellation to page disposal', () async {
    final client = _TrackingApiClient(blockTimedPostUntilCancelled: true);
    final repository = _repository(client, config: config);

    final response = repository.respond(
      requestId: coachRequestId,
      message: 'Wait for this response',
      receiveTimeout: const Duration(seconds: 55),
    );
    await Future<void>.delayed(Duration.zero);
    repository.cancelActiveResponse();

    await expectLater(
      response,
      throwsA(
        isA<AppException>().having(
          (error) => (error.cause as DioException).type,
          'Dio cancellation',
          DioExceptionType.cancel,
        ),
      ),
    );
  });
}

CoachRepositoryImpl _repository(
  _TrackingApiClient client, {
  required AppConfig config,
  bool isLocalDemo = false,
  bool canAccessCoachBackend = true,
  String? token = ' account-token ',
}) =>
    CoachRepositoryImpl(
      config: config,
      apiDataSource: CoachApiDataSource(client),
      accessTokenProvider: () => token,
      isLocalDemo: isLocalDemo,
      canAccessCoachBackend: canAccessCoachBackend,
    );

class _TrackingApiClient extends ApiClient {
  _TrackingApiClient({
    this.getResponses = const {},
    this.postResponses = const {},
    this.timedPostResponses = const {},
    this.deleteResponses = const {},
    this.timedPostError,
    this.throwOnRequest = false,
    this.blockTimedPostUntilCancelled = false,
  }) : super(Dio());

  final Map<String, Map<String, dynamic>> getResponses;
  final Map<String, Map<String, dynamic>> postResponses;
  final Map<String, Map<String, dynamic>> timedPostResponses;
  final Map<String, Map<String, dynamic>> deleteResponses;
  final Object? timedPostError;
  final bool throwOnRequest;
  final bool blockTimedPostUntilCancelled;
  final List<String> getCalls = [];
  final List<String> postCalls = [];
  final List<String> timedPostCalls = [];
  final List<String> deleteCalls = [];
  final Map<String, Map<String, dynamic>?> bodyByPath = {};
  final Map<String, Map<String, String>?> headersByPath = {};
  final Map<String, Duration> timeoutByPath = {};
  final Map<String, CancelToken?> cancelTokenByPath = {};

  int get totalCalls =>
      getCalls.length +
      postCalls.length +
      timedPostCalls.length +
      deleteCalls.length;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    _guard();
    getCalls.add(path);
    headersByPath[path] = headers;
    return getResponses[path] ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    _guard();
    postCalls.add(path);
    bodyByPath[path] = body;
    headersByPath[path] = headers;
    return postResponses[path] ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> postJsonWithTimeout(
    String path, {
    required Duration receiveTimeout,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    _guard();
    timedPostCalls.add(path);
    bodyByPath[path] = body;
    headersByPath[path] = headers;
    timeoutByPath[path] = receiveTimeout;
    cancelTokenByPath[path] = cancelToken;
    if (timedPostError != null) throw timedPostError!;
    if (blockTimedPostUntilCancelled) {
      final cancellation = await cancelToken!.whenCancel;
      throw AppException('Network request failed', cause: cancellation);
    }
    return timedPostResponses[path] ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    _guard();
    deleteCalls.add(path);
    headersByPath[path] = headers;
    return deleteResponses[path] ?? <String, dynamic>{};
  }

  void _guard() {
    if (throwOnRequest) throw StateError('Unexpected HTTP request');
  }
}
