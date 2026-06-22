import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/optimization/data/datasources/optimization_mock_data_source.dart';
import 'package:my_life_graph/features/optimization/data/datasources/recommendations_api_data_source.dart';
import 'package:my_life_graph/features/optimization/data/repositories/optimization_repository_impl.dart';
import 'package:my_life_graph/features/optimization/domain/entities/recommendation.dart';

void main() {
  group('OptimizationRepositoryImpl.getRecommendations', () {
    test('mock mode returns mock recommendations and does not call backend',
        () async {
      final apiClient = _FakeApiClient();
      final repository = _buildRepository(
        config: _config(useMockData: true, supabaseConfigured: true),
        apiClient: apiClient,
        accessTokenProvider: () => 'token',
      );

      final recommendations = await repository.getRecommendations();

      expect(recommendations, [_mockRecommendation]);
      expect(apiClient.getCalls, isEmpty);
      expect(apiClient.postCalls, isEmpty);
    });

    test('missing Supabase config falls back safely and does not call backend',
        () async {
      final apiClient = _FakeApiClient();
      final repository = _buildRepository(
        config: _config(useMockData: false),
        apiClient: apiClient,
        accessTokenProvider: () => 'token',
      );

      final recommendations = await repository.getRecommendations();

      expect(recommendations, [_mockRecommendation]);
      expect(apiClient.getCalls, isEmpty);
      expect(apiClient.postCalls, isEmpty);
    });

    test('missing access token falls back safely and does not call backend',
        () async {
      final apiClient = _FakeApiClient();
      final repository = _buildRepository(
        config: _config(useMockData: false, supabaseConfigured: true),
        apiClient: apiClient,
        accessTokenProvider: () => null,
      );

      final recommendations = await repository.getRecommendations();

      expect(recommendations, [_mockRecommendation]);
      expect(apiClient.getCalls, isEmpty);
      expect(apiClient.postCalls, isEmpty);
    });

    test('authenticated real mode calls GET with bearer auth and maps items',
        () async {
      final apiClient = _FakeApiClient(
        getResponse: {
          'items': [
            {
              'id': 'rec_backend_focus',
              'title': 'Protect a morning focus block',
              'reason': 'Recent focus evidence supports it.',
              'action_label': 'Schedule focus block',
              'category': 'focus',
              'priority': 'medium',
              'confidence': 0.82,
              'generated_at': '2026-06-22T10:15:00Z',
              'metadata': {'period_key': '2026-W26'},
            },
          ],
          'needs_generation': false,
          'generated_at': '2026-06-22T10:15:00Z',
          'period_key': '2026-W26',
          'stale_reason': null,
        },
      );
      final repository = _buildRepository(
        config: _config(useMockData: false, supabaseConfigured: true),
        apiClient: apiClient,
        accessTokenProvider: () => 'access-token-123',
      );

      final recommendations = await repository.getRecommendations();

      expect(apiClient.getCalls, ['/v1/recommendations']);
      expect(apiClient.postCalls, isEmpty);
      expect(apiClient.lastHeaders, {
        'Authorization': 'Bearer access-token-123',
      });
      expect(recommendations, hasLength(1));
      expect(recommendations.single.id, 'rec_backend_focus');
      expect(recommendations.single.title, 'Protect a morning focus block');
      expect(
        recommendations.single.reason,
        'Recent focus evidence supports it.',
      );
      expect(recommendations.single.actionLabel, 'Schedule focus block');
      expect(recommendations.single.category, RecommendationCategory.focus);
      expect(recommendations.single.confidence, 0.82);
    });

    test('unknown backend categories are skipped without crashing', () async {
      final apiClient = _FakeApiClient(
        getResponse: {
          'items': [
            {
              'id': 'rec_unknown',
              'title': 'Unsupported item',
              'reason': 'The backend category is outside v1.',
              'action_label': 'Ignore',
              'category': 'nutrition',
              'confidence': 0.7,
            },
            {
              'id': 'rec_planning',
              'title': 'Reset the plan',
              'reason': 'Planning friction is present.',
              'action_label': 'Review plan',
              'category': 'planning',
              'confidence': 1,
            },
          ],
          'needs_generation': false,
        },
      );
      final repository = _buildRepository(
        config: _config(useMockData: false, supabaseConfigured: true),
        apiClient: apiClient,
        accessTokenProvider: () => 'token',
      );

      final recommendations = await repository.getRecommendations();

      expect(recommendations, hasLength(1));
      expect(recommendations.single.id, 'rec_planning');
      expect(recommendations.single.category, RecommendationCategory.planning);
      expect(recommendations.single.confidence, 1.0);
    });

    test('stale empty responses do not trigger automatic generation', () async {
      final apiClient = _FakeApiClient(
        getResponse: {
          'items': [],
          'needs_generation': true,
          'generated_at': null,
          'period_key': '2026-W26',
          'stale_reason': 'missing',
        },
      );
      final repository = _buildRepository(
        config: _config(useMockData: false, supabaseConfigured: true),
        apiClient: apiClient,
        accessTokenProvider: () => 'token',
      );

      final recommendations = await repository.getRecommendations();

      expect(recommendations, isEmpty);
      expect(apiClient.getCalls, ['/v1/recommendations']);
      expect(apiClient.postCalls, isEmpty);
    });

    test('network failures fall back to mock recommendations', () async {
      final apiClient = _FakeApiClient(throwOnGet: true);
      final repository = _buildRepository(
        config: _config(useMockData: false, supabaseConfigured: true),
        apiClient: apiClient,
        accessTokenProvider: () => 'token',
      );

      final recommendations = await repository.getRecommendations();

      expect(recommendations, [_mockRecommendation]);
      expect(apiClient.getCalls, ['/v1/recommendations']);
      expect(apiClient.postCalls, isEmpty);
    });
  });
}

OptimizationRepositoryImpl _buildRepository({
  required AppConfig config,
  required _FakeApiClient apiClient,
  required AccessTokenProvider accessTokenProvider,
}) {
  return OptimizationRepositoryImpl(
    config: config,
    mockDataSource: const _FakeMockDataSource(),
    recommendationsApiDataSource: RecommendationsApiDataSource(apiClient),
    accessTokenProvider: accessTokenProvider,
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

const _mockRecommendation = Recommendation(
  id: 'mock_rec',
  title: 'Mock recommendation',
  reason: 'Mock fallback reason',
  actionLabel: 'Use mock',
  category: RecommendationCategory.focus,
  confidence: 0.5,
);

class _FakeMockDataSource extends OptimizationMockDataSource {
  const _FakeMockDataSource();

  @override
  Future<List<Recommendation>> getRecommendations() async {
    return const [_mockRecommendation];
  }
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient({
    Map<String, dynamic>? getResponse,
    this.throwOnGet = false,
  })  : getResponse = getResponse ?? <String, dynamic>{},
        super(Dio());

  final Map<String, dynamic> getResponse;
  final bool throwOnGet;
  final List<String> getCalls = [];
  final List<String> postCalls = [];
  Map<String, String>? lastHeaders;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    getCalls.add(path);
    lastHeaders = headers;
    if (throwOnGet) {
      throw Exception('network failed');
    }
    return getResponse;
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    postCalls.add(path);
    return <String, dynamic>{};
  }
}
