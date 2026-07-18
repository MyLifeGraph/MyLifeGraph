import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../application/deadline_plan_controller.dart';
import '../../data/deadline_calendar_prefill_data_source.dart';
import '../../data/deadline_plan_api_data_source.dart';
import '../../data/deadline_plan_repository_impl.dart';
import '../../domain/deadline_plan_repository.dart';
import '../../domain/deadline_calendar_prefill.dart';

final deadlinePlanApiDataSourceProvider = Provider<DeadlinePlanApiDataSource>(
  (ref) => DeadlinePlanApiDataSource(ref.watch(apiClientProvider)),
);

final deadlinePlanAccessTokenProvider =
    Provider<DeadlinePlanAccessTokenProvider>(
  (ref) =>
      () => ref.read(supabaseClientProvider)?.auth.currentSession?.accessToken,
);

final deadlinePlanRepositoryProvider = Provider<DeadlinePlanRepository>((ref) {
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  return DeadlinePlanRepositoryImpl(
    config: ref.watch(appConfigProvider),
    apiDataSource: ref.watch(deadlinePlanApiDataSourceProvider),
    accessTokenProvider: ref.watch(deadlinePlanAccessTokenProvider),
    canUseSyncedPlanner: capabilities.canUseDeadlinePlanner,
  );
});

final deadlineCalendarPrefillDataSourceProvider =
    Provider<DeadlineCalendarPrefillDataSource?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? null
      : DeadlineCalendarPrefillSupabaseDataSource(client);
});

final deadlineCalendarPrefillProvider = FutureProvider.autoDispose
    .family<DeadlineCalendarPrefill, String>((ref, eventId) async {
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  final dataSource = ref.watch(deadlineCalendarPrefillDataSourceProvider);
  if (!capabilities.canUseDeadlinePlanner || dataSource == null) {
    throw const DeadlineCalendarPrefillException(
      'Calendar preparation prefill requires a synced account.',
    );
  }
  return dataSource.getEvent(eventId);
});

final deadlinePlanControllerProvider = StateNotifierProvider.autoDispose<
    DeadlinePlanController, DeadlinePlanState>((ref) {
  return DeadlinePlanController(
    repository: ref.watch(deadlinePlanRepositoryProvider),
  );
});
