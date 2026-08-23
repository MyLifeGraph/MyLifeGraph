import '../../../core/config/app_config.dart';
import '../domain/learning_preferences.dart';
import '../domain/learning_repository.dart';
import 'learning_api_data_source.dart';

typedef LearningAccessTokenProvider = Future<String?> Function();

class LearningRepositoryImpl implements LearningRepository {
  const LearningRepositoryImpl({
    required AppConfig config,
    required LearningApiDataSource api,
    required LearningAccessTokenProvider accessTokenProvider,
    required bool canUseSyncedLearning,
  })  : _config = config,
        _api = api,
        _accessTokenProvider = accessTokenProvider,
        _canUseSyncedLearning = canUseSyncedLearning;

  final AppConfig _config;
  final LearningApiDataSource _api;
  final LearningAccessTokenProvider _accessTokenProvider;
  final bool _canUseSyncedLearning;

  @override
  Future<LearningPreferences> getPreferences() async {
    final token = await _token();
    return _api.getPreferences(accessToken: token);
  }

  @override
  Future<LearningPreferences> updatePreferences(
    LearningPreferencesUpdate request,
  ) async {
    final token = await _token();
    return _api.updatePreferences(accessToken: token, request: request);
  }

  @override
  Future<FocusReflectionHistoryClearResult> clearFocusReflections(
    FocusReflectionHistoryClearRequest request,
  ) async {
    final token = await _token();
    return _api.clearFocusReflections(
      accessToken: token,
      request: request,
    );
  }

  Future<String> _token() async {
    if (_config.useMockData || !_canUseSyncedLearning) {
      throw const LearningAccessException(
        'Personal learning is available only for a synced account.',
      );
    }
    final token = await _accessTokenProvider();
    if (token == null || token.isEmpty) {
      throw const LearningAccessException(
        'Sign in again to use Personal learning.',
      );
    }
    return token;
  }
}
