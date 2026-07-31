import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/projection_refresh_coordinator.dart';

void main() {
  late List<String> snapshotDates;
  late List<ProductProjection> invalidated;
  late ProjectionRefreshCoordinator coordinator;

  setUp(() {
    snapshotDates = [];
    invalidated = [];
    coordinator = ProjectionRefreshCoordinator(
      refreshDailySnapshot: (targetDate) async {
        snapshotDates.add(targetDate);
      },
      invalidateProjection: invalidated.add,
    );
  });

  test('daily capture refreshes its snapshot and exact dependent projections',
      () async {
    await coordinator.dailyCaptureChanged(
      targetDate: '2026-07-31',
      refreshDailySnapshot: true,
    );

    expect(snapshotDates, ['2026-07-31']);
    expect(invalidated, [
      ProductProjection.latestDailyCapture,
      ProductProjection.today,
      ProductProjection.examWeekOutlook,
    ]);
  });

  test('guest capture invalidates local reads without a remote refresh',
      () async {
    await coordinator.dailyCaptureChanged(
      targetDate: '2026-07-31',
      refreshDailySnapshot: false,
    );

    expect(snapshotDates, isEmpty);
    expect(invalidated, [
      ProductProjection.latestDailyCapture,
      ProductProjection.today,
      ProductProjection.examWeekOutlook,
    ]);
  });

  test('habit definition names planning and Today projections explicitly',
      () async {
    await coordinator.habitDefinitionChanged(targetDate: '2026-07-31');

    expect(snapshotDates, ['2026-07-31']);
    expect(invalidated, [
      ProductProjection.today,
      ProductProjection.planner,
    ]);
  });

  test('Today-owned task reload is not invalidated by the coordinator',
      () async {
    await coordinator.todayTaskChanged(targetDate: '2026-07-31');

    expect(snapshotDates, ['2026-07-31']);
    expect(invalidated, [
      ProductProjection.planner,
      ProductProjection.preparationWorkload,
      ProductProjection.examWeekOutlook,
    ]);
    expect(invalidated, isNot(contains(ProductProjection.today)));
  });

  test('Today-owned habit reload refreshes only its snapshot input', () async {
    await coordinator.todayHabitOutcomeChanged(targetDate: '2026-07-31');

    expect(snapshotDates, ['2026-07-31']);
    expect(invalidated, isEmpty);
    expect(invalidated, isNot(contains(ProductProjection.today)));
  });

  test('focus change refreshes execution and capacity projections', () async {
    await coordinator.focusChanged(targetDate: '2026-07-31');

    expect(snapshotDates, ['2026-07-31']);
    expect(invalidated, [
      ProductProjection.today,
      ProductProjection.preparationWorkload,
      ProductProjection.examWeekOutlook,
    ]);
  });

  test('deadline plan change refreshes every dependent planning read',
      () async {
    await coordinator.deadlinePlanChanged(targetDate: '2026-07-31');

    expect(snapshotDates, ['2026-07-31']);
    expect(invalidated, [
      ProductProjection.today,
      ProductProjection.planner,
      ProductProjection.preparationWorkload,
      ProductProjection.examWeekOutlook,
    ]);
  });

  test('planner change leaves its owned overview to the controller', () async {
    await coordinator.plannerChanged(targetDate: '2026-07-31');

    expect(snapshotDates, ['2026-07-31']);
    expect(invalidated, [
      ProductProjection.today,
      ProductProjection.preparationWorkload,
      ProductProjection.examWeekOutlook,
    ]);
    expect(invalidated, isNot(contains(ProductProjection.planner)));
  });

  test('setup change invalidates all setup-derived reads without a write',
      () async {
    await coordinator.setupChanged();

    expect(snapshotDates, isEmpty);
    expect(invalidated, [
      ProductProjection.today,
      ProductProjection.recommendations,
      ProductProjection.planner,
      ProductProjection.preparationWorkload,
      ProductProjection.examWeekOutlook,
    ]);
  });

  test('recommendation refresh keeps snapshot input and feed impacts separate',
      () async {
    await coordinator.recommendationInputsChanged(targetDate: '2026-07-31');

    expect(snapshotDates, ['2026-07-31']);
    expect(invalidated, isEmpty);

    await coordinator.recommendationsChanged();
    expect(snapshotDates, ['2026-07-31']);
    expect(invalidated, [
      ProductProjection.recommendations,
      ProductProjection.today,
    ]);
  });

  test('settings-only impact invalidates no unrelated projection', () async {
    await coordinator.preparationBudgetChanged();

    expect(snapshotDates, isEmpty);
    expect(invalidated, [ProductProjection.preparationWorkload]);
  });

  test('projection invalidation still happens when snapshot refresh fails',
      () async {
    coordinator = ProjectionRefreshCoordinator(
      refreshDailySnapshot: (_) => throw StateError('snapshot failed'),
      invalidateProjection: invalidated.add,
    );

    await expectLater(
      coordinator.habitOutcomeChanged(targetDate: '2026-07-31'),
      throwsStateError,
    );
    expect(invalidated, [
      ProductProjection.today,
    ]);
  });

  test('timezone change invalidates every date-bound projection without write',
      () async {
    await coordinator.timezoneChanged();

    expect(snapshotDates, isEmpty);
    expect(invalidated, [
      ProductProjection.latestDailyCapture,
      ProductProjection.today,
      ProductProjection.recommendations,
      ProductProjection.planner,
      ProductProjection.preparationWorkload,
      ProductProjection.examWeekOutlook,
    ]);
  });
}
