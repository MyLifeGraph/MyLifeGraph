import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_life_graph/composition/dashboard_providers.dart';
import 'package:my_life_graph/composition/deadline_plan_providers.dart';
import '../features/planner/presentation/providers/planner_providers.dart';
import 'package:my_life_graph/composition/quick_check_in_providers.dart';
import '../features/snapshots/presentation/providers/snapshot_providers.dart';
import 'projection_refresh_coordinator.dart';

export 'projection_refresh_coordinator.dart';

final projectionRefreshCoordinatorProvider =
    Provider<ProjectionRefreshCoordinator>((ref) {
  return ProjectionRefreshCoordinator(
    refreshDailySnapshot: (targetDate) => ref
        .read(snapshotRefreshServiceProvider)
        .refreshDailyAfterUserSignal(targetDate: targetDate),
    invalidateProjection: (projection) {
      switch (projection) {
        case ProductProjection.latestDailyCapture:
          ref.invalidate(latestQuickCheckInProvider);
        case ProductProjection.today:
          ref.invalidate(dashboardSnapshotProvider);
        case ProductProjection.todayLatestCheckIn:
          ref.invalidate(dashboardLatestCheckInProvider);
        case ProductProjection.todayFullWeek:
          ref.invalidate(dashboardFullWeekProvider);
        case ProductProjection.planner:
          ref.invalidate(plannerControllerProvider);
        case ProductProjection.preparationWorkload:
          ref.invalidate(preparationWorkloadProvider);
        case ProductProjection.examWeekOutlook:
          ref.invalidate(examWeekOutlookProvider);
        case ProductProjection.examPlanHealth:
          ref.invalidate(examPlanHealthProvider);
      }
    },
  );
});
