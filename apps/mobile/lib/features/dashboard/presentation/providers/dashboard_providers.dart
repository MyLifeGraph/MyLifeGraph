import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../quick_action/presentation/providers/quick_check_in_providers.dart';
import '../../data/datasources/deadline_preparation_schedule_data_source.dart';
import '../../data/datasources/dashboard_mock_data_source.dart';
import '../../data/datasources/dashboard_supabase_data_source.dart';
import '../../data/datasources/today_overview_api_data_source.dart';
import '../../data/repositories/dashboard_repository_impl.dart';
import '../../domain/entities/dashboard_snapshot.dart';
import '../../domain/deadline_plan_schedule_merger.dart';
import '../../domain/repositories/dashboard_repository.dart';

final dashboardMockDataSourceProvider = Provider<DashboardMockDataSource>(
  (ref) => DashboardMockDataSource(
    quickCheckInStore: ref.watch(quickCheckInStoreProvider),
  ),
);

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    final allowMockData = ref.watch(appSurfaceCapabilitiesProvider).isLocalDemo;
    return DashboardRepositoryImpl(
      mockDataSource: ref.watch(dashboardMockDataSourceProvider),
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

/// Legacy detail/week projection loaded only after the user expands More.
/// The primary Today read remains the read-only `today-overview-v1` API.
final dashboardSupportingSnapshotProvider =
    FutureProvider.autoDispose<DashboardSnapshot>((ref) async {
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  if (capabilities.isLocalDemo) {
    return ref.watch(dashboardMockDataSourceProvider).getSnapshot();
  }
  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    throw const DashboardUnavailableException(
      'Supporting account details are unavailable.',
    );
  }
  final snapshot = await DashboardSupabaseDataSource(client).getSnapshot();
  if (!capabilities.canUseDeadlinePlanner) return snapshot;
  final preparation = ref.watch(deadlinePreparationScheduleDataSourceProvider);
  const merger = DeadlinePlanScheduleMerger();
  if (preparation == null) {
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
    final blocks = await preparation.getActiveBlocksForWeek(
      startDate: displayedDates.first,
      endDate: displayedDates.last,
    );
    return merger.merge(snapshot, blocks);
  } catch (_) {
    return merger.withUnavailablePreparationSchedule(snapshot);
  }
});
