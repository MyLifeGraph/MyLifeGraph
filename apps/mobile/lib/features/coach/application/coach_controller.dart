import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/client_uuid.dart';
import '../domain/coach.dart';
import '../domain/coach_repository.dart';

const coachResponseTimeoutMargin = Duration(seconds: 10);

class CoachRetryPayload {
  const CoachRetryPayload({
    required this.message,
    required this.context,
  });

  final String message;
  final CoachContextSelection context;
}

class CoachState {
  const CoachState({
    required this.isLoading,
    required this.capabilities,
    required this.history,
    required this.memories,
    required this.contextOptions,
    required this.capabilityError,
    required this.historyError,
    required this.memoryError,
    required this.contextOptionsError,
    required this.isSending,
    required this.isDeletingHistory,
    required this.updatingMemoryId,
    required this.sendError,
    required this.historyActionError,
    required this.memoryActionError,
    required this.draft,
    required this.requestId,
    required this.exactRetryPayload,
    required this.selectedScope,
    required this.patternHorizon,
    required this.selectedFocusSessionId,
    required this.latestResponse,
    required this.latestMessage,
  });

  factory CoachState.loading() => CoachState(
        isLoading: true,
        capabilities: null,
        history: CoachHistory.empty(),
        memories: CoachMemorySelection.empty(),
        contextOptions: CoachContextOptions.localDemo(),
        capabilityError: null,
        historyError: null,
        memoryError: null,
        contextOptionsError: null,
        isSending: false,
        isDeletingHistory: false,
        updatingMemoryId: null,
        sendError: null,
        historyActionError: null,
        memoryActionError: null,
        draft: '',
        requestId: newClientUuid(),
        exactRetryPayload: null,
        selectedScope: CoachContextScope.today,
        patternHorizon: CoachPatternHorizon.days90,
        selectedFocusSessionId: null,
        latestResponse: null,
        latestMessage: null,
      );

  final bool isLoading;
  final CoachCapabilities? capabilities;
  final CoachHistory history;
  final CoachMemorySelection memories;
  final CoachContextOptions contextOptions;
  final Object? capabilityError;
  final Object? historyError;
  final Object? memoryError;
  final Object? contextOptionsError;
  final bool isSending;
  final bool isDeletingHistory;
  final String? updatingMemoryId;
  final Object? sendError;
  final Object? historyActionError;
  final Object? memoryActionError;
  final String draft;
  final String requestId;
  final CoachRetryPayload? exactRetryPayload;
  final CoachContextScope selectedScope;
  final CoachPatternHorizon patternHorizon;
  final String? selectedFocusSessionId;
  final CoachResponse? latestResponse;
  final String? latestMessage;

  String? get exactRetryMessage => exactRetryPayload?.message;
  int get draftCodepoints => draft.trim().runes.length;
  bool get draftIsValid =>
      draftCodepoints > 0 && draftCodepoints <= coachMessageCodepoints;
  CoachContextSelection? get selectedContext => switch (selectedScope) {
        CoachContextScope.today => const CoachContextSelection.today(),
        CoachContextScope.patterns =>
          CoachContextSelection.patterns(patternHorizon),
        CoachContextScope.focus => selectedFocusSessionId == null
            ? null
            : CoachContextSelection.focus(selectedFocusSessionId!),
        CoachContextScope.review => const CoachContextSelection.review(),
      };
  bool get contextIsValid {
    final selection = selectedContext;
    if (selection == null) return false;
    if (exactRetryPayload?.context == selection) return true;
    return switch (selectedScope) {
      CoachContextScope.today || CoachContextScope.review => true,
      CoachContextScope.patterns =>
        contextOptions.personalPatternAnalysisEnabled,
      CoachContextScope.focus => contextOptions.focusOptions.any(
          (option) => option.focusSessionId == selectedFocusSessionId,
        ),
    };
  }

  bool get isRateLimited =>
      capabilities?.state == CoachCapabilityState.ready &&
          capabilities?.limits.remainingRequests == 0 ||
      sendError is CoachRemoteException &&
          (sendError as CoachRemoteException).isRateLimited;
  bool get canSend =>
      capabilities?.canRespond == true &&
      draftIsValid &&
      contextIsValid &&
      !isSending &&
      !isRateLimited;

  CoachState copyWith({
    bool? isLoading,
    Object? capabilities = _unset,
    CoachHistory? history,
    CoachMemorySelection? memories,
    CoachContextOptions? contextOptions,
    Object? capabilityError = _unset,
    Object? historyError = _unset,
    Object? memoryError = _unset,
    Object? contextOptionsError = _unset,
    bool? isSending,
    bool? isDeletingHistory,
    Object? updatingMemoryId = _unset,
    Object? sendError = _unset,
    Object? historyActionError = _unset,
    Object? memoryActionError = _unset,
    String? draft,
    String? requestId,
    Object? exactRetryPayload = _unset,
    CoachContextScope? selectedScope,
    CoachPatternHorizon? patternHorizon,
    Object? selectedFocusSessionId = _unset,
    Object? latestResponse = _unset,
    Object? latestMessage = _unset,
  }) {
    return CoachState(
      isLoading: isLoading ?? this.isLoading,
      capabilities: identical(capabilities, _unset)
          ? this.capabilities
          : capabilities as CoachCapabilities?,
      history: history ?? this.history,
      memories: memories ?? this.memories,
      contextOptions: contextOptions ?? this.contextOptions,
      capabilityError: identical(capabilityError, _unset)
          ? this.capabilityError
          : capabilityError,
      historyError:
          identical(historyError, _unset) ? this.historyError : historyError,
      memoryError:
          identical(memoryError, _unset) ? this.memoryError : memoryError,
      contextOptionsError: identical(contextOptionsError, _unset)
          ? this.contextOptionsError
          : contextOptionsError,
      isSending: isSending ?? this.isSending,
      isDeletingHistory: isDeletingHistory ?? this.isDeletingHistory,
      updatingMemoryId: identical(updatingMemoryId, _unset)
          ? this.updatingMemoryId
          : updatingMemoryId as String?,
      sendError: identical(sendError, _unset) ? this.sendError : sendError,
      historyActionError: identical(historyActionError, _unset)
          ? this.historyActionError
          : historyActionError,
      memoryActionError: identical(memoryActionError, _unset)
          ? this.memoryActionError
          : memoryActionError,
      draft: draft ?? this.draft,
      requestId: requestId ?? this.requestId,
      exactRetryPayload: identical(exactRetryPayload, _unset)
          ? this.exactRetryPayload
          : exactRetryPayload as CoachRetryPayload?,
      selectedScope: selectedScope ?? this.selectedScope,
      patternHorizon: patternHorizon ?? this.patternHorizon,
      selectedFocusSessionId: identical(selectedFocusSessionId, _unset)
          ? this.selectedFocusSessionId
          : selectedFocusSessionId as String?,
      latestResponse: identical(latestResponse, _unset)
          ? this.latestResponse
          : latestResponse as CoachResponse?,
      latestMessage: identical(latestMessage, _unset)
          ? this.latestMessage
          : latestMessage as String?,
    );
  }
}

class CoachController extends StateNotifier<CoachState> {
  CoachController({required CoachRepository repository})
      : _repository = repository,
        super(CoachState.loading()) {
    Future<void>.microtask(load);
  }

  final CoachRepository _repository;
  bool _disposed = false;

  Future<void> load() async {
    if (state.isSending) return;
    state = state.copyWith(
      isLoading: true,
      capabilityError: null,
      historyError: null,
      memoryError: null,
      contextOptionsError: null,
      sendError: null,
    );

    CoachCapabilities? capabilities;
    CoachHistory? history;
    CoachMemorySelection? memories;
    CoachContextOptions? contextOptions;
    Object? capabilityError;
    Object? historyError;
    Object? memoryError;
    Object? contextOptionsError;

    await Future.wait([
      () async {
        try {
          capabilities = await _repository.getCapabilities();
        } catch (error) {
          capabilityError = error;
        }
      }(),
      () async {
        try {
          history = await _repository.getHistory();
        } catch (error) {
          historyError = error;
        }
      }(),
      () async {
        try {
          memories = await _repository.getMemories();
        } catch (error) {
          memoryError = error;
        }
      }(),
      () async {
        try {
          contextOptions = await _repository.getContextOptions();
        } catch (error) {
          contextOptionsError = error;
        }
      }(),
    ]);
    if (_disposed) return;
    final resolvedOptions = contextOptions ?? state.contextOptions;
    var selectedFocusSessionId = state.selectedFocusSessionId;
    final lockedFocusId = state.exactRetryPayload?.context.focusSessionId;
    if (lockedFocusId != null) {
      selectedFocusSessionId = lockedFocusId;
    } else if (contextOptions != null &&
        !resolvedOptions.focusOptions.any(
          (option) => option.focusSessionId == selectedFocusSessionId,
        )) {
      selectedFocusSessionId = resolvedOptions.defaultFocusSessionId;
    }
    state = state.copyWith(
      isLoading: false,
      capabilities: capabilities ?? state.capabilities,
      history: history ?? state.history,
      memories: memories ?? state.memories,
      contextOptions: resolvedOptions,
      capabilityError: capabilityError,
      historyError: historyError,
      memoryError: memoryError,
      contextOptionsError: contextOptionsError,
      selectedFocusSessionId: selectedFocusSessionId,
    );
  }

  void updateDraft(String value) {
    if (state.isSending) return;
    final normalized = value.trim();
    final changedExactPayload = state.exactRetryPayload != null &&
        normalized != state.exactRetryPayload!.message;
    state = state.copyWith(
      draft: value,
      requestId: changedExactPayload ? newClientUuid() : state.requestId,
      exactRetryPayload: changedExactPayload ? null : state.exactRetryPayload,
      sendError: changedExactPayload ? null : state.sendError,
    );
  }

  void selectScope(CoachContextScope scope) {
    _updateContext(scope: scope);
  }

  void selectPatternHorizon(CoachPatternHorizon horizon) {
    _updateContext(patternHorizon: horizon);
  }

  void selectFocusSession(String focusSessionId) {
    final normalized = focusSessionId.trim().toLowerCase();
    if (!state.contextOptions.focusOptions.any(
      (option) => option.focusSessionId == normalized,
    )) {
      return;
    }
    _updateContext(selectedFocusSessionId: normalized);
  }

  void _updateContext({
    CoachContextScope? scope,
    CoachPatternHorizon? patternHorizon,
    Object? selectedFocusSessionId = _unset,
  }) {
    if (state.isSending) return;
    final nextScope = scope ?? state.selectedScope;
    final nextHorizon = patternHorizon ?? state.patternHorizon;
    final nextFocusId = identical(selectedFocusSessionId, _unset)
        ? state.selectedFocusSessionId
        : selectedFocusSessionId as String?;
    if (nextScope == state.selectedScope &&
        nextHorizon == state.patternHorizon &&
        nextFocusId == state.selectedFocusSessionId) {
      return;
    }
    final nextContext = _contextFor(
      scope: nextScope,
      patternHorizon: nextHorizon,
      focusSessionId: nextFocusId,
    );
    final changedExactPayload = state.exactRetryPayload != null &&
        state.exactRetryPayload!.context != nextContext;
    state = state.copyWith(
      selectedScope: nextScope,
      patternHorizon: nextHorizon,
      selectedFocusSessionId: nextFocusId,
      requestId: changedExactPayload ? newClientUuid() : state.requestId,
      exactRetryPayload: changedExactPayload ? null : state.exactRetryPayload,
      sendError: changedExactPayload ? null : state.sendError,
    );
  }

  Future<bool> send() async {
    if (state.isSending) return false;
    final capabilities = state.capabilities;
    final message = state.draft.trim();
    final context = state.selectedContext;
    if (message.isEmpty || message.runes.length > coachMessageCodepoints) {
      state = state.copyWith(
        sendError: const CoachInputException(
          'Enter 1 to 2,000 Unicode code points before sending.',
        ),
      );
      return false;
    }
    if (context == null || !state.contextIsValid) {
      state = state.copyWith(
        sendError: const CoachInputException(
          'Choose an available Coach context before sending.',
        ),
      );
      return false;
    }
    if (capabilities?.state != CoachCapabilityState.ready) {
      state = state.copyWith(
        sendError: const CoachAccessException(
          'Coach is not ready to respond.',
        ),
      );
      return false;
    }
    if (capabilities!.limits.remainingRequests == 0) {
      state = state.copyWith(
        sendError: const CoachRemoteException(
          code: 'daily_limit',
          message: 'The local Coach request limit has been reached.',
          retryable: true,
          statusCode: 429,
        ),
      );
      return false;
    }

    var requestId = state.requestId;
    final exactRetry = state.exactRetryPayload;
    if (exactRetry != null &&
        (exactRetry.message != message || exactRetry.context != context)) {
      requestId = newClientUuid();
    }
    state = state.copyWith(
      isSending: true,
      sendError: null,
      requestId: requestId,
    );
    try {
      final response = await _repository.respond(
        requestId: requestId,
        message: message,
        context: context,
        receiveTimeout: Duration(
          seconds: capabilities.limits.timeoutSeconds +
              coachResponseTimeoutMargin.inSeconds,
        ),
      );
      if (_disposed) return false;
      await _refreshAfterResponse();
      if (_disposed) return false;
      state = state.copyWith(
        isSending: false,
        draft: '',
        requestId: newClientUuid(),
        exactRetryPayload: null,
        sendError: null,
        latestResponse: response,
        latestMessage: message,
      );
      return true;
    } catch (error) {
      if (_disposed) return false;
      final preserveIdentity = coachFailurePreservesRequestIdentity(error);
      state = state.copyWith(
        isSending: false,
        sendError: error,
        requestId: preserveIdentity ? requestId : newClientUuid(),
        exactRetryPayload: preserveIdentity
            ? CoachRetryPayload(message: message, context: context)
            : null,
      );
      return false;
    }
  }

  Future<void> deleteHistory() async {
    if (state.isDeletingHistory || state.isSending) return;
    state = state.copyWith(
      isDeletingHistory: true,
      historyActionError: null,
    );
    try {
      await _repository.deleteHistory();
      if (_disposed) return;
      state = state.copyWith(
        isDeletingHistory: false,
        history: CoachHistory.empty(),
        latestResponse: null,
        latestMessage: null,
        historyActionError: null,
      );
    } catch (error) {
      if (_disposed) return;
      state = state.copyWith(
        isDeletingHistory: false,
        historyActionError: error,
      );
    }
  }

  Future<void> setMemorySelected(CoachMemory memory, bool selected) async {
    if (state.updatingMemoryId != null || state.isSending) return;
    if (selected &&
        !memory.selected &&
        state.memories.selectedCount >= state.memories.maxSelected) {
      state = state.copyWith(
        memoryActionError: const CoachAccessException(
          'At most eight memories can be selected for Coach context.',
        ),
      );
      return;
    }
    state = state.copyWith(
      updatingMemoryId: memory.id,
      memoryActionError: null,
    );
    try {
      final memories = selected
          ? await _repository.selectMemory(memory.id)
          : await _repository.deselectMemory(memory.id);
      if (_disposed) return;
      state = state.copyWith(
        memories: memories,
        updatingMemoryId: null,
        memoryActionError: null,
      );
    } catch (error) {
      if (_disposed) return;
      state = state.copyWith(
        updatingMemoryId: null,
        memoryActionError: error,
      );
    }
  }

  Future<void> _refreshAfterResponse() async {
    CoachCapabilities? capabilities;
    CoachHistory? history;
    Object? capabilityError;
    Object? historyError;
    await Future.wait([
      () async {
        try {
          capabilities = await _repository.getCapabilities();
        } catch (error) {
          capabilityError = error;
        }
      }(),
      () async {
        try {
          history = await _repository.getHistory();
        } catch (error) {
          historyError = error;
        }
      }(),
    ]);
    if (_disposed) return;
    state = state.copyWith(
      capabilities: capabilities ?? state.capabilities,
      history: history ?? state.history,
      capabilityError: capabilityError,
      historyError: historyError,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _repository.cancelActiveResponse();
    super.dispose();
  }
}

CoachContextSelection? _contextFor({
  required CoachContextScope scope,
  required CoachPatternHorizon patternHorizon,
  required String? focusSessionId,
}) =>
    switch (scope) {
      CoachContextScope.today => const CoachContextSelection.today(),
      CoachContextScope.patterns =>
        CoachContextSelection.patterns(patternHorizon),
      CoachContextScope.focus => focusSessionId == null
          ? null
          : CoachContextSelection.focus(focusSessionId),
      CoachContextScope.review => const CoachContextSelection.review(),
    };

bool coachFailurePreservesRequestIdentity(Object error) {
  if (error is CoachRemoteException) return error.preservesRequestIdentity;
  if (error is CoachContractException ||
      error is CoachAccessException ||
      error is CoachInputException) {
    return true;
  }
  final dio = _dioExceptionFrom(error);
  if (dio != null) return dio.response == null;
  return true;
}

String coachErrorMessage(Object? error) {
  if (error is CoachRemoteException) return error.message;
  if (error is CoachAccessException) return error.message;
  if (error is CoachInputException) return error.message;
  if (error is CoachContractException) {
    return 'Coach returned an invalid response. Retry the exact message.';
  }
  final dio = _dioExceptionFrom(error);
  if (dio?.type == DioExceptionType.receiveTimeout ||
      dio?.type == DioExceptionType.connectionTimeout ||
      dio?.type == DioExceptionType.sendTimeout) {
    return 'Coach timed out. Retry the exact message.';
  }
  if (dio != null) {
    return 'Coach could not be reached. Retry the exact message.';
  }
  return 'Coach could not complete this operation. Try again.';
}

DioException? _dioExceptionFrom(Object? error) {
  if (error is DioException) return error;
  final cause = error is AppException ? error.cause : null;
  return cause is DioException ? cause : null;
}

const Object _unset = Object();
