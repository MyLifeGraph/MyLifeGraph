import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../application/planner_controller.dart';
import '../../data/planner_api_data_source.dart';

final plannerApiDataSourceProvider = Provider<PlannerApiDataSource>(
  (ref) => PlannerApiDataSource(ref.watch(apiClientProvider)),
);

final plannerControllerProvider =
    StateNotifierProvider.autoDispose<PlannerController, PlannerState>((ref) {
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  final config = ref.watch(appConfigProvider);
  return PlannerController(
    api: ref.watch(plannerApiDataSourceProvider),
    accessTokenProvider: () =>
        ref.read(supabaseClientProvider)?.auth.currentSession?.accessToken,
    canUseSyncedPlanner: capabilities.canUseSyncedExecution,
    isBackendConfigured: config.isSupabaseConfigured,
  );
});
