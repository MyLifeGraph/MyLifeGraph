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
}
