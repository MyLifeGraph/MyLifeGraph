import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../errors/app_exception.dart';

final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);

  return Dio(
    BaseOptions(
      baseUrl: config.aiServiceBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
    ),
  );
});

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(dioProvider)),
);

class ApiClient {
  const ApiClient(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        options: headers == null ? null : Options(headers: headers),
      );
      return response.data ?? <String, dynamic>{};
    } on DioException catch (error) {
      throw AppException('Network request failed', cause: error);
    }
  }

  Future<Uint8List> getBytesWithTimeout(
    String path, {
    required Duration receiveTimeout,
    required int maxResponseBytes,
    Map<String, String>? headers,
  }) async {
    if (maxResponseBytes <= 0) {
      throw ArgumentError.value(
        maxResponseBytes,
        'maxResponseBytes',
        'must be positive',
      );
    }
    final cancelToken = CancelToken();
    var responseTooLarge = false;
    try {
      final response = await _dio.get<List<int>>(
        path,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (received > maxResponseBytes || total > maxResponseBytes) {
            responseTooLarge = true;
            if (!cancelToken.isCancelled) {
              cancelToken.cancel('Response exceeded its byte limit.');
            }
          }
        },
        options: Options(
          headers: headers,
          receiveTimeout: receiveTimeout,
          responseType: ResponseType.bytes,
        ),
      );
      final bytes = response.data ?? const <int>[];
      if (responseTooLarge || bytes.length > maxResponseBytes) {
        throw const ApiResponseTooLargeException();
      }
      return Uint8List.fromList(bytes);
    } on DioException catch (error) {
      if (responseTooLarge) {
        throw const ApiResponseTooLargeException();
      }
      throw AppException('Network request failed', cause: error);
    }
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        data: body ?? <String, dynamic>{},
        options: headers == null ? null : Options(headers: headers),
      );
      return response.data ?? <String, dynamic>{};
    } on DioException catch (error) {
      throw AppException('Network request failed', cause: error);
    }
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        path,
        data: body ?? <String, dynamic>{},
        options: headers == null ? null : Options(headers: headers),
      );
      return response.data ?? <String, dynamic>{};
    } on DioException catch (error) {
      throw AppException('Network request failed', cause: error);
    }
  }

  Future<Map<String, dynamic>> postJsonWithTimeout(
    String path, {
    required Duration receiveTimeout,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        data: body ?? <String, dynamic>{},
        options: Options(
          headers: headers,
          receiveTimeout: receiveTimeout,
        ),
        cancelToken: cancelToken,
      );
      return response.data ?? <String, dynamic>{};
    } on DioException catch (error) {
      throw AppException('Network request failed', cause: error);
    }
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.delete<Map<String, dynamic>>(
        path,
        options: headers == null ? null : Options(headers: headers),
      );
      return response.data ?? <String, dynamic>{};
    } on DioException catch (error) {
      throw AppException('Network request failed', cause: error);
    }
  }

  Future<ApiMutationResponse> deleteWithBodyResponse(
    String path, {
    required Map<String, dynamic> body,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.delete<String>(
        path,
        data: body,
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
        ),
      );
      final statusCode = response.statusCode;
      if (statusCode == null) {
        throw const AppException(
          'Network response did not include an HTTP status.',
        );
      }
      return ApiMutationResponse(
        statusCode: statusCode,
        body: response.data,
      );
    } on DioException catch (error) {
      throw AppException('Network request failed', cause: error);
    }
  }
}

class ApiResponseTooLargeException implements Exception {
  const ApiResponseTooLargeException();

  @override
  String toString() => 'Network response exceeded its byte limit.';
}

class ApiMutationResponse {
  const ApiMutationResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String? body;

  bool get hasBody => body != null && body!.isNotEmpty;
}
