import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../../composition/account_deletion_providers.dart';
import '../../application/account_export_saver.dart';
import '../../data/account_settings_repository_impl.dart';
import '../../domain/account_settings_repository.dart';

final accountAccessTokenProvider = Provider<AccountAccessTokenProvider>(
  (ref) =>
      () => ref.read(supabaseClientProvider)?.auth.currentSession?.accessToken,
);

final accountAuthSnapshotProvider = Provider<AccountAuthSnapshotProvider>(
  (ref) => () {
    final session = ref.read(supabaseClientProvider)?.auth.currentSession;
    if (session == null) return null;
    return AccountAuthSnapshot(
      userId: session.user.id,
      accessToken: session.accessToken,
    );
  },
);

final accountSettingsRepositoryProvider = Provider<AccountSettingsRepository>(
  (ref) {
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    return AccountSettingsRepositoryImpl(
      config: ref.watch(appConfigProvider),
      apiDataSource: ref.watch(accountApiDataSourceProvider),
      deletionCoordinator: ref.watch(accountDeletionCoordinatorProvider),
      accessTokenProvider: ref.watch(accountAccessTokenProvider),
      authSnapshotProvider: ref.watch(accountAuthSnapshotProvider),
      canUseSyncedAccount: capabilities.canUseSyncedExecution,
    );
  },
);

final accountExportSaverProvider = Provider<AccountExportSaver>(
  (_) => const PlatformAccountExportSaver(),
);
