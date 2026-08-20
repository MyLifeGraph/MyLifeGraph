import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/utils/client_uuid.dart';
import '../domain/coach.dart';
import '../domain/coach_repository.dart';
import 'coach_turn_notice.dart';

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
    this.busyRetrySeconds = 0,
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
        busyRetrySeconds: 0,
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
  final int busyRetrySeconds;

  int get draftCodepoints => draft.trim().runes.length;
  bool get draftIsValid =>
      draftCodepoints > 0 && draftCodepoints <= coachMessageCodepoints;
  bool get isRateLimited =>
      capabilities?.state == CoachCapabilityState.ready &&
          capabilities?.limits.remainingRequests == 0 ||
      sendError is CoachRemoteException &&
          (sendError as CoachRemoteException).isRateLimited;
  bool get canRetryExact =>
      exactRetryMessage != null &&
      draft.trim() == exactRetryMessage &&
      draftIsValid &&
      busyRetrySeconds == 0;
  bool get canSend =>
      (canRetryExact || capabilities?.canRespond == true && !isRateLimited) &&
      draftIsValid &&
      !isLoading &&
      !isSending &&
      !isDeletingHistory &&
      busyRetrySeconds == 0;

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
    int? busyRetrySeconds,
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
        busyRetrySeconds: busyRetrySeconds ?? this.busyRetrySeconds,
      );
}

class CoachController extends StateNotifier<CoachState> {
  CoachController({
    required CoachRepository repository,
    String? profileId,
    CoachTurnNoticeController? turnNoticeController,
  })  : _repository = repository,
        _profileId = profileId,
        _turnNoticeController = turnNoticeController,
        super(CoachState.loading()) {
    Future<void>.microtask(load);
  }

  final CoachRepository _repository;
  final String? _profileId;
  final CoachTurnNoticeController? _turnNoticeController;
  bool _disposed = false;
  bool _cancelRequested = false;
  bool _operationInProgress = false;
  Timer? _busyRetryTimer;

  Future<void> load() async {
    if (_operationInProgress ||
        state.isSending ||
        state.isDeletingHistory ||
        state.busyRetrySeconds > 0) {
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
    final exactRetry = state.exactRetryMessage == message;
    if (!exactRetry && capability?.canRespond != true) {
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
      _markCurrentFailureRead();
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
          busyRetrySeconds: 0,
        );
        _publishNotice(
          requestId,
          status: CoachTurnNoticeStatus.completed,
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
        final busySeconds =
            error is CoachRemoteException && error.isTransientAdmission
                ? (error.retryAfterSeconds ?? error.fallbackRetryAfterSeconds)
                    .clamp(1, 60)
                : 0;
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
          busyRetrySeconds: busySeconds,
        );
        if (busySeconds > 0) _startBusyRetryCountdown(busySeconds);
        _publishNotice(
          requestId,
          status: CoachTurnNoticeStatus.failed,
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

  void _startBusyRetryCountdown(int seconds) {
    _busyRetryTimer?.cancel();
    var remaining = seconds;
    _busyRetryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      remaining -= 1;
      state = state.copyWith(
        busyRetrySeconds: remaining.clamp(0, 60),
      );
      if (remaining <= 0) timer.cancel();
    });
  }

  void _publishNotice(
    String requestId, {
    required CoachTurnNoticeStatus status,
  }) {
    final profileId = _profileId;
    if (profileId == null) return;
    _turnNoticeController?.publish(
      profileId: profileId,
      requestId: requestId,
      status: status,
    );
  }

  void _markCurrentFailureRead() {
    final profileId = _profileId;
    final notice = _turnNoticeController?.state;
    if (profileId == null ||
        notice == null ||
        notice.profileId != profileId ||
        notice.status != CoachTurnNoticeStatus.failed) {
      return;
    }
    _turnNoticeController?.markRead(
      profileId: profileId,
      requestId: notice.requestId,
      status: CoachTurnNoticeStatus.failed,
    );
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
    _busyRetryTimer?.cancel();
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
  final failure = apiFailureFrom(error);
  return failure != null && failure.statusCode == null;
}

String coachErrorMessage(Object? error) {
  if (error is CoachRemoteException) {
    if (error.isProviderBusy) {
      return 'Project Coach is busy. Retry manually when the countdown ends.';
    }
    if (error.code == 'route_busy') {
      return 'Coach service is busy. Retry manually when the countdown ends.';
    }
    if (error.code == 'route_rate_limited') {
      return 'Coach service is temporarily rate limited. '
          'Retry manually when the countdown ends.';
    }
    if (error.timedOut) {
      return 'Coach timed out. Retry the exact message.';
    }
    return error.message;
  }
  if (error is CoachAccessException) return error.message;
  if (error is CoachInputException) return error.message;
  if (error is CoachContractException) {
    return 'Coach returned an invalid response. Retry the exact message.';
  }
  if (apiFailureFrom(error)?.isTimeout ?? false) {
    return 'Coach timed out. Retry the exact message.';
  }
  if (apiFailureFrom(error) != null) {
    return 'Coach could not be reached. Retry the exact message.';
  }
  return 'Coach could not complete this operation. Try again.';
}

const Object _unset = Object();
