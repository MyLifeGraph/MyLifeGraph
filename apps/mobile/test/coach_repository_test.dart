import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/core/network/api_failure.dart';
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
  const pilotConfig = AppConfig(
    environment: 'pilot',
    supabaseUrl: 'https://bcdefghijklmnopqrstu.supabase.co',
    supabasePublishableKey: 'sb_publishable_test-value',
    stagingSupabaseProjectRef: 'abcdefghijklmnopqrst',
    pilotSupabaseProjectRef: 'bcdefghijklmnopqrstu',
    pilotContactEmail: 'pilot@example.test',
    aiServiceBaseUrl: 'https://coach.example.test',
    useMockData: false,
  );

  test('reads and streams exact V3 request without a mode', () async {
    final client = _TrackingApiClient(
      getResponses: {
        '/v1/coach/capabilities': coachCapabilitiesJson(),
        '/v1/coach/history': coachHistoryJson(),
      },
      responseSse: _successfulSse(),
    );
    final repository = _repository(client, config: config);

    expect((await repository.getCapabilities()).canRespond, isTrue);
    expect((await repository.getHistory()).turns, hasLength(1));
    final events = await repository
        .respond(
          requestId: coachRequestId,
          message: '  Compare all available data.  ',
        )
        .toList();

    expect(
      events.whereType<CoachActivityEvent>().single.message,
      contains('history'),
    );
    expect(events.whereType<CoachCompletedEvent>(), hasLength(1));
    expect(client.streamPath, '/v1/coach/respond/stream');
    expect(client.requestBody, {
      'contract_version': 'coach-request-v3',
      'request_id': coachRequestId,
      'message': 'Compare all available data.',
    });
    expect(client.requestBody, isNot(contains('context_scope')));
    expect(client.streamHeaders?['Accept'], 'text/event-stream');
    expect(client.streamTimeout, const Duration(seconds: 190));
  });

  test('SSE failed event becomes a typed remote error', () async {
    final client = _TrackingApiClient(
      responseSse: _sse([
        (
          'started',
          {
            'request_id': coachRequestId,
            'contract_version': 'coach-request-v3',
          },
        ),
        (
          'failed',
          {
            'error': {
              'code': 'account_limit',
              'message': 'Daily limit reached.',
              'retryable': true,
            },
          },
        ),
      ]),
    );
    final repository = _repository(client, config: config);

    await expectLater(
      repository.respond(requestId: coachRequestId, message: 'Hello'),
      emitsInOrder([
        isA<CoachStartedEvent>(),
        emitsError(
          isA<CoachRemoteException>()
              .having((value) => value.code, 'code', 'account_limit')
              .having((value) => value.isRateLimited, 'rate limited', isTrue),
        ),
      ]),
    );
  });

  test('SSE global Project Coach limit remains a typed 429', () async {
    final client = _TrackingApiClient(
      responseSse: _sse([
        (
          'started',
          {
            'request_id': coachRequestId,
            'contract_version': 'coach-request-v3',
          },
        ),
        (
          'failed',
          {
            'error': {
              'code': 'provider_limit',
              'message': 'Shared provider limit reached.',
              'retryable': true,
            },
          },
        ),
      ]),
    );
    final repository = _repository(client, config: config);

    await expectLater(
      repository.respond(requestId: coachRequestId, message: 'Hello'),
      emitsInOrder([
        isA<CoachStartedEvent>(),
        emitsError(
          isA<CoachRemoteException>()
              .having((value) => value.code, 'code', 'provider_limit')
              .having((value) => value.statusCode, 'statusCode', 429)
              .having((value) => value.isRateLimited, 'rate limited', isTrue),
        ),
      ]),
    );
  });

  test('transport timeout becomes a typed replay-safe remote outcome',
      () async {
    final repository = _repository(
      _TrackingApiClient(
        requestError: const AppException(
          'Network request failed',
          cause: ApiFailure(kind: ApiFailureKind.timeout),
        ),
      ),
      config: config,
    );

    await expectLater(
      repository.getCapabilities(),
      throwsA(
        isA<CoachRemoteException>()
            .having((value) => value.code, 'code', 'network_error')
            .having((value) => value.timedOut, 'timedOut', isTrue)
            .having(
              (value) => value.preservesRequestIdentity,
              'preservesRequestIdentity',
              isTrue,
            ),
      ),
    );
  });

  for (final admission in const [
    (code: 'route_busy', retryAfter: 1),
    (code: 'route_rate_limited', retryAfter: 60),
  ]) {
    test('HTTP ${admission.code} remains a typed transient admission outcome',
        () async {
      final repository = _repository(
        _TrackingApiClient(
          requestError: AppException(
            'Network request failed',
            cause: ApiFailure(
              kind: ApiFailureKind.response,
              statusCode: 429,
              responseData: {
                'detail': {
                  'code': admission.code,
                  'message': 'The public service is temporarily rate limited.',
                  'retryable': true,
                },
              },
              retryAfterSeconds: admission.retryAfter,
            ),
          ),
        ),
        config: config,
      );

      await expectLater(
        repository.getCapabilities(),
        throwsA(
          isA<CoachRemoteException>()
              .having((value) => value.code, 'code', admission.code)
              .having(
                (value) => value.retryAfterSeconds,
                'retryAfterSeconds',
                admission.retryAfter,
              )
              .having(
                (value) => value.isTransientAdmission,
                'isTransientAdmission',
                isTrue,
              )
              .having((value) => value.isRateLimited, 'isRateLimited', isFalse)
              .having(
                (value) => value.preservesRequestIdentity,
                'preservesRequestIdentity',
                isTrue,
              ),
        ),
      );
    });
  }

  test('guest uses local read truth and never calls HTTP', () async {
    final client = _TrackingApiClient(throwOnRequest: true);
    final repository = _repository(
      client,
      config: config,
      isLocalDemo: true,
      canAccessCoachBackend: false,
      token: null,
    );

    expect(
      (await repository.getCapabilities()).state,
      CoachCapabilityState.disabled,
    );
    expect((await repository.getHistory()).turns, isEmpty);
    await expectLater(
      repository.respond(requestId: coachRequestId, message: 'Hello'),
      emitsError(isA<CoachAccessException>()),
    );
    expect(client.totalCalls, 0);
  });

  test('completed event with another request id is rejected', () async {
    final client = _TrackingApiClient(
      responseSse: _successfulSse(responseRequestId: coachSecondRequestId),
    );
    final repository = _repository(client, config: config);

    await expectLater(
      repository.respond(requestId: coachRequestId, message: 'Hello'),
      emitsInOrder([
        isA<CoachStartedEvent>(),
        isA<CoachActivityEvent>(),
        emitsError(isA<CoachContractException>()),
      ]),
    );
  });

  test('SSE rejects unsafe activity copy and oversized responses', () async {
    final unsafeActivity = _repository(
      _TrackingApiClient(
        responseSse: _sse([
          (
            'started',
            {
              'request_id': coachRequestId,
              'contract_version': 'coach-request-v3',
            },
          ),
          (
            'activity',
            {'message': 'Internal reasoning: inspect every hidden token.'},
          ),
        ]),
      ),
      config: config,
    );
    await expectLater(
      unsafeActivity.respond(requestId: coachRequestId, message: 'Hello'),
      emitsInOrder([
        isA<CoachStartedEvent>(),
        emitsError(isA<CoachContractException>()),
      ]),
    );

    final oversized = _repository(
      _TrackingApiClient(responseSse: 'x' * (512 * 1024 + 1)),
      config: config,
    );
    await expectLater(
      oversized.respond(requestId: coachRequestId, message: 'Hello'),
      emitsError(isA<CoachContractException>()),
    );
  });

  test('SSE maps malformed UTF-8 to a replay-safe contract error', () async {
    final started = utf8.encode(
      'event: started\n'
      'data: {"request_id":"$coachRequestId",'
      '"contract_version":"coach-request-v3"}\n\n',
    );
    final repository = _repository(
      _TrackingApiClient(
        responseBytes: [...started, 0xc3, 0x28],
      ),
      config: config,
    );

    await expectLater(
      repository.respond(requestId: coachRequestId, message: 'Hello'),
      emitsError(isA<CoachContractException>()),
    );
  });

  test('hosted Project Coach sends V4 provider header without any key',
      () async {
    final client = _TrackingApiClient(
      getResponses: {
        '/v1/coach/capabilities': coachCapabilitiesJson(
          provider: 'operator_codex_pilot',
          providerMode: 'operator_subscription_pilot',
          modelRequested: 'gpt-5.5',
          modelSource: 'explicit',
          serviceTier: 'fast',
          fastMode: true,
          requestsPerLocalDay: 5,
          remainingRequests: 5,
          globalRequestsPerUtcDay: 15,
          globalRemainingRequests: 15,
        ),
      },
      responseSse: _successfulSse(
        requestContractVersion: 'coach-request-v4',
      ),
    );
    final repository = _repository(
      client,
      config: pilotConfig,
      credentials: const CoachProviderCredentials(
        provider: CoachProviderName.operatorCodexPilot,
      ),
    );

    final capability = await repository.getCapabilities();
    final events = await repository
        .respond(requestId: coachRequestId, message: 'Compare my data.')
        .toList();

    expect(capability.provider, CoachProviderName.operatorCodexPilot);
    expect(
      client.lastGetHeaders?['X-MyLifeGraph-Coach-Provider'],
      'operator_codex_pilot',
    );
    expect(
      client.lastGetHeaders,
      isNot(contains('X-MyLifeGraph-Coach-Api-Key')),
    );
    expect(
      client.streamHeaders?['X-MyLifeGraph-Coach-Provider'],
      'operator_codex_pilot',
    );
    expect(
      client.streamHeaders,
      isNot(contains('X-MyLifeGraph-Coach-Api-Key')),
    );
    expect(client.requestBody?['contract_version'], 'coach-request-v4');
    expect(events.whereType<CoachCompletedEvent>(), hasLength(1));
  });

  test('hosted Coach refuses sending before an explicit selection', () async {
    final client = _TrackingApiClient(throwOnRequest: true);
    final repository = _repository(client, config: pilotConfig);

    await expectLater(
      repository.getCapabilities(),
      throwsA(isA<CoachAccessException>()),
    );
    await expectLater(
      repository.respond(requestId: coachRequestId, message: 'Hello'),
      emitsError(isA<CoachAccessException>()),
    );
    expect(client.totalCalls, 0);
  });
}

CoachRepositoryImpl _repository(
  _TrackingApiClient client, {
  required AppConfig config,
  bool isLocalDemo = false,
  bool canAccessCoachBackend = true,
  String? token = ' account-token ',
  CoachProviderCredentials? credentials,
}) =>
    CoachRepositoryImpl(
      config: config,
      apiDataSource: CoachApiDataSource(client),
      accessTokenProvider: () => token,
      isLocalDemo: isLocalDemo,
      canAccessCoachBackend: canAccessCoachBackend,
      credentialsProvider: () => credentials,
    );

String _successfulSse({
  String responseRequestId = coachRequestId,
  String requestContractVersion = 'coach-request-v3',
}) =>
    _sse([
      (
        'started',
        {
          'request_id': coachRequestId,
          'contract_version': requestContractVersion,
        },
      ),
      (
        'activity',
        {'message': 'Checking relevant history …'},
      ),
      (
        'completed',
        {'response': coachResponseJson(requestId: responseRequestId)},
      ),
    ]);

String _sse(List<(String, Map<String, dynamic>)> events) => events
    .map(
      (value) => 'event: ${value.$1}\ndata: ${jsonEncode(value.$2)}\n\n',
    )
    .join();

class _TrackingApiClient extends ApiClient {
  _TrackingApiClient({
    this.getResponses = const {},
    this.responseSse = '',
    this.responseBytes,
    this.throwOnRequest = false,
    this.requestError,
  }) : super(Dio());

  final Map<String, Map<String, dynamic>> getResponses;
  final String responseSse;
  final List<int>? responseBytes;
  final bool throwOnRequest;
  final Object? requestError;
  final List<String> getCalls = [];
  Map<String, String>? lastGetHeaders;
  String? streamPath;
  Map<String, dynamic>? requestBody;
  Map<String, String>? streamHeaders;
  Duration? streamTimeout;

  int get totalCalls => getCalls.length + (streamPath == null ? 0 : 1);

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    _guard();
    getCalls.add(path);
    lastGetHeaders = headers;
    return getResponses[path] ?? <String, dynamic>{};
  }

  @override
  Future<ResponseBody> postStream(
    String path, {
    required Map<String, dynamic> body,
    required Duration receiveTimeout,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    _guard();
    streamPath = path;
    requestBody = body;
    streamHeaders = headers;
    streamTimeout = receiveTimeout;
    final bytes = responseBytes;
    return bytes == null
        ? ResponseBody.fromString(responseSse, 200)
        : ResponseBody.fromBytes(bytes, 200);
  }

  void _guard() {
    final error = requestError;
    if (error != null) throw error;
    if (throwOnRequest) throw StateError('Unexpected HTTP request');
  }
}
