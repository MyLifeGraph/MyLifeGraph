import '../../../core/contracts/account_deletion.dart';
import '../domain/account_settings.dart';
import 'account_api_data_source.dart';
import 'account_deletion_pending_store.dart';

class AccountDeletionCoordinator {
  const AccountDeletionCoordinator({
    required AccountApiDataSource apiDataSource,
    required AccountDeletionPendingStore pendingStore,
  })  : _apiDataSource = apiDataSource,
        _pendingStore = pendingStore;

  final AccountApiDataSource _apiDataSource;
  final AccountDeletionPendingStore _pendingStore;

  Future<AccountDeletionResult> request({
    required String userId,
    required String accessToken,
    required bool Function() principalStillMatches,
  }) async {
    if (!principalStillMatches()) {
      throw const AccountSettingsAccessException(
        'Your account changed before deletion could start.',
      );
    }
    final deletionId = await _pendingStore.getOrCreate(userId: userId);
    if (!principalStillMatches()) {
      await _pendingStore.clearForUser(userId: userId);
      throw const AccountSettingsAccessException(
        'Your account changed before deletion could start.',
      );
    }
    try {
      final result = await _apiDataSource.deleteAccount(
        accessToken: accessToken,
        deletionId: deletionId,
      );
      if (result.isCompleted) {
        await _pendingStore.clearForUser(userId: userId);
      }
      return result;
    } on AccountRecentAuthenticationRequiredException {
      await _pendingStore.clearForUser(userId: userId);
      rethrow;
    }
  }

  Future<AccountDeletionRecovery?> resume({
    required String userId,
    required String accessToken,
  }) async {
    final localDeletionId = await _pendingStore.read(userId: userId);
    AccountDeletionResult? knownStatus;
    try {
      knownStatus = await _apiDataSource.getAccountDeletionStatus(
        accessToken: accessToken,
      );
    } catch (_) {
      if (localDeletionId == null) rethrow;
    }
    final deletionId = knownStatus?.deletionId ?? localDeletionId;
    if (deletionId == null) return null;
    if (knownStatus != null && localDeletionId != knownStatus.deletionId) {
      await _pendingStore.record(
        userId: userId,
        deletionId: knownStatus.deletionId,
      );
    }
    try {
      final result = await _apiDataSource.deleteAccount(
        accessToken: accessToken,
        deletionId: deletionId,
      );
      if (result.isCompleted) {
        await _pendingStore.clearForUser(userId: userId);
      }
      return AccountDeletionRecovery(
        deletionId: deletionId,
        result: result,
      );
    } catch (_) {
      // The durable local identity is retained. The dedicated recovery surface
      // can retry it without first depending on a profile read that deletion
      // RLS intentionally blocks.
      return AccountDeletionRecovery(
        deletionId: deletionId,
        result: knownStatus,
      );
    }
  }
}
