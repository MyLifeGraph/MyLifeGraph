import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/client_uuid.dart';
import '../domain/deadline_plan.dart';
import '../domain/deadline_plan_repository.dart';

enum DeadlinePlanOperation {
  idle,
  proposing,
  confirming,
  completing,
  cancelling,
}

enum DeadlinePlanMutationKind { proposal, confirm, complete, cancel }

enum DeadlinePlanConflictKind {
  revision,
  activeFocus,
  calendarContext,
  stalePreview,
  accountBudget,
  openPlanCap,
  unknown,
}

class DeadlinePlanPendingMutation {
  const DeadlinePlanPendingMutation._({
    required this.kind,
    required this.requestId,
    required this.planId,
    this.draft,
    this.expectedRevision,
  });

  factory DeadlinePlanPendingMutation.proposal({
    required String requestId,
    required DeadlinePlanProposalDraft draft,
  }) =>
      DeadlinePlanPendingMutation._(
        kind: DeadlinePlanMutationKind.proposal,
        requestId: requestId,
        planId: draft.planId,
        draft: draft,
      );

  factory DeadlinePlanPendingMutation.lifecycle({
    required DeadlinePlanMutationKind kind,
    required String requestId,
    required String planId,
    required int expectedRevision,
  }) =>
      DeadlinePlanPendingMutation._(
        kind: kind,
        requestId: requestId,
        planId: planId,
        expectedRevision: expectedRevision,
      );

  final DeadlinePlanMutationKind kind;
  final String requestId;
  final String planId;
  final DeadlinePlanProposalDraft? draft;
  final int? expectedRevision;
}

class DeadlinePlanState {
  const DeadlinePlanState({
    required this.isLoading,
    required this.plans,
    required this.loadError,
    required this.operation,
    required this.operationError,
    required this.pendingMutation,
    required this.reloadSuggested,
    required this.lastChangedPlanId,
  });

  factory DeadlinePlanState.loading() => const DeadlinePlanState(
        isLoading: true,
        plans: [],
        loadError: null,
        operation: DeadlinePlanOperation.idle,
        operationError: null,
        pendingMutation: null,
        reloadSuggested: false,
        lastChangedPlanId: null,
      );

  final bool isLoading;
  final List<DeadlinePlan> plans;
  final Object? loadError;
  final DeadlinePlanOperation operation;
  final Object? operationError;
  final DeadlinePlanPendingMutation? pendingMutation;
  final bool reloadSuggested;
  final String? lastChangedPlanId;

  bool get isBusy => operation != DeadlinePlanOperation.idle;
  bool get requiresExactRetry => pendingMutation != null;

  DeadlinePlanState copyWith({
    bool? isLoading,
    List<DeadlinePlan>? plans,
    Object? loadError = _unset,
    DeadlinePlanOperation? operation,
    Object? operationError = _unset,
    Object? pendingMutation = _unset,
    bool? reloadSuggested,
    Object? lastChangedPlanId = _unset,
  }) {
    return DeadlinePlanState(
      isLoading: isLoading ?? this.isLoading,
      plans: plans ?? this.plans,
      loadError: identical(loadError, _unset) ? this.loadError : loadError,
      operation: operation ?? this.operation,
      operationError: identical(operationError, _unset)
          ? this.operationError
          : operationError,
      pendingMutation: identical(pendingMutation, _unset)
          ? this.pendingMutation
          : pendingMutation as DeadlinePlanPendingMutation?,
      reloadSuggested: reloadSuggested ?? this.reloadSuggested,
      lastChangedPlanId: identical(lastChangedPlanId, _unset)
          ? this.lastChangedPlanId
          : lastChangedPlanId as String?,
    );
  }
}

class DeadlinePlanController extends StateNotifier<DeadlinePlanState> {
  DeadlinePlanController({required DeadlinePlanRepository repository})
      : _repository = repository,
        super(DeadlinePlanState.loading()) {
    Future<void>.microtask(load);
  }

  final DeadlinePlanRepository _repository;

  Future<void> load() async {
    if (state.isBusy) return;
    state = DeadlinePlanState.loading();
    try {
      final feed = await _repository.getPlans();
      state = state.copyWith(isLoading: false, plans: feed.plans);
    } catch (error) {
      state = state.copyWith(isLoading: false, loadError: error);
    }
  }

  Future<bool> propose(DeadlinePlanProposalDraft draft) {
    if (state.isBusy || state.requiresExactRetry) return Future.value(false);
    return _applyProposal(
      DeadlinePlanPendingMutation.proposal(
        requestId: newClientUuid(),
        draft: draft,
      ),
    );
  }

  Future<bool> confirm(DeadlinePlan plan) {
    final revision = plan.pendingRevision?.revision;
    if (revision == null || state.isBusy || state.requiresExactRetry) {
      return Future.value(false);
    }
    return _applyLifecycle(
      DeadlinePlanPendingMutation.lifecycle(
        kind: DeadlinePlanMutationKind.confirm,
        requestId: newClientUuid(),
        planId: plan.id,
        expectedRevision: revision,
      ),
    );
  }

  Future<bool> complete(DeadlinePlan plan) {
    final revision = plan.activeRevision?.revision;
    if (revision == null || state.isBusy || state.requiresExactRetry) {
      return Future.value(false);
    }
    return _applyLifecycle(
      DeadlinePlanPendingMutation.lifecycle(
        kind: DeadlinePlanMutationKind.complete,
        requestId: newClientUuid(),
        planId: plan.id,
        expectedRevision: revision,
      ),
    );
  }

  Future<bool> cancel(DeadlinePlan plan) {
    final expectedRevision = plan.isDraft
        ? plan.pendingRevision?.revision
        : plan.activeRevision?.revision;
    if (expectedRevision == null || state.isBusy || state.requiresExactRetry) {
      return Future.value(false);
    }
    return _applyLifecycle(
      DeadlinePlanPendingMutation.lifecycle(
        kind: DeadlinePlanMutationKind.cancel,
        requestId: newClientUuid(),
        planId: plan.id,
        expectedRevision: expectedRevision,
      ),
    );
  }

  Future<bool> retryExact() {
    final pending = state.pendingMutation;
    if (pending == null || state.isBusy) return Future.value(false);
    return pending.kind == DeadlinePlanMutationKind.proposal
        ? _applyProposal(pending)
        : _applyLifecycle(pending);
  }

  void clearOperationError() {
    if (state.isBusy || state.requiresExactRetry) return;
    state = state.copyWith(operationError: null, reloadSuggested: false);
  }

  void includeReadPlan(DeadlinePlan plan) {
    if (state.isLoading || state.isBusy) return;
    final plans = [...state.plans];
    final index = plans.indexWhere((candidate) => candidate.id == plan.id);
    if (index == -1) {
      plans.add(plan);
    } else {
      plans[index] = plan;
    }
    state = state.copyWith(plans: List.unmodifiable(plans));
  }

  Future<bool> _applyProposal(DeadlinePlanPendingMutation pending) async {
    state = state.copyWith(
      operation: DeadlinePlanOperation.proposing,
      operationError: null,
      reloadSuggested: false,
    );
    try {
      final plan = await _repository.propose(
        requestId: pending.requestId,
        draft: pending.draft!,
      );
      _recordSuccess(plan);
      return true;
    } catch (error) {
      _recordFailure(error, pending);
      return false;
    }
  }

  Future<bool> _applyLifecycle(DeadlinePlanPendingMutation pending) async {
    state = state.copyWith(
      operation: switch (pending.kind) {
        DeadlinePlanMutationKind.confirm => DeadlinePlanOperation.confirming,
        DeadlinePlanMutationKind.complete => DeadlinePlanOperation.completing,
        DeadlinePlanMutationKind.cancel => DeadlinePlanOperation.cancelling,
        DeadlinePlanMutationKind.proposal => DeadlinePlanOperation.proposing,
      },
      operationError: null,
      reloadSuggested: false,
    );
    try {
      final args = (
        planId: pending.planId,
        requestId: pending.requestId,
        expectedRevision: pending.expectedRevision!,
      );
      final plan = switch (pending.kind) {
        DeadlinePlanMutationKind.confirm => _repository.confirm(
            planId: args.planId,
            requestId: args.requestId,
            expectedRevision: args.expectedRevision,
          ),
        DeadlinePlanMutationKind.complete => _repository.complete(
            planId: args.planId,
            requestId: args.requestId,
            expectedRevision: args.expectedRevision,
          ),
        DeadlinePlanMutationKind.cancel => _repository.cancel(
            planId: args.planId,
            requestId: args.requestId,
            expectedRevision: args.expectedRevision,
          ),
        DeadlinePlanMutationKind.proposal => throw StateError(
            'Proposal cannot use the lifecycle mutation path.',
          ),
      };
      _recordSuccess(await plan);
      return true;
    } catch (error) {
      _recordFailure(error, pending);
      return false;
    }
  }

  void _recordSuccess(DeadlinePlan plan) {
    final plans = [...state.plans];
    final index = plans.indexWhere((candidate) => candidate.id == plan.id);
    if (index == -1) {
      plans.insert(0, plan);
    } else {
      plans[index] = plan;
    }
    state = state.copyWith(
      plans: List.unmodifiable(plans),
      operation: DeadlinePlanOperation.idle,
      operationError: null,
      pendingMutation: null,
      reloadSuggested: false,
      lastChangedPlanId: plan.id,
    );
  }

  void _recordFailure(Object error, DeadlinePlanPendingMutation pending) {
    final exact = deadlinePlanMutationRequiresExactRetry(error);
    state = state.copyWith(
      operation: DeadlinePlanOperation.idle,
      operationError: error,
      pendingMutation: exact ? pending : null,
      reloadSuggested: deadlinePlanMutationSuggestsReload(error),
    );
  }
}

bool deadlinePlanMutationRequiresExactRetry(Object error) {
  final status = _dioExceptionFrom(error)?.response?.statusCode;
  return status == null || status < 400 || status >= 500;
}

bool deadlinePlanMutationSuggestsReload(Object error) {
  if (_dioExceptionFrom(error)?.response?.statusCode != 409) return false;
  final kind = deadlinePlanConflictKind(error);
  return kind == DeadlinePlanConflictKind.revision ||
      kind == DeadlinePlanConflictKind.unknown;
}

DeadlinePlanConflictKind deadlinePlanConflictKind(Object error) {
  if (_dioExceptionFrom(error)?.response?.statusCode != 409) {
    return DeadlinePlanConflictKind.unknown;
  }
  final detail = _conflictDetail(error);
  if (_revisionConflictDetails.contains(detail)) {
    return DeadlinePlanConflictKind.revision;
  }
  if (_activeFocusConflictDetails.contains(detail)) {
    return DeadlinePlanConflictKind.activeFocus;
  }
  if (_calendarConflictDetails.contains(detail)) {
    return DeadlinePlanConflictKind.calendarContext;
  }
  if (_stalePreviewConflictDetails.contains(detail)) {
    return DeadlinePlanConflictKind.stalePreview;
  }
  if (detail ==
      'Daily preparation budget is exceeded. Create a fresh preview.') {
    return DeadlinePlanConflictKind.accountBudget;
  }
  if (detail == 'You already have 50 open deadline plans.') {
    return DeadlinePlanConflictKind.openPlanCap;
  }
  return DeadlinePlanConflictKind.unknown;
}

String? deadlinePlanConflictGuidance(Object error) {
  if (_dioExceptionFrom(error)?.response?.statusCode != 409) return null;
  return switch (deadlinePlanConflictKind(error)) {
    DeadlinePlanConflictKind.activeFocus =>
      'Finish or abandon the active Focus session before changing or confirming this preparation plan.',
    DeadlinePlanConflictKind.calendarContext =>
      'Calendar data changed. Review the plan, unlink the imported event or turn off imported busy times, then create a fresh preview.',
    DeadlinePlanConflictKind.stalePreview =>
      'This preview no longer matches current time, Focus progress, or reservations. Adjust the plan to create a fresh preview.',
    DeadlinePlanConflictKind.accountBudget =>
      'Your total daily preparation budget or another confirmed plan changed. Adjust this plan to create a fresh preview.',
    DeadlinePlanConflictKind.openPlanCap =>
      'Close or cancel one open preparation plan before creating another.',
    DeadlinePlanConflictKind.revision =>
      'The plan changed elsewhere. Load the latest saved plan before reviewing your retained values.',
    DeadlinePlanConflictKind.unknown =>
      'The plan changed or cannot be updated in its current state. Load the latest saved plan before trying again.',
  };
}

String? _conflictDetail(Object error) {
  final data = _dioExceptionFrom(error)?.response?.data;
  if (data is! Map) return null;
  final detail = data['detail'];
  return detail is String ? detail : null;
}

DioException? _dioExceptionFrom(Object error) {
  if (error is DioException) return error;
  final cause = error is AppException ? error.cause : null;
  return cause is DioException ? cause : null;
}

const _revisionConflictDetails = {
  'Deadline plan base revision is stale.',
  'Deadline plan changed. Reload before replanning.',
  'Deadline proposal changed. Reload before confirmation.',
  'Deadline plan changed. Reload before updating it.',
  'A new deadline plan must start at base_revision 0.',
  'A terminal deadline plan cannot be replanned.',
  'request_id is already bound to another deadline operation.',
  'Deadline revision history exceeds the V1 bound.',
  'Draft deadline plan cannot perform this lifecycle action.',
  'Managed task is unavailable for lifecycle update.',
  'Managed task is unavailable for replanning.',
  'Managed task identity is unavailable.',
};

const _activeFocusConflictDetails = {
  'Finish or abandon the active focus session first.',
  'Finish or abandon active focus before replanning.',
  'Finish or abandon active focus before confirmation.',
};

const _stalePreviewConflictDetails = {
  'Deadline proposal is stale or conflicts with a reservation.',
  'Focus progress changed; replan.',
  'Focus progress changed; replan before confirmation.',
};

const _calendarConflictDetails = {
  'Calendar availability is not current. Reconnect or disable it.',
  'Calendar availability is no longer current.',
  'Calendar availability changed. Replan before confirmation.',
  'Availability changed. Replan before confirmation.',
  'Selected calendar source is unavailable. Reload before planning.',
  'Selected calendar source changed. Reload before planning.',
  'Selected calendar source is no longer current.',
  'Calendar source changed. Replan before confirmation.',
};

const Object _unset = Object();
