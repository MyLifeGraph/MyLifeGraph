import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/client_uuid.dart';
import '../domain/assignment_series.dart';
import '../domain/assignment_series_repository.dart';
import 'deadline_plan_controller.dart';
import 'preparation_mutation_gate.dart';

enum AssignmentSeriesOperation { idle, proposing, confirming, cancelling }

enum AssignmentSeriesMutationKind { proposal, confirm, cancelFuture }

typedef AssignmentSeriesProjectionRefresh = Future<void> Function();

class AssignmentSeriesPendingMutation {
  const AssignmentSeriesPendingMutation._({
    required this.kind,
    required this.requestId,
    required this.seriesId,
    this.draft,
    this.expectedRevision,
  });

  factory AssignmentSeriesPendingMutation.proposal({
    required String requestId,
    required AssignmentSeriesProposalDraft draft,
  }) =>
      AssignmentSeriesPendingMutation._(
        kind: AssignmentSeriesMutationKind.proposal,
        requestId: requestId,
        seriesId: draft.seriesId,
        draft: draft,
      );

  factory AssignmentSeriesPendingMutation.lifecycle({
    required AssignmentSeriesMutationKind kind,
    required String requestId,
    required String seriesId,
    required int expectedRevision,
  }) =>
      AssignmentSeriesPendingMutation._(
        kind: kind,
        requestId: requestId,
        seriesId: seriesId,
        expectedRevision: expectedRevision,
      );

  final AssignmentSeriesMutationKind kind;
  final String requestId;
  final String seriesId;
  final AssignmentSeriesProposalDraft? draft;
  final int? expectedRevision;
}

class AssignmentSeriesState {
  const AssignmentSeriesState({
    required this.isLoading,
    required this.series,
    required this.loadError,
    required this.operation,
    required this.operationError,
    required this.pendingMutation,
    required this.reloadSuggested,
    required this.lastChangedSeriesId,
  });

  factory AssignmentSeriesState.loading() => const AssignmentSeriesState(
        isLoading: true,
        series: [],
        loadError: null,
        operation: AssignmentSeriesOperation.idle,
        operationError: null,
        pendingMutation: null,
        reloadSuggested: false,
        lastChangedSeriesId: null,
      );

  final bool isLoading;
  final List<AssignmentSeries> series;
  final Object? loadError;
  final AssignmentSeriesOperation operation;
  final Object? operationError;
  final AssignmentSeriesPendingMutation? pendingMutation;
  final bool reloadSuggested;
  final String? lastChangedSeriesId;

  bool get isBusy => operation != AssignmentSeriesOperation.idle;
  bool get requiresExactRetry => pendingMutation != null;

  AssignmentSeriesState copyWith({
    bool? isLoading,
    List<AssignmentSeries>? series,
    Object? loadError = _unset,
    AssignmentSeriesOperation? operation,
    Object? operationError = _unset,
    Object? pendingMutation = _unset,
    bool? reloadSuggested,
    Object? lastChangedSeriesId = _unset,
  }) =>
      AssignmentSeriesState(
        isLoading: isLoading ?? this.isLoading,
        series: series ?? this.series,
        loadError: identical(loadError, _unset) ? this.loadError : loadError,
        operation: operation ?? this.operation,
        operationError: identical(operationError, _unset)
            ? this.operationError
            : operationError,
        pendingMutation: identical(pendingMutation, _unset)
            ? this.pendingMutation
            : pendingMutation as AssignmentSeriesPendingMutation?,
        reloadSuggested: reloadSuggested ?? this.reloadSuggested,
        lastChangedSeriesId: identical(lastChangedSeriesId, _unset)
            ? this.lastChangedSeriesId
            : lastChangedSeriesId as String?,
      );
}

class AssignmentSeriesController extends StateNotifier<AssignmentSeriesState> {
  AssignmentSeriesController({
    required AssignmentSeriesRepository repository,
    required AssignmentSeriesProjectionRefresh projectionRefresh,
    PreparationMutationGate? mutationGate,
  })  : _projectionRefresh = projectionRefresh,
        _repository = repository,
        _mutationGate = mutationGate ?? PreparationMutationGate(),
        super(AssignmentSeriesState.loading()) {
    Future<void>.microtask(load);
  }

  final AssignmentSeriesRepository _repository;
  final AssignmentSeriesProjectionRefresh _projectionRefresh;
  final PreparationMutationGate _mutationGate;

  Future<void> load() async {
    if (state.isBusy || state.requiresExactRetry) return;
    state = AssignmentSeriesState.loading();
    try {
      final feed = await _repository.getSeries();
      state = state.copyWith(isLoading: false, series: feed.series);
    } catch (error) {
      state = state.copyWith(isLoading: false, loadError: error);
    }
  }

  Future<bool> propose(AssignmentSeriesProposalDraft draft) {
    if (state.isBusy || state.requiresExactRetry) return Future.value(false);
    return _apply(
      AssignmentSeriesPendingMutation.proposal(
        requestId: newClientUuid(),
        draft: draft,
      ),
    );
  }

  Future<bool> confirm(AssignmentSeries series) {
    final revision = series.pendingRevision?.revision;
    if (revision == null || state.isBusy || state.requiresExactRetry) {
      return Future.value(false);
    }
    return _apply(
      AssignmentSeriesPendingMutation.lifecycle(
        kind: AssignmentSeriesMutationKind.confirm,
        requestId: newClientUuid(),
        seriesId: series.id,
        expectedRevision: revision,
      ),
    );
  }

  Future<bool> cancelFuture(AssignmentSeries series) {
    final revision =
        series.pendingRevision?.revision ?? series.activeRevision?.revision;
    if (revision == null || state.isBusy || state.requiresExactRetry) {
      return Future.value(false);
    }
    return _apply(
      AssignmentSeriesPendingMutation.lifecycle(
        kind: AssignmentSeriesMutationKind.cancelFuture,
        requestId: newClientUuid(),
        seriesId: series.id,
        expectedRevision: revision,
      ),
    );
  }

  Future<bool> retryExact() {
    final pending = state.pendingMutation;
    if (pending == null || state.isBusy) return Future.value(false);
    return _apply(pending);
  }

  void clearOperationError() {
    if (state.isBusy || state.requiresExactRetry) return;
    state = state.copyWith(operationError: null, reloadSuggested: false);
  }

  Future<bool> _apply(AssignmentSeriesPendingMutation pending) async {
    if (!_mutationGate.tryAcquire(this)) return false;
    state = state.copyWith(
      operation: switch (pending.kind) {
        AssignmentSeriesMutationKind.proposal =>
          AssignmentSeriesOperation.proposing,
        AssignmentSeriesMutationKind.confirm =>
          AssignmentSeriesOperation.confirming,
        AssignmentSeriesMutationKind.cancelFuture =>
          AssignmentSeriesOperation.cancelling,
      },
      operationError: null,
      reloadSuggested: false,
    );
    try {
      final saved = switch (pending.kind) {
        AssignmentSeriesMutationKind.proposal => _repository.propose(
            requestId: pending.requestId,
            draft: pending.draft!,
          ),
        AssignmentSeriesMutationKind.confirm => _repository.confirm(
            seriesId: pending.seriesId,
            requestId: pending.requestId,
            expectedRevision: pending.expectedRevision!,
          ),
        AssignmentSeriesMutationKind.cancelFuture => _repository.cancelFuture(
            seriesId: pending.seriesId,
            requestId: pending.requestId,
            expectedRevision: pending.expectedRevision!,
          ),
      };
      _recordSuccess(await saved);
      if (pending.kind != AssignmentSeriesMutationKind.proposal) {
        try {
          await _projectionRefresh();
        } catch (_) {
          // The series lifecycle write is durable. Refresh remains best effort
          // and must not turn a proven success into an exact retry.
        }
      }
      return true;
    } catch (error) {
      final exact = deadlinePlanMutationRequiresExactRetry(error);
      state = state.copyWith(
        operation: AssignmentSeriesOperation.idle,
        operationError: error,
        pendingMutation: exact ? pending : null,
        reloadSuggested: deadlinePlanMutationSuggestsReload(error),
      );
      return false;
    } finally {
      _mutationGate.release(this);
    }
  }

  void _recordSuccess(AssignmentSeries saved) {
    final series = [...state.series];
    final index = series.indexWhere((item) => item.id == saved.id);
    if (index == -1) {
      series.insert(0, saved);
    } else {
      series[index] = saved;
    }
    state = state.copyWith(
      series: List.unmodifiable(series),
      operation: AssignmentSeriesOperation.idle,
      operationError: null,
      pendingMutation: null,
      reloadSuggested: false,
      lastChangedSeriesId: saved.id,
    );
  }
}

const _unset = Object();
