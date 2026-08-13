import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/network/api_failure.dart';
import 'package:my_life_graph/features/deadline_plans/application/multi_exam_plan_controller.dart';
import 'package:my_life_graph/features/deadline_plans/application/preparation_mutation_gate.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_plan.dart';
import 'package:my_life_graph/features/deadline_plans/domain/multi_exam_plan.dart';
import 'package:my_life_graph/features/deadline_plans/domain/multi_exam_plan_repository.dart';

import 'support/deadline_plan_fixtures.dart';
import 'support/multi_exam_plan_fixtures.dart';

void main() {
  test('single-plan replay adopts persisted Deadline V1 revision once',
      () async {
    final plan = DeadlinePlanResponse.fromJson(
      deadlinePlanEnvelope(status: 'draft'),
    ).plan;
    final repository = _Repository(
      proposalResults: [
        const ApiFailure(kind: ApiFailureKind.connection),
        MultiExamPlanSingle(plan: plan),
      ],
    );
    final adopted = <DeadlinePlan>[];
    final controller = _controller(repository, adopted: adopted);
    addTearDown(controller.dispose);

    expect(await controller.propose(_draft), isFalse);
    expect(controller.state.requiresExactRetry, isTrue);
    final requestId = repository.requestIds.single;
    expect(await controller.retryExact(), isTrue);

    expect(repository.requestIds, [requestId, requestId]);
    expect(adopted, [plan]);
    expect(controller.state.lastOutcome, 'single_plan');
    expect(controller.state.requiresExactRetry, isFalse);
  });

  test('double tap and common mutation gate allow one writer only', () async {
    final completer = Completer<MultiExamPlanProposalResult>();
    final repository = _Repository(proposalCompleter: completer);
    final gate = PreparationMutationGate();
    final controller = _controller(repository, gate: gate);
    addTearDown(controller.dispose);

    final first = controller.propose(_draft);
    await Future<void>.delayed(Duration.zero);
    expect(await controller.propose(_draft), isFalse);
    completer.complete(MultiExamPlanNoChange(targetPlanId: multiExamTargetId));
    expect(await first, isTrue);
    expect(repository.requestIds, hasLength(1));

    final other = Object();
    expect(gate.tryAcquire(other), isTrue);
    expect(await controller.propose(_draft), isFalse);
    gate.release(other);
    expect(repository.requestIds, hasLength(1));
  });

  test('stale 409 keeps review readable and never exact-retries', () async {
    final batch = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(),
    ).balance;
    final repository = _Repository(
      balance: batch,
      confirmResults: [
        const ApiFailure(
          kind: ApiFailureKind.response,
          statusCode: 409,
          responseData: {
            'detail': 'Exam balance proposal is stale. Create a fresh preview.',
          },
        ),
      ],
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.loadBalance(batch.id);

    expect(await controller.confirm(batch), isFalse);
    expect(controller.state.requiresExactRetry, isFalse);
    expect(controller.state.selectedBalance, same(batch));
    expect(
      controller.state.projectionStatus,
      MultiExamPlanProjectionStatus.stale,
    );
  });

  test('response-loss confirm retries immutable identity and refreshes once',
      () async {
    final proposed = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(),
    ).balance;
    final confirmed = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(status: 'confirmed'),
    ).balance;
    final repository = _Repository(
      balance: proposed,
      confirmResults: [
        const ApiFailure(kind: ApiFailureKind.connection),
        confirmed,
      ],
    );
    var refreshes = 0;
    final controller = _controller(
      repository,
      onRefresh: () async => refreshes += 1,
    );
    addTearDown(controller.dispose);
    await controller.load();
    await controller.loadBalance(proposed.id);

    expect(await controller.confirm(proposed), isFalse);
    final requestId = repository.requestIds.single;
    expect(controller.state.requiresExactRetry, isTrue);
    expect(await controller.retryExact(), isTrue);

    expect(repository.requestIds, [requestId, requestId]);
    expect(
      controller.state.selectedBalance?.status,
      MultiExamPlanStatus.confirmed,
    );
    expect(refreshes, 1);
    expect(repository.balanceFeedCalls, 2);
  });

  test('durable result with failed refresh is truthful and retryable',
      () async {
    final proposed = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(),
    ).balance;
    final cancelled = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(status: 'cancelled'),
    ).balance;
    var failRefresh = true;
    final repository = _Repository(
      balance: proposed,
      cancelResults: [cancelled],
    );
    final controller = _controller(
      repository,
      onRefresh: () async {
        if (failRefresh) throw StateError('projection unavailable');
      },
    );
    addTearDown(controller.dispose);
    await controller.load();
    await controller.loadBalance(proposed.id);

    expect(await controller.cancel(proposed), isTrue);
    expect(controller.state.savedButRefreshFailed, isTrue);
    expect(controller.state.requiresExactRetry, isFalse);
    expect(
      controller.state.selectedBalance?.status,
      MultiExamPlanStatus.cancelled,
    );

    failRefresh = false;
    await controller.refreshSavedProjection();
    expect(controller.state.savedButRefreshFailed, isFalse);
  });

  test('targeted detail loads independently of bounded feed', () async {
    final batch = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(),
    ).balance;
    final repository = _Repository(
      feed: MultiExamPlanFeed(balances: const []),
      balance: batch,
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);

    await controller.loadBalance(batch.id);

    expect(repository.detailIds, [batch.id]);
    expect(controller.state.selectedBalance?.id, batch.id);
    expect(
      controller.state.metadataStatus,
      MultiExamPlanMetadataStatus.checking,
    );
  });

  test('late targeted detail cannot replace a newer deep-link selection',
      () async {
    final first = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(),
    ).balance;
    final secondJson = multiExamBatchEnvelope();
    final secondBalance = secondJson['balance'] as Map<String, dynamic>;
    const secondId = '92000000-0000-4000-8000-000000000009';
    secondBalance['id'] = secondId;
    for (final link in secondBalance['child_links'] as List) {
      (link as Map<String, dynamic>)['balance_id'] = secondId;
    }
    final second = MultiExamPlanBatchResponse.fromJson(secondJson).balance;
    final repository = _RacingRepository();
    final controller = MultiExamPlanController(
      repository: repository,
      mutationGate: PreparationMutationGate(),
      adoptSinglePlan: (_) {},
      projectionRefresh: () async {},
      autoLoad: false,
    );
    addTearDown(controller.dispose);

    final oldRead = controller.loadBalance(first.id);
    final newRead = controller.loadBalance(second.id);
    repository.complete(second.id, second);
    await newRead;
    repository.complete(first.id, first);
    await oldRead;

    expect(controller.state.selectedBalanceId, second.id);
    expect(controller.state.selectedBalance, same(second));
  });

  test('exact retry locks its selected batch against another detail read',
      () async {
    final first = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(),
    ).balance;
    final secondJson = multiExamBatchEnvelope();
    final secondBalance = secondJson['balance'] as Map<String, dynamic>;
    const secondId = '92000000-0000-4000-8000-000000000009';
    secondBalance['id'] = secondId;
    for (final link in secondBalance['child_links'] as List) {
      (link as Map<String, dynamic>)['balance_id'] = secondId;
    }
    final repository = _Repository(
      balance: first,
      confirmResults: const [
        ApiFailure(kind: ApiFailureKind.connection),
      ],
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.loadBalance(first.id);

    expect(await controller.confirm(first), isFalse);
    expect(controller.state.requiresExactRetry, isTrue);
    await controller.loadBalance(secondId);

    expect(repository.detailIds, [first.id, first.id]);
    expect(controller.state.selectedBalanceId, first.id);
  });

  test('stale confirm remains blocked while discard remains available',
      () async {
    final proposed = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(),
    ).balance;
    final cancelled = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(status: 'cancelled'),
    ).balance;
    final repository = _Repository(
      balance: proposed,
      confirmResults: const [
        ApiFailure(kind: ApiFailureKind.response, statusCode: 409),
      ],
      cancelResults: [cancelled],
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.loadBalance(proposed.id);

    expect(await controller.confirm(proposed), isFalse);
    expect(controller.state.canConfirm(proposed), isFalse);
    expect(controller.state.canCancel(proposed), isTrue);
    expect(await controller.confirm(proposed), isFalse);
    expect(await controller.cancel(proposed), isTrue);
    expect(repository.requestIds, hasLength(2));
  });

  test('failed feed cannot evict a targeted deep-link detail', () async {
    final batch = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(),
    ).balance;
    final repository = _Repository(
      balance: batch,
      feedResults: [StateError('legacy feed unavailable')],
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await controller.loadBalance(batch.id);

    await controller.load();

    expect(controller.state.loadError, isNotNull);
    expect(controller.state.selectedBalance, same(batch));
  });

  test('late bounded feed cannot evict a targeted deep-link detail', () async {
    final batch = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(),
    ).balance;
    final feedCompleter = Completer<MultiExamPlanFeed>();
    final repository = _Repository(
      balance: batch,
      feedCompleter: feedCompleter,
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);

    final lateFeed = controller.load();
    await Future<void>.delayed(Duration.zero);
    await controller.loadBalance(batch.id);
    expect(controller.state.selectedBalance, same(batch));

    feedCompleter.complete(MultiExamPlanFeed(balances: const []));
    await lateFeed;

    expect(controller.state.selectedBalanceId, batch.id);
    expect(controller.state.selectedBalance, same(batch));
    expect(repository.detailIds, [batch.id, batch.id]);
  });

  test('late list detail phase merges without removing a newer targeted detail',
      () async {
    final listed = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(),
    ).balance;
    final targetedJson = multiExamBatchEnvelope();
    final targetedBalance = targetedJson['balance'] as Map<String, dynamic>;
    const targetedId = '92000000-0000-4000-8000-000000000009';
    targetedBalance['id'] = targetedId;
    for (final link in targetedBalance['child_links'] as List) {
      (link as Map<String, dynamic>)['balance_id'] = targetedId;
    }
    final targeted = MultiExamPlanBatchResponse.fromJson(
      targetedJson,
    ).balance;
    final repository = _RacingRepository(
      feed: MultiExamPlanFeed(
        balances: [MultiExamPlanBatchSummary.fromBatch(listed)],
      ),
    );
    final controller = MultiExamPlanController(
      repository: repository,
      mutationGate: PreparationMutationGate(),
      adoptSinglePlan: (_) {},
      projectionRefresh: () async {},
      autoLoad: false,
    );
    addTearDown(controller.dispose);

    final listRead = controller.load();
    await Future<void>.delayed(Duration.zero);
    expect(repository.requestedDetailIds, [listed.id]);

    final targetedRead = controller.loadBalance(targeted.id);
    repository.complete(targeted.id, targeted);
    await targetedRead;
    expect(controller.state.selectedBalance, same(targeted));

    repository.complete(listed.id, listed);
    await listRead;

    expect(controller.state.selectedBalanceId, targeted.id);
    expect(controller.state.selectedBalance, same(targeted));
    expect(controller.state.details[listed.id], same(listed));
  });

  test('late list success cannot clear an error bound to another target',
      () async {
    final listed = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(),
    ).balance;
    final targetedJson = multiExamBatchEnvelope();
    final targetedBalance = targetedJson['balance'] as Map<String, dynamic>;
    const targetedId = '92000000-0000-4000-8000-000000000009';
    targetedBalance['id'] = targetedId;
    for (final link in targetedBalance['child_links'] as List) {
      (link as Map<String, dynamic>)['balance_id'] = targetedId;
    }
    final repository = _RacingRepository(
      feed: MultiExamPlanFeed(
        balances: [MultiExamPlanBatchSummary.fromBatch(listed)],
      ),
    );
    final controller = MultiExamPlanController(
      repository: repository,
      mutationGate: PreparationMutationGate(),
      adoptSinglePlan: (_) {},
      projectionRefresh: () async {},
      autoLoad: false,
    );
    addTearDown(controller.dispose);

    final listRead = controller.load();
    await Future<void>.delayed(Duration.zero);
    final targetedRead = controller.loadBalance(targetedId);
    repository.completeError(
      targetedId,
      StateError('targeted balance unavailable'),
    );
    await targetedRead;

    expect(controller.state.selectedDetailError, isNotNull);
    expect(controller.state.selectedDetailErrorBalanceId, targetedId);

    repository.complete(listed.id, listed);
    await listRead;

    expect(controller.state.listDetailError, isNull);
    expect(controller.state.selectedBalanceId, targetedId);
    expect(controller.state.selectedDetailError, isNotNull);
    expect(controller.state.selectedDetailErrorBalanceId, targetedId);
    expect(controller.state.details[listed.id], same(listed));
  });

  test('late list error stays separate from a successful targeted detail',
      () async {
    final listed = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(),
    ).balance;
    final targetedJson = multiExamBatchEnvelope();
    final targetedBalance = targetedJson['balance'] as Map<String, dynamic>;
    const targetedId = '92000000-0000-4000-8000-000000000009';
    targetedBalance['id'] = targetedId;
    for (final link in targetedBalance['child_links'] as List) {
      (link as Map<String, dynamic>)['balance_id'] = targetedId;
    }
    final targeted = MultiExamPlanBatchResponse.fromJson(
      targetedJson,
    ).balance;
    final repository = _RacingRepository(
      feed: MultiExamPlanFeed(
        balances: [MultiExamPlanBatchSummary.fromBatch(listed)],
      ),
    );
    final controller = MultiExamPlanController(
      repository: repository,
      mutationGate: PreparationMutationGate(),
      adoptSinglePlan: (_) {},
      projectionRefresh: () async {},
      autoLoad: false,
    );
    addTearDown(controller.dispose);

    final listRead = controller.load();
    await Future<void>.delayed(Duration.zero);
    final targetedRead = controller.loadBalance(targetedId);
    repository.complete(targetedId, targeted);
    await targetedRead;
    expect(controller.state.selectedBalance, same(targeted));

    repository.completeError(
      listed.id,
      StateError('listed balance unavailable'),
    );
    await listRead;

    expect(controller.state.listDetailError, isNotNull);
    expect(controller.state.selectedBalanceId, targetedId);
    expect(controller.state.selectedBalance, same(targeted));
    expect(controller.state.selectedDetailError, isNull);
    expect(controller.state.selectedDetailErrorBalanceId, isNull);
  });

  test('fresh authoritative reload clears stale conflict only after success',
      () async {
    final proposed = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(),
    ).balance;
    final repository = _Repository(
      balance: proposed,
      confirmResults: const [
        ApiFailure(kind: ApiFailureKind.response, statusCode: 409),
      ],
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.loadBalance(proposed.id);

    expect(await controller.confirm(proposed), isFalse);
    expect(controller.state.operationError, isNotNull);
    expect(controller.state.canConfirm(proposed), isFalse);

    repository.feedError = StateError('feed unavailable');
    await controller.load();
    expect(controller.state.operationError, isNotNull);
    expect(
      controller.state.projectionStatus,
      MultiExamPlanProjectionStatus.stale,
    );
    expect(controller.state.canConfirm(proposed), isFalse);

    repository.feedError = null;
    await controller.load();
    expect(controller.state.operationError, isNull);
    expect(
      controller.state.projectionStatus,
      MultiExamPlanProjectionStatus.current,
    );
    expect(
      controller.state.metadataStatus,
      MultiExamPlanMetadataStatus.current,
    );
    expect(controller.state.canConfirm(proposed), isTrue);
  });

  test('no-change proposal clears an older selected balance', () async {
    final batch = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(),
    ).balance;
    final repository = _Repository(
      balance: batch,
      proposalResults: [
        MultiExamPlanNoChange(targetPlanId: multiExamTargetId),
      ],
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.loadBalance(batch.id);
    expect(controller.state.selectedBalanceId, batch.id);

    expect(await controller.propose(_draft), isTrue);

    expect(controller.state.lastOutcome, 'no_change');
    expect(controller.state.selectedBalanceId, isNull);
    expect(controller.state.selectedBalance, isNull);
  });

  test('preview reconciliation does not emit lifecycle refresh', () async {
    final batch = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(),
    ).balance;
    final repository = _Repository(
      balance: batch,
      proposalResults: [MultiExamPlanBatchProposal(balance: batch)],
    );
    var lifecycleRefreshes = 0;
    final controller = _controller(
      repository,
      onRefresh: () async => lifecycleRefreshes += 1,
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.propose(_draft), isTrue);

    expect(controller.state.lastOutcome, 'multi_exam_batch');
    expect(lifecycleRefreshes, 0);
    expect(repository.balanceFeedCalls, 2);
  });

  test('dispose during an in-flight proposal performs no late adoption',
      () async {
    final plan = DeadlinePlanResponse.fromJson(
      deadlinePlanEnvelope(status: 'draft'),
    ).plan;
    final completer = Completer<MultiExamPlanProposalResult>();
    final repository = _Repository(proposalCompleter: completer);
    final adopted = <DeadlinePlan>[];
    final controller = _controller(repository, adopted: adopted);

    final result = controller.propose(_draft);
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    completer.complete(MultiExamPlanSingle(plan: plan));

    expect(await result, isFalse);
    expect(adopted, isEmpty);
  });
}

const _draft = MultiExamPlanProposalDraft(
  targetPlanId: multiExamTargetId,
  expectedPlanRevision: 1,
);

MultiExamPlanController _controller(
  _Repository repository, {
  PreparationMutationGate? gate,
  List<DeadlinePlan>? adopted,
  Future<void> Function()? onRefresh,
}) =>
    MultiExamPlanController(
      repository: repository,
      mutationGate: gate ?? PreparationMutationGate(),
      adoptSinglePlan: (plan) => adopted?.add(plan),
      projectionRefresh: onRefresh ?? () async {},
      autoLoad: false,
    );

class _Repository implements MultiExamPlanRepository {
  _Repository({
    this.feed,
    this.feedResults = const [],
    MultiExamPlanBatch? balance,
    this.proposalResults = const [],
    this.confirmResults = const [],
    this.cancelResults = const [],
    this.proposalCompleter,
    this.feedCompleter,
  }) : _currentBalance = balance;

  final MultiExamPlanFeed? feed;
  final List<Object> feedResults;
  MultiExamPlanBatch? _currentBalance;
  final List<Object> proposalResults;
  final List<Object> confirmResults;
  final List<Object> cancelResults;
  final Completer<MultiExamPlanProposalResult>? proposalCompleter;
  final Completer<MultiExamPlanFeed>? feedCompleter;
  Object? feedError;
  final List<String> requestIds = [];
  final List<String> detailIds = [];
  var balanceFeedCalls = 0;
  var _feedIndex = 0;
  var _proposalIndex = 0;
  var _confirmIndex = 0;
  var _cancelIndex = 0;

  @override
  Future<MultiExamPlanFeed> getBalances() async {
    balanceFeedCalls += 1;
    final error = feedError;
    if (error != null) return _result<MultiExamPlanFeed>(error);
    if (feedCompleter != null) return feedCompleter!.future;
    if (_feedIndex < feedResults.length) {
      return _result<MultiExamPlanFeed>(feedResults[_feedIndex++]);
    }
    final explicit = feed;
    if (explicit != null) return explicit;
    final current = _currentBalance;
    return MultiExamPlanFeed(
      balances: current == null
          ? const []
          : [MultiExamPlanBatchSummary.fromBatch(current)],
    );
  }

  @override
  Future<MultiExamPlanBatch> getBalance(String balanceId) async {
    detailIds.add(balanceId);
    return _currentBalance ?? (throw StateError('Missing balance'));
  }

  @override
  Future<MultiExamPlanProposalResult> propose({
    required String requestId,
    required MultiExamPlanProposalDraft draft,
  }) async {
    requestIds.add(requestId);
    if (proposalCompleter != null) return proposalCompleter!.future;
    return _result(proposalResults[_proposalIndex++]);
  }

  @override
  Future<MultiExamPlanBatch> confirm({
    required String balanceId,
    required String requestId,
    required int expectedRevision,
  }) async {
    requestIds.add(requestId);
    final result = _result<MultiExamPlanBatch>(confirmResults[_confirmIndex++]);
    _currentBalance = result;
    return result;
  }

  @override
  Future<MultiExamPlanBatch> cancel({
    required String balanceId,
    required String requestId,
    required int expectedRevision,
  }) async {
    requestIds.add(requestId);
    final result = _result<MultiExamPlanBatch>(cancelResults[_cancelIndex++]);
    _currentBalance = result;
    return result;
  }

  T _result<T>(Object value) {
    if (value is Error) throw value;
    if (value is Exception) throw value;
    if (value is ApiFailure) throw value;
    return value as T;
  }
}

class _RacingRepository implements MultiExamPlanRepository {
  _RacingRepository({MultiExamPlanFeed? feed})
      : _feed = feed ?? MultiExamPlanFeed(balances: const []);

  final MultiExamPlanFeed _feed;
  final Map<String, Completer<MultiExamPlanBatch>> _details = {};
  final List<String> requestedDetailIds = [];

  void complete(String id, MultiExamPlanBatch balance) {
    (_details[id] ??= Completer<MultiExamPlanBatch>()).complete(balance);
  }

  void completeError(String id, Object error) {
    (_details[id] ??= Completer<MultiExamPlanBatch>()).completeError(error);
  }

  @override
  Future<MultiExamPlanBatch> getBalance(String balanceId) {
    requestedDetailIds.add(balanceId);
    return (_details[balanceId] ??= Completer<MultiExamPlanBatch>()).future;
  }

  @override
  Future<MultiExamPlanFeed> getBalances() async => _feed;

  @override
  Future<MultiExamPlanBatch> cancel({
    required String balanceId,
    required String requestId,
    required int expectedRevision,
  }) =>
      throw UnimplementedError();

  @override
  Future<MultiExamPlanBatch> confirm({
    required String balanceId,
    required String requestId,
    required int expectedRevision,
  }) =>
      throw UnimplementedError();

  @override
  Future<MultiExamPlanProposalResult> propose({
    required String requestId,
    required MultiExamPlanProposalDraft draft,
  }) =>
      throw UnimplementedError();
}
