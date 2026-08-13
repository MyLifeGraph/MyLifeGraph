import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/capabilities/app_surface_capabilities.dart';
import '../core/network/api_client.dart';
import '../core/supabase/supabase_providers.dart';
import '../features/dashboard/data/datasources/deadline_preparation_schedule_data_source.dart';
import '../features/dashboard/data/datasources/dashboard_full_week_api_data_source.dart';
import '../features/dashboard/data/datasources/dashboard_supabase_data_source.dart';
import '../features/dashboard/data/datasources/today_overview_api_data_source.dart';
import '../features/dashboard/data/repositories/dashboard_full_week_repository_impl.dart';
import '../features/dashboard/data/repositories/dashboard_repository_impl.dart';
import '../features/dashboard/domain/deadline_plan_schedule_merger.dart';
import '../features/dashboard/domain/entities/dashboard_full_week.dart';
import '../features/dashboard/domain/entities/dashboard_snapshot.dart';
import '../features/dashboard/domain/repositories/dashboard_full_week_repository.dart';
import '../features/dashboard/domain/repositories/dashboard_repository.dart';
import 'dashboard_guest_snapshot_adapter.dart';
import 'package:my_life_graph/composition/quick_check_in_providers.dart';

final dashboardMockDataSourceProvider = Provider<DashboardGuestSnapshotAdapter>(
  (ref) => DashboardGuestSnapshotAdapter(
    quickCheckInStore: ref.watch(quickCheckInStoreProvider),
  ),
);

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    final allowMockData = ref.watch(appSurfaceCapabilitiesProvider).isLocalDemo;
    final mockDataSource = ref.watch(dashboardMockDataSourceProvider);
    return DashboardRepositoryImpl(
      mockSnapshotLoader: mockDataSource.getSnapshot,
      supabaseDataSource:
          client == null ? null : DashboardSupabaseDataSource(client),
      todayApiDataSource: TodayOverviewApiDataSource(
        ref.watch(apiClientProvider),
      ),
      accessTokenProvider: () async =>
          ref.read(supabaseClientProvider)?.auth.currentSession?.accessToken,
      allowMockData: allowMockData,
    );
  },
);

final deadlinePreparationScheduleDataSourceProvider =
    Provider<DeadlinePreparationScheduleDataSource?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? null
      : DeadlinePreparationScheduleSupabaseDataSource(client);
});

final dashboardFullWeekApiDataSourceProvider =
    Provider<DashboardFullWeekApiDataSource>(
  (ref) => DashboardFullWeekApiDataSource(ref.watch(apiClientProvider)),
);

final dashboardFullWeekRepositoryProvider =
    Provider<DashboardFullWeekRepository>((ref) {
  return DashboardFullWeekRepositoryImpl(
    dataSource: ref.watch(dashboardFullWeekApiDataSourceProvider),
    accessTokenProvider: () async =>
        ref.read(supabaseClientProvider)?.auth.currentSession?.accessToken,
  );
});

final dashboardSnapshotProvider =
    FutureProvider.autoDispose<DashboardSnapshot>((ref) async {
  final repository = ref.watch(dashboardRepositoryProvider);
  final canLoadPreparation =
      ref.watch(appSurfaceCapabilitiesProvider).canUseDeadlinePlanner;
  final preparationDataSource = canLoadPreparation
      ? ref.watch(deadlinePreparationScheduleDataSourceProvider)
      : null;
  final snapshot = await repository.getSnapshot();
  if (snapshot.isTodayOverview) return snapshot;
  if (!canLoadPreparation || snapshot.origin != DashboardOrigin.account) {
    return snapshot;
  }
  const merger = DeadlinePlanScheduleMerger();
  if (preparationDataSource == null) {
    return merger.withUnavailablePreparationSchedule(snapshot);
  }
  final displayedDates = snapshot.scheduleDays
      .map((day) => day.date)
      .whereType<DateTime>()
      .map((date) => DateTime(date.year, date.month, date.day))
      .toList(growable: false)
    ..sort();
  if (displayedDates.isEmpty) return snapshot;
  try {
    final blocks = await preparationDataSource.getActiveBlocksForWeek(
      startDate: displayedDates.first,
      endDate: displayedDates.last,
    );
    return merger.merge(snapshot, blocks);
  } catch (_) {
    return merger.withUnavailablePreparationSchedule(snapshot);
  }
});

final dashboardLatestCheckInProvider = FutureProvider.autoDispose
    .family<DashboardCheckIn?, DateTime>((ref, displayedLocalDate) async {
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  if (capabilities.isLocalDemo) {
    final snapshot = await ref
        .watch(dashboardMockDataSourceProvider)
        .getSnapshot(throughLocalDate: displayedLocalDate);
    return snapshot.latestCheckIn;
  }
  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    throw const DashboardUnavailableException(
      'Saved check-in details are unavailable.',
    );
  }
  return DashboardSupabaseDataSource(client).getLatestCheckIn(
    throughLocalDate: displayedLocalDate,
  );
});

final dashboardFullWeekProvider =
    FutureProvider.autoDispose.family<DashboardFullWeekProjection, DateTime>(
  (ref, displayedLocalDate) async {
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    if (capabilities.isLocalDemo) {
      return DashboardFullWeekProjection.empty(displayedLocalDate);
    }
    if (!capabilities.canUseSyncedExecution) {
      throw const DashboardFullWeekUnavailableException(
        'Full week requires an authenticated account.',
      );
    }
    return ref.watch(dashboardFullWeekRepositoryProvider).getCurrentWeek();
  },
);
