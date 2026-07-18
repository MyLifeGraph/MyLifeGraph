import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../quick_action/presentation/providers/quick_check_in_providers.dart';
import '../../data/datasources/deadline_preparation_schedule_data_source.dart';
import '../../data/datasources/dashboard_mock_data_source.dart';
import '../../data/datasources/dashboard_supabase_data_source.dart';
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
    FutureProvider<DashboardSnapshot>((ref) async {
  final repository = ref.watch(dashboardRepositoryProvider);
  final canLoadPreparation =
      ref.watch(appSurfaceCapabilitiesProvider).canUseDeadlinePlanner;
  final preparationDataSource = canLoadPreparation
      ? ref.watch(deadlinePreparationScheduleDataSourceProvider)
      : null;
  final snapshot = await repository.getSnapshot();
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
