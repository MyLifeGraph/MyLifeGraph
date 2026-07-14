import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/optimization/data/datasources/optimization_mock_data_source.dart';
import 'package:my_life_graph/features/optimization/data/datasources/recommendations_api_data_source.dart';
import 'package:my_life_graph/features/optimization/data/repositories/optimization_repository_impl.dart';
import 'package:my_life_graph/features/optimization/domain/entities/recommendation.dart';
import 'package:my_life_graph/features/optimization/domain/entities/recommendation_feed.dart';
import 'package:my_life_graph/features/optimization/domain/entities/skillset_profile.dart';

void main() {
  group('OptimizationRepositoryImpl.getRecommendations', () {
    test('mock mode returns a labeled demo feed without backend calls',
        () async {
      final apiClient = _FakeApiClient();
      final repository = _buildRepository(
        config: _config(useMockData: true, supabaseConfigured: true),
        apiClient: apiClient,
        accessTokenProvider: () => 'leftover-real-token',
      );

      final feed = await repository.getRecommendations();

      expect(feed.items, [_mockRecommendation]);
      expect(feed.provenance, RecommendationProvenance.demo);
      expect(feed.freshness, RecommendationFreshness.notApplicable);
      expect(feed.needsGeneration, isFalse);
      expect(feed.generatedAt, isNull);
      expect(feed.periodKey, isNull);
      expect(apiClient.getCalls, isEmpty);
      expect(apiClient.postCalls, isEmpty);
    });

    test('explicit guest mode never uses a leftover real access token',
        () async {
      final apiClient = _FakeApiClient();
      final repository = _buildRepository(
        config: _config(useMockData: false, supabaseConfigured: true),
        apiClient: apiClient,
        accessTokenProvider: () => 'leftover-real-token',
        allowDemoData: true,
      );

      final feed = await repository.getRecommendations();

      expect(feed.provenance, RecommendationProvenance.demo);
      expect(apiClient.getCalls, isEmpty);
      expect(apiClient.postCalls, isEmpty);
    });

    test('missing Supabase config is a real configuration error', () async {
      final apiClient = _FakeApiClient();
      final mockDataSource = _FakeMockDataSource();
      final repository = _buildRepository(
        config: _config(useMockData: false),
        apiClient: apiClient,
        accessTokenProvider: () => 'token',
        mockDataSource: mockDataSource,
      );

      await expectLater(
        repository.getRecommendations(),
        throwsA(
          isA<RecommendationAccessException>().having(
            (error) => error.failure,
            'failure',
            RecommendationAccessFailure.configuration,
          ),
        ),
      );
      expect(mockDataSource.recommendationCalls, 0);
      expect(apiClient.getCalls, isEmpty);
    });

    test('missing access token is a real session error', () async {
      final apiClient = _FakeApiClient();
      final mockDataSource = _FakeMockDataSource();
      final repository = _buildRepository(
        config: _config(useMockData: false, supabaseConfigured: true),
        apiClient: apiClient,
        accessTokenProvider: () => null,
        mockDataSource: mockDataSource,
      );

      await expectLater(
        repository.getRecommendations(),
        throwsA(
          isA<RecommendationAccessException>().having(
            (error) => error.failure,
            'failure',
            RecommendationAccessFailure.session,
          ),
        ),
      );
      expect(mockDataSource.recommendationCalls, 0);
      expect(apiClient.getCalls, isEmpty);
    });

    test('authenticated mode maps the complete backend feed contract',
        () async {
      final apiClient = _FakeApiClient(
        getResponse: _response(
          items: [_item()],
          generatedAt: '2026-06-22T10:15:00Z',
        ),
      );
      final repository = _buildRepository(
        config: _config(useMockData: false, supabaseConfigured: true),
        apiClient: apiClient,
        accessTokenProvider: () => ' access-token-123 ',
      );

      final feed = await repository.getRecommendations();

      expect(apiClient.getCalls, ['/v1/recommendations']);
      expect(apiClient.postCalls, isEmpty);
      expect(apiClient.lastHeaders, {
        'Authorization': 'Bearer access-token-123',
      });
      expect(feed.provenance, RecommendationProvenance.authenticatedBackend);
      expect(feed.freshness, RecommendationFreshness.current);
      expect(feed.needsGeneration, isFalse);
      expect(feed.generatedAt, DateTime.parse('2026-06-22T10:15:00Z'));
      expect(feed.periodKey, '2026-W26');
      expect(feed.items, hasLength(1));
      expect(feed.items.single.id, 'rec_backend_focus');
      expect(feed.items.single.title, 'Protect a morning focus block');
      expect(
        feed.items.single.reason,
        'Recent focus evidence supports it.',
      );
      expect(feed.items.single.actionLabel, 'Schedule focus block');
      expect(feed.items.single.category, RecommendationCategory.focus);
      expect(feed.items.single.confidence, 0.82);
    });

    test(
        'missing recommendations envelope is rejected instead of becoming empty',
        () async {
      final repository = _buildRepository(
        config: _config(useMockData: false, supabaseConfigured: true),
        apiClient: _FakeApiClient(getResponse: const {}),
        accessTokenProvider: () => 'token',
      );

      await expectLater(
        repository.getRecommendations(),
        throwsA(isA<FormatException>()),
      );
    });

    test('unknown backend categories reject the feed instead of dropping items',
        () async {
      final repository = _buildRepository(
        config: _config(useMockData: false, supabaseConfigured: true),
        apiClient: _FakeApiClient(
          getResponse: _response(
            items: [_item(category: 'nutrition')],
            generatedAt: '2026-06-22T10:15:00Z',
          ),
        ),
        accessTokenProvider: () => 'token',
      );

      await expectLater(
        repository.getRecommendations(),
        throwsA(isA<FormatException>()),
      );
    });

    test('freshness and needs_generation must agree', () async {
      final repository = _buildRepository(
        config: _config(useMockData: false, supabaseConfigured: true),
        apiClient: _FakeApiClient(
          getResponse: _response(
            items: const [],
            needsGeneration: false,
            staleReason: 'missing',
          ),
        ),
        accessTokenProvider: () => 'token',
      );

      await expectLater(
        repository.getRecommendations(),
        throwsA(isA<FormatException>()),
      );
    });

    test('stale empty response remains an authenticated missing feed',
        () async {
      final apiClient = _FakeApiClient(
        getResponse: _response(
          items: const [],
          needsGeneration: true,
          staleReason: 'missing',
        ),
      );
      final repository = _buildRepository(
        config: _config(useMockData: false, supabaseConfigured: true),
        apiClient: apiClient,
        accessTokenProvider: () => 'token',
      );

      final feed = await repository.getRecommendations();

      expect(feed.items, isEmpty);
      expect(feed.provenance, RecommendationProvenance.authenticatedBackend);
      expect(feed.freshness, RecommendationFreshness.missing);
      expect(feed.needsGeneration, isTrue);
      expect(feed.generatedAt, isNull);
      expect(apiClient.getCalls, ['/v1/recommendations']);
      expect(apiClient.postCalls, isEmpty);
    });

    for (final staleCase in const [
      (
        backendValue: 'older_than_7_days',
        freshness: RecommendationFreshness.olderThanSevenDays,
      ),
      (
        backendValue: 'period_mismatch',
        freshness: RecommendationFreshness.periodMismatch,
      ),
    ]) {
      test('maps authenticated ${staleCase.backendValue} freshness', () async {
        final repository = _buildRepository(
          config: _config(useMockData: false, supabaseConfigured: true),
          apiClient: _FakeApiClient(
            getResponse: _response(
              items: [_item()],
              needsGeneration: true,
              generatedAt: '2026-06-14T10:15:00Z',
              staleReason: staleCase.backendValue,
            ),
          ),
          accessTokenProvider: () => 'token',
        );

        final feed = await repository.getRecommendations();

        expect(feed.items, hasLength(1));
        expect(feed.provenance, RecommendationProvenance.authenticatedBackend);
        expect(feed.freshness, staleCase.freshness);
        expect(feed.needsGeneration, isTrue);
      });
    }

    test('network failures propagate and never read mock recommendations',
        () async {
      final apiClient = _FakeApiClient(throwOnGet: true);
      final mockDataSource = _FakeMockDataSource();
      final repository = _buildRepository(
        config: _config(useMockData: false, supabaseConfigured: true),
        apiClient: apiClient,
        accessTokenProvider: () => 'token',
        mockDataSource: mockDataSource,
      );

      await expectLater(
        repository.getRecommendations(),
        throwsA(isA<Exception>()),
      );
      expect(mockDataSource.recommendationCalls, 0);
      expect(apiClient.getCalls, ['/v1/recommendations']);
      expect(apiClient.postCalls, isEmpty);
    });
  });

  group('OptimizationRepositoryImpl.refreshRecommendations', () {
    test('demo refresh stays local and remains labeled demo', () async {
      final apiClient = _FakeApiClient();
      final repository = _buildRepository(
        config: _config(useMockData: false, supabaseConfigured: true),
        apiClient: apiClient,
        accessTokenProvider: () => 'leftover-real-token',
        allowDemoData: true,
      );

      final feed = await repository.refreshRecommendations();

      expect(feed.items, [_mockRecommendation]);
      expect(feed.provenance, RecommendationProvenance.demo);
      expect(apiClient.getCalls, isEmpty);
      expect(apiClient.postCalls, isEmpty);
    });

    test('missing access token blocks real refresh without mock fallback',
        () async {
      final mockDataSource = _FakeMockDataSource();
      final repository = _buildRepository(
        config: _config(useMockData: false, supabaseConfigured: true),
        apiClient: _FakeApiClient(),
        accessTokenProvider: () => '',
        mockDataSource: mockDataSource,
      );

      await expectLater(
        repository.refreshRecommendations(),
        throwsA(
          isA<RecommendationAccessException>().having(
            (error) => error.failure,
            'failure',
            RecommendationAccessFailure.session,
          ),
        ),
      );
      expect(mockDataSource.recommendationCalls, 0);
    });

    test('authenticated refresh posts and returns the generated feed',
        () async {
      final apiClient = _FakeApiClient(
        postResponse: _response(
          items: [
            _item(
              id: 'rec_backend_planning',
              category: 'planning',
              title: 'Reset the week plan',
              actionLabel: 'Review plan',
            ),
          ],
          generatedAt: '2026-06-22T11:15:00Z',
        ),
      );
      final repository = _buildRepository(
        config: _config(useMockData: false, supabaseConfigured: true),
        apiClient: apiClient,
        accessTokenProvider: () => 'access-token-123',
      );

      final feed = await repository.refreshRecommendations();

      expect(apiClient.getCalls, isEmpty);
      expect(apiClient.postCalls, ['/v1/recommendations/generate']);
      expect(apiClient.lastBody, {
        'window_days': 28,
        'force': false,
        'allow_llm_wording': false,
      });
      expect(apiClient.lastHeaders, {
        'Authorization': 'Bearer access-token-123',
      });
      expect(feed.provenance, RecommendationProvenance.authenticatedBackend);
      expect(feed.freshness, RecommendationFreshness.current);
      expect(feed.items.single.id, 'rec_backend_planning');
      expect(feed.items.single.category, RecommendationCategory.planning);
    });

    test('refresh network failures propagate without mock fallback', () async {
      final apiClient = _FakeApiClient(throwOnPost: true);
      final mockDataSource = _FakeMockDataSource();
      final repository = _buildRepository(
        config: _config(useMockData: false, supabaseConfigured: true),
        apiClient: apiClient,
        accessTokenProvider: () => 'token',
        mockDataSource: mockDataSource,
      );

      await expectLater(
        repository.refreshRecommendations(),
        throwsA(isA<Exception>()),
      );
      expect(mockDataSource.recommendationCalls, 0);
      expect(apiClient.getCalls, isEmpty);
      expect(apiClient.postCalls, ['/v1/recommendations/generate']);
    });
  });

  test('real skillset profile uses the authenticated loader', () async {
    final expected = SkillsetProfile(
      userName: 'Taylor',
      overallScore: 71,
      primaryArchetype: 'Steady Builder',
      scores: const [],
      updatedAt: DateTime.utc(2026, 7, 13),
    );
    final repository = _buildRepository(
      config: _config(useMockData: false, supabaseConfigured: true),
      apiClient: _FakeApiClient(),
      accessTokenProvider: () => 'token',
      skillsetProfileLoader: () async => expected,
    );

    expect(await repository.getSkillsetProfile(), same(expected));
  });

  test('real skillset profile reports missing Supabase configuration',
      () async {
    final repository = _buildRepository(
      config: _config(useMockData: false),
      apiClient: _FakeApiClient(),
      accessTokenProvider: () => null,
    );

    await expectLater(
      repository.getSkillsetProfile(),
      throwsA(isA<SkillsetProfileAccessException>()),
    );
  });
}

OptimizationRepositoryImpl _buildRepository({
  required AppConfig config,
  required _FakeApiClient apiClient,
  required AccessTokenProvider accessTokenProvider,
  bool allowDemoData = false,
  _FakeMockDataSource? mockDataSource,
  SkillsetProfileLoader? skillsetProfileLoader,
}) {
  return OptimizationRepositoryImpl(
    config: config,
    mockDataSource: mockDataSource ?? _FakeMockDataSource(),
    recommendationsApiDataSource: RecommendationsApiDataSource(apiClient),
    accessTokenProvider: accessTokenProvider,
    skillsetProfileLoader: skillsetProfileLoader,
    allowDemoData: allowDemoData,
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

Map<String, dynamic> _response({
  required List<Map<String, dynamic>> items,
  bool needsGeneration = false,
  String? generatedAt,
  String periodKey = '2026-W26',
  String? staleReason,
}) {
  return {
    'items': items,
    'needs_generation': needsGeneration,
    'generated_at': generatedAt,
    'period_key': periodKey,
    'stale_reason': staleReason,
  };
}

Map<String, dynamic> _item({
  String id = 'rec_backend_focus',
  String title = 'Protect a morning focus block',
  String reason = 'Recent focus evidence supports it.',
  String actionLabel = 'Schedule focus block',
  String category = 'focus',
  double confidence = 0.82,
}) {
  return {
    'id': id,
    'title': title,
    'reason': reason,
    'action_label': actionLabel,
    'category': category,
    'confidence': confidence,
  };
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
  int recommendationCalls = 0;

  @override
  Future<List<Recommendation>> getRecommendations() async {
    recommendationCalls++;
    return const [_mockRecommendation];
  }
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient({
    Map<String, dynamic>? getResponse,
    Map<String, dynamic>? postResponse,
    this.throwOnGet = false,
    this.throwOnPost = false,
  })  : getResponse = getResponse ?? <String, dynamic>{},
        postResponse = postResponse ?? <String, dynamic>{},
        super(Dio());

  final Map<String, dynamic> getResponse;
  final Map<String, dynamic> postResponse;
  final bool throwOnGet;
  final bool throwOnPost;
  final List<String> getCalls = [];
  final List<String> postCalls = [];
  Map<String, dynamic>? lastBody;
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
    lastBody = body;
    lastHeaders = headers;
    if (throwOnPost) {
      throw Exception('network failed');
    }
    return postResponse;
  }
}
