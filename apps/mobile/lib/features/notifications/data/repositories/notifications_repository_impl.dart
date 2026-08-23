import 'dart:async';

import '../../domain/entities/app_notification.dart';
import '../../domain/entities/notification_delivery.dart';
import '../../domain/entities/notification_lifecycle.dart';
import '../../domain/repositories/notification_delivery_repository.dart';
import '../../domain/repositories/notifications_repository.dart';
import '../datasources/notifications_api_data_source.dart';
import '../datasources/notifications_mock_data_source.dart';
import '../datasources/notifications_supabase_data_source.dart';

typedef NotificationsAccessTokenProvider = FutureOr<String?> Function();

class NotificationsRepositoryImpl
    implements NotificationsRepository, NotificationDeliveryRepository {
  const NotificationsRepositoryImpl({
    required NotificationsMockDataSource mockDataSource,
    NotificationsSupabaseDataSource? supabaseDataSource,
    NotificationsApiDataSource? apiDataSource,
    NotificationsAccessTokenProvider? accessTokenProvider,
    required bool allowMockData,
  })  : _mockDataSource = mockDataSource,
        _supabaseDataSource = supabaseDataSource,
        _apiDataSource = apiDataSource,
        _accessTokenProvider = accessTokenProvider,
        _allowMockData = allowMockData;

  final NotificationsMockDataSource _mockDataSource;
  final NotificationsSupabaseDataSource? _supabaseDataSource;
  final NotificationsApiDataSource? _apiDataSource;
  final NotificationsAccessTokenProvider? _accessTokenProvider;
  final bool _allowMockData;

  @override
  Future<List<AppNotification>> getNotifications() async {
    if (_allowMockData) {
      return _mockDataSource.getNotifications();
    }

    final supabaseDataSource = _supabaseDataSource;
    if (supabaseDataSource == null) {
      throw StateError(
        'Authenticated notifications require a Supabase data source.',
      );
    }

    return supabaseDataSource.getNotifications();
  }

  @override
  Future<NotificationLifecycleResult> performLifecycleAction(
    NotificationLifecycleRequest request,
  ) async {
    if (_allowMockData) {
      throw const NotificationsLifecycleAccessException(
        'Inbox actions are unavailable for local demo items.',
      );
    }
    final apiDataSource = _apiDataSource;
    final tokenProvider = _accessTokenProvider;
    if (apiDataSource == null || tokenProvider == null) {
      throw const NotificationsLifecycleAccessException(
        'Inbox actions require the authenticated API service.',
      );
    }
    final token = await tokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw const NotificationsLifecycleAccessException(
        'Inbox actions require an authenticated session.',
      );
    }
    final result = await apiDataSource.performAction(
      accessToken: token.trim(),
      request: request,
    );
    result.requireMatches(request);
    return result;
  }

  @override
  Future<NotificationSettings> getDeliverySettings() async {
    final access = await _authenticatedDeliveryAccess();
    return access.api.getSettings(accessToken: access.token);
  }

  @override
  Future<NotificationSettings> updateDeliverySettings(
    NotificationSettingsUpdate request,
  ) async {
    final access = await _authenticatedDeliveryAccess();
    final result = await access.api.updateSettings(
      accessToken: access.token,
      request: request,
    );
    _requireSettingsMatch(result, request);
    return result;
  }

  @override
  Future<List<AppNotification>> getPendingInAppNotifications({
    required NotificationCategories categories,
  }) async {
    if (_allowMockData) {
      throw const NotificationsDeliveryAccessException(
        'In-app delivery is unavailable for local demo items.',
      );
    }
    final source = _supabaseDataSource;
    if (source == null) {
      throw const NotificationsDeliveryAccessException(
        'In-app delivery requires the authenticated data source.',
      );
    }
    final enabledCategories = categories.enabledCategoryCodes;
    if (enabledCategories.isEmpty) return const [];
    return source.getPendingInAppNotifications(
      enabledCategories: enabledCategories,
    );
  }

  @override
  Future<NotificationDeliveryReceipt> acknowledgeInAppDelivery(
    AppNotification notification,
  ) async {
    final access = await _authenticatedDeliveryAccess();
    return access.api.acknowledgeDelivery(
      accessToken: access.token,
      notification: notification,
    );
  }

  Future<_NotificationDeliveryAccess> _authenticatedDeliveryAccess() async {
    if (_allowMockData) {
      throw const NotificationsDeliveryAccessException(
        'In-app delivery is unavailable for local demo items.',
      );
    }
    final api = _apiDataSource;
    final tokenProvider = _accessTokenProvider;
    if (api == null || tokenProvider == null) {
      throw const NotificationsDeliveryAccessException(
        'In-app delivery requires the authenticated API service.',
      );
    }
    final token = await tokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw const NotificationsDeliveryAccessException(
        'In-app delivery requires an authenticated session.',
      );
    }
    return _NotificationDeliveryAccess(api: api, token: token.trim());
  }
}

class NotificationsLifecycleAccessException implements Exception {
  const NotificationsLifecycleAccessException(this.message);

  final String message;

  @override
  String toString() => 'NotificationsLifecycleAccessException: $message';
}

class NotificationsDeliveryAccessException implements Exception {
  const NotificationsDeliveryAccessException(this.message);

  final String message;

  @override
  String toString() => 'NotificationsDeliveryAccessException: $message';
}

class _NotificationDeliveryAccess {
  const _NotificationDeliveryAccess({required this.api, required this.token});

  final NotificationsApiDataSource api;
  final String token;
}

void _requireSettingsMatch(
  NotificationSettings result,
  NotificationSettingsUpdate request,
) {
  final quiet = result.quietHours;
  final expectedQuiet = request.quietHours;
  if (result.updatedAt.isBefore(request.expectedUpdatedAt) ||
      result.inAppDeliveryEnabled != request.inAppDeliveryEnabled ||
      result.categories.focusPrompt != request.categories.focusPrompt ||
      result.categories.recoveryPrompt != request.categories.recoveryPrompt ||
      result.categories.weeklySummary != request.categories.weeklySummary ||
      result.dailyLimit != request.dailyLimit ||
      (quiet == null) != (expectedQuiet == null) ||
      (quiet != null &&
          (quiet.startsAt != expectedQuiet!.startsAt ||
              quiet.endsAt != expectedQuiet.endsAt))) {
    throw const NotificationLifecycleContractException(
      'Notification settings response does not match its request.',
    );
  }
}
