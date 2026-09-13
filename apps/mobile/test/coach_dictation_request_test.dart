import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/network/api_failure.dart';
import 'package:my_life_graph/features/coach/data/coach_dictation_request_impl.dart';

void main() {
  test(
    'dictation sends unchanged PCM and bearer only to the configured route',
    () async {
      final pcm = Uint8List.fromList([0, 1, 2, 255]);
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            expect(
              options.uri.toString(),
              'https://speech.example.test/dev/v1/speech/transcribe',
            );
            expect(options.method, 'POST');
            expect(options.headers['Authorization'], 'Bearer test-token');
            expect(options.contentType, 'application/octet-stream');
            expect(options.sendTimeout, const Duration(seconds: 30));
            expect(options.receiveTimeout, const Duration(seconds: 90));
            expect(options.followRedirects, isFalse);
            final chunks = await (options.data as Stream<Uint8List>).toList();
            expect(chunks.expand((chunk) => chunk), orderedEquals(pcm));
            handler.resolve(
              Response(requestOptions: options, data: {'text': '  Hello  '}),
            );
          },
        ),
      );
      final request = CoachDictationRequestImpl(
        baseUrl: 'https://speech.example.test/dev/',
        dio: dio,
      );
      expect(await request.transcribe(pcm, accessToken: 'test-token'), 'Hello');
    },
  );

  test(
    'dictation accepts only nonempty text within the existing character limit',
    () async {
      for (final text in [null, 42, '', '   ', 'x' * 2001, '😀' * 2001]) {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(requestOptions: options, data: {'text': text}),
              );
            },
          ),
        );
        final request = CoachDictationRequestImpl(
          baseUrl: 'https://speech.example.test',
          dio: dio,
        );
        expect(
          await request.transcribe(Uint8List(3200), accessToken: 'test-token'),
          isNull,
        );
      }
    },
  );

  test(
    'HTTP, timeout and cancellation evidence stays framework neutral',
    () async {
      for (final status in [401, 403, 429, 503, null]) {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: status == null
                      ? DioExceptionType.receiveTimeout
                      : DioExceptionType.badResponse,
                  response: status == null
                      ? null
                      : Response(requestOptions: options, statusCode: status),
                ),
              );
            },
          ),
        );
        final request = CoachDictationRequestImpl(
          baseUrl: 'https://speech.example.test',
          dio: dio,
        );
        await expectLater(
          request.transcribe(Uint8List(3200), accessToken: 'test-token'),
          throwsA(
            predicate<Object>((error) {
              final failure = apiFailureFrom(error);
              return error is! DioException &&
                  failure != null &&
                  failure.statusCode == status &&
                  (status != null || failure.isTimeout);
            }),
          ),
        );
      }
      final request = CoachDictationRequestImpl(
        baseUrl: 'https://speech.example.test',
      );
      request.cancel();
      await expectLater(
        request.transcribe(Uint8List(3200), accessToken: 'test-token'),
        throwsA(
          predicate<Object>(
            (error) => apiFailureFrom(error)?.isCancelled == true,
          ),
        ),
      );
    },
  );
}
