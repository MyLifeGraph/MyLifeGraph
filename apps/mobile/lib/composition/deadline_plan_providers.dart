import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/capabilities/app_surface_capabilities.dart';
import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/supabase/supabase_providers.dart';
import '../features/auth/domain/app_session.dart';
import '../features/deadline_plans/application/deadline_plan_controller.dart';
import '../features/deadline_plans/application/assignment_series_controller.dart';
import '../features/deadline_plans/application/multi_exam_plan_controller.dart';
import '../features/deadline_plans/application/preparation_mutation_gate.dart';
import '../features/deadline_plans/data/assignment_series_api_data_source.dart';
import '../features/deadline_plans/data/assignment_series_repository_impl.dart';
import '../features/deadline_plans/data/deadline_calendar_prefill_data_source.dart';
import '../features/deadline_plans/data/deadline_plan_api_data_source.dart';
import '../features/deadline_plans/data/deadline_plan_repository_impl.dart';
import '../features/deadline_plans/data/exam_plan_health_api_data_source.dart';
import '../features/deadline_plans/data/exam_plan_health_repository_impl.dart';
import '../features/deadline_plans/data/multi_exam_plan_api_data_source.dart';
import '../features/deadline_plans/data/multi_exam_plan_repository_impl.dart';
import '../features/deadline_plans/domain/deadline_calendar_prefill.dart';
import '../features/deadline_plans/domain/assignment_series_repository.dart';
import '../features/deadline_plans/domain/deadline_plan.dart';
import '../features/deadline_plans/domain/deadline_plan_repository.dart';
import '../features/deadline_plans/domain/exam_week_outlook.dart';
import '../features/deadline_plans/domain/exam_plan_health.dart';
import '../features/deadline_plans/domain/exam_plan_health_repository.dart';
import '../features/deadline_plans/domain/multi_exam_plan_repository.dart';
import '../features/deadline_plans/domain/multi_exam_plan.dart';
import 'auth_providers.dart';
import 'profile_local_date_providers.dart';
import 'projection_refresh_providers.dart';

final deadlinePlanApiDataSourceProvider = Provider<DeadlinePlanApiDataSource>(
  (ref) => DeadlinePlanApiDataSource(ref.watch(apiClientProvider)),
);

final multiExamPlanApiDataSourceProvider = Provider<MultiExamPlanApiDataSource>(
  (ref) => MultiExamPlanApiDataSource(ref.watch(apiClientProvider)),
);

final preparationMutationGateProvider = Provider<PreparationMutationGate>(
  (_) => PreparationMutationGate(),
);

final examPlanHealthApiDataSourceProvider =
    Provider<ExamPlanHealthApiDataSource>(
  (ref) => ExamPlanHealthApiDataSource(ref.watch(apiClientProvider)),
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

final multiExamPlanRepositoryProvider =
    Provider<MultiExamPlanRepository>((ref) {
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  return MultiExamPlanRepositoryImpl(
    apiDataSource: ref.watch(multiExamPlanApiDataSourceProvider),
    accessTokenProvider: ref.watch(deadlinePlanAccessTokenProvider),
    canUseSyncedPlanner: capabilities.canUseDeadlinePlanner,
  );
});

final examPlanHealthRepositoryProvider =
    Provider<ExamPlanHealthRepository>((ref) {
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  return ExamPlanHealthRepositoryImpl(
    config: ref.watch(appConfigProvider),
    apiDataSource: ref.watch(examPlanHealthApiDataSourceProvider),
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

final examPlanHealthProvider =
    FutureProvider.autoDispose<ExamPlanHealth?>((ref) async {
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  if (!capabilities.canUseDeadlinePlanner) return null;
  return ref.watch(examPlanHealthRepositoryProvider).getHealth();
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
    mutationGate: ref.watch(preparationMutationGateProvider),
    projectionRefresh: ({required managedTaskChanged}) =>
        projectionRefresh.deadlinePlanChanged(
      targetDate: managedTaskChanged ? profileLocalDate.todayKey() : null,
    ),
  );
});

final assignmentSeriesControllerProvider = StateNotifierProvider.autoDispose<
    AssignmentSeriesController, AssignmentSeriesState>((ref) {
  final projectionRefresh = ref.watch(projectionRefreshCoordinatorProvider);
  final profileLocalDate = ref.watch(profileLocalDateSourceProvider);
  return AssignmentSeriesController(
    repository: ref.watch(assignmentSeriesRepositoryProvider),
    mutationGate: ref.watch(preparationMutationGateProvider),
    projectionRefresh: () => projectionRefresh.deadlinePlanChanged(
      targetDate: profileLocalDate.todayKey(),
    ),
  );
});

final multiExamPlanControllerProvider =
    StateNotifierProvider<MultiExamPlanController, MultiExamPlanState>((ref) {
  // Preserve an exact in-flight/retry identity across token and profile
  // refreshes. A transient Auth loading/error state is not a sign-out; only
  // an authoritative data state with a different principal replaces it.
  String? principalOf(AsyncValue<AppSession?> value) {
    final session = value.asData?.value;
    return session == null || session.isGuestSession
        ? null
        : session.profile.id;
  }

  var principal = principalOf(ref.read(authControllerProvider));
  ref.listen<AsyncValue<AppSession?>>(authControllerProvider, (_, next) {
    if (next.asData == null) return;
    final nextPrincipal = principalOf(next);
    if (nextPrincipal == principal) return;
    principal = nextPrincipal;
    ref.invalidateSelf();
  });
  return MultiExamPlanController(
    repository: _ReadingMultiExamPlanRepository(ref),
    mutationGate: ref.read(preparationMutationGateProvider),
    adoptSinglePlan: (plan) {
      ref.read(deadlinePlanControllerProvider.notifier).includeReadPlan(plan);
    },
    projectionRefresh: () async {
      final projectionRefresh = ref.read(projectionRefreshCoordinatorProvider);
      final profileLocalDate = ref.read(profileLocalDateSourceProvider);
      await projectionRefresh.deadlinePlanChanged(
        targetDate: profileLocalDate.todayKey(),
      );
      ref.invalidate(preparationWorkloadProvider);
      ref.invalidate(examPlanHealthProvider);
      await Future.wait([
        ref.read(deadlinePlanControllerProvider.notifier).load(),
        ref.read(assignmentSeriesControllerProvider.notifier).load(),
      ]);
    },
  );
});

class _ReadingMultiExamPlanRepository implements MultiExamPlanRepository {
  const _ReadingMultiExamPlanRepository(this._ref);

  final Ref _ref;

  MultiExamPlanRepository get _current =>
      _ref.read(multiExamPlanRepositoryProvider);

  @override
  Future<MultiExamPlanFeed> getBalances() => _current.getBalances();

  @override
  Future<MultiExamPlanBatch> getBalance(String balanceId) =>
      _current.getBalance(balanceId);

  @override
  Future<MultiExamPlanProposalResult> propose({
    required String requestId,
    required MultiExamPlanProposalDraft draft,
  }) =>
      _current.propose(requestId: requestId, draft: draft);

  @override
  Future<MultiExamPlanBatch> confirm({
    required String balanceId,
    required String requestId,
    required int expectedRevision,
  }) =>
      _current.confirm(
        balanceId: balanceId,
        requestId: requestId,
        expectedRevision: expectedRevision,
      );

  @override
  Future<MultiExamPlanBatch> cancel({
    required String balanceId,
    required String requestId,
    required int expectedRevision,
  }) =>
      _current.cancel(
        balanceId: balanceId,
        requestId: requestId,
        expectedRevision: expectedRevision,
      );
}
