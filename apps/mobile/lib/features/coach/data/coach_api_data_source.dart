import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/contracts/strict_contract.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import '../domain/coach.dart';
import '../domain/coach_repository.dart';

class CoachApiDataSource {
  const CoachApiDataSource(this._client);

  final ApiClient _client;

  Future<CoachCapabilities> getCapabilities({
    required String accessToken,
  }) async {
    final json = await _guardRemote(
      () => _client.getJson(
        '/v1/coach/capabilities',
        headers: _headers(accessToken),
      ),
    );
    return CoachCapabilities.fromJson(json);
  }

  Future<CoachHistory> getHistory({required String accessToken}) async {
    final json = await _guardRemote(
      () => _client.getJson(
        '/v1/coach/history',
        headers: _headers(accessToken),
      ),
    );
    return CoachHistory.fromJson(json);
  }

  Stream<CoachStreamEvent> respond({
    required String accessToken,
    required CoachRequest request,
    required CancelToken cancelToken,
  }) async* {
    final body = await _guardStream(
      () => _client.postStream(
        '/v1/coach/respond/stream',
        headers: {
          ..._headers(accessToken),
          'Accept': 'text/event-stream',
        },
        body: request.toJson(),
        receiveTimeout: const Duration(seconds: 190),
        cancelToken: cancelToken,
      ),
    );
    yield* _parseSse(body.stream.cast<List<int>>());
  }

  Future<CoachHistoryDeleteResult> deleteHistory({
    required String accessToken,
  }) async {
    final json = await _guardRemote(
      () => _client.deleteJson(
        '/v1/coach/history',
        headers: _headers(accessToken),
      ),
    );
    return CoachHistoryDeleteResult.fromJson(json);
  }

  Map<String, String> _headers(String accessToken) => {
        'Authorization': 'Bearer $accessToken',
      };
}

const _maxCoachStreamBytes = 512 * 1024;
const _maxCoachEventCodepoints = 256 * 1024;
const _safeCoachActivityMessages = {
  'Preparing a private data snapshot …',
  'Preparing a direct answer …',
  'Checking available personal data …',
  'Checking relevant history …',
  'Testing the data with isolated analysis …',
  'Working with personal data …',
};

Stream<CoachStreamEvent> _parseSse(Stream<List<int>> bytes) async* {
  String? event;
  final data = StringBuffer();
  var started = false;
  var terminal = false;
  var activityCount = 0;

  await for (final line in _decodeSseLines(bytes)) {
    if (line.isEmpty) {
      if (event == null) continue;
      final payloadText = data.toString();
      if (payloadText.runes.length > _maxCoachEventCodepoints) {
        throw const CoachContractException('Coach stream event is too large.');
      }
      Map<String, dynamic> payload;
      try {
        final decoded = jsonDecode(payloadText);
        if (decoded is! Map) {
          throw const FormatException();
        }
        payload = Map<String, dynamic>.from(decoded);
      } on Object {
        throw const CoachContractException('Coach stream event is invalid.');
      }
      switch (event) {
        case 'started':
          if (started || terminal) {
            throw const CoachContractException(
              'Coach stream order is invalid.',
            );
          }
          _expectKeys(
            payload,
            const {'request_id', 'contract_version'},
            'started event',
          );
          if (payload['contract_version'] != coachRequestContractVersion) {
            throw const CoachContractException(
              'Coach stream contract is invalid.',
            );
          }
          final requestId = payload['request_id'];
          if (requestId is! String || requestId.isEmpty) {
            throw const CoachContractException(
              'Coach stream request identity is invalid.',
            );
          }
          started = true;
          yield CoachStartedEvent(requestId);
          break;
        case 'activity':
          if (!started || terminal || ++activityCount > 16) {
            throw const CoachContractException(
              'Coach stream activity is invalid.',
            );
          }
          _expectKeys(payload, const {'message'}, 'activity event');
          final message = payload['message'];
          if (message is! String ||
              !_safeCoachActivityMessages.contains(message)) {
            throw const CoachContractException(
              'Coach stream activity is invalid.',
            );
          }
          yield CoachActivityEvent(message);
          break;
        case 'completed':
          if (!started || terminal) {
            throw const CoachContractException(
              'Coach stream completion is invalid.',
            );
          }
          _expectKeys(payload, const {'response'}, 'completed event');
          final response = payload['response'];
          if (response is! Map) {
            throw const CoachContractException(
              'Coach stream completion is invalid.',
            );
          }
          terminal = true;
          yield CoachCompletedEvent(
            CoachResponse.fromJson(
              Map<String, dynamic>.from(response),
            ),
          );
          break;
        case 'failed':
          if (!started || terminal) {
            throw const CoachContractException(
              'Coach stream failure is invalid.',
            );
          }
          _expectKeys(payload, const {'error'}, 'failed event');
          final error = payload['error'];
          if (error is! Map) {
            throw const CoachContractException(
              'Coach stream failure is invalid.',
            );
          }
          terminal = true;
          yield CoachFailedEvent(
            CoachErrorDetail.fromJson(
              Map<String, dynamic>.from(error),
            ),
          );
          break;
        default:
          throw const CoachContractException(
            'Coach stream event is unsupported.',
          );
      }
      event = null;
      data.clear();
      continue;
    }
    if (line.startsWith('event: ')) {
      if (event != null || data.isNotEmpty) {
        throw const CoachContractException('Coach stream line is invalid.');
      }
      event = line.substring(7);
    } else if (line.startsWith('data: ')) {
      if (event == null) {
        throw const CoachContractException('Coach stream line is invalid.');
      }
      if (data.isNotEmpty) data.write('\n');
      data.write(line.substring(6));
    } else if (!line.startsWith(':')) {
      throw const CoachContractException('Coach stream line is invalid.');
    }
  }
  if (!terminal || event != null || data.isNotEmpty) {
    throw const CoachContractException(
      'Coach stream ended without a terminal event.',
    );
  }
}

Stream<String> _decodeSseLines(Stream<List<int>> bytes) async* {
  try {
    await for (final line in _boundedSseBytes(bytes)
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      yield line;
    }
  } on FormatException {
    throw const CoachContractException('Coach stream encoding is invalid.');
  }
}

Stream<List<int>> _boundedSseBytes(Stream<List<int>> source) async* {
  var total = 0;
  await for (final chunk in source) {
    total += chunk.length;
    if (total > _maxCoachStreamBytes) {
      throw const CoachContractException('Coach stream is too large.');
    }
    yield chunk;
  }
}

void _expectKeys(
  Map<String, dynamic> value,
  Set<String> keys,
  String label,
) {
  requireStrictKeys(
    value,
    requiredKeys: keys,
    onFailure: () => throw CoachContractException(
      'Coach $label is invalid.',
    ),
  );
}

Future<Map<String, dynamic>> _guardRemote(
  Future<Map<String, dynamic>> Function() operation,
) async {
  try {
    return await operation();
  } on AppException catch (error) {
    throw _remoteException(error);
  }
}

Future<ResponseBody> _guardStream(
  Future<ResponseBody> Function() operation,
) async {
  try {
    return await operation();
  } on AppException catch (error) {
    throw _remoteException(error);
  }
}

CoachRemoteException _remoteException(AppException error) {
  final failure = apiFailureFrom(error);
  if (failure == null || failure.statusCode == null) {
    return CoachRemoteException(
      code: 'network_error',
      message: 'Coach could not be reached.',
      retryable: true,
      statusCode: 503,
      timedOut: failure?.isTimeout ?? false,
    );
  }
  final detail = _parseErrorDetail(failure.responseData);
  return CoachRemoteException(
    code: detail?.code ?? 'remote_error',
    message: detail?.message ?? 'Coach request failed.',
    retryable: detail?.retryable ?? false,
    statusCode: failure.statusCode!,
  );
}

CoachErrorDetail? _parseErrorDetail(Object? body) {
  if (body is! Map || body['detail'] is! Map) return null;
  try {
    final outer = Map<String, dynamic>.from(body);
    if (outer.length != 1 || !outer.containsKey('detail')) return null;
    return CoachErrorDetail.fromJson(
      Map<String, dynamic>.from(outer['detail'] as Map),
    );
  } catch (_) {
    return null;
  }
}
