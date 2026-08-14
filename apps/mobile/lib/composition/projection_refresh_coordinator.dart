typedef DailySnapshotRefresh = Future<void> Function(String targetDate);
typedef ProjectionInvalidator = void Function(ProductProjection projection);

enum ProductProjection {
  latestDailyCapture,
  today,
  todayLatestCheckIn,
  todayFullWeek,
  planner,
  preparationWorkload,
  examWeekOutlook,
  examPlanHealth,
}

/// Coordinates the explicit read projections affected by a durable mutation.
///
/// This is a direct application service, not a broadcast event bus. Callers
/// name the mutation's domain impact; the app composition owns downstream
/// projection knowledge.
class ProjectionRefreshCoordinator {
  const ProjectionRefreshCoordinator({
    required DailySnapshotRefresh refreshDailySnapshot,
    required ProjectionInvalidator invalidateProjection,
  })  : _refreshDailySnapshot = refreshDailySnapshot,
        _invalidateProjection = invalidateProjection;

  final DailySnapshotRefresh _refreshDailySnapshot;
  final ProjectionInvalidator _invalidateProjection;

  Future<void> dailyCaptureChanged({
    required String targetDate,
    required bool refreshDailySnapshot,
  }) =>
      _refresh(
        targetDate: refreshDailySnapshot ? targetDate : null,
        projections: const [
          ProductProjection.latestDailyCapture,
          ProductProjection.today,
          ProductProjection.todayLatestCheckIn,
          ProductProjection.examWeekOutlook,
        ],
      );

  Future<void> habitOutcomeChanged({required String targetDate}) => _refresh(
        targetDate: targetDate,
        projections: const [
          ProductProjection.today,
          ProductProjection.todayFullWeek,
        ],
      );

  Future<void> habitDefinitionChanged({required String targetDate}) => _refresh(
        targetDate: targetDate,
        projections: const [
          ProductProjection.today,
          ProductProjection.todayFullWeek,
          ProductProjection.planner,
          ProductProjection.examPlanHealth,
        ],
      );

  /// Refreshes the snapshot after a Habit write initiated by Today.
  ///
  /// The Today page owns its durable-state reload so it can keep showing the
  /// saved stale projection when that read fails.
  Future<void> todayHabitOutcomeChanged({required String targetDate}) =>
      _refresh(
        targetDate: targetDate,
        projections: const [ProductProjection.todayFullWeek],
      );

  /// Refreshes foreign projections after a Task write initiated by Today.
  ///
  /// The Today page owns its durable-state reload so it can keep showing the
  /// saved stale projection when that read fails.
  Future<void> todayTaskChanged({required String targetDate}) => _refresh(
        targetDate: targetDate,
        projections: const [
          ProductProjection.planner,
          ProductProjection.todayFullWeek,
          ProductProjection.preparationWorkload,
          ProductProjection.examWeekOutlook,
          ProductProjection.examPlanHealth,
        ],
      );

  Future<void> focusChanged({required String targetDate}) => _refresh(
        targetDate: targetDate,
        projections: const [
          ProductProjection.today,
          ProductProjection.todayFullWeek,
          ProductProjection.preparationWorkload,
          ProductProjection.examWeekOutlook,
          ProductProjection.examPlanHealth,
        ],
      );

  Future<void> deadlinePlanChanged({String? targetDate}) => _refresh(
        targetDate: targetDate,
        projections: const [
          ProductProjection.today,
          ProductProjection.todayFullWeek,
          ProductProjection.planner,
          ProductProjection.preparationWorkload,
          ProductProjection.examWeekOutlook,
          ProductProjection.examPlanHealth,
        ],
      );

  Future<void> plannerChanged({String? targetDate}) => _refresh(
        targetDate: targetDate,
        projections: const [
          ProductProjection.today,
          ProductProjection.todayFullWeek,
          ProductProjection.preparationWorkload,
          ProductProjection.examWeekOutlook,
          ProductProjection.examPlanHealth,
        ],
      );

  Future<void> setupChanged() => _refresh(
        projections: const [
          ProductProjection.today,
          ProductProjection.planner,
          ProductProjection.todayFullWeek,
          ProductProjection.preparationWorkload,
          ProductProjection.examWeekOutlook,
          ProductProjection.examPlanHealth,
        ],
      );

  Future<void> timezoneChanged() => _refresh(
        projections: const [
          ProductProjection.latestDailyCapture,
          ProductProjection.today,
          ProductProjection.todayLatestCheckIn,
          ProductProjection.todayFullWeek,
          ProductProjection.planner,
          ProductProjection.preparationWorkload,
          ProductProjection.examWeekOutlook,
          ProductProjection.examPlanHealth,
        ],
      );

  Future<void> preparationBudgetChanged() => _refresh(
        projections: const [
          ProductProjection.preparationWorkload,
          ProductProjection.examPlanHealth,
        ],
      );

  Future<void> calendarPlanningChanged() => _refresh(
        projections: const [
          ProductProjection.planner,
          ProductProjection.preparationWorkload,
          ProductProjection.examWeekOutlook,
          ProductProjection.examPlanHealth,
          ProductProjection.today,
          ProductProjection.todayFullWeek,
        ],
      );

  Future<void> focusReflectionChanged() => _refresh();

  Future<void> _refresh({
    String? targetDate,
    List<ProductProjection> projections = const [],
  }) async {
    if (targetDate == null) {
      _invalidateAll(projections);
      return;
    }
    try {
      await _refreshDailySnapshot(targetDate);
    } finally {
      _invalidateAll(projections);
    }
  }

  void _invalidateAll(List<ProductProjection> projections) {
    for (final projection in projections) {
      _invalidateProjection(projection);
    }
  }
}
