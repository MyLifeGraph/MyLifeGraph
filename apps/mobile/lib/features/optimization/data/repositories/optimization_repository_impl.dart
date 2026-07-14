import 'dart:async';

import '../../../../core/config/app_config.dart';
import '../../domain/entities/recommendation_feed.dart';
import '../../domain/entities/skillset_profile.dart';
import '../../domain/repositories/optimization_repository.dart';
import '../datasources/optimization_mock_data_source.dart';
import '../datasources/recommendations_api_data_source.dart';

typedef AccessTokenProvider = FutureOr<String?> Function();
typedef SkillsetProfileLoader = Future<SkillsetProfile> Function();

class OptimizationRepositoryImpl implements OptimizationRepository {
  const OptimizationRepositoryImpl({
    required AppConfig config,
    required OptimizationMockDataSource mockDataSource,
    required RecommendationsApiDataSource recommendationsApiDataSource,
    required AccessTokenProvider accessTokenProvider,
    SkillsetProfileLoader? skillsetProfileLoader,
    required bool allowDemoData,
  })  : _config = config,
        _mockDataSource = mockDataSource,
        _recommendationsApiDataSource = recommendationsApiDataSource,
        _accessTokenProvider = accessTokenProvider,
        _skillsetProfileLoader = skillsetProfileLoader,
        _allowDemoData = allowDemoData;

  final AppConfig _config;
  final OptimizationMockDataSource _mockDataSource;
  final RecommendationsApiDataSource _recommendationsApiDataSource;
  final AccessTokenProvider _accessTokenProvider;
  final SkillsetProfileLoader? _skillsetProfileLoader;
  final bool _allowDemoData;

  bool get _usesDemoData => _config.useMockData || _allowDemoData;

  @override
  Future<SkillsetProfile> getSkillsetProfile() async {
    if (_usesDemoData) {
      return _mockDataSource.getSkillsetProfile();
    }

    if (!_config.isSupabaseConfigured || _skillsetProfileLoader == null) {
      throw const SkillsetProfileAccessException(
        'Authenticated skillset profiles require Supabase configuration.',
      );
    }
    return _skillsetProfileLoader();
  }

  @override
  Future<RecommendationFeed> getRecommendations() async {
    if (_usesDemoData) {
      return RecommendationFeed.demo(
        await _mockDataSource.getRecommendations(),
      );
    }

    final accessToken = await _requireRealAccessToken();
    return _recommendationsApiDataSource.getRecommendations(
      accessToken: accessToken,
    );
  }

  @override
  Future<RecommendationFeed> refreshRecommendations() async {
    if (_usesDemoData) {
      return RecommendationFeed.demo(
        await _mockDataSource.getRecommendations(),
      );
    }

    final accessToken = await _requireRealAccessToken();
    return _recommendationsApiDataSource.generateRecommendations(
      accessToken: accessToken,
    );
  }

  Future<String> _requireRealAccessToken() async {
    if (!_config.isSupabaseConfigured) {
      throw const RecommendationAccessException(
        RecommendationAccessFailure.configuration,
        'Authenticated recommendations require Supabase configuration.',
      );
    }

    final accessToken = await _accessTokenProvider();
    if (accessToken == null || accessToken.trim().isEmpty) {
      throw const RecommendationAccessException(
        RecommendationAccessFailure.session,
        'Authenticated recommendations require an active access token.',
      );
    }
    return accessToken.trim();
  }
}

class SkillsetProfileAccessException implements Exception {
  const SkillsetProfileAccessException(this.message);

  final String message;

  @override
  String toString() => 'SkillsetProfileAccessException: $message';
}

enum RecommendationAccessFailure {
  configuration,
  session,
}

class RecommendationAccessException implements Exception {
  const RecommendationAccessException(this.failure, this.message);

  final RecommendationAccessFailure failure;
  final String message;

  @override
  String toString() => 'RecommendationAccessException: $message';
}
