import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/deadline_plan_providers.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import 'package:my_life_graph/composition/projection_refresh_providers.dart';
import 'package:my_life_graph/core/network/api_failure.dart';
import 'package:my_life_graph/features/auth/application/profile_local_date_source.dart';
import 'package:my_life_graph/features/deadline_plans/application/deadline_plan_controller.dart';
import 'package:my_life_graph/features/deadline_plans/application/preparation_mutation_gate.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_plan.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_plan_repository.dart';

import 'support/deadline_plan_fixtures.dart';

void main() {
  for (final proposal in [false, true]) {
    test(
      'pending feed preserves newer ${proposal ? 'proposal' : 'lifecycle'} and unrelated rows',
      () async {
        final repository = _ControlledWriteRepository();
        final controller = DeadlinePlanController(
          repository: repository,
          projectionRefresh: ({required managedTaskChanged}) async {},
        );
        addTearDown(controller.dispose);
        final load = controller.load();
        final write = proposal
            ? controller.propose(_proposal())
            : controller.complete(_plan());
        final saved = proposal
            ? _plan(status: 'draft')
            : _plan(status: 'completed');
        repository.write.complete(saved);
        expect(await write, isTrue);
        const otherId = '44444444-4444-4444-8444-444444444444';
        repository.reads.single.complete(
          DeadlinePlanFeed(
            plans: [
              if (!proposal) _plan(),
              _cancelledDraft(id: otherId),
            ],
          ),
        );
        await load;
        expect(
          controller.state.plans.map((plan) => plan.id),
          containsAll([deadlinePlanId, otherId]),
        );
        expect(
          controller.state.plans
              .singleWhere((plan) => plan.id == deadlinePlanId)
              .status,
          saved.status,
        );
        expect(controller.state.isLoading, isFalse);
        // The overlay must not mask a later authoritative reload.
        final laterLoad = controller.load();
        repository.reads.last.complete(
          DeadlinePlanFeed(plans: [_cancelledDraft(id: otherId)]),
        );
        await laterLoad;
        expect(controller.state.plans.single.id, otherId);
      },
    );
  }

  for (final proposal in [false, true]) {
    for (final fails in [false, true]) {
      test(
        'disposed ${proposal ? 'proposal' : 'lifecycle'} ${fails ? 'failure' : 'success'} releases gate safely',
        () async {
          final repository = _ControlledWriteRepository();
          final gate = PreparationMutationGate();
          var refreshes = 0;
          final controller = DeadlinePlanController(
            repository: repository,
            mutationGate: gate,
            projectionRefresh: ({required managedTaskChanged}) async {
              refreshes++;
              expect(managedTaskChanged, isTrue);
            },
          );
          final load = controller.load();
          repository.reads.single.complete(DeadlinePlanFeed(plans: [_plan()]));
          await load;
          final write = proposal
              ? controller.propose(_proposal())
              : controller.complete(_plan());
          final writeAssertion = expectLater(
            write,
            completion(fails ? isFalse : isTrue),
          );
          expect(gate.isLocked, isTrue);
          controller.dispose();
          if (fails) {
            repository.write.completeError(
              const ApiFailure(kind: ApiFailureKind.connection),
            );
          } else {
            repository.write.complete(_plan(status: 'completed'));
          }
          await writeAssertion;
          expect(gate.isLocked, isFalse);
          expect(refreshes, !proposal && !fails ? 1 : 0);
        },
      );
    }
  }

  test('pending feed retains exact retry after a failed write', () async {
    final repository = _ControlledWriteRepository();
    final controller = DeadlinePlanController(
      repository: repository,
      projectionRefresh: ({required managedTaskChanged}) async {},
    );
    addTearDown(controller.dispose);
    final load = controller.load();
    final write = controller.complete(_plan());
    repository.write.completeError(
      const ApiFailure(kind: ApiFailureKind.connection),
    );
    expect(await write, isFalse);
    final pending = controller.state.pendingMutation;
    expect(pending, isNotNull);
    repository.reads.single.complete(DeadlinePlanFeed(plans: [_plan()]));
    await load;
    expect(controller.state.pendingMutation, same(pending));
    expect(controller.state.requiresExactRetry, isTrue);
    final reload = controller.load();
    repository.reads.last.complete(DeadlinePlanFeed(plans: [_plan()]));
    await reload;
    expect(controller.state.requiresExactRetry, isFalse);
  });

  test(
    'failed pending feed preserves successful mutation and exposes read error',
    () async {
      final repository = _ControlledWriteRepository();
      final controller = DeadlinePlanController(
        repository: repository,
        projectionRefresh: ({required managedTaskChanged}) async {},
      );
      addTearDown(controller.dispose);
      final load = controller.load();
      final write = controller.complete(_plan());
      repository.write.complete(_plan(status: 'completed'));
      expect(await write, isTrue);
      repository.reads.single.completeError(
        const ApiFailure(kind: ApiFailureKind.connection),
      );
      await load;
      expect(
        controller.state.plans.single.status,
        DeadlinePlanStatus.completed,
      );
      expect(controller.state.loadError, isA<ApiFailure>());
      expect(controller.state.isLoading, isFalse);
    },
  );

  test(
    'disposed controller rejects commands without repository or gate work',
    () async {
      final repository = _ControlledWriteRepository();
      final gate = PreparationMutationGate();
      final controller = DeadlinePlanController(
        repository: repository,
        mutationGate: gate,
        projectionRefresh: ({required managedTaskChanged}) async {},
      );
      controller.dispose();
      await controller.load();
      expect(await controller.propose(_proposal()), isFalse);
      expect(await controller.confirm(_plan(status: 'draft')), isFalse);
      expect(await controller.complete(_plan()), isFalse);
      expect(await controller.cancel(_plan()), isFalse);
      expect(await controller.retryExact(), isFalse);
      controller.clearOperationError();
      controller.includeReadPlan(_plan());
      expect(repository.reads, isEmpty);
      expect(gate.isLocked, isFalse);
    },
  );

  test(
    'disposed durable lifecycle ignores projection failure and releases gate',
    () async {
      final repository = _ControlledWriteRepository();
      final gate = PreparationMutationGate();
      var refreshes = 0;
      final controller = DeadlinePlanController(
        repository: repository,
        mutationGate: gate,
        projectionRefresh: ({required managedTaskChanged}) async {
          refreshes++;
          throw StateError('projection unavailable');
        },
      );
      final load = controller.load();
      repository.reads.single.complete(DeadlinePlanFeed(plans: [_plan()]));
      await load;
      final write = controller.complete(_plan());
      controller.dispose();
      repository.write.complete(_plan(status: 'completed'));
      expect(await write, isTrue);
      expect(refreshes, 1);
      expect(gate.isLocked, isFalse);
    },
  );

  test(
    'overlapping reload cannot replace a completed plan with an old feed',
    () async {
      final repository = _ControlledReadRepository();
      final controller = DeadlinePlanController(
        repository: repository,
        projectionRefresh: ({required managedTaskChanged}) async {},
      );
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);
      repository.reads.single.complete(DeadlinePlanFeed(plans: [_plan()]));
      await Future<void>.delayed(Duration.zero);

      final olderLoad = controller.load();
      final newerLoad = controller.load();
      // A coalesced implementation has one pending read. Otherwise finish the
      // newer request first, exactly as an out-of-order network can do.
      repository.reads.last.complete(DeadlinePlanFeed(plans: [_plan()]));
      await newerLoad;
      expect(controller.state.isLoading, isFalse);
      expect(await controller.complete(_plan()), isTrue);
      expect(
        controller.state.plans.single.status,
        DeadlinePlanStatus.completed,
      );

      for (final read in repository.reads) {
        if (!read.isCompleted) {
          read.complete(DeadlinePlanFeed(plans: [_plan()]));
        }
      }
      await olderLoad;
      expect(
        controller.state.plans.single.status,
        DeadlinePlanStatus.completed,
      );
    },
  );

  for (final fails in [false, true]) {
    test(
      'pending reload ${fails ? 'failure' : 'success'} is safe after disposal',
      () async {
        final repository = _ControlledReadRepository();
        final controller = DeadlinePlanController(
          repository: repository,
          projectionRefresh: ({required managedTaskChanged}) async {},
        );
        await Future<void>.delayed(Duration.zero);
        repository.reads.single.complete(DeadlinePlanFeed(plans: [_plan()]));
        await Future<void>.delayed(Duration.zero);

        final load = controller.load();
        final completion = expectLater(load, completes);
        controller.dispose();
        if (fails) {
          repository.reads.last.completeError(
            const ApiFailure(kind: ApiFailureKind.connection),
          );
        } else {
          repository.reads.last.complete(DeadlinePlanFeed(plans: [_plan()]));
        }
        await completion;
      },
    );
  }

  test('confirm, complete, and active cancel refresh exactly once', () async {
    final cases =
        <
          ({
            DeadlinePlan input,
            DeadlinePlan result,
            Future<bool> Function(DeadlinePlanController, DeadlinePlan) mutate,
          })
        >[
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

  test(
    'composition invalidates draft cancel without a Snapshot date',
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
      final controller = container.read(
        deadlinePlanControllerProvider.notifier,
      );
      await Future<void>.delayed(Duration.zero);

      expect(await controller.cancel(_plan(status: 'draft')), isTrue);
      expect(snapshotDates, isEmpty);
      expect(invalidations, [
        ProductProjection.today,
        ProductProjection.todayFullWeek,
        ProductProjection.planner,
        ProductProjection.preparationWorkload,
        ProductProjection.examWeekOutlook,
        ProductProjection.examPlanHealth,
      ]);
    },
  );

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

  test(
    'projection refresh failure preserves durable lifecycle success',
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
      expect(
        controller.state.plans.single.status,
        DeadlinePlanStatus.completed,
      );
    },
  );
}

DeadlinePlan _plan({String status = 'active'}) =>
    DeadlinePlan.fromDetailJson(deadlinePlanDetail(status: status));

DeadlinePlan _cancelledDraft({String id = deadlinePlanId}) {
  final json = deadlinePlanDetail(status: 'draft');
  final record = json['plan']! as Map<String, dynamic>;
  record
    ..['id'] = id
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

class _ControlledReadRepository extends _LifecycleRepository {
  _ControlledReadRepository() : super(result: _plan(status: 'completed'));

  final reads = <Completer<DeadlinePlanFeed>>[];

  @override
  Future<DeadlinePlanFeed> getPlans() {
    final read = Completer<DeadlinePlanFeed>();
    reads.add(read);
    return read.future;
  }
}

class _ControlledWriteRepository extends _ControlledReadRepository {
  final write = Completer<DeadlinePlan>();

  @override
  Future<DeadlinePlan> propose({
    required String requestId,
    required DeadlinePlanProposalDraft draft,
  }) => write.future;

  @override
  Future<DeadlinePlan> complete({
    required String planId,
    required String requestId,
    required int expectedRevision,
  }) => write.future;
}

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
  }) async => result;

  @override
  Future<DeadlinePlan> confirm({
    required String planId,
    required String requestId,
    required int expectedRevision,
  }) => _lifecycle(requestId);

  @override
  Future<DeadlinePlan> complete({
    required String planId,
    required String requestId,
    required int expectedRevision,
  }) => _lifecycle(requestId);

  @override
  Future<DeadlinePlan> cancel({
    required String planId,
    required String requestId,
    required int expectedRevision,
  }) => _lifecycle(requestId);

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
