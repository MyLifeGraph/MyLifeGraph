import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/client_uuid.dart';
import '../domain/entities/app_notification.dart';
import '../domain/entities/notification_delivery.dart';
import '../domain/repositories/notification_delivery_repository.dart';
import 'notifications_controller.dart';

class NotificationSettingsState {
  const NotificationSettingsState({
    required this.isLoading,
    required this.isSaving,
    required this.settings,
    required this.error,
    required this.exactRetryRequest,
    required this.reloadRequired,
  });

  const NotificationSettingsState.initial()
      : isLoading = true,
        isSaving = false,
        settings = null,
        error = null,
        exactRetryRequest = null,
        reloadRequired = false;

  final bool isLoading;
  final bool isSaving;
  final NotificationSettings? settings;
  final Object? error;
  final NotificationSettingsUpdate? exactRetryRequest;
  final bool reloadRequired;

  bool get requiresExactRetry => exactRetryRequest != null;
  bool get requiresReload => reloadRequired;
}

class NotificationSettingsController
    extends StateNotifier<NotificationSettingsState> {
  NotificationSettingsController({
    required NotificationDeliveryRepository repository,
    bool autoLoad = true,
  })  : _repository = repository,
        super(const NotificationSettingsState.initial()) {
    if (autoLoad) Future<void>.microtask(load);
  }

  final NotificationDeliveryRepository _repository;
  bool _disposed = false;

  Future<void> load() async {
    if (state.isSaving) return;
    state = NotificationSettingsState(
      isLoading: true,
      isSaving: false,
      settings: state.settings,
      error: null,
      exactRetryRequest: null,
      reloadRequired: state.reloadRequired || state.requiresExactRetry,
    );
    try {
      final settings = await _repository.getDeliverySettings();
      if (_disposed) return;
      state = NotificationSettingsState(
        isLoading: false,
        isSaving: false,
        settings: settings,
        error: null,
        exactRetryRequest: null,
        reloadRequired: false,
      );
    } catch (error) {
      if (_disposed) return;
      state = NotificationSettingsState(
        isLoading: false,
        isSaving: false,
        settings: state.settings,
        error: error,
        exactRetryRequest: null,
        reloadRequired: state.reloadRequired,
      );
    }
  }

  Future<bool> save({
    required bool inAppDeliveryEnabled,
    required NotificationCategories categories,
    required NotificationQuietHours? quietHours,
    required int dailyLimit,
  }) async {
    final settings = state.settings;
    if (settings == null ||
        state.isSaving ||
        state.isLoading ||
        state.requiresExactRetry ||
        state.requiresReload) {
      return false;
    }
    return _saveExact(
      NotificationSettingsUpdate(
        requestId: newClientUuid(),
        expectedUpdatedAt: settings.updatedAt,
        inAppDeliveryEnabled: inAppDeliveryEnabled,
        categories: categories,
        quietHours: quietHours,
        dailyLimit: dailyLimit,
      ),
    );
  }

  Future<bool> retryExact() async {
    final request = state.exactRetryRequest;
    if (request == null || state.isSaving) return false;
    return _saveExact(request);
  }

  Future<bool> _saveExact(NotificationSettingsUpdate request) async {
    state = NotificationSettingsState(
      isLoading: false,
      isSaving: true,
      settings: state.settings,
      error: null,
      exactRetryRequest: state.exactRetryRequest,
      reloadRequired: state.reloadRequired,
    );
    try {
      final settings = await _repository.updateDeliverySettings(request);
      if (_disposed) return false;
      state = NotificationSettingsState(
        isLoading: false,
        isSaving: false,
        settings: settings,
        error: null,
        exactRetryRequest: null,
        reloadRequired: false,
      );
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = NotificationSettingsState(
        isLoading: false,
        isSaving: false,
        settings: state.settings,
        error: error,
        exactRetryRequest: notificationLifecycleFailureRequiresExactRetry(error)
            ? request
            : null,
        reloadRequired: notificationLifecycleFailureRequiresReload(error),
      );
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class InAppNotificationDeliveryState {
  const InAppNotificationDeliveryState({
    required this.sequence,
    required this.notification,
    required this.isPolling,
    required this.lastError,
  });

  const InAppNotificationDeliveryState.initial()
      : sequence = 0,
        notification = null,
        isPolling = false,
        lastError = null;

  final int sequence;
  final AppNotification? notification;
  final bool isPolling;
  final Object? lastError;
}

class InAppNotificationDeliveryController
    extends StateNotifier<InAppNotificationDeliveryState> {
  InAppNotificationDeliveryController({
    required NotificationDeliveryRepository repository,
    required bool enabled,
    Duration interval = const Duration(seconds: 15),
    bool autoStart = true,
  })  : _repository = repository,
        _enabled = enabled,
        super(const InAppNotificationDeliveryState.initial()) {
    if (enabled && autoStart) {
      Future<void>.microtask(poll);
      _timer = Timer.periodic(interval, (_) => poll());
    }
  }

  final NotificationDeliveryRepository _repository;
  final bool _enabled;
  Timer? _timer;
  bool _disposed = false;

  Future<void> poll() async {
    if (!_enabled || state.isPolling || _disposed) return;
    state = InAppNotificationDeliveryState(
      sequence: state.sequence,
      notification: state.notification,
      isPolling: true,
      lastError: null,
    );
    try {
      final settings = await _repository.getDeliverySettings();
      if (!settings.inAppDeliveryEnabled) {
        if (!_disposed) _finish();
        return;
      }
      final pending = await _repository.getPendingInAppNotifications(
        categories: settings.categories,
      );
      if (pending.isEmpty) {
        if (!_disposed) _finish();
        return;
      }
      AppNotification? notification;
      for (final candidate in pending) {
        if (settings.categories.allows(candidate.generationCategory)) {
          notification = candidate;
          break;
        }
      }
      if (notification == null) {
        if (!_disposed) _finish();
        return;
      }
      final receipt = await _repository.acknowledgeInAppDelivery(notification);
      if (_disposed) return;
      if (receipt.replayed) {
        _finish();
        return;
      }
      state = InAppNotificationDeliveryState(
        sequence: state.sequence + 1,
        notification: notification,
        isPolling: false,
        lastError: null,
      );
    } catch (error) {
      if (_disposed) return;
      state = InAppNotificationDeliveryState(
        sequence: state.sequence,
        notification: state.notification,
        isPolling: false,
        lastError: error,
      );
    }
  }

  void _finish() {
    state = InAppNotificationDeliveryState(
      sequence: state.sequence,
      notification: state.notification,
      isPolling: false,
      lastError: null,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
