import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
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

String _successfulSse({String responseRequestId = coachRequestId}) => _sse([
      (
        'started',
        {
          'request_id': coachRequestId,
          'contract_version': 'coach-request-v3',
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
  }) : super(Dio());

  final Map<String, Map<String, dynamic>> getResponses;
  final String responseSse;
  final List<int>? responseBytes;
  final bool throwOnRequest;
  final List<String> getCalls = [];
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
    if (throwOnRequest) throw StateError('Unexpected HTTP request');
  }
}
