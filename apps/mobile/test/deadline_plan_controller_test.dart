import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/deadline_plan_providers.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import 'package:my_life_graph/composition/projection_refresh_providers.dart';
import 'package:my_life_graph/core/network/api_failure.dart';
import 'package:my_life_graph/features/auth/application/profile_local_date_source.dart';
import 'package:my_life_graph/features/deadline_plans/application/deadline_plan_controller.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_plan.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_plan_repository.dart';

import 'support/deadline_plan_fixtures.dart';

void main() {
  test('confirm, complete, and active cancel refresh exactly once', () async {
    final cases = <({
      DeadlinePlan input,
      DeadlinePlan result,
      Future<bool> Function(DeadlinePlanController, DeadlinePlan) mutate,
    })>[
      (
        input: _plan(status: 'draft'),
        result: _plan(),
        mutate: (controller, plan) => controller.confirm(plan),
      ),
      (
        input: _plan(),
        result: _plan(status: 'completed'),
        mutate: (controller, plan) => controller.complete(plan),
      ),
      (
        input: _plan(),
        result: _plan(status: 'cancelled'),
        mutate: (controller, plan) => controller.cancel(plan),
      ),
    ];

    for (final testCase in cases) {
      final repository = _LifecycleRepository(result: testCase.result);
      final impacts = <bool>[];
      final controller = DeadlinePlanController(
        repository: repository,
        projectionRefresh: ({required managedTaskChanged}) async {
          impacts.add(managedTaskChanged);
        },
      );
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(await testCase.mutate(controller, testCase.input), isTrue);
      expect(impacts, [true]);
    }
  });

  test('draft cancel refreshes once without managed-task impact', () async {
    final repository = _LifecycleRepository(result: _cancelledDraft());
    final impacts = <bool>[];
    final controller = DeadlinePlanController(
      repository: repository,
      projectionRefresh: ({required managedTaskChanged}) async {
        impacts.add(managedTaskChanged);
      },
    );
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);

    expect(await controller.cancel(_plan(status: 'draft')), isTrue);
    expect(impacts, [false]);
  });

  test('composition invalidates draft cancel without a Snapshot date',
      () async {
    final snapshotDates = <String>[];
    final invalidations = <ProductProjection>[];
    final container = ProviderContainer(
      overrides: [
        deadlinePlanRepositoryProvider.overrideWithValue(
          _LifecycleRepository(result: _cancelledDraft()),
        ),
        profileLocalDateSourceProvider.overrideWithValue(
          SessionProfileLocalDateSource(
            session: null,
            currentInstant: () => DateTime(2026, 8, 5, 12),
          ),
        ),
        projectionRefreshCoordinatorProvider.overrideWithValue(
          ProjectionRefreshCoordinator(
            refreshDailySnapshot: (targetDate) async {
              snapshotDates.add(targetDate);
            },
            invalidateProjection: invalidations.add,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      deadlinePlanControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final controller = container.read(deadlinePlanControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    expect(await controller.cancel(_plan(status: 'draft')), isTrue);
    expect(snapshotDates, isEmpty);
    expect(
      invalidations,
      [
        ProductProjection.today,
        ProductProjection.todayFullWeek,
        ProductProjection.planner,
        ProductProjection.preparationWorkload,
        ProductProjection.examWeekOutlook,
      ],
    );
  });

  test('proposal preview does not refresh projections', () async {
    final repository = _LifecycleRepository(result: _plan(status: 'draft'));
    var refreshCalls = 0;
    final controller = DeadlinePlanController(
      repository: repository,
      projectionRefresh: ({required managedTaskChanged}) async {
        refreshCalls += 1;
      },
    );
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);

    expect(await controller.propose(_proposal()), isTrue);
    expect(refreshCalls, 0);
  });

  test('successful exact lifecycle retry refreshes exactly once', () async {
    final repository = _LifecycleRepository(
      result: _plan(status: 'completed'),
      failuresRemaining: 1,
    );
    final impacts = <bool>[];
    final controller = DeadlinePlanController(
      repository: repository,
      projectionRefresh: ({required managedTaskChanged}) async {
        impacts.add(managedTaskChanged);
      },
    );
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);

    expect(await controller.complete(_plan()), isFalse);
    expect(controller.state.requiresExactRetry, isTrue);
    expect(impacts, isEmpty);
    final firstRequestId = repository.requestIds.single;

    expect(await controller.retryExact(), isTrue);
    expect(repository.requestIds, [firstRequestId, firstRequestId]);
    expect(impacts, [true]);
    expect(controller.state.requiresExactRetry, isFalse);
  });

  test('projection refresh failure preserves durable lifecycle success',
      () async {
    final controller = DeadlinePlanController(
      repository: _LifecycleRepository(result: _plan(status: 'completed')),
      projectionRefresh: ({required managedTaskChanged}) async {
        throw StateError('projection unavailable');
      },
    );
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);

    expect(await controller.complete(_plan()), isTrue);
    expect(controller.state.operation, DeadlinePlanOperation.idle);
    expect(controller.state.operationError, isNull);
    expect(controller.state.requiresExactRetry, isFalse);
    expect(controller.state.plans.single.status, DeadlinePlanStatus.completed);
  });
}

DeadlinePlan _plan({String status = 'active'}) => DeadlinePlan.fromDetailJson(
      deadlinePlanDetail(status: status),
    );

DeadlinePlan _cancelledDraft() {
  final json = deadlinePlanDetail(status: 'draft');
  final record = json['plan']! as Map<String, dynamic>;
  record
    ..['status'] = 'cancelled'
    ..['cancelled_at'] = '2026-07-18T12:00:00Z';
  json.remove('pending_revision');
  return DeadlinePlan.fromDetailJson(json);
}

DeadlinePlanProposalDraft _proposal() => DeadlinePlanProposalDraft(
      planId: deadlinePlanId,
      baseRevision: 0,
      kind: DeadlinePlanKind.exam,
      title: 'Algorithms exam',
      deadlineAt: DateTime.parse('2026-07-25T15:00:00Z'),
      estimatedTotalMinutes: 300,
      creditedPriorMinutes: 30,
      preferredSessionMinutes: 50,
      maxDailyMinutes: 120,
      planningStartOn: '2026-07-18',
      bufferDays: 1,
      sourceKind: DeadlinePlanSourceKind.manual,
      sourceCalendarEventId: null,
      sourceCalendarEventFingerprint: null,
      useCalendarAvailability: true,
    );

class _LifecycleRepository implements DeadlinePlanRepository {
  _LifecycleRepository({required this.result, this.failuresRemaining = 0});

  final DeadlinePlan result;
  int failuresRemaining;
  final List<String> requestIds = [];

  @override
  Future<DeadlinePlanFeed> getPlans() async =>
      DeadlinePlanFeed(plans: const []);

  @override
  Future<DeadlinePlan> propose({
    required String requestId,
    required DeadlinePlanProposalDraft draft,
  }) async =>
      result;

  @override
  Future<DeadlinePlan> confirm({
    required String planId,
    required String requestId,
    required int expectedRevision,
  }) =>
      _lifecycle(requestId);

  @override
  Future<DeadlinePlan> complete({
    required String planId,
    required String requestId,
    required int expectedRevision,
  }) =>
      _lifecycle(requestId);

  @override
  Future<DeadlinePlan> cancel({
    required String planId,
    required String requestId,
    required int expectedRevision,
  }) =>
      _lifecycle(requestId);

  Future<DeadlinePlan> _lifecycle(String requestId) async {
    requestIds.add(requestId);
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw const ApiFailure(kind: ApiFailureKind.connection);
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
