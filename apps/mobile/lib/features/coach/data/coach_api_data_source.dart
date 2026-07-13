import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
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

  Future<CoachMemorySelection> getMemories({
    required String accessToken,
  }) async {
    final json = await _guardRemote(
      () => _client.getJson(
        '/v1/coach/memories',
        headers: _headers(accessToken),
      ),
    );
    return CoachMemorySelection.fromJson(json);
  }

  Future<CoachResponse> respond({
    required String accessToken,
    required CoachRequest request,
    required Duration receiveTimeout,
    required CancelToken cancelToken,
  }) async {
    final json = await _guardRemote(
      () => _client.postJsonWithTimeout(
        '/v1/coach/respond',
        headers: _headers(accessToken),
        body: request.toJson(),
        receiveTimeout: receiveTimeout,
        cancelToken: cancelToken,
      ),
    );
    return CoachResponse.fromJson(json);
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

  Future<CoachMemorySelection> selectMemory({
    required String accessToken,
    required String memoryId,
  }) async {
    final json = await _guardRemote(
      () => _client.postJson(
        '/v1/coach/memories/$memoryId/selection',
        headers: _headers(accessToken),
        body: const {'selected': true},
      ),
    );
    return CoachMemorySelection.fromJson(json);
  }

  Future<CoachMemorySelection> deselectMemory({
    required String accessToken,
    required String memoryId,
  }) async {
    final json = await _guardRemote(
      () => _client.deleteJson(
        '/v1/coach/memories/$memoryId/selection',
        headers: _headers(accessToken),
      ),
    );
    return CoachMemorySelection.fromJson(json);
  }

  Map<String, String> _headers(String accessToken) => {
        'Authorization': 'Bearer $accessToken',
      };
}

Future<Map<String, dynamic>> _guardRemote(
  Future<Map<String, dynamic>> Function() operation,
) async {
  try {
    return await operation();
  } on AppException catch (error) {
    final cause = error.cause;
    if (cause is! DioException || cause.response == null) rethrow;
    final response = cause.response!;
    final detail = _parseErrorDetail(response.data);
    throw CoachRemoteException(
      code: detail?.code ?? 'remote_error',
      message: detail?.message ?? 'Coach request failed.',
      retryable: detail?.retryable ?? false,
      statusCode: response.statusCode ?? 500,
    );
  }
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
