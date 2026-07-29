import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/client_uuid.dart';
import '../data/repositories/notifications_repository_impl.dart';
import '../domain/entities/app_notification.dart';
import '../domain/entities/notification_lifecycle.dart';
import '../domain/repositories/notifications_repository.dart';

class NotificationRowActionState {
  const NotificationRowActionState({
    required this.isPending,
    required this.command,
    required this.error,
    required this.exactRetryRequest,
    this.committedRequiresReload = false,
    this.committedResult,
  });

  final bool isPending;
  final NotificationLifecycleCommand command;
  final Object? error;
  final NotificationLifecycleRequest? exactRetryRequest;
  final bool committedRequiresReload;
  final NotificationLifecycleResult? committedResult;

  bool get requiresExactRetry => exactRetryRequest != null;
  bool get requiresReload =>
      committedRequiresReload ||
      error != null && notificationLifecycleFailureRequiresReload(error!);
}

class NotificationsState {
  const NotificationsState({
    required this.isLoading,
    required this.items,
    required this.loadError,
    required this.rowActions,
    required this.canManageLifecycle,
  });

  factory NotificationsState.initial({required bool canManageLifecycle}) {
    return NotificationsState(
      isLoading: true,
      items: const [],
      loadError: null,
      rowActions: const {},
      canManageLifecycle: canManageLifecycle,
    );
  }

  final bool isLoading;
  final List<AppNotification> items;
  final Object? loadError;
  final Map<String, NotificationRowActionState> rowActions;
  final bool canManageLifecycle;

  bool get hasPendingAction =>
      rowActions.values.any((operation) => operation.isPending);

  NotificationRowActionState? actionFor(String notificationId) {
    return rowActions[notificationId];
  }

  NotificationsState copyWith({
    bool? isLoading,
    List<AppNotification>? items,
    Object? loadError = _unset,
    Map<String, NotificationRowActionState>? rowActions,
    bool? canManageLifecycle,
  }) {
    return NotificationsState(
      isLoading: isLoading ?? this.isLoading,
      items: items ?? this.items,
      loadError: identical(loadError, _unset) ? this.loadError : loadError,
      rowActions: rowActions ?? this.rowActions,
      canManageLifecycle: canManageLifecycle ?? this.canManageLifecycle,
    );
  }
}

class NotificationsController extends StateNotifier<NotificationsState> {
  NotificationsController({
    required NotificationsRepository repository,
    required bool canManageLifecycle,
    bool autoLoad = true,
  })  : _repository = repository,
        super(
          NotificationsState.initial(
            canManageLifecycle: canManageLifecycle,
          ),
        ) {
    if (autoLoad) Future<void>.microtask(load);
  }

  final NotificationsRepository _repository;
  bool _disposed = false;

  Future<void> load() async {
    if (state.hasPendingAction) return;
    await _reloadInbox(clearRowActionsOnSuccess: true);
  }

  Future<bool> _reloadInbox({required bool clearRowActionsOnSuccess}) async {
    state = state.copyWith(isLoading: true, loadError: null);
    try {
      final items = await _repository.getNotifications();
      if (_disposed) return false;
      if (clearRowActionsOnSuccess &&
          !_matchesCommittedResults(items, state.rowActions)) {
        throw const NotificationLifecycleContractException(
          'Inbox reload did not include the committed notification change.',
        );
      }
      state = state.copyWith(
        isLoading: false,
        items: List.unmodifiable(items),
        loadError: null,
        rowActions: clearRowActionsOnSuccess ? const {} : state.rowActions,
      );
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(isLoading: false, loadError: error);
      return false;
    }
  }

  Future<bool> markRead(String notificationId) {
    return performAction(notificationId, NotificationLifecycleCommand.markRead);
  }

  Future<bool> markUnread(String notificationId) {
    return performAction(
      notificationId,
      NotificationLifecycleCommand.markUnread,
    );
  }

  Future<bool> dismiss(String notificationId) {
    return performAction(notificationId, NotificationLifecycleCommand.dismiss);
  }

  Future<bool> retry(String notificationId) async {
    final operation = state.actionFor(notificationId);
    if (operation?.committedRequiresReload == true) {
      return _reloadInbox(clearRowActionsOnSuccess: true);
    }
    if (operation == null ||
        operation.isPending ||
        operation.error == null ||
        operation.exactRetryRequest == null) {
      return false;
    }
    return performAction(notificationId, operation.command);
  }

  Future<bool> performAction(
    String notificationId,
    NotificationLifecycleCommand command,
  ) async {
    if (!state.canManageLifecycle) return false;
    final index = state.items.indexWhere((item) => item.id == notificationId);
    if (index < 0) return false;
    final existingOperation = state.actionFor(notificationId);
    if (existingOperation?.isPending == true) return false;
    if (existingOperation?.committedRequiresReload == true) return false;
    final exactRequest = existingOperation?.exactRetryRequest;
    if (existingOperation?.error != null && exactRequest == null) return false;
    if (exactRequest != null && exactRequest.command != command) return false;

    final notification = state.items[index];
    final request = exactRequest ??
        NotificationLifecycleRequest(
          notificationId: notification.id,
          requestId: newClientUuid(),
          command: command,
          expectedUpdatedAt: notification.updatedAt,
        );
    _setRowAction(
      notificationId,
      NotificationRowActionState(
        isPending: true,
        command: command,
        error: null,
        exactRetryRequest: exactRequest,
      ),
    );
    try {
      final result = await _repository.performLifecycleAction(request);
      result.requireMatches(request);
      if (_disposed) return false;
      if (!result.replayed) {
        final currentIndex =
            state.items.indexWhere((item) => item.id == notificationId);
        if (currentIndex < 0) return false;
        final current = state.items[currentIndex];
        if (current.updatedAt != request.expectedUpdatedAt) {
          throw const NotificationLifecycleContractException(
            'Notification changed while its action was pending.',
          );
        }
        final updated = current.applyLifecycle(result);
        final items = [...state.items];
        if (command == NotificationLifecycleCommand.dismiss) {
          // Keep the durable row visible but locked until the Inbox confirms
          // the current projection. Removing it now would hide a failed
          // reload and invite a second mutation from stale state.
        } else {
          items[currentIndex] = updated;
        }
        state = state.copyWith(items: List.unmodifiable(items));
      }
      _setRowAction(
        notificationId,
        NotificationRowActionState(
          isPending: false,
          command: command,
          error: null,
          exactRetryRequest: null,
          committedRequiresReload: true,
          committedResult: result,
        ),
      );
      return _reloadInbox(clearRowActionsOnSuccess: true);
    } catch (error) {
      if (_disposed) return false;
      final requiresExactRetry =
          notificationLifecycleFailureRequiresExactRetry(error);
      _setRowAction(
        notificationId,
        NotificationRowActionState(
          isPending: false,
          command: command,
          error: error,
          exactRetryRequest: requiresExactRetry ? request : null,
        ),
      );
      return false;
    }
  }

  bool _matchesCommittedResults(
    List<AppNotification> items,
    Map<String, NotificationRowActionState> actions,
  ) {
    for (final entry in actions.entries) {
      final result = entry.value.committedResult;
      if (!entry.value.committedRequiresReload || result == null) continue;
      final matching = items.where((item) => item.id == entry.key).toList();
      if (result.command == NotificationLifecycleCommand.dismiss) {
        if (matching.isNotEmpty) return false;
        continue;
      }
      if (matching.length != 1) return false;
      final item = matching.single;
      if (item.updatedAt.isBefore(result.updatedAt)) return false;
      if (!result.replayed &&
          (item.isRead != result.isRead || item.readAt != result.readAt)) {
        return false;
      }
    }
    return true;
  }

  void _setRowAction(
    String notificationId,
    NotificationRowActionState operation,
  ) {
    final actions = {...state.rowActions, notificationId: operation};
    state = state.copyWith(rowActions: Map.unmodifiable(actions));
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

bool notificationLifecycleFailureRequiresExactRetry(Object error) {
  if (error is NotificationsLifecycleAccessException) return false;
  final dioError = _dioExceptionFrom(error);
  if (dioError == null) return true;
  final statusCode = dioError.response?.statusCode;
  return statusCode == null || statusCode < 400 || statusCode >= 500;
}

bool notificationLifecycleFailureRequiresReload(Object error) {
  final statusCode = _dioExceptionFrom(error)?.response?.statusCode;
  return statusCode != null && statusCode >= 400 && statusCode < 500;
}

DioException? _dioExceptionFrom(Object error) {
  if (error is DioException) return error;
  final cause = error is AppException ? error.cause : null;
  return cause is DioException ? cause : null;
}

const Object _unset = Object();
