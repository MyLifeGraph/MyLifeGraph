import 'dart:async';

import '../../../core/config/app_config.dart';
import '../domain/briefing_repository.dart';
import '../domain/daily_briefing.dart';
import 'briefing_api_data_source.dart';

typedef BriefingAccessTokenProvider = FutureOr<String?> Function();

class BriefingRepositoryImpl implements BriefingRepository {
  const BriefingRepositoryImpl({
    required AppConfig config,
    required BriefingApiDataSource apiDataSource,
    required BriefingAccessTokenProvider accessTokenProvider,
    required bool isLocalDemo,
  })  : _config = config,
        _apiDataSource = apiDataSource,
        _accessTokenProvider = accessTokenProvider,
        _isLocalDemo = isLocalDemo;

  final AppConfig _config;
  final BriefingApiDataSource _apiDataSource;
  final BriefingAccessTokenProvider _accessTokenProvider;
  final bool _isLocalDemo;

  @override
  Future<BriefingFeed> getToday() async {
    if (_isLocalDemo) {
      return BriefingFeed.localDemo();
    }
    return _apiDataSource.getToday(accessToken: await _requireAccessToken());
  }

  @override
  Future<BriefingFeed> generateToday({required bool force}) async {
    if (_isLocalDemo) {
      throw const BriefingAccessException(
        'Daily briefing generation is unavailable in local demo mode.',
      );
    }
    return _apiDataSource.generateToday(
      accessToken: await _requireAccessToken(),
      force: force,
    );
  }

  Future<String> _requireAccessToken() async {
    if (!_config.isSupabaseConfigured) {
      throw const BriefingAccessException(
        'Daily briefings require Supabase configuration.',
      );
    }
    final token = await _accessTokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw const BriefingAccessException(
        'Daily briefings require an authenticated session.',
      );
    }
    return token.trim();
  }
}

class BriefingAccessException implements Exception {
  const BriefingAccessException(this.message);

  final String message;

  @override
  String toString() => 'BriefingAccessException: $message';
}
