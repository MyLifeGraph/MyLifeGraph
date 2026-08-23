import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/supabase/supabase_providers.dart';
import '../core/utils/client_uuid.dart';
import '../features/focus/application/focus_protection_reconciler.dart';
import '../features/focus/application/focus_recovery_store.dart';
import '../features/focus/application/focus_session_controller.dart';
import '../features/focus/data/focus_session_supabase_data_source.dart';
import '../features/focus/data/shared_preferences_focus_recovery_store.dart';
import '../features/focus_protection/application/focus_protection_gateway.dart';
import 'profile_local_date_providers.dart';
import 'projection_refresh_providers.dart';

final focusSessionPageDataSourceProvider =
    Provider<FocusSessionSupabaseDataSource?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? null
      : FocusSessionSupabaseDataSource(
          client,
          entryDateProvider:
              ref.watch(profileLocalDateSourceProvider).dateKeyAt,
          apiClient: ref.watch(apiClientProvider),
          accessTokenProvider: () async => ref
              .read(supabaseClientProvider)
              ?.auth
              .currentSession
              ?.accessToken,
        );
});

final focusStudySettingsDataSourceProvider =
    Provider<FocusSessionSupabaseDataSource?>((ref) {
  return ref.watch(focusSessionPageDataSourceProvider);
});

final focusRecoveryStoreProvider = Provider<FocusRecoveryStore>((ref) {
  return const SharedPreferencesFocusRecoveryStore();
});

final focusSessionControllerProvider = StateNotifierProvider.autoDispose
    .family<FocusSessionController, FocusSessionState, FocusSessionLaunch>(
  (ref, launch) {
    final projectionRefresh = ref.watch(projectionRefreshCoordinatorProvider);
    return FocusSessionController(
      launch: launch,
      source: ref.watch(focusSessionPageDataSourceProvider),
      studySource: ref.watch(focusStudySettingsDataSourceProvider),
      protection: FocusProtectionReconciler(
        gateway: ref.watch(focusProtectionGatewayProvider),
        platformSupported: ref.watch(focusProtectionPlatformSupportedProvider),
      ),
      recoveryStore: ref.watch(focusRecoveryStoreProvider),
      refreshProjection: (targetDate) =>
          projectionRefresh.focusChanged(targetDate: targetDate),
      refreshReflectionProjection: projectionRefresh.focusReflectionChanged,
      requestIdFactory: newClientUuid,
      useMockData: ref.watch(appConfigProvider).useMockData,
    );
  },
);
