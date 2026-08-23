import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/client_uuid.dart';
import '../domain/deadline_plan.dart';
import '../domain/multi_exam_plan.dart';
import '../domain/multi_exam_plan_repository.dart';
import 'deadline_plan_controller.dart';
import 'preparation_mutation_gate.dart';

enum MultiExamPlanOperation { idle, proposing, confirming, cancelling }

enum MultiExamPlanMutationKind { proposal, confirm, cancel }

enum MultiExamPlanProjectionStatus { current, refreshing, stale }

enum MultiExamPlanMetadataStatus { checking, current, unavailable }

enum MultiExamPlanRefreshScope { preview, lifecycle }

typedef MultiExamPlanProjectionRefresh = Future<void> Function();
typedef MultiExamPlanSingleAdoption = void Function(DeadlinePlan plan);

class MultiExamPlanPendingMutation {
  const MultiExamPlanPendingMutation._({
    required this.kind,
    required this.requestId,
    required this.targetId,
    this.draft,
    this.expectedRevision,
  });

  factory MultiExamPlanPendingMutation.proposal({
    required String requestId,
    required MultiExamPlanProposalDraft draft,
  }) =>
      MultiExamPlanPendingMutation._(
        kind: MultiExamPlanMutationKind.proposal,
        requestId: requestId,
        targetId: draft.targetPlanId,
        draft: draft,
      );

  factory MultiExamPlanPendingMutation.lifecycle({
    required MultiExamPlanMutationKind kind,
    required String requestId,
    required String balanceId,
    required int expectedRevision,
  }) =>
      MultiExamPlanPendingMutation._(
        kind: kind,
        requestId: requestId,
        targetId: balanceId,
        expectedRevision: expectedRevision,
      );

  final MultiExamPlanMutationKind kind;
  final String requestId;
  final String targetId;
  final MultiExamPlanProposalDraft? draft;
  final int? expectedRevision;
}

class MultiExamPlanState {
  const MultiExamPlanState({
    required this.isLoading,
    required this.balances,
    required this.details,
    required this.authoritativeDetailIds,
    required this.loadError,
    required this.listDetailError,
    required this.targetedDetailErrors,
    required this.selectedBalanceId,
    required this.operation,
    required this.operationError,
    required this.pendingMutation,
    required this.projectionStatus,
    required this.metadataStatus,
    required this.savedButRefreshFailed,
    required this.savedRefreshScope,
    required this.lastOutcome,
  });

  factory MultiExamPlanState.loading() => const MultiExamPlanState(
        isLoading: true,
        balances: [],
        details: {},
        authoritativeDetailIds: {},
        loadError: null,
        listDetailError: null,
        targetedDetailErrors: {},
        selectedBalanceId: null,
        operation: MultiExamPlanOperation.idle,
        operationError: null,
        pendingMutation: null,
        projectionStatus: MultiExamPlanProjectionStatus.current,
        metadataStatus: MultiExamPlanMetadataStatus.checking,
        savedButRefreshFailed: false,
        savedRefreshScope: null,
        lastOutcome: null,
      );

  final bool isLoading;
  final List<MultiExamPlanBatchSummary> balances;
  final Map<String, MultiExamPlanBatch> details;
  final Set<String> authoritativeDetailIds;
  final Object? loadError;
  final Object? listDetailError;
  final Map<String, Object> targetedDetailErrors;
  final String? selectedBalanceId;
  final MultiExamPlanOperation operation;
  final Object? operationError;
  final MultiExamPlanPendingMutation? pendingMutation;
  final MultiExamPlanProjectionStatus projectionStatus;
  final MultiExamPlanMetadataStatus metadataStatus;
  final bool savedButRefreshFailed;
  final MultiExamPlanRefreshScope? savedRefreshScope;
  final String? lastOutcome;

  bool get isBusy => operation != MultiExamPlanOperation.idle;
  bool get requiresExactRetry => pendingMutation != null;

  MultiExamPlanBatch? get selectedBalance =>
      selectedBalanceId == null ? null : details[selectedBalanceId];

  Object? get selectedDetailError => selectedBalanceId == null
      ? null
      : targetedDetailErrors[selectedBalanceId];

  String? get selectedDetailErrorBalanceId {
    final balanceId = selectedBalanceId;
    return balanceId != null && targetedDetailErrors.containsKey(balanceId)
        ? balanceId
        : null;
  }

  bool canConfirm(MultiExamPlanBatch balance) {
    final authoritative = details[balance.id];
    return !isBusy &&
        !requiresExactRetry &&
        !savedButRefreshFailed &&
        projectionStatus == MultiExamPlanProjectionStatus.current &&
        metadataStatus == MultiExamPlanMetadataStatus.current &&
        targetedDetailErrors[balance.id] == null &&
        selectedBalanceId == balance.id &&
        authoritativeDetailIds.contains(balance.id) &&
        authoritative != null &&
        authoritative.status == MultiExamPlanStatus.proposed &&
        authoritative.revision == balance.revision &&
        authoritative.contextFingerprint == balance.contextFingerprint &&
        authoritative.confirmationFingerprint ==
            balance.confirmationFingerprint;
  }

  bool canCancel(MultiExamPlanBatch balance) {
    final authoritative = details[balance.id];
    return !isBusy &&
        !requiresExactRetry &&
        selectedBalanceId == balance.id &&
        authoritativeDetailIds.contains(balance.id) &&
        authoritative != null &&
        authoritative.status == MultiExamPlanStatus.proposed &&
        authoritative.revision == balance.revision;
  }

  Map<String, MultiExamPlanChildLink> get proposedChildLinks {
    if (metadataStatus != MultiExamPlanMetadataStatus.current) return const {};
    return {
      for (final batch in details.values)
        if (batch.status == MultiExamPlanStatus.proposed)
          for (final link in batch.childLinks) link.childKey: link,
    };
  }

  MultiExamPlanState copyWith({
    bool? isLoading,
    List<MultiExamPlanBatchSummary>? balances,
    Map<String, MultiExamPlanBatch>? details,
    Set<String>? authoritativeDetailIds,
    Object? loadError = _unset,
    Object? listDetailError = _unset,
    Map<String, Object>? targetedDetailErrors,
    Object? selectedBalanceId = _unset,
    MultiExamPlanOperation? operation,
    Object? operationError = _unset,
    Object? pendingMutation = _unset,
    MultiExamPlanProjectionStatus? projectionStatus,
    MultiExamPlanMetadataStatus? metadataStatus,
    bool? savedButRefreshFailed,
    Object? savedRefreshScope = _unset,
    Object? lastOutcome = _unset,
  }) =>
      MultiExamPlanState(
        isLoading: isLoading ?? this.isLoading,
        balances: balances ?? this.balances,
        details: details ?? this.details,
        authoritativeDetailIds:
            authoritativeDetailIds ?? this.authoritativeDetailIds,
        loadError: identical(loadError, _unset) ? this.loadError : loadError,
        listDetailError: identical(listDetailError, _unset)
            ? this.listDetailError
            : listDetailError,
        targetedDetailErrors: targetedDetailErrors ?? this.targetedDetailErrors,
        selectedBalanceId: identical(selectedBalanceId, _unset)
            ? this.selectedBalanceId
            : selectedBalanceId as String?,
        operation: operation ?? this.operation,
        operationError: identical(operationError, _unset)
            ? this.operationError
            : operationError,
        pendingMutation: identical(pendingMutation, _unset)
            ? this.pendingMutation
            : pendingMutation as MultiExamPlanPendingMutation?,
        projectionStatus: projectionStatus ?? this.projectionStatus,
        metadataStatus: metadataStatus ?? this.metadataStatus,
        savedButRefreshFailed:
            savedButRefreshFailed ?? this.savedButRefreshFailed,
        savedRefreshScope: identical(savedRefreshScope, _unset)
            ? this.savedRefreshScope
            : savedRefreshScope as MultiExamPlanRefreshScope?,
        lastOutcome: identical(lastOutcome, _unset)
            ? this.lastOutcome
            : lastOutcome as String?,
      );
}

class MultiExamPlanController extends StateNotifier<MultiExamPlanState> {
  MultiExamPlanController({
    required MultiExamPlanRepository repository,
    required PreparationMutationGate mutationGate,
    required MultiExamPlanSingleAdoption adoptSinglePlan,
    required MultiExamPlanProjectionRefresh projectionRefresh,
    bool autoLoad = true,
  })  : _repository = repository,
        _mutationGate = mutationGate,
        _adoptSinglePlan = adoptSinglePlan,
        _projectionRefresh = projectionRefresh,
        super(MultiExamPlanState.loading()) {
    if (autoLoad) Future<void>.microtask(load);
  }

  final MultiExamPlanRepository _repository;
  final PreparationMutationGate _mutationGate;
  final MultiExamPlanSingleAdoption _adoptSinglePlan;
  final MultiExamPlanProjectionRefresh _projectionRefresh;
  final Set<String> _adoptedSingleRevisions = {};
  int _loadGeneration = 0;
  int _detailEpoch = 0;
  int _detailReadSerial = 0;
  final Map<String, int> _latestDetailReads = {};
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration += 1;
    _detailEpoch += 1;
    super.dispose();
  }

  Future<void> load() async {
    if (_disposed || state.isBusy || state.requiresExactRetry) return;
    final generation = ++_loadGeneration;
    state = state.copyWith(
      isLoading: true,
      loadError: null,
      listDetailError: null,
      metadataStatus: MultiExamPlanMetadataStatus.checking,
    );
    try {
      final feed = await _repository.getBalances();
      if (_disposed || generation != _loadGeneration) return;
      final proposed = feed.balances
          .where((summary) => summary.status == MultiExamPlanStatus.proposed)
          .toList(growable: false);
      final detailReadIds = <String>{
        for (final summary in proposed) summary.id,
        if (state.selectedBalanceId case final selectedId?) selectedId,
      }.toList(growable: false);
      final claims = {
        for (final id in detailReadIds) id: _claimDetailRead(id),
      };
      try {
        final loaded = await Future.wait(
          detailReadIds.map(_repository.getBalance),
        );
        if (_disposed || generation != _loadGeneration) return;
        final visibleIds = feed.balances.map((summary) => summary.id).toSet();
        final selectedId = state.selectedBalanceId;
        final details = <String, MultiExamPlanBatch>{...state.details}
          ..removeWhere(
            (id, _) => !visibleIds.contains(id) && id != selectedId,
          );
        final authoritativeIds = <String>{...state.authoritativeDetailIds}
          ..removeWhere((id) => !details.containsKey(id));
        final targetedDetailErrors = <String, Object>{
          ...state.targetedDetailErrors,
        };
        for (var index = 0; index < loaded.length; index += 1) {
          final balance = loaded[index];
          final requestedId = detailReadIds[index];
          if (!_isCurrentDetailRead(requestedId, claims[requestedId]!)) {
            continue;
          }
          if (balance.id != requestedId) {
            throw const MultiExamPlanContractException(
              'Exam balance detail does not match the requested balance.',
            );
          }
          MultiExamPlanBatchSummary? summary;
          for (final candidate in proposed) {
            if (candidate.id == balance.id) {
              summary = candidate;
              break;
            }
          }
          if (summary != null && !summary.matchesBatch(balance)) {
            throw const MultiExamPlanContractException(
              'Exam balance summary and detail disagree.',
            );
          }
          details[balance.id] = balance;
          authoritativeIds.add(balance.id);
          targetedDetailErrors.remove(balance.id);
        }
        final hasCompleteProposedMetadata = proposed.every(
          (summary) => authoritativeIds.contains(summary.id),
        );
        state = state.copyWith(
          isLoading: false,
          balances: feed.balances,
          details: Map.unmodifiable(details),
          authoritativeDetailIds: Set.unmodifiable(authoritativeIds),
          loadError: null,
          listDetailError: null,
          targetedDetailErrors:
              Map<String, Object>.unmodifiable(targetedDetailErrors),
          metadataStatus: hasCompleteProposedMetadata
              ? MultiExamPlanMetadataStatus.current
              : MultiExamPlanMetadataStatus.unavailable,
          operationError: null,
          projectionStatus: MultiExamPlanProjectionStatus.current,
        );
      } catch (error) {
        if (_disposed || generation != _loadGeneration) return;
        final visibleIds = feed.balances.map((summary) => summary.id).toSet();
        final selectedId = state.selectedBalanceId;
        final details = <String, MultiExamPlanBatch>{...state.details}
          ..removeWhere(
            (id, _) => !visibleIds.contains(id) && id != selectedId,
          );
        final authoritativeIds = <String>{...state.authoritativeDetailIds}
          ..removeWhere((id) => !details.containsKey(id));
        state = state.copyWith(
          isLoading: false,
          balances: feed.balances,
          details: Map.unmodifiable(details),
          authoritativeDetailIds: Set.unmodifiable(authoritativeIds),
          loadError: null,
          listDetailError: error,
          metadataStatus: MultiExamPlanMetadataStatus.unavailable,
        );
      }
    } catch (error) {
      if (_disposed || generation != _loadGeneration) return;
      state = state.copyWith(
        isLoading: false,
        loadError: error,
        metadataStatus: MultiExamPlanMetadataStatus.unavailable,
      );
    }
  }

  Future<void> loadBalance(String balanceId) async {
    if (_disposed || state.isBusy || state.requiresExactRetry) return;
    final claim = _claimDetailRead(balanceId);
    final targetedDetailErrors = <String, Object>{
      ...state.targetedDetailErrors,
    }..remove(balanceId);
    state = state.copyWith(
      selectedBalanceId: balanceId,
      targetedDetailErrors:
          Map<String, Object>.unmodifiable(targetedDetailErrors),
    );
    try {
      final balance = await _repository.getBalance(balanceId);
      if (_disposed || !_isCurrentDetailRead(balanceId, claim)) return;
      _recordBalance(
        balance,
        select: state.selectedBalanceId == balanceId,
        validateExistingSummary: true,
      );
    } catch (error) {
      if (_disposed || !_isCurrentDetailRead(balanceId, claim)) return;
      if (state.selectedBalanceId == balanceId) {
        state = state.copyWith(
          targetedDetailErrors: Map<String, Object>.unmodifiable({
            ...state.targetedDetailErrors,
            balanceId: error,
          }),
        );
      }
    }
  }

  Future<bool> propose(MultiExamPlanProposalDraft draft) {
    if (_disposed || state.isBusy || state.requiresExactRetry) {
      return Future.value(false);
    }
    return _apply(
      MultiExamPlanPendingMutation.proposal(
        requestId: newClientUuid(),
        draft: draft,
      ),
    );
  }

  Future<bool> confirm(MultiExamPlanBatch balance) {
    if (_disposed || !state.canConfirm(balance)) {
      return Future.value(false);
    }
    return _apply(
      MultiExamPlanPendingMutation.lifecycle(
        kind: MultiExamPlanMutationKind.confirm,
        requestId: newClientUuid(),
        balanceId: balance.id,
        expectedRevision: balance.revision,
      ),
    );
  }

  Future<bool> cancel(MultiExamPlanBatch balance) {
    if (_disposed || !state.canCancel(balance)) {
      return Future.value(false);
    }
    return _apply(
      MultiExamPlanPendingMutation.lifecycle(
        kind: MultiExamPlanMutationKind.cancel,
        requestId: newClientUuid(),
        balanceId: balance.id,
        expectedRevision: balance.revision,
      ),
    );
  }

  Future<bool> retryExact() {
    if (_disposed) return Future.value(false);
    final pending = state.pendingMutation;
    if (pending == null || state.isBusy) return Future.value(false);
    return _apply(pending);
  }

  Future<void> refreshSavedProjection() async {
    if (_disposed || !state.savedButRefreshFailed || state.isBusy) return;
    final scope = state.savedRefreshScope;
    if (scope == null) return;
    state = state.copyWith(
      projectionStatus: MultiExamPlanProjectionStatus.refreshing,
    );
    try {
      if (scope == MultiExamPlanRefreshScope.lifecycle) {
        await _projectionRefresh();
      }
      if (_disposed) return;
      await _reloadBatchProjectionOrThrow();
      if (_disposed) return;
      state = state.copyWith(
        projectionStatus: MultiExamPlanProjectionStatus.current,
        savedButRefreshFailed: false,
        savedRefreshScope: null,
      );
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        projectionStatus: MultiExamPlanProjectionStatus.stale,
        metadataStatus: MultiExamPlanMetadataStatus.unavailable,
        savedButRefreshFailed: true,
      );
    }
  }

  void clearOperationError() {
    if (_disposed || state.isBusy || state.requiresExactRetry) return;
    state = state.copyWith(operationError: null);
  }

  Future<bool> _apply(MultiExamPlanPendingMutation pending) async {
    if (_disposed) return false;
    if (!_mutationGate.tryAcquire(this)) return false;
    _loadGeneration += 1;
    _detailEpoch += 1;
    state = state.copyWith(
      isLoading: false,
      operation: switch (pending.kind) {
        MultiExamPlanMutationKind.proposal => MultiExamPlanOperation.proposing,
        MultiExamPlanMutationKind.confirm => MultiExamPlanOperation.confirming,
        MultiExamPlanMutationKind.cancel => MultiExamPlanOperation.cancelling,
      },
      operationError: null,
      lastOutcome: null,
      selectedBalanceId: pending.kind == MultiExamPlanMutationKind.proposal
          ? null
          : pending.targetId,
    );
    MultiExamPlanRefreshScope? refreshScope;
    try {
      switch (pending.kind) {
        case MultiExamPlanMutationKind.proposal:
          final result = await _repository.propose(
            requestId: pending.requestId,
            draft: pending.draft!,
          );
          if (_disposed) return false;
          switch (result) {
            case MultiExamPlanNoChange():
              state = state.copyWith(
                lastOutcome: 'no_change',
                selectedBalanceId: null,
              );
            case MultiExamPlanSingle(:final plan):
              final key = '${plan.id}:${plan.latestRevision}';
              if (_adoptedSingleRevisions.add(key)) _adoptSinglePlan(plan);
              state = state.copyWith(
                lastOutcome: 'single_plan',
                selectedBalanceId: null,
              );
              refreshScope = MultiExamPlanRefreshScope.preview;
            case MultiExamPlanBatchProposal(:final balance):
              _recordBalance(balance, select: true);
              state = state.copyWith(lastOutcome: 'multi_exam_batch');
              refreshScope = MultiExamPlanRefreshScope.preview;
          }
        case MultiExamPlanMutationKind.confirm:
          final balance = await _repository.confirm(
            balanceId: pending.targetId,
            requestId: pending.requestId,
            expectedRevision: pending.expectedRevision!,
          );
          if (_disposed) return false;
          _recordBalance(balance, select: true);
          state = state.copyWith(lastOutcome: 'confirmed');
          refreshScope = MultiExamPlanRefreshScope.lifecycle;
        case MultiExamPlanMutationKind.cancel:
          final balance = await _repository.cancel(
            balanceId: pending.targetId,
            requestId: pending.requestId,
            expectedRevision: pending.expectedRevision!,
          );
          if (_disposed) return false;
          _recordBalance(balance, select: true);
          state = state.copyWith(lastOutcome: 'cancelled');
          refreshScope = MultiExamPlanRefreshScope.lifecycle;
      }
      if (_disposed) return false;
      state = state.copyWith(
        operation: MultiExamPlanOperation.idle,
        operationError: null,
        pendingMutation: null,
      );
      if (refreshScope != null) {
        await _refreshAfterDurableWrite(refreshScope);
      }
      return true;
    } catch (error) {
      if (_disposed) return false;
      final exact = deadlinePlanMutationRequiresExactRetry(error);
      state = state.copyWith(
        operation: MultiExamPlanOperation.idle,
        operationError: error,
        pendingMutation: exact ? pending : null,
        projectionStatus: exact
            ? state.projectionStatus
            : MultiExamPlanProjectionStatus.stale,
      );
      return false;
    } finally {
      _mutationGate.release(this);
    }
  }

  Future<void> _refreshAfterDurableWrite(
    MultiExamPlanRefreshScope scope,
  ) async {
    if (_disposed) return;
    state = state.copyWith(
      projectionStatus: MultiExamPlanProjectionStatus.refreshing,
      savedButRefreshFailed: false,
    );
    try {
      if (scope == MultiExamPlanRefreshScope.lifecycle) {
        await _projectionRefresh();
      }
      if (_disposed) return;
      await _reloadBatchProjectionOrThrow();
      if (_disposed) return;
      state = state.copyWith(
        projectionStatus: MultiExamPlanProjectionStatus.current,
        savedButRefreshFailed: false,
        savedRefreshScope: null,
      );
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        projectionStatus: MultiExamPlanProjectionStatus.stale,
        metadataStatus: MultiExamPlanMetadataStatus.unavailable,
        savedButRefreshFailed: true,
        savedRefreshScope: scope,
      );
    }
  }

  Future<void> _reloadBatchProjectionOrThrow() async {
    await load();
    if (_disposed) return;
    if (state.metadataStatus != MultiExamPlanMetadataStatus.current ||
        state.loadError != null ||
        state.listDetailError != null ||
        state.selectedDetailError != null) {
      throw StateError('Exam balance projection refresh failed.');
    }
  }

  void _recordBalance(
    MultiExamPlanBatch balance, {
    required bool select,
    bool validateExistingSummary = false,
  }) {
    if (_disposed) return;
    MultiExamPlanBatchSummary? matchingSummary;
    for (final summary in state.balances) {
      if (summary.id == balance.id) {
        matchingSummary = summary;
        break;
      }
    }
    if (validateExistingSummary &&
        matchingSummary != null &&
        !matchingSummary.matchesBatch(balance)) {
      throw const MultiExamPlanContractException(
        'Exam balance summary and detail disagree.',
      );
    }
    final details = {...state.details, balance.id: balance};
    final balances = [...state.balances];
    final summary = MultiExamPlanBatchSummary.fromBatch(balance);
    final index =
        balances.indexWhere((candidate) => candidate.id == balance.id);
    if (index == -1) {
      balances.insert(0, summary);
    } else {
      balances[index] = summary;
    }
    balances.sort((left, right) {
      final updated = right.updatedAt.compareTo(left.updatedAt);
      return updated != 0 ? updated : right.id.compareTo(left.id);
    });
    final targetedDetailErrors = <String, Object>{
      ...state.targetedDetailErrors,
    }..remove(balance.id);
    state = state.copyWith(
      balances: List.unmodifiable(balances),
      details: Map.unmodifiable(details),
      authoritativeDetailIds: Set.unmodifiable({
        ...state.authoritativeDetailIds,
        balance.id,
      }),
      selectedBalanceId: select ? balance.id : state.selectedBalanceId,
      targetedDetailErrors:
          Map<String, Object>.unmodifiable(targetedDetailErrors),
      metadataStatus: !state.isLoading &&
              state.loadError == null &&
              state.listDetailError == null &&
              balances
                  .where(
                    (summary) => summary.status == MultiExamPlanStatus.proposed,
                  )
                  .every(
                    (summary) => {...state.authoritativeDetailIds, balance.id}
                        .contains(summary.id),
                  )
          ? MultiExamPlanMetadataStatus.current
          : state.metadataStatus,
    );
  }

  ({int epoch, int serial}) _claimDetailRead(String balanceId) {
    final serial = ++_detailReadSerial;
    _latestDetailReads[balanceId] = serial;
    return (epoch: _detailEpoch, serial: serial);
  }

  bool _isCurrentDetailRead(
    String balanceId,
    ({int epoch, int serial}) claim,
  ) =>
      claim.epoch == _detailEpoch &&
      _latestDetailReads[balanceId] == claim.serial;
}

const Object _unset = Object();
