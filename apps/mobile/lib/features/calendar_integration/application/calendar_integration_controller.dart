import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/client_uuid.dart';
import '../domain/calendar_integration.dart';
import '../domain/calendar_integration_repository.dart';
import 'calendar_ics_file_picker.dart';

enum CalendarIntegrationOperation {
  idle,
  selectingFile,
  creating,
  importing,
  loadingMore,
  disconnecting,
  deleting,
}

enum CalendarIntegrationRetryKind { create, import, disconnect, delete }

class CalendarIntegrationState {
  const CalendarIntegrationState({
    required this.isLoading,
    required this.feed,
    required this.events,
    required this.eventImportId,
    required this.nextCursor,
    required this.loadError,
    required this.eventError,
    required this.operation,
    required this.operationError,
    required this.retryKind,
    required this.sourceLabel,
    required this.consentAccepted,
    required this.selectedFile,
    required this.createRequestId,
    required this.importRequestId,
    required this.disconnectRequestId,
    required this.deleteRequestId,
  });

  factory CalendarIntegrationState.loading() => CalendarIntegrationState(
        isLoading: true,
        feed: null,
        events: const [],
        eventImportId: null,
        nextCursor: null,
        loadError: null,
        eventError: null,
        operation: CalendarIntegrationOperation.idle,
        operationError: null,
        retryKind: null,
        sourceLabel: '',
        consentAccepted: false,
        selectedFile: null,
        createRequestId: newClientUuid(),
        importRequestId: null,
        disconnectRequestId: null,
        deleteRequestId: null,
      );

  final bool isLoading;
  final CalendarIntegrationFeed? feed;
  final List<CalendarImportedEvent> events;
  final String? eventImportId;
  final String? nextCursor;
  final Object? loadError;
  final Object? eventError;
  final CalendarIntegrationOperation operation;
  final Object? operationError;
  final CalendarIntegrationRetryKind? retryKind;
  final String sourceLabel;
  final bool consentAccepted;
  final SelectedCalendarIcsFile? selectedFile;
  final String createRequestId;
  final String? importRequestId;
  final String? disconnectRequestId;
  final String? deleteRequestId;

  bool get isBusy => operation != CalendarIntegrationOperation.idle;
  bool get operationRequiresExactRetry => retryKind != null;

  CalendarIntegrationState copyWith({
    bool? isLoading,
    Object? feed = _unset,
    List<CalendarImportedEvent>? events,
    Object? eventImportId = _unset,
    Object? nextCursor = _unset,
    Object? loadError = _unset,
    Object? eventError = _unset,
    CalendarIntegrationOperation? operation,
    Object? operationError = _unset,
    Object? retryKind = _unset,
    String? sourceLabel,
    bool? consentAccepted,
    Object? selectedFile = _unset,
    String? createRequestId,
    Object? importRequestId = _unset,
    Object? disconnectRequestId = _unset,
    Object? deleteRequestId = _unset,
  }) {
    return CalendarIntegrationState(
      isLoading: isLoading ?? this.isLoading,
      feed: identical(feed, _unset)
          ? this.feed
          : feed as CalendarIntegrationFeed?,
      events: events ?? this.events,
      eventImportId: identical(eventImportId, _unset)
          ? this.eventImportId
          : eventImportId as String?,
      nextCursor: identical(nextCursor, _unset)
          ? this.nextCursor
          : nextCursor as String?,
      loadError: identical(loadError, _unset) ? this.loadError : loadError,
      eventError: identical(eventError, _unset) ? this.eventError : eventError,
      operation: operation ?? this.operation,
      operationError: identical(operationError, _unset)
          ? this.operationError
          : operationError,
      retryKind: identical(retryKind, _unset)
          ? this.retryKind
          : retryKind as CalendarIntegrationRetryKind?,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      consentAccepted: consentAccepted ?? this.consentAccepted,
      selectedFile: identical(selectedFile, _unset)
          ? this.selectedFile
          : selectedFile as SelectedCalendarIcsFile?,
      createRequestId: createRequestId ?? this.createRequestId,
      importRequestId: identical(importRequestId, _unset)
          ? this.importRequestId
          : importRequestId as String?,
      disconnectRequestId: identical(disconnectRequestId, _unset)
          ? this.disconnectRequestId
          : disconnectRequestId as String?,
      deleteRequestId: identical(deleteRequestId, _unset)
          ? this.deleteRequestId
          : deleteRequestId as String?,
    );
  }
}

class CalendarIntegrationController
    extends StateNotifier<CalendarIntegrationState> {
  CalendarIntegrationController({
    required CalendarIntegrationRepository repository,
    required CalendarIcsFilePicker filePicker,
  })  : _repository = repository,
        _filePicker = filePicker,
        super(CalendarIntegrationState.loading()) {
    Future<void>.microtask(load);
  }

  final CalendarIntegrationRepository _repository;
  final CalendarIcsFilePicker _filePicker;

  Future<void> load() async {
    if (state.isBusy) return;
    state = CalendarIntegrationState.loading();
    try {
      final feed = await _repository.getIntegration();
      state = state.copyWith(
        isLoading: false,
        feed: feed,
        sourceLabel: feed.connection?.sourceLabel ?? '',
        loadError: null,
      );
      await _loadFirstEventPage(feed.connection);
    } catch (error) {
      state = state.copyWith(isLoading: false, loadError: error);
    }
  }

  void updateSourceLabel(String value) {
    if (state.isBusy || state.operationRequiresExactRetry) return;
    state = state.copyWith(
      sourceLabel: value,
      createRequestId: newClientUuid(),
      operationError: null,
    );
  }

  void setConsentAccepted(bool value) {
    if (state.isBusy || state.operationRequiresExactRetry) return;
    state = state.copyWith(
      consentAccepted: value,
      createRequestId: newClientUuid(),
      operationError: null,
    );
  }

  Future<void> createConnection() async {
    final connection = state.feed?.connection;
    if (state.isBusy ||
        connection != null && !connection.importedDataDeleted ||
        !state.consentAccepted ||
        state.sourceLabel.trim().isEmpty) {
      return;
    }
    state = state.copyWith(
      operation: CalendarIntegrationOperation.creating,
      operationError: null,
    );
    try {
      final feed = await _repository.createConnection(
        requestId: state.createRequestId,
        sourceLabel: state.sourceLabel.trim(),
      );
      state = state.copyWith(
        feed: feed,
        operation: CalendarIntegrationOperation.idle,
        retryKind: null,
        operationError: null,
        consentAccepted: false,
        createRequestId: newClientUuid(),
        events: const [],
        eventImportId: null,
        nextCursor: null,
      );
    } catch (error) {
      _recordOperationFailure(error, CalendarIntegrationRetryKind.create);
    }
  }

  Future<void> selectFile() async {
    if (state.isBusy || state.operationRequiresExactRetry) return;
    state = state.copyWith(
      operation: CalendarIntegrationOperation.selectingFile,
      operationError: null,
    );
    try {
      final file = await _filePicker.pickFile();
      state = state.copyWith(
        operation: CalendarIntegrationOperation.idle,
        selectedFile: file ?? state.selectedFile,
        importRequestId: file == null ? state.importRequestId : newClientUuid(),
      );
    } catch (error) {
      state = state.copyWith(
        operation: CalendarIntegrationOperation.idle,
        operationError: error,
        retryKind: null,
      );
    }
  }

  void clearSelectedFile() {
    if (state.isBusy || state.operationRequiresExactRetry) return;
    state = state.copyWith(
      selectedFile: null,
      importRequestId: null,
      operationError: null,
    );
  }

  Future<void> importSelectedFile() async {
    final connection = state.feed?.connection;
    final file = state.selectedFile;
    final requestId = state.importRequestId;
    if (state.isBusy ||
        state.retryKind != null &&
            state.retryKind != CalendarIntegrationRetryKind.import ||
        connection?.isConnected != true ||
        file == null ||
        requestId == null) {
      return;
    }
    state = state.copyWith(
      operation: CalendarIntegrationOperation.importing,
      operationError: null,
    );
    try {
      final result = await _repository.importCalendar(
        connectionId: connection!.id,
        requestId: requestId,
        calendarText: file.calendarText,
      );
      final feed = CalendarIntegrationFeed.authenticated(result.connection);
      state = state.copyWith(
        feed: feed,
        operation: CalendarIntegrationOperation.idle,
        operationError: null,
        retryKind: null,
        selectedFile: null,
        importRequestId: null,
        events: const [],
        eventImportId: null,
        nextCursor: null,
        eventError: null,
      );
      await _loadFirstEventPage(result.connection);
    } catch (error) {
      _recordOperationFailure(error, CalendarIntegrationRetryKind.import);
    }
  }

  Future<void> loadMoreEvents() async {
    final connection = state.feed?.connection;
    final cursor = state.nextCursor;
    if (state.isBusy || connection == null || cursor == null) return;
    state = state.copyWith(
      operation: CalendarIntegrationOperation.loadingMore,
      eventError: null,
    );
    try {
      final page = await _repository.getEvents(
        connectionId: connection.id,
        cursor: cursor,
      );
      if (page.importId != state.eventImportId) {
        throw const CalendarIntegrationContractException(
          'Calendar event page changed during pagination. Reload the source.',
        );
      }
      final ids = state.events.map((event) => event.id).toSet();
      if (page.events.any((event) => ids.contains(event.id))) {
        throw const CalendarIntegrationContractException(
          'Calendar event pagination returned duplicate events.',
        );
      }
      state = state.copyWith(
        events: [...state.events, ...page.events],
        nextCursor: page.nextCursor,
        operation: CalendarIntegrationOperation.idle,
      );
    } catch (error) {
      state = state.copyWith(
        operation: CalendarIntegrationOperation.idle,
        eventError: error,
      );
    }
  }

  Future<void> disconnect() async {
    final connection = state.feed?.connection;
    if (state.isBusy ||
        state.retryKind != null &&
            state.retryKind != CalendarIntegrationRetryKind.disconnect ||
        connection?.isConnected != true) {
      return;
    }
    final requestId = state.disconnectRequestId ?? newClientUuid();
    state = state.copyWith(
      operation: CalendarIntegrationOperation.disconnecting,
      disconnectRequestId: requestId,
      operationError: null,
    );
    try {
      final feed = await _repository.disconnect(
        connectionId: connection!.id,
        requestId: requestId,
      );
      state = state.copyWith(
        feed: feed,
        operation: CalendarIntegrationOperation.idle,
        operationError: null,
        retryKind: null,
        disconnectRequestId: null,
        selectedFile: null,
        importRequestId: null,
      );
    } catch (error) {
      _recordOperationFailure(error, CalendarIntegrationRetryKind.disconnect);
    }
  }

  Future<void> deleteImportedData() async {
    final connection = state.feed?.connection;
    if (state.isBusy ||
        state.retryKind != null &&
            state.retryKind != CalendarIntegrationRetryKind.delete ||
        connection?.status != CalendarConnectionStatus.disconnected) {
      return;
    }
    final requestId = state.deleteRequestId ?? newClientUuid();
    state = state.copyWith(
      operation: CalendarIntegrationOperation.deleting,
      deleteRequestId: requestId,
      operationError: null,
    );
    try {
      final feed = await _repository.deleteImportedData(
        connectionId: connection!.id,
        requestId: requestId,
      );
      state = state.copyWith(
        feed: feed,
        operation: CalendarIntegrationOperation.idle,
        operationError: null,
        retryKind: null,
        deleteRequestId: null,
        sourceLabel: '',
        consentAccepted: false,
        createRequestId: newClientUuid(),
        events: const [],
        eventImportId: null,
        nextCursor: null,
        eventError: null,
      );
    } catch (error) {
      _recordOperationFailure(error, CalendarIntegrationRetryKind.delete);
    }
  }

  Future<void> _loadFirstEventPage(CalendarConnection? connection) async {
    if (connection?.lastImport == null) {
      state = state.copyWith(
        events: const [],
        eventImportId: null,
        nextCursor: null,
        eventError: null,
      );
      return;
    }
    try {
      final page = await _repository.getEvents(connectionId: connection!.id);
      if (page.importId != connection.lastImport!.id) {
        throw const CalendarIntegrationContractException(
          'Calendar events do not match the latest import.',
        );
      }
      state = state.copyWith(
        events: page.events,
        eventImportId: page.importId,
        nextCursor: page.nextCursor,
        eventError: null,
      );
    } catch (error) {
      state = state.copyWith(
        events: const [],
        eventImportId: null,
        nextCursor: null,
        eventError: error,
      );
    }
  }

  void _recordOperationFailure(
    Object error,
    CalendarIntegrationRetryKind retryKind,
  ) {
    final requiresExactRetry = calendarOperationRequiresExactRetry(error);
    state = state.copyWith(
      operation: CalendarIntegrationOperation.idle,
      operationError: error,
      retryKind: requiresExactRetry ? retryKind : null,
    );
  }
}

bool calendarOperationRequiresExactRetry(Object error) {
  final statusCode = _dioExceptionFrom(error)?.response?.statusCode;
  return statusCode == null || statusCode < 400 || statusCode >= 500;
}

DioException? _dioExceptionFrom(Object error) {
  if (error is DioException) return error;
  final cause = error is AppException ? error.cause : null;
  return cause is DioException ? cause : null;
}

const Object _unset = Object();
