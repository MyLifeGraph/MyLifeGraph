import '../../../core/config/app_config.dart';
import '../domain/account_settings.dart';
import '../domain/account_settings_repository.dart';
import 'account_api_data_source.dart';

typedef AccountAccessTokenProvider = String? Function();

class AccountSettingsRepositoryImpl implements AccountSettingsRepository {
  const AccountSettingsRepositoryImpl({
    required AppConfig config,
    required AccountApiDataSource apiDataSource,
    required AccountAccessTokenProvider accessTokenProvider,
    required bool canUseSyncedAccount,
  })  : _config = config,
        _apiDataSource = apiDataSource,
        _accessTokenProvider = accessTokenProvider,
        _canUseSyncedAccount = canUseSyncedAccount;

  final AppConfig _config;
  final AccountApiDataSource _apiDataSource;
  final AccountAccessTokenProvider _accessTokenProvider;
  final bool _canUseSyncedAccount;

  @override
  Future<String> updateTimezone(String timezone) async {
    final cleanTimezone = timezone.trim();
    if (!isValidAccountTimezone(cleanTimezone)) {
      throw const AccountSettingsContractException(
        'Choose a supported IANA timezone.',
      );
    }
    return _apiDataSource.updateTimezone(
      accessToken: _requireAccessToken(),
      timezone: cleanTimezone,
    );
  }

  @override
  Future<AccountExportEnvelope> exportAccount() async {
    return _apiDataSource.exportAccount(accessToken: _requireAccessToken());
  }

  @override
  Future<void> deleteAccount() async {
    await _apiDataSource.deleteAccount(accessToken: _requireAccessToken());
  }

  String _requireAccessToken() {
    if (_config.useMockData ||
        !_config.isSupabaseConfigured ||
        !_canUseSyncedAccount) {
      throw const AccountSettingsAccessException(
        'Account controls are available only for a synced account.',
      );
    }
    final token = _accessTokenProvider()?.trim();
    if (token == null || token.isEmpty) {
      throw const AccountSettingsAccessException(
        'Your account session is unavailable. Sign in again and retry.',
      );
    }
    return token;
  }
}
