import '../../../core/contracts/account_deletion.dart';
import 'account_settings.dart';

abstract interface class AccountSettingsRepository {
  Future<AccountTimezoneWrite> updateTimezone(
    String timezone, {
    required int expectedRevision,
  });

  Future<AccountPreparationBudgetWrite> updateDailyPreparationBudget(
    int? minutes, {
    required int expectedRevision,
  });

  Future<AccountExportEnvelope> exportAccount();

  Future<AccountDeletionResult> deleteAccount({required String expectedUserId});
}
