import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/capabilities/app_surface_capabilities.dart';
import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/supabase/supabase_providers.dart';
import '../features/deadline_plans/application/deadline_plan_controller.dart';
import '../features/deadline_plans/application/assignment_series_controller.dart';
import '../features/deadline_plans/data/assignment_series_api_data_source.dart';
import '../features/deadline_plans/data/assignment_series_repository_impl.dart';
import '../features/deadline_plans/data/deadline_calendar_prefill_data_source.dart';
import '../features/deadline_plans/data/deadline_plan_api_data_source.dart';
import '../features/deadline_plans/data/deadline_plan_repository_impl.dart';
import '../features/deadline_plans/domain/deadline_calendar_prefill.dart';
import '../features/deadline_plans/domain/assignment_series_repository.dart';
import '../features/deadline_plans/domain/deadline_plan.dart';
import '../features/deadline_plans/domain/deadline_plan_repository.dart';
import '../features/deadline_plans/domain/exam_week_outlook.dart';
import 'profile_local_date_providers.dart';
import 'projection_refresh_providers.dart';

final deadlinePlanApiDataSourceProvider = Provider<DeadlinePlanApiDataSource>(
  (ref) => DeadlinePlanApiDataSource(ref.watch(apiClientProvider)),
);

final assignmentSeriesApiDataSourceProvider =
    Provider<AssignmentSeriesApiDataSource>(
  (ref) => AssignmentSeriesApiDataSource(ref.watch(apiClientProvider)),
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

final assignmentSeriesRepositoryProvider =
    Provider<AssignmentSeriesRepository>((ref) {
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  return AssignmentSeriesRepositoryImpl(
    config: ref.watch(appConfigProvider),
    apiDataSource: ref.watch(assignmentSeriesApiDataSourceProvider),
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

final preparationWorkloadProvider =
    FutureProvider.autoDispose<PreparationWorkload>((ref) {
  return ref.watch(deadlinePlanRepositoryProvider).getWorkload();
});

final examWeekOutlookProvider =
    FutureProvider.autoDispose<ExamWeekOutlook?>((ref) async {
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  if (!capabilities.canUseDeadlinePlanner) {
    return null;
  }
  final token =
      ref.read(supabaseClientProvider)?.auth.currentSession?.accessToken;
  if (token == null || token.isEmpty) {
    throw const ExamWeekOutlookContractException(
      'Exam-week outlook requires an authenticated session.',
    );
  }
  return ref
      .watch(deadlinePlanApiDataSourceProvider)
      .getExamWeekOutlook(accessToken: token);
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
  final projectionRefresh = ref.watch(projectionRefreshCoordinatorProvider);
  final profileLocalDate = ref.watch(profileLocalDateSourceProvider);
  return DeadlinePlanController(
    repository: ref.watch(deadlinePlanRepositoryProvider),
    projectionRefresh: ({required managedTaskChanged}) =>
        projectionRefresh.deadlinePlanChanged(
      targetDate: managedTaskChanged ? profileLocalDate.todayKey() : null,
    ),
  );
});

final assignmentSeriesControllerProvider = StateNotifierProvider.autoDispose<
    AssignmentSeriesController, AssignmentSeriesState>((ref) {
  return AssignmentSeriesController(
    repository: ref.watch(assignmentSeriesRepositoryProvider),
  );
});
