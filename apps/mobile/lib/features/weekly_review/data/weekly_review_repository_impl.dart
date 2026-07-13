import 'dart:async';

import '../../../core/config/app_config.dart';
import '../domain/weekly_review.dart';
import '../domain/weekly_review_repository.dart';
import 'weekly_review_api_data_source.dart';

typedef WeeklyReviewAccessTokenProvider = FutureOr<String?> Function();

class WeeklyReviewRepositoryImpl implements WeeklyReviewRepository {
  const WeeklyReviewRepositoryImpl({
    required AppConfig config,
    required WeeklyReviewApiDataSource apiDataSource,
    required WeeklyReviewAccessTokenProvider accessTokenProvider,
    required bool isLocalDemo,
  })  : _config = config,
        _apiDataSource = apiDataSource,
        _accessTokenProvider = accessTokenProvider,
        _isLocalDemo = isLocalDemo;

  final AppConfig _config;
  final WeeklyReviewApiDataSource _apiDataSource;
  final WeeklyReviewAccessTokenProvider _accessTokenProvider;
  final bool _isLocalDemo;

  @override
  Future<WeeklyReviewFeed> getLatest() async {
    if (_isLocalDemo) return WeeklyReviewFeed.localDemo();
    return _apiDataSource.getLatest(accessToken: await _requireAccessToken());
  }

  @override
  Future<WeeklyReviewFeed> generate({
    required String periodKey,
    required bool force,
  }) async {
    if (_isLocalDemo) {
      throw const WeeklyReviewAccessException(
        'Weekly review generation is unavailable in local demo mode.',
      );
    }
    return _apiDataSource.generate(
      accessToken: await _requireAccessToken(),
      periodKey: periodKey,
      force: force,
    );
  }

  Future<String> _requireAccessToken() async {
    if (!_config.isSupabaseConfigured) {
      throw const WeeklyReviewAccessException(
        'Weekly reviews require Supabase configuration.',
      );
    }
    final token = await _accessTokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw const WeeklyReviewAccessException(
        'Weekly reviews require an authenticated session.',
      );
    }
    return token.trim();
  }
}

class WeeklyReviewAccessException implements Exception {
  const WeeklyReviewAccessException(this.message);

  final String message;

  @override
  String toString() => 'WeeklyReviewAccessException: $message';
}
