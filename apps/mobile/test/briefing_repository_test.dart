import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/briefings/data/briefing_api_data_source.dart';
import 'package:my_life_graph/features/briefings/data/briefing_repository_impl.dart';
import 'package:my_life_graph/features/briefings/domain/daily_briefing.dart';

import 'support/briefing_fixtures.dart';

void main() {
  const config = AppConfig(
    environment: 'test',
    supabaseUrl: 'http://127.0.0.1:54321',
    supabaseAnonKey: 'anon-key',
    aiServiceBaseUrl: 'http://127.0.0.1:8000',
    useMockData: false,
  );

  test('normal account read uses GET with the bearer token', () async {
    final client = _TrackingApiClient(getResponse: briefingResponseJson());
    final repository = BriefingRepositoryImpl(
      config: config,
      apiDataSource: BriefingApiDataSource(client),
      accessTokenProvider: () => ' account-token ',
      isLocalDemo: false,
    );

    final feed = await repository.getToday();

    expect(feed.freshness, BriefingFreshness.current);
    expect(client.getCalls, ['/v1/briefings/today']);
    expect(client.postCalls, isEmpty);
    expect(client.lastHeaders, {
      'Authorization': 'Bearer account-token',
    });
  });

  test('deliberate generation posts only force and validates response',
      () async {
    final client = _TrackingApiClient(postResponse: briefingResponseJson());
    final repository = BriefingRepositoryImpl(
      config: config,
      apiDataSource: BriefingApiDataSource(client),
      accessTokenProvider: () => 'account-token',
      isLocalDemo: false,
    );

    final feed = await repository.generateToday(force: true);

    expect(feed.freshness, BriefingFreshness.current);
    expect(client.getCalls, isEmpty);
    expect(client.postCalls, ['/v1/briefings/generate']);
    expect(client.lastBody, {'force': true});
  });

  test('local demo read stays local and generation is unavailable', () async {
    final client = _TrackingApiClient(throwOnRequest: true);
    final repository = BriefingRepositoryImpl(
      config: config,
      apiDataSource: BriefingApiDataSource(client),
      accessTokenProvider: () => null,
      isLocalDemo: true,
    );

    final feed = await repository.getToday();

    expect(feed.origin, BriefingOrigin.localDemo);
    expect(client.getCalls, isEmpty);
    expect(client.postCalls, isEmpty);
    expect(
      () => repository.generateToday(force: false),
      throwsA(isA<BriefingAccessException>()),
    );
  });

  test('real account without a token fails before any request', () async {
    final client = _TrackingApiClient(throwOnRequest: true);
    final repository = BriefingRepositoryImpl(
      config: config,
      apiDataSource: BriefingApiDataSource(client),
      accessTokenProvider: () => ' ',
      isLocalDemo: false,
    );

    expect(repository.getToday, throwsA(isA<BriefingAccessException>()));
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
    if (throwOnRequest) {
      throw StateError('Network must not be used.');
    }
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
    if (throwOnRequest) {
      throw StateError('Network must not be used.');
    }
    postCalls.add(path);
    lastBody = body;
    lastHeaders = headers;
    return postResponse;
  }
}
