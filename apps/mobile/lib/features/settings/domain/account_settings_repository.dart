import 'account_settings.dart';

abstract interface class AccountSettingsRepository {
  Future<String> updateTimezone(String timezone);

  Future<AccountExportEnvelope> exportAccount();

  Future<void> deleteAccount();
}
