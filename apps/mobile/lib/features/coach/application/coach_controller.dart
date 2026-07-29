import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/client_uuid.dart';
import '../domain/coach.dart';
import '../domain/coach_repository.dart';

class CoachState {
  const CoachState({
    required this.isLoading,
    required this.capabilities,
    required this.history,
    required this.capabilityError,
    required this.historyError,
    required this.isSending,
    required this.isCancelling,
    required this.isDeletingHistory,
    required this.activityMessage,
    required this.sendError,
    required this.historyActionError,
    required this.draft,
    required this.requestId,
    required this.exactRetryMessage,
    required this.latestResponse,
    required this.latestMessage,
  });

  factory CoachState.loading() => CoachState(
        isLoading: true,
        capabilities: null,
        history: CoachHistory.empty(),
        capabilityError: null,
        historyError: null,
        isSending: false,
        isCancelling: false,
        isDeletingHistory: false,
        activityMessage: null,
        sendError: null,
        historyActionError: null,
        draft: '',
        requestId: newClientUuid(),
        exactRetryMessage: null,
        latestResponse: null,
        latestMessage: null,
      );

  final bool isLoading;
  final CoachCapabilities? capabilities;
  final CoachHistory history;
  final Object? capabilityError;
  final Object? historyError;
  final bool isSending;
  final bool isCancelling;
  final bool isDeletingHistory;
  final String? activityMessage;
  final Object? sendError;
  final Object? historyActionError;
  final String draft;
  final String requestId;
  final String? exactRetryMessage;
  final CoachResponse? latestResponse;
  final String? latestMessage;

  int get draftCodepoints => draft.trim().runes.length;
  bool get draftIsValid =>
      draftCodepoints > 0 && draftCodepoints <= coachMessageCodepoints;
  bool get isRateLimited =>
      capabilities?.state == CoachCapabilityState.ready &&
          capabilities?.limits.remainingRequests == 0 ||
      sendError is CoachRemoteException &&
          (sendError as CoachRemoteException).isRateLimited;
  bool get canSend =>
      capabilities?.canRespond == true &&
      draftIsValid &&
      !isLoading &&
      !isSending &&
      !isDeletingHistory &&
      !isRateLimited;

  CoachState copyWith({
    bool? isLoading,
    Object? capabilities = _unset,
    CoachHistory? history,
    Object? capabilityError = _unset,
    Object? historyError = _unset,
    bool? isSending,
    bool? isCancelling,
    bool? isDeletingHistory,
    Object? activityMessage = _unset,
    Object? sendError = _unset,
    Object? historyActionError = _unset,
    String? draft,
    String? requestId,
    Object? exactRetryMessage = _unset,
    Object? latestResponse = _unset,
    Object? latestMessage = _unset,
  }) =>
      CoachState(
        isLoading: isLoading ?? this.isLoading,
        capabilities: identical(capabilities, _unset)
            ? this.capabilities
            : capabilities as CoachCapabilities?,
        history: history ?? this.history,
        capabilityError: identical(capabilityError, _unset)
            ? this.capabilityError
            : capabilityError,
        historyError:
            identical(historyError, _unset) ? this.historyError : historyError,
        isSending: isSending ?? this.isSending,
        isCancelling: isCancelling ?? this.isCancelling,
        isDeletingHistory: isDeletingHistory ?? this.isDeletingHistory,
        activityMessage: identical(activityMessage, _unset)
            ? this.activityMessage
            : activityMessage as String?,
        sendError: identical(sendError, _unset) ? this.sendError : sendError,
        historyActionError: identical(historyActionError, _unset)
            ? this.historyActionError
            : historyActionError,
        draft: draft ?? this.draft,
        requestId: requestId ?? this.requestId,
        exactRetryMessage: identical(exactRetryMessage, _unset)
            ? this.exactRetryMessage
            : exactRetryMessage as String?,
        latestResponse: identical(latestResponse, _unset)
            ? this.latestResponse
            : latestResponse as CoachResponse?,
        latestMessage: identical(latestMessage, _unset)
            ? this.latestMessage
            : latestMessage as String?,
      );
}

class CoachController extends StateNotifier<CoachState> {
  CoachController({required CoachRepository repository})
      : _repository = repository,
        super(CoachState.loading()) {
    Future<void>.microtask(load);
  }

  final CoachRepository _repository;
  bool _disposed = false;
  bool _cancelRequested = false;
  bool _operationInProgress = false;

  Future<void> load() async {
    if (_operationInProgress || state.isSending || state.isDeletingHistory) {
      return;
    }
    _operationInProgress = true;
    try {
      state = state.copyWith(
        isLoading: true,
        capabilityError: null,
        historyError: null,
        sendError: null,
      );
      await _refreshProjections();
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> _refreshProjections() async {
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
      isLoading: false,
      capabilities: capabilities ?? state.capabilities,
      history: history ?? state.history,
      capabilityError: capabilityError,
      historyError: historyError,
    );
  }

  void updateDraft(String value) {
    if (_operationInProgress ||
        state.isLoading ||
        state.isSending ||
        state.isDeletingHistory) {
      return;
    }
    final changedRetry = state.exactRetryMessage != null &&
        value.trim() != state.exactRetryMessage;
    state = state.copyWith(
      draft: value,
      requestId: changedRetry ? newClientUuid() : state.requestId,
      exactRetryMessage: changedRetry ? null : state.exactRetryMessage,
      sendError: changedRetry ? null : state.sendError,
    );
  }

  Future<bool> send() async {
    if (_operationInProgress ||
        state.isLoading ||
        state.isSending ||
        state.isDeletingHistory) {
      return false;
    }
    final message = state.draft.trim();
    final capability = state.capabilities;
    if (message.isEmpty || message.runes.length > coachMessageCodepoints) {
      state = state.copyWith(
        sendError: const CoachInputException(
          'Enter 1 to 2,000 Unicode code points before sending.',
        ),
      );
      return false;
    }
    if (capability?.canRespond != true) {
      state = state.copyWith(
        sendError: const CoachAccessException(
          'Coach is not ready to respond.',
        ),
      );
      return false;
    }
    var requestId = state.requestId;
    if (state.exactRetryMessage != null && state.exactRetryMessage != message) {
      requestId = newClientUuid();
    }
    _operationInProgress = true;
    try {
      _cancelRequested = false;
      state = state.copyWith(
        isSending: true,
        isCancelling: false,
        activityMessage: 'Starting private analysis …',
        sendError: null,
        requestId: requestId,
      );
      CoachResponse? completed;
      try {
        await for (final event in _repository.respond(
          requestId: requestId,
          message: message,
        )) {
          if (_disposed) return false;
          if (event is CoachStartedEvent) {
            state = state.copyWith(activityMessage: 'Preparing Coach …');
          } else if (event is CoachActivityEvent) {
            state = state.copyWith(activityMessage: event.message);
          } else if (event is CoachCompletedEvent) {
            completed = event.response;
          }
        }
        if (completed == null) {
          throw const CoachContractException(
            'Coach stream ended without a response.',
          );
        }
        if (_disposed) return false;
        state = state.copyWith(
          isLoading: true,
          isSending: false,
          isCancelling: false,
          capabilityError: null,
          historyError: null,
          activityMessage: null,
          draft: '',
          requestId: newClientUuid(),
          exactRetryMessage: null,
          sendError: null,
          latestResponse: completed,
          latestMessage: message,
        );
        await _refreshProjections();
        return !_disposed;
      } catch (error) {
        if (_disposed) return false;
        if (_cancelRequested) {
          state = state.copyWith(
            isLoading: true,
            isSending: false,
            isCancelling: false,
            capabilityError: null,
            historyError: null,
            activityMessage: null,
            sendError: null,
            requestId: newClientUuid(),
            exactRetryMessage: null,
          );
          await _refreshProjections();
          return false;
        }
        final preserve = coachFailurePreservesRequestIdentity(error);
        state = state.copyWith(
          isLoading: true,
          isSending: false,
          isCancelling: false,
          capabilityError: null,
          historyError: null,
          activityMessage: null,
          sendError: error,
          requestId: preserve ? requestId : newClientUuid(),
          exactRetryMessage: preserve ? message : null,
        );
        await _refreshProjections();
        return false;
      }
    } finally {
      _operationInProgress = false;
    }
  }

  void cancelAnalysis() {
    if (!state.isSending || state.isCancelling) return;
    _cancelRequested = true;
    state = state.copyWith(
      isCancelling: true,
      activityMessage: 'Cancelling analysis …',
    );
    _repository.cancelActiveResponse();
  }

  Future<void> deleteHistory() async {
    if (_operationInProgress ||
        state.isLoading ||
        state.isDeletingHistory ||
        state.isSending) {
      return;
    }
    _operationInProgress = true;
    try {
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
    } finally {
      _operationInProgress = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _repository.cancelActiveResponse();
    super.dispose();
  }
}

bool coachFailurePreservesRequestIdentity(Object error) {
  if (error is CoachRemoteException) return error.preservesRequestIdentity;
  if (error is CoachContractException ||
      error is CoachAccessException ||
      error is CoachInputException) {
    return true;
  }
  final dio = _dioExceptionFrom(error);
  return dio != null && dio.response == null;
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
