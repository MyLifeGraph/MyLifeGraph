import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/core/network/api_failure.dart';

void main() {
  test('API boundary retains response status and contract response data',
      () async {
    final responseData = {
      'detail': 'Saved projection changed.',
    };

    final failure = await _requestFailure(
      DioExceptionType.badResponse,
      statusCode: 409,
      responseData: responseData,
    );

    expect(failure.kind, ApiFailureKind.response);
    expect(failure.statusCode, 409);
    expect(failure.responseData, same(responseData));
    expect(failure.isConflict, isTrue);
    expect(failure.hasClientError, isTrue);
    expect(failure.hasAmbiguousMutationOutcome, isFalse);
  });

  test('API boundary keeps transport outcomes distinguishable', () async {
    final timeout = await _requestFailure(DioExceptionType.receiveTimeout);
    final connection = await _requestFailure(DioExceptionType.connectionError);
    final cancelled = await _requestFailure(DioExceptionType.cancel);
    final unknown = await _requestFailure(DioExceptionType.unknown);

    expect(timeout.kind, ApiFailureKind.timeout);
    expect(timeout.isTimeout, isTrue);
    expect(connection.kind, ApiFailureKind.connection);
    expect(connection.isConnectionFailure, isTrue);
    expect(cancelled.kind, ApiFailureKind.cancelled);
    expect(cancelled.isCancelled, isTrue);
    expect(unknown.kind, ApiFailureKind.unknown);
    expect(
      [timeout, connection, cancelled, unknown]
          .every((failure) => failure.hasAmbiguousMutationOutcome),
      isTrue,
    );
  });

  test('Retry-After accepts the exact hosted admission range only', () async {
    final oneSecond = await _requestFailure(
      DioExceptionType.badResponse,
      statusCode: 429,
      retryAfter: '1',
    );
    final sixtySeconds = await _requestFailure(
      DioExceptionType.badResponse,
      statusCode: 429,
      retryAfter: '60',
    );
    final zero = await _requestFailure(
      DioExceptionType.badResponse,
      statusCode: 429,
      retryAfter: '0',
    );
    final overBound = await _requestFailure(
      DioExceptionType.badResponse,
      statusCode: 429,
      retryAfter: '61',
    );
    final httpDate = await _requestFailure(
      DioExceptionType.badResponse,
      statusCode: 429,
      retryAfter: 'Wed, 21 Oct 2030 07:28:00 GMT',
    );

    expect(oneSecond.retryAfterSeconds, 1);
    expect(sixtySeconds.retryAfterSeconds, 60);
    expect(zero.retryAfterSeconds, isNull);
    expect(overBound.retryAfterSeconds, isNull);
    expect(httpDate.retryAfterSeconds, isNull);
  });

  test('authorization and server outcomes remain queryable without Dio', () {
    const unauthorized = ApiFailure(
      kind: ApiFailureKind.response,
      statusCode: 401,
    );
    const server = ApiFailure(
      kind: ApiFailureKind.response,
      statusCode: 503,
    );

    expect(unauthorized.isUnauthorized, isTrue);
    expect(server.hasServerError, isTrue);
    expect(server.hasAmbiguousMutationOutcome, isTrue);
    expect(
      apiFailureFrom(
        const AppException('failed', cause: unauthorized),
      ),
      same(unauthorized),
    );
    expect(apiFailureFrom(const AppException('not transport-related')), isNull);
  });

  test('feature application, domain, and presentation layers do not import Dio',
      () {
    final layerPattern = RegExp(r'[/\\](application|domain|presentation)[/\\]');
    final violations = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => layerPattern.hasMatch(file.path))
        .where(
          (file) => file.readAsStringSync().contains(
                'package:dio/dio.dart',
              ),
        )
        .map((file) => file.path)
        .toList(growable: false);

    expect(
      violations,
      isEmpty,
      reason: 'Dio belongs at core/data transport boundaries only.',
    );
  });
}

Future<ApiFailure> _requestFailure(
  DioExceptionType type, {
  int? statusCode,
  Object? responseData,
  String? retryAfter,
}) async {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: type,
            response: statusCode == null
                ? null
                : Response<Object?>(
                    requestOptions: options,
                    statusCode: statusCode,
                    data: responseData,
                    headers: retryAfter == null
                        ? null
                        : Headers.fromMap({
                            'retry-after': [retryAfter],
                          }),
                  ),
          ),
        );
      },
    ),
  );

  try {
    await ApiClient(dio).getJson('/failure');
  } on AppException catch (error) {
    final failure = apiFailureFrom(error);
    expect(failure, isNotNull);
    return failure!;
  }
  fail('Expected ApiClient to throw an AppException.');
}
