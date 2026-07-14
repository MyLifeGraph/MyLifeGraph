import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../application/account_export_saver.dart';
import '../../data/account_api_data_source.dart';
import '../../data/account_settings_repository_impl.dart';
import '../../domain/account_settings_repository.dart';

final accountApiDataSourceProvider = Provider<AccountApiDataSource>(
  (ref) => AccountApiDataSource(ref.watch(apiClientProvider)),
);

final accountAccessTokenProvider = Provider<AccountAccessTokenProvider>(
  (ref) =>
      () => ref.read(supabaseClientProvider)?.auth.currentSession?.accessToken,
);

final accountSettingsRepositoryProvider = Provider<AccountSettingsRepository>(
  (ref) {
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    return AccountSettingsRepositoryImpl(
      config: ref.watch(appConfigProvider),
      apiDataSource: ref.watch(accountApiDataSourceProvider),
      accessTokenProvider: ref.watch(accountAccessTokenProvider),
      canUseSyncedAccount: capabilities.canUseSyncedExecution,
    );
  },
);

final accountExportSaverProvider = Provider<AccountExportSaver>(
  (_) => const PlatformAccountExportSaver(),
);
