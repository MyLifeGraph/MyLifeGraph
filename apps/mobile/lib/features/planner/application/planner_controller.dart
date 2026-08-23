import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/utils/client_uuid.dart';
import '../data/planner_api_data_source.dart';
import '../domain/planner.dart';

typedef PlannerAccessTokenProvider = FutureOr<String?> Function();

enum PlannerOperation {
  idle,
  loading,
  proposing,
  confirming,
  savingCommitment,
  savingPreferences,
  archiving,
  cancelling,
}

enum PlannerPendingKind {
  proposal,
  confirm,
  commitmentCreate,
  commitmentUpdate,
  preferences,
  commitmentArchive,
  cancel,
}

enum PlannerProjectionStatus {
  current,
  refreshingAfterMutation,
  staleAfterMutation,
}

enum PlannerExactRetryDisposition {
  succeeded,
  ambiguous,
  conflict,
  deterministicFailure,
}

class PlannerExactRetryResult {
  const PlannerExactRetryResult({
    required this.pending,
    required this.disposition,
  });

  final PlannerPendingMutation pending;
  final PlannerExactRetryDisposition disposition;

  bool get succeeded => disposition == PlannerExactRetryDisposition.succeeded;
}

class PlannerMutationOutcome {
  const PlannerMutationOutcome({
    required this.committed,
    required this.projectionCurrent,
  });

  final bool committed;
  final bool projectionCurrent;
}

class PlannerPendingMutation {
  const PlannerPendingMutation({
    required this.kind,
    required this.requestId,
    this.body,
    this.planId,
    this.expectedRevision,
    this.commitmentId,
    this.expectedUpdatedAt,
  });

  final PlannerPendingKind kind;
  final String requestId;
  final Map<String, dynamic>? body;
  final String? planId;
  final int? expectedRevision;
  final String? commitmentId;
  final DateTime? expectedUpdatedAt;
}

class PlannerState {
  const PlannerState({
    required this.overview,
    required this.operation,
    required this.loadError,
    required this.operationError,
    required this.pendingMutation,
    required this.reloadSuggested,
    required this.preview,
    required this.projectionStatus,
    required this.mutationOutcome,
  });

  factory PlannerState.initial() => const PlannerState(
        overview: null,
        operation: PlannerOperation.loading,
        loadError: null,
        operationError: null,
        pendingMutation: null,
        reloadSuggested: false,
        preview: null,
        projectionStatus: PlannerProjectionStatus.current,
        mutationOutcome: null,
      );

  final PlannerOverview? overview;
  final PlannerOperation operation;
  final Object? loadError;
  final Object? operationError;
  final PlannerPendingMutation? pendingMutation;
  final bool reloadSuggested;
  final PlannerActionPlan? preview;
  final PlannerProjectionStatus projectionStatus;
  final PlannerMutationOutcome? mutationOutcome;

  bool get isBusy => operation != PlannerOperation.idle;
  bool get requiresExactRetry => pendingMutation != null;
  bool get canMutate =>
      !isBusy &&
      !requiresExactRetry &&
      !reloadSuggested &&
      overview != null &&
      projectionStatus == PlannerProjectionStatus.current;

  PlannerState copyWith({
    Object? overview = _unset,
    PlannerOperation? operation,
    Object? loadError = _unset,
    Object? operationError = _unset,
    Object? pendingMutation = _unset,
    bool? reloadSuggested,
    Object? preview = _unset,
    PlannerProjectionStatus? projectionStatus,
    Object? mutationOutcome = _unset,
  }) =>
      PlannerState(
        overview: identical(overview, _unset)
            ? this.overview
            : overview as PlannerOverview?,
        operation: operation ?? this.operation,
        loadError: identical(loadError, _unset) ? this.loadError : loadError,
        operationError: identical(operationError, _unset)
            ? this.operationError
            : operationError,
        pendingMutation: identical(pendingMutation, _unset)
            ? this.pendingMutation
            : pendingMutation as PlannerPendingMutation?,
        reloadSuggested: reloadSuggested ?? this.reloadSuggested,
        preview: identical(preview, _unset)
            ? this.preview
            : preview as PlannerActionPlan?,
        projectionStatus: projectionStatus ?? this.projectionStatus,
        mutationOutcome: identical(mutationOutcome, _unset)
            ? this.mutationOutcome
            : mutationOutcome as PlannerMutationOutcome?,
      );
}

class PlannerController extends StateNotifier<PlannerState> {
  PlannerController({
    required PlannerApiDataSource api,
    required PlannerAccessTokenProvider accessTokenProvider,
    required bool canUseSyncedPlanner,
    required bool isBackendConfigured,
  })  : _api = api,
        _accessTokenProvider = accessTokenProvider,
        _canUseSyncedPlanner = canUseSyncedPlanner,
        _isBackendConfigured = isBackendConfigured,
        super(PlannerState.initial()) {
    Future<void>.microtask(load);
  }

  final PlannerApiDataSource _api;
  final PlannerAccessTokenProvider _accessTokenProvider;
  final bool _canUseSyncedPlanner;
  final bool _isBackendConfigured;

  Future<void> load() => _loadOverview();

  Future<void> _loadOverview() async {
    if (!mounted) return;
    if (state.isBusy && state.operation != PlannerOperation.loading) return;
    state = state.copyWith(
      operation: PlannerOperation.loading,
      loadError: null,
    );
    try {
      _requireRemote();
      final overview = await _api.getOverview(accessToken: await _token());
      if (!mounted) return;
      state = state.copyWith(
        overview: overview,
        operation: PlannerOperation.idle,
        loadError: null,
        projectionStatus: PlannerProjectionStatus.current,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        operation: PlannerOperation.idle,
        loadError: error,
      );
    }
  }

  PlannerPendingMutation? prepareTaskProposal(PlannerTaskDraft draft) {
    if (!state.canMutate) return null;
    final requestId = newClientUuid();
    final targetId = draft.targetId ?? newClientUuid();
    final existing = _actionPlanFor('task', targetId);
    final body = draft.proposalJson(
      requestId: requestId,
      planId: existing?.id ?? newClientUuid(),
      newTargetId: targetId,
      baseRevision: existing?.latestRevision ?? 0,
      planningStartOn: _planningDate(),
    );
    return PlannerPendingMutation(
      kind: PlannerPendingKind.proposal,
      requestId: requestId,
      body: body,
    );
  }

  PlannerPendingMutation? prepareHabitProposal(PlannerHabitDraft draft) {
    if (!state.canMutate) return null;
    final requestId = newClientUuid();
    final targetId = draft.targetId ?? newClientUuid();
    final existing = _actionPlanFor('habit', targetId);
    final body = draft.proposalJson(
      requestId: requestId,
      planId: existing?.id ?? newClientUuid(),
      newTargetId: targetId,
      baseRevision: existing?.latestRevision ?? 0,
      planningStartOn: _planningDate(),
    );
    return PlannerPendingMutation(
      kind: PlannerPendingKind.proposal,
      requestId: requestId,
      body: body,
    );
  }

  Future<PlannerActionPlan?> submitProposal(PlannerPendingMutation pending) {
    if (pending.kind != PlannerPendingKind.proposal || pending.body == null) {
      throw ArgumentError.value(pending.kind, 'pending', 'Not a proposal');
    }
    return _propose(pending);
  }

  Future<PlannerActionPlan?> _propose(PlannerPendingMutation pending) async {
    if (!state.canMutate) return null;
    state = state.copyWith(
      operation: PlannerOperation.proposing,
      operationError: null,
      reloadSuggested: false,
      mutationOutcome: null,
    );
    try {
      final plan = await _api.propose(
        accessToken: await _token(),
        body: pending.body!,
      );
      if (!mounted) return null;
      state = state.copyWith(
        operation: PlannerOperation.idle,
        pendingMutation: null,
        preview: plan,
        projectionStatus: PlannerProjectionStatus.refreshingAfterMutation,
        mutationOutcome: const PlannerMutationOutcome(
          committed: true,
          projectionCurrent: false,
        ),
      );
      await _reloadAfterMutation();
      return plan;
    } catch (error) {
      if (!mounted) return null;
      _recordFailure(error, pending);
      return null;
    }
  }

  Future<bool> confirm(PlannerActionPlan plan) async {
    final revision = plan.pendingRevision?.revision;
    if (revision == null || !state.canMutate) {
      return false;
    }
    final pending = PlannerPendingMutation(
      kind: PlannerPendingKind.confirm,
      requestId: newClientUuid(),
      planId: plan.id,
      expectedRevision: revision,
    );
    return _confirm(pending);
  }

  Future<bool> _confirm(PlannerPendingMutation pending) async {
    state = state.copyWith(
      operation: PlannerOperation.confirming,
      operationError: null,
      reloadSuggested: false,
      mutationOutcome: null,
    );
    try {
      await _api.mutatePlan(
        accessToken: await _token(),
        planId: pending.planId!,
        operation: 'confirm',
        requestId: pending.requestId,
        expectedRevision: pending.expectedRevision!,
      );
      if (!mounted) return false;
      state = state.copyWith(
        operation: PlannerOperation.idle,
        pendingMutation: null,
        preview: null,
        projectionStatus: PlannerProjectionStatus.refreshingAfterMutation,
        mutationOutcome: const PlannerMutationOutcome(
          committed: true,
          projectionCurrent: false,
        ),
      );
      await _reloadAfterMutation();
      return true;
    } catch (error) {
      if (!mounted) return false;
      _recordFailure(error, pending);
      return false;
    }
  }

  Future<bool> cancelPlan(PlannerActionPlan plan) async {
    if (!state.canMutate) return false;
    final revision =
        plan.pendingRevision?.revision ?? plan.activeRevision?.revision;
    if (revision == null) return false;
    return _cancelPlan(
      PlannerPendingMutation(
        kind: PlannerPendingKind.cancel,
        requestId: newClientUuid(),
        planId: plan.id,
        expectedRevision: revision,
      ),
    );
  }

  Future<bool> _cancelPlan(PlannerPendingMutation pending) async {
    state = state.copyWith(
      operation: PlannerOperation.cancelling,
      operationError: null,
      reloadSuggested: false,
      mutationOutcome: null,
    );
    try {
      await _api.mutatePlan(
        accessToken: await _token(),
        planId: pending.planId!,
        operation: 'cancel',
        requestId: pending.requestId,
        expectedRevision: pending.expectedRevision!,
      );
      if (!mounted) return false;
      state = state.copyWith(
        operation: PlannerOperation.idle,
        pendingMutation: null,
        preview: null,
        projectionStatus: PlannerProjectionStatus.refreshingAfterMutation,
        mutationOutcome: const PlannerMutationOutcome(
          committed: true,
          projectionCurrent: false,
        ),
      );
      await _reloadAfterMutation();
      return true;
    } catch (error) {
      if (!mounted) return false;
      _recordFailure(error, pending);
      return false;
    }
  }

  Future<bool> createCommitment(PlannerCommitmentDraft draft) async {
    if (!state.canMutate) return false;
    final requestId = newClientUuid();
    final body = draft.createJson(
      requestId: requestId,
      commitmentId: newClientUuid(),
    );
    final pending = PlannerPendingMutation(
      kind: PlannerPendingKind.commitmentCreate,
      requestId: requestId,
      body: body,
    );
    return _createCommitment(pending);
  }

  Future<bool> _createCommitment(PlannerPendingMutation pending) async {
    state = state.copyWith(
      operation: PlannerOperation.savingCommitment,
      operationError: null,
      reloadSuggested: false,
      mutationOutcome: null,
    );
    try {
      await _api.createCommitment(
        accessToken: await _token(),
        body: pending.body!,
      );
      if (!mounted) return false;
      state = state.copyWith(
        operation: PlannerOperation.idle,
        pendingMutation: null,
        projectionStatus: PlannerProjectionStatus.refreshingAfterMutation,
        mutationOutcome: const PlannerMutationOutcome(
          committed: true,
          projectionCurrent: false,
        ),
      );
      await _reloadAfterMutation();
      return true;
    } catch (error) {
      if (!mounted) return false;
      _recordFailure(error, pending);
      return false;
    }
  }

  Future<bool> updateCommitment(
    PlannerCommitment commitment,
    PlannerCommitmentDraft draft,
  ) async {
    if (!state.canMutate) return false;
    final requestId = newClientUuid();
    return _updateCommitment(
      PlannerPendingMutation(
        kind: PlannerPendingKind.commitmentUpdate,
        requestId: requestId,
        commitmentId: commitment.id,
        expectedUpdatedAt: commitment.updatedAt,
        body: draft.updateJson(
          requestId: requestId,
          commitment: commitment,
        ),
      ),
    );
  }

  Future<bool> _updateCommitment(PlannerPendingMutation pending) async {
    state = state.copyWith(
      operation: PlannerOperation.savingCommitment,
      operationError: null,
      reloadSuggested: false,
      mutationOutcome: null,
    );
    try {
      await _api.updateCommitment(
        accessToken: await _token(),
        commitmentId: pending.commitmentId!,
        body: pending.body!,
      );
      if (!mounted) return false;
      state = state.copyWith(
        operation: PlannerOperation.idle,
        pendingMutation: null,
        projectionStatus: PlannerProjectionStatus.refreshingAfterMutation,
        mutationOutcome: const PlannerMutationOutcome(
          committed: true,
          projectionCurrent: false,
        ),
      );
      await _reloadAfterMutation();
      return true;
    } catch (error) {
      if (!mounted) return false;
      _recordFailure(error, pending);
      return false;
    }
  }

  Future<bool> updateCalendarPreference(bool enabled) async {
    if (!state.canMutate) {
      return false;
    }
    final pending = PlannerPendingMutation(
      kind: PlannerPendingKind.preferences,
      requestId: newClientUuid(),
      expectedUpdatedAt: state.overview!.preferences.updatedAt,
      body: {'enabled': enabled},
    );
    return _updatePreferences(pending);
  }

  Future<bool> _updatePreferences(PlannerPendingMutation pending) async {
    state = state.copyWith(
      operation: PlannerOperation.savingPreferences,
      operationError: null,
      reloadSuggested: false,
      mutationOutcome: null,
    );
    try {
      await _api.updatePreferences(
        accessToken: await _token(),
        requestId: pending.requestId,
        expectedUpdatedAt: pending.expectedUpdatedAt,
        useCalendarBusyTime: pending.body!['enabled'] as bool,
      );
      if (!mounted) return false;
      state = state.copyWith(
        operation: PlannerOperation.idle,
        pendingMutation: null,
        projectionStatus: PlannerProjectionStatus.refreshingAfterMutation,
        mutationOutcome: const PlannerMutationOutcome(
          committed: true,
          projectionCurrent: false,
        ),
      );
      await _reloadAfterMutation();
      return true;
    } catch (error) {
      if (!mounted) return false;
      _recordFailure(error, pending);
      return false;
    }
  }

  Future<bool> archiveCommitment(PlannerCommitment commitment) async {
    if (!state.canMutate) return false;
    final pending = PlannerPendingMutation(
      kind: PlannerPendingKind.commitmentArchive,
      requestId: newClientUuid(),
      commitmentId: commitment.id,
      expectedUpdatedAt: commitment.updatedAt,
    );
    return _archiveCommitment(pending);
  }

  Future<bool> _archiveCommitment(PlannerPendingMutation pending) async {
    state = state.copyWith(
      operation: PlannerOperation.archiving,
      operationError: null,
      reloadSuggested: false,
      mutationOutcome: null,
    );
    try {
      await _api.archiveCommitment(
        accessToken: await _token(),
        commitmentId: pending.commitmentId!,
        requestId: pending.requestId,
        expectedUpdatedAt: pending.expectedUpdatedAt!,
      );
      if (!mounted) return false;
      state = state.copyWith(
        operation: PlannerOperation.idle,
        pendingMutation: null,
        projectionStatus: PlannerProjectionStatus.refreshingAfterMutation,
        mutationOutcome: const PlannerMutationOutcome(
          committed: true,
          projectionCurrent: false,
        ),
      );
      await _reloadAfterMutation();
      return true;
    } catch (error) {
      if (!mounted) return false;
      _recordFailure(error, pending);
      return false;
    }
  }

  Future<PlannerExactRetryResult?> retryExact() async {
    final pending = state.pendingMutation;
    if (pending == null || state.isBusy) return null;
    state = state.copyWith(pendingMutation: null);
    final succeeded = switch (pending.kind) {
      PlannerPendingKind.proposal => await _propose(pending) != null,
      PlannerPendingKind.confirm => await _confirm(pending),
      PlannerPendingKind.commitmentCreate => await _createCommitment(pending),
      PlannerPendingKind.commitmentUpdate => await _updateCommitment(pending),
      PlannerPendingKind.preferences => await _updatePreferences(pending),
      PlannerPendingKind.commitmentArchive => await _archiveCommitment(pending),
      PlannerPendingKind.cancel => await _cancelPlan(pending),
    };
    final disposition = succeeded
        ? PlannerExactRetryDisposition.succeeded
        : state.pendingMutation?.requestId == pending.requestId &&
                state.requiresExactRetry
            ? PlannerExactRetryDisposition.ambiguous
            : state.reloadSuggested
                ? PlannerExactRetryDisposition.conflict
                : PlannerExactRetryDisposition.deterministicFailure;
    return PlannerExactRetryResult(
      pending: pending,
      disposition: disposition,
    );
  }

  Future<void> discardPendingAndReload() async {
    if (!await reloadBeforeDiscardingPending()) return;
    clearPendingFailureAfterSuccessfulReload();
  }

  Future<bool> reloadBeforeDiscardingPending() async {
    if (state.isBusy) return false;
    await _loadOverview();
    return mounted &&
        state.operation == PlannerOperation.idle &&
        state.loadError == null &&
        state.overview != null &&
        state.projectionStatus == PlannerProjectionStatus.current;
  }

  void clearPendingFailureAfterSuccessfulReload() {
    if (!mounted ||
        state.isBusy ||
        state.loadError != null ||
        state.overview == null ||
        state.projectionStatus != PlannerProjectionStatus.current) {
      return;
    }
    state = state.copyWith(
      operationError: null,
      pendingMutation: null,
      reloadSuggested: false,
      preview: null,
    );
  }

  void clearPreview() {
    if (!state.isBusy) state = state.copyWith(preview: null);
  }

  void requireFreshProjectionAfterCommittedMutation() {
    if (state.isBusy || state.mutationOutcome?.committed != true) return;
    state = state.copyWith(
      projectionStatus: PlannerProjectionStatus.staleAfterMutation,
      mutationOutcome: const PlannerMutationOutcome(
        committed: true,
        projectionCurrent: false,
      ),
    );
  }

  Future<void> _reloadAfterMutation() async {
    try {
      final overview = await _api.getOverview(accessToken: await _token());
      if (!mounted) return;
      state = state.copyWith(overview: overview, loadError: null);
      state = state.copyWith(
        projectionStatus: PlannerProjectionStatus.current,
        mutationOutcome: state.mutationOutcome?.committed == true
            ? const PlannerMutationOutcome(
                committed: true,
                projectionCurrent: true,
              )
            : state.mutationOutcome,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        loadError: error,
        projectionStatus: PlannerProjectionStatus.staleAfterMutation,
        mutationOutcome: const PlannerMutationOutcome(
          committed: true,
          projectionCurrent: false,
        ),
      );
    }
  }

  void _recordFailure(Object error, PlannerPendingMutation pending) {
    if (!mounted) return;
    final ambiguous = _isAmbiguous(error);
    state = state.copyWith(
      operation: PlannerOperation.idle,
      operationError: error,
      pendingMutation: ambiguous ? pending : null,
      reloadSuggested: _isConflict(error),
      mutationOutcome: null,
    );
  }

  void _requireRemote() {
    if (!_canUseSyncedPlanner || !_isBackendConfigured) {
      throw const PlannerAccessException(
        'Planner requires an authenticated synced account.',
      );
    }
  }

  Future<String> _token() async {
    _requireRemote();
    final value = await _accessTokenProvider();
    if (value == null || value.trim().isEmpty) {
      throw const PlannerAccessException(
        'Planner requires an authenticated session.',
      );
    }
    return value.trim();
  }

  String _planningDate() {
    final date = state.overview!.localDate;
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  PlannerActionPlan? _actionPlanFor(String kind, String targetId) {
    final matches = state.overview?.actionPlans.where(
          (plan) =>
              plan.targetKind == kind &&
              plan.targetId == targetId &&
              plan.status != 'cancelled',
        ) ??
        const Iterable<PlannerActionPlan>.empty();
    return matches.isEmpty ? null : matches.single;
  }
}

bool _isConflict(Object error) {
  return apiFailureFrom(error)?.isConflict ?? false;
}

bool _isAmbiguous(Object error) {
  final failure = apiFailureFrom(error);
  if (failure == null) return false;
  final status = failure.statusCode;
  return status == null || status >= 500;
}

const _unset = Object();
