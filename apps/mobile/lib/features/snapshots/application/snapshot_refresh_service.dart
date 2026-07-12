import '../../../core/config/app_config.dart';
import '../data/snapshot_api_data_source.dart';

typedef SnapshotAccessTokenProvider = String? Function();

class SnapshotRefreshService {
  const SnapshotRefreshService({
    required AppConfig config,
    required SnapshotApiDataSource apiDataSource,
    required SnapshotAccessTokenProvider accessTokenProvider,
    required bool allowRemoteRefresh,
  })  : _config = config,
        _apiDataSource = apiDataSource,
        _accessTokenProvider = accessTokenProvider,
        _allowRemoteRefresh = allowRemoteRefresh;

  final AppConfig _config;
  final SnapshotApiDataSource _apiDataSource;
  final SnapshotAccessTokenProvider _accessTokenProvider;
  final bool _allowRemoteRefresh;

  Future<void> refreshDailyAfterTaskChange({required String targetDate}) =>
      refreshDailyAfterUserSignal(targetDate: targetDate);

  Future<void> refreshDailyAfterHabitChange({required String targetDate}) =>
      refreshDailyAfterUserSignal(targetDate: targetDate);

  Future<void> refreshDailyAfterFocusChange({required String targetDate}) =>
      refreshDailyAfterUserSignal(targetDate: targetDate);

  Future<void> refreshDailyAfterUserSignal({String? targetDate}) async {
    if (!_allowRemoteRefresh ||
        _config.useMockData ||
        !_config.isSupabaseConfigured) {
      return;
    }

    final accessToken = _accessTokenProvider();
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    try {
      await _apiDataSource.generateDailySnapshot(
        accessToken: accessToken,
        targetDate: targetDate,
      );
    } catch (_) {
      return;
    }
  }
}
