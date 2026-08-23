import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/network/api_client.dart';

void main() {
  test('bounded byte download preserves the exact response bytes', () async {
    final dio = Dio()
      ..httpClientAdapter = _ChunkedAdapter(const [
        [0, 1, 2],
        [254, 255],
      ]);

    final bytes = await ApiClient(dio).getBytesWithTimeout(
      'https://example.test/export',
      receiveTimeout: const Duration(seconds: 1),
      maxResponseBytes: 5,
    );

    expect(bytes, Uint8List.fromList(const [0, 1, 2, 254, 255]));
  });

  test('bounded byte download cancels while an oversized body arrives',
      () async {
    final adapter = _ChunkedAdapter(const [
      [0, 1, 2],
      [3, 4, 5],
      [6, 7, 8],
    ]);
    final dio = Dio()..httpClientAdapter = adapter;

    await expectLater(
      ApiClient(dio).getBytesWithTimeout(
        'https://example.test/export',
        receiveTimeout: const Duration(seconds: 1),
        maxResponseBytes: 5,
      ),
      throwsA(isA<ApiResponseTooLargeException>()),
    );

    expect(adapter.cancellationObserved, isTrue);
  });
}

class _ChunkedAdapter implements HttpClientAdapter {
  _ChunkedAdapter(this.chunks);

  final List<List<int>> chunks;
  bool cancellationObserved = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    cancelFuture?.then((_) => cancellationObserved = true);
    return ResponseBody(
      Stream<Uint8List>.fromIterable(
        chunks.map(Uint8List.fromList),
      ),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
