import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../domain/coach_dictation_request.dart';

class CoachDictationRequestImpl implements CoachDictationRequest {
  CoachDictationRequestImpl({required String baseUrl, Dio? dio})
    : _path =
          '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/v1/speech/transcribe',
      _dio =
          dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  final String _path;
  final Dio _dio;
  final _cancellation = CancelToken();

  @override
  Future<String?> transcribe(
    Uint8List pcm, {
    required String accessToken,
  }) async {
    try {
      final response = await ApiClient(_dio).postBytesWithTimeout(
        _path,
        bytes: pcm,
        headers: {'Authorization': 'Bearer $accessToken'},
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 90),
        cancelToken: _cancellation,
      );
      final text = response['text'];
      return text is String &&
              text.trim().isNotEmpty &&
              text.runes.length <= 2000
          ? text.trim()
          : null;
    } finally {
      _dio.close(force: true);
    }
  }

  @override
  void cancel() => _cancellation.cancel();
}
