import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/weekly_review/data/weekly_review_api_data_source.dart';
import 'package:my_life_graph/features/weekly_review/data/weekly_review_repository_impl.dart';
import 'package:my_life_graph/features/weekly_review/domain/weekly_review.dart';

import 'support/weekly_review_fixtures.dart';

void main() {
  const config = AppConfig(
    environment: 'test',
    supabaseUrl: 'http://127.0.0.1:54321',
    supabaseAnonKey: 'anon-key',
    aiServiceBaseUrl: 'http://127.0.0.1:8000',
    useMockData: false,
  );

  test('normal read uses GET latest with the bearer token only', () async {
    final client = _TrackingApiClient(getResponse: weeklyReviewResponseJson());
    final repository = WeeklyReviewRepositoryImpl(
      config: config,
      apiDataSource: WeeklyReviewApiDataSource(client),
      accessTokenProvider: () => ' account-token ',
      isLocalDemo: false,
    );

    final feed = await repository.getLatest();

    expect(feed.freshness, WeeklyReviewFreshness.current);
    expect(client.getCalls, ['/v1/weekly-reviews/latest']);
    expect(client.postCalls, isEmpty);
    expect(client.lastHeaders, {'Authorization': 'Bearer account-token'});
  });

  test('deliberate generation posts exact period key and force', () async {
    final client = _TrackingApiClient(postResponse: weeklyReviewResponseJson());
    final repository = WeeklyReviewRepositoryImpl(
      config: config,
      apiDataSource: WeeklyReviewApiDataSource(client),
      accessTokenProvider: () => 'account-token',
      isLocalDemo: false,
    );

    await repository.generate(periodKey: '2026-W28', force: true);

    expect(client.getCalls, isEmpty);
    expect(client.postCalls, ['/v1/weekly-reviews/generate']);
    expect(client.lastBody, {'period_key': '2026-W28', 'force': true});
  });

  test('local demo stays local and never generates over network', () async {
    final client = _TrackingApiClient(throwOnRequest: true);
    final repository = WeeklyReviewRepositoryImpl(
      config: config,
      apiDataSource: WeeklyReviewApiDataSource(client),
      accessTokenProvider: () => null,
      isLocalDemo: true,
    );

    final feed = await repository.getLatest();

    expect(feed.origin, WeeklyReviewOrigin.localDemo);
    expect(client.getCalls, isEmpty);
    expect(client.postCalls, isEmpty);
    expect(
      () => repository.generate(periodKey: '2026-W28', force: false),
      throwsA(isA<WeeklyReviewAccessException>()),
    );
  });

  test('missing config or token fails before a request', () async {
    final client = _TrackingApiClient(throwOnRequest: true);
    final noConfig = WeeklyReviewRepositoryImpl(
      config: const AppConfig(
        environment: 'test',
        supabaseUrl: '',
        supabaseAnonKey: '',
        aiServiceBaseUrl: 'http://127.0.0.1:8000',
        useMockData: false,
      ),
      apiDataSource: WeeklyReviewApiDataSource(client),
      accessTokenProvider: () => 'token',
      isLocalDemo: false,
    );
    final noToken = WeeklyReviewRepositoryImpl(
      config: config,
      apiDataSource: WeeklyReviewApiDataSource(client),
      accessTokenProvider: () => ' ',
      isLocalDemo: false,
    );

    expect(noConfig.getLatest, throwsA(isA<WeeklyReviewAccessException>()));
    expect(noToken.getLatest, throwsA(isA<WeeklyReviewAccessException>()));
    expect(client.getCalls, isEmpty);
  });
}

class _TrackingApiClient extends ApiClient {
  _TrackingApiClient({
    this.getResponse = const <String, dynamic>{},
    this.postResponse = const <String, dynamic>{},
    this.throwOnRequest = false,
  }) : super(Dio());

  final Map<String, dynamic> getResponse;
  final Map<String, dynamic> postResponse;
  final bool throwOnRequest;
  final List<String> getCalls = [];
  final List<String> postCalls = [];
  Map<String, dynamic>? lastBody;
  Map<String, String>? lastHeaders;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    if (throwOnRequest) throw StateError('Network must not be used.');
    getCalls.add(path);
    lastHeaders = headers;
    return getResponse;
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    if (throwOnRequest) throw StateError('Network must not be used.');
    postCalls.add(path);
    lastBody = body;
    lastHeaders = headers;
    return postResponse;
  }
}
