import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/capabilities/app_surface_capabilities.dart';
import '../core/network/api_client.dart';
import '../core/supabase/supabase_providers.dart';
import '../features/dashboard/data/datasources/deadline_preparation_schedule_data_source.dart';
import '../features/dashboard/data/datasources/dashboard_full_week_supabase_data_source.dart';
import '../features/dashboard/data/datasources/dashboard_supabase_data_source.dart';
import '../features/dashboard/data/datasources/today_overview_api_data_source.dart';
import '../features/dashboard/data/repositories/dashboard_repository_impl.dart';
import '../features/dashboard/domain/deadline_plan_schedule_merger.dart';
import '../features/dashboard/domain/entities/dashboard_full_week.dart';
import '../features/dashboard/domain/entities/dashboard_snapshot.dart';
import '../features/dashboard/domain/repositories/dashboard_repository.dart';
import '../features/deadline_plans/domain/deadline_plan.dart';
import 'dashboard_guest_snapshot_adapter.dart';
import 'deadline_plan_providers.dart';
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

final dashboardFullWeekDataSourceProvider =
    Provider<DashboardFullWeekDataSource?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : DashboardFullWeekSupabaseDataSource(client);
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

    final source = ref.watch(dashboardFullWeekDataSourceProvider);
    final commitmentsReadFuture = _captureDashboardRead(
      () => source == null
          ? Future<List<DashboardSetupCommitmentFact>>.error(
              const DashboardFullWeekDataException(
                'Setup commitments are unavailable.',
              ),
            )
          : source.getSetupCommitments(),
    );
    final deadlinePlanRepository = capabilities.canUseDeadlinePlanner
        ? ref.watch(deadlinePlanRepositoryProvider)
        : null;
    final preparationReadFuture =
        _captureDashboardRead<List<DashboardPreparationBlockFact>?>(() async {
      if (deadlinePlanRepository == null) return null;
      final feed = await deadlinePlanRepository.getPlans();
      return _preparationFacts(feed, displayedLocalDate);
    });

    // Both reads own an error handler from the moment they start. Awaiting them
    // sequentially therefore cannot surface the faster failure as an unhandled
    // asynchronous error while the other source is still pending.
    final commitmentsRead = await commitmentsReadFuture;
    final preparationRead = await preparationReadFuture;
    if (commitmentsRead.error != null &&
        (!capabilities.canUseDeadlinePlanner ||
            preparationRead.error != null)) {
      throw const DashboardFullWeekDataException(
        'Full-week sources are unavailable.',
      );
    }

    final commitments = commitmentsRead.value ?? const [];
    final commitmentLoadError = commitmentsRead.error == null
        ? null
        : 'Setup commitments could not be loaded. Available Preparation items are still shown.';

    final preparationBlocks = preparationRead.value ?? const [];
    final preparationLoadError = preparationRead.error == null
        ? null
        : 'Preparation blocks could not be loaded. Available Setup commitments are still shown.';

    Map<String, List<DashboardBlockFocusFact>> focusByBlock = const {};
    String? ratingLoadError;
    if (preparationBlocks.isNotEmpty && source != null) {
      try {
        focusByBlock = await source.getBlockFocusFacts(
          preparationBlocks.map((block) => block.id),
        );
      } catch (_) {
        ratingLoadError =
            'Rating status could not be loaded. Known completed blocks remain checked.';
      }
    } else if (preparationBlocks.isNotEmpty) {
      ratingLoadError =
          'Rating status could not be loaded. Known completed blocks remain checked.';
    }

    return const DashboardFullWeekProjector().project(
      displayedLocalDate: displayedLocalDate,
      commitments: commitments,
      preparationBlocks: preparationBlocks,
      focusByBlock: focusByBlock,
      commitmentLoadError: commitmentLoadError,
      preparationLoadError: preparationLoadError,
      ratingLoadError: ratingLoadError,
    );
  },
);

Future<_DashboardRead<T>> _captureDashboardRead<T>(
  Future<T> Function() read,
) async {
  try {
    return _DashboardRead.success(await read());
  } catch (error) {
    return _DashboardRead.failure(error);
  }
}

class _DashboardRead<T> {
  const _DashboardRead.success(this.value) : error = null;

  const _DashboardRead.failure(this.error) : value = null;

  final T? value;
  final Object? error;
}

List<DashboardPreparationBlockFact> _preparationFacts(
  DeadlinePlanFeed feed,
  DateTime displayedLocalDate,
) {
  final facts = <DashboardPreparationBlockFact>[];
  final displayed = DateTime.utc(
    displayedLocalDate.year,
    displayedLocalDate.month,
    displayedLocalDate.day,
  );
  final monday = displayed.subtract(Duration(days: displayed.weekday - 1));
  final firstDate = _dateKey(monday);
  final lastDate = _dateKey(monday.add(const Duration(days: 6)));
  for (final plan in feed.plans) {
    if (plan.status == DeadlinePlanStatus.cancelled) continue;
    final revision = plan.activeRevision;
    if (revision == null) continue;
    for (final block in revision.blocks) {
      if (block.localDate.compareTo(firstDate) < 0 ||
          block.localDate.compareTo(lastDate) > 0) {
        continue;
      }
      facts.add(
        DashboardPreparationBlockFact(
          id: block.id,
          planId: plan.id,
          planTitle: plan.title,
          localDate: block.localDate,
          localStartTime: block.localStartTime,
          localEndTime: block.localEndTime,
          sortMinutes: _timeMinutes(block.localStartTime),
          state: block.state.code,
          recoveryMinutes: block.recoveryMinutes,
          reservedLocalEndTime: _addMinutes(
            block.localEndTime,
            block.recoveryMinutes,
          ),
        ),
      );
      if (facts.length > maxDashboardFullWeekBlocks) {
        throw const DashboardFullWeekDataException(
          'Preparation block result exceeded its bounded size.',
        );
      }
    }
  }
  return List.unmodifiable(facts);
}

int _timeMinutes(String value) {
  final parts = value.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String _addMinutes(String value, int minutes) {
  final total = _timeMinutes(value) + minutes;
  final hours = (total ~/ 60) % 24;
  final minute = total % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
}

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
