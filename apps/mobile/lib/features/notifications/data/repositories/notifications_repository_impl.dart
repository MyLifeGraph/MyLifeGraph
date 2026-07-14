import 'dart:async';

import '../../domain/entities/app_notification.dart';
import '../../domain/entities/notification_lifecycle.dart';
import '../../domain/repositories/notifications_repository.dart';
import '../datasources/notifications_api_data_source.dart';
import '../datasources/notifications_mock_data_source.dart';
import '../datasources/notifications_supabase_data_source.dart';

typedef NotificationsAccessTokenProvider = FutureOr<String?> Function();

class NotificationsRepositoryImpl implements NotificationsRepository {
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
}

class NotificationsLifecycleAccessException implements Exception {
  const NotificationsLifecycleAccessException(this.message);

  final String message;

  @override
  String toString() => 'NotificationsLifecycleAccessException: $message';
}
