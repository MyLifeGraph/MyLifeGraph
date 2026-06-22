import 'dart:async';

import '../../../../core/config/app_config.dart';
import '../../domain/entities/recommendation.dart';
import '../../domain/entities/skillset_profile.dart';
import '../../domain/repositories/optimization_repository.dart';
import '../datasources/optimization_mock_data_source.dart';
import '../datasources/recommendations_api_data_source.dart';

typedef AccessTokenProvider = FutureOr<String?> Function();

class OptimizationRepositoryImpl implements OptimizationRepository {
  const OptimizationRepositoryImpl({
    required AppConfig config,
    required OptimizationMockDataSource mockDataSource,
    required RecommendationsApiDataSource recommendationsApiDataSource,
    required AccessTokenProvider accessTokenProvider,
  })  : _config = config,
        _mockDataSource = mockDataSource,
        _recommendationsApiDataSource = recommendationsApiDataSource,
        _accessTokenProvider = accessTokenProvider;

  final AppConfig _config;
  final OptimizationMockDataSource _mockDataSource;
  final RecommendationsApiDataSource _recommendationsApiDataSource;
  final AccessTokenProvider _accessTokenProvider;

  @override
  Future<SkillsetProfile> getSkillsetProfile() {
    if (_config.useMockData) {
      return _mockDataSource.getSkillsetProfile();
    }

    // The endpoint contract is intentionally isolated here. The UI and domain
    // layers do not need to know whether data came from Supabase or FastAPI.
    return _mockDataSource.getSkillsetProfile();
  }

  @override
  Future<List<Recommendation>> getRecommendations() async {
    if (_config.useMockData || !_config.isSupabaseConfigured) {
      return _mockDataSource.getRecommendations();
    }

    final accessToken = await _accessTokenProvider();
    if (accessToken == null || accessToken.trim().isEmpty) {
      return _mockDataSource.getRecommendations();
    }

    try {
      return await _recommendationsApiDataSource.getRecommendations(
        accessToken: accessToken,
      );
    } catch (_) {
      return _mockDataSource.getRecommendations();
    }
  }
}
