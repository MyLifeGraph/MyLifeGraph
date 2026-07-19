import 'account_settings.dart';

abstract interface class AccountSettingsRepository {
  Future<String> updateTimezone(String timezone);

  Future<int?> updateDailyPreparationBudget(int? minutes);

  Future<AccountExportEnvelope> exportAccount();

  Future<void> deleteAccount();
}
