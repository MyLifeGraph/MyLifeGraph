import '../../../core/config/app_config.dart';
import '../../../core/contracts/account_deletion.dart';
import '../domain/account_settings.dart';
import '../domain/account_settings_repository.dart';
import 'account_api_data_source.dart';
import 'account_deletion_coordinator.dart';

typedef AccountAccessTokenProvider = String? Function();

class AccountAuthSnapshot {
  const AccountAuthSnapshot({required this.userId, required this.accessToken});

  final String userId;
  final String accessToken;
}

typedef AccountAuthSnapshotProvider = AccountAuthSnapshot? Function();

AccountAuthSnapshot? _noAccountAuthSnapshot() => null;

class AccountSettingsRepositoryImpl implements AccountSettingsRepository {
  const AccountSettingsRepositoryImpl({
    required AppConfig config,
    required AccountApiDataSource apiDataSource,
    AccountDeletionCoordinator? deletionCoordinator,
    required AccountAccessTokenProvider accessTokenProvider,
    AccountAuthSnapshotProvider authSnapshotProvider = _noAccountAuthSnapshot,
    required bool canUseSyncedAccount,
  })  : _config = config,
        _apiDataSource = apiDataSource,
        _deletionCoordinator = deletionCoordinator,
        _accessTokenProvider = accessTokenProvider,
        _authSnapshotProvider = authSnapshotProvider,
        _canUseSyncedAccount = canUseSyncedAccount;

  final AppConfig _config;
  final AccountApiDataSource _apiDataSource;
  final AccountDeletionCoordinator? _deletionCoordinator;
  final AccountAccessTokenProvider _accessTokenProvider;
  final AccountAuthSnapshotProvider _authSnapshotProvider;
  final bool _canUseSyncedAccount;

  @override
  Future<AccountTimezoneWrite> updateTimezone(
    String timezone, {
    required int expectedRevision,
  }) async {
    final cleanTimezone = timezone.trim();
    if (!isValidAccountTimezone(cleanTimezone)) {
      throw const AccountSettingsContractException(
        'Choose a supported IANA timezone.',
      );
    }
    return _apiDataSource.updateTimezone(
      accessToken: _requireAccessToken(),
      expectedRevision: expectedRevision,
      timezone: cleanTimezone,
    );
  }

  @override
  Future<AccountPreparationBudgetWrite> updateDailyPreparationBudget(
    int? minutes, {
    required int expectedRevision,
  }) async {
    if (!isValidDailyPreparationBudget(minutes)) {
      throw const AccountSettingsContractException(
        'Choose 25 to 480 minutes in five-minute steps.',
      );
    }
    return _apiDataSource.updateDailyPreparationBudget(
      accessToken: _requireAccessToken(),
      expectedRevision: expectedRevision,
      minutes: minutes,
    );
  }

  @override
  Future<AccountExportEnvelope> exportAccount() async {
    return _apiDataSource.exportAccount(accessToken: _requireAccessToken());
  }

  @override
  Future<AccountDeletionResult> deleteAccount({
    required String expectedUserId,
  }) async {
    final deletionCoordinator = _deletionCoordinator;
    final snapshot = _authSnapshotProvider();
    if (deletionCoordinator == null ||
        snapshot == null ||
        snapshot.userId != expectedUserId ||
        snapshot.userId.isEmpty ||
        snapshot.accessToken.trim().isEmpty) {
      throw const AccountSettingsAccessException(
        'Your account identity is unavailable. Sign in again and retry.',
      );
    }
    return deletionCoordinator.request(
      userId: snapshot.userId,
      accessToken: snapshot.accessToken,
      principalStillMatches: () =>
          _authSnapshotProvider()?.userId == expectedUserId,
    );
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
