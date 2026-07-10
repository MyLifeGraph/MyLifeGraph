import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/snapshots/application/snapshot_refresh_service.dart';
import 'package:my_life_graph/features/snapshots/data/snapshot_api_data_source.dart';

void main() {
  test('SnapshotApiDataSource posts daily snapshot refresh with bearer auth',
      () async {
    final apiClient = _FakeApiClient();
    final dataSource = SnapshotApiDataSource(apiClient);

    await dataSource.generateDailySnapshot(accessToken: 'access-token-123');

    expect(apiClient.postCalls, ['/v1/snapshots/generate']);
    expect(apiClient.lastBody, {
      'scope': 'daily',
      'window_days': 7,
    });
    expect(apiClient.lastHeaders, {
      'Authorization': 'Bearer access-token-123',
    });
  });

  test('mock mode skips snapshot refresh', () async {
    final apiClient = _FakeApiClient();
    final service = _buildService(
      config: _config(useMockData: true, supabaseConfigured: true),
      apiClient: apiClient,
      accessTokenProvider: () => 'access-token-123',
    );

    await service.refreshDailyAfterUserSignal();

    expect(apiClient.postCalls, isEmpty);
  });

  test('missing Supabase config skips snapshot refresh', () async {
    final apiClient = _FakeApiClient();
    final service = _buildService(
      config: _config(useMockData: false),
      apiClient: apiClient,
      accessTokenProvider: () => 'access-token-123',
    );

    await service.refreshDailyAfterUserSignal();

    expect(apiClient.postCalls, isEmpty);
  });

  test('local guest skips refresh even with a leftover token', () async {
    final apiClient = _FakeApiClient();
    final service = _buildService(
      config: _config(useMockData: false, supabaseConfigured: true),
      apiClient: apiClient,
      accessTokenProvider: () => 'leftover-access-token',
      allowRemoteRefresh: false,
    );

    await service.refreshDailyAfterUserSignal();

    expect(apiClient.postCalls, isEmpty);
  });

  test('missing access token skips snapshot refresh', () async {
    final apiClient = _FakeApiClient();
    final service = _buildService(
      config: _config(useMockData: false, supabaseConfigured: true),
      apiClient: apiClient,
      accessTokenProvider: () => null,
    );

    await service.refreshDailyAfterUserSignal();

    expect(apiClient.postCalls, isEmpty);
  });

  test('real backend mode refreshes daily snapshot', () async {
    final apiClient = _FakeApiClient();
    final service = _buildService(
      config: _config(useMockData: false, supabaseConfigured: true),
      apiClient: apiClient,
      accessTokenProvider: () => 'access-token-123',
    );

    await service.refreshDailyAfterUserSignal();

    expect(apiClient.postCalls, ['/v1/snapshots/generate']);
    expect(apiClient.lastHeaders, {
      'Authorization': 'Bearer access-token-123',
    });
  });

  test('task changes refresh the daily snapshot', () async {
    final apiClient = _FakeApiClient();
    final service = _buildService(
      config: _config(useMockData: false, supabaseConfigured: true),
      apiClient: apiClient,
      accessTokenProvider: () => 'access-token-123',
    );

    await service.refreshDailyAfterTaskChange();

    expect(apiClient.postCalls, ['/v1/snapshots/generate']);
  });

  test('habit changes refresh the daily snapshot', () async {
    final apiClient = _FakeApiClient();
    final service = _buildService(
      config: _config(useMockData: false, supabaseConfigured: true),
      apiClient: apiClient,
      accessTokenProvider: () => 'access-token-123',
    );

    await service.refreshDailyAfterHabitChange();

    expect(apiClient.postCalls, ['/v1/snapshots/generate']);
  });

  test('snapshot refresh failures are best-effort', () async {
    final apiClient = _FakeApiClient(throwOnPost: true);
    final service = _buildService(
      config: _config(useMockData: false, supabaseConfigured: true),
      apiClient: apiClient,
      accessTokenProvider: () => 'access-token-123',
    );

    await service.refreshDailyAfterUserSignal();

    expect(apiClient.postCalls, ['/v1/snapshots/generate']);
  });
}

SnapshotRefreshService _buildService({
  required AppConfig config,
  required _FakeApiClient apiClient,
  required SnapshotAccessTokenProvider accessTokenProvider,
  bool allowRemoteRefresh = true,
}) {
  return SnapshotRefreshService(
    config: config,
    apiDataSource: SnapshotApiDataSource(apiClient),
    accessTokenProvider: accessTokenProvider,
    allowRemoteRefresh: allowRemoteRefresh,
  );
}

AppConfig _config({
  required bool useMockData,
  bool supabaseConfigured = false,
}) {
  return AppConfig(
    environment: 'test',
    supabaseUrl: supabaseConfigured ? 'http://127.0.0.1:54321' : '',
    supabaseAnonKey: supabaseConfigured ? 'anon-key' : '',
    aiServiceBaseUrl: 'http://localhost:8000',
    useMockData: useMockData,
  );
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.throwOnPost = false}) : super(Dio());

  final bool throwOnPost;
  final List<String> postCalls = [];
  Map<String, dynamic>? lastBody;
  Map<String, String>? lastHeaders;

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    postCalls.add(path);
    lastBody = body;
    lastHeaders = headers;
    if (throwOnPost) {
      throw Exception('network failed');
    }
    return <String, dynamic>{};
  }
}
