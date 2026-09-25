import '../entities/app_notification.dart';
import '../entities/notification_lifecycle.dart';

abstract interface class NotificationsRepository {
  Future<List<AppNotification>> getNotifications();

  Future<NotificationLifecycleResult> performLifecycleAction(
    NotificationLifecycleRequest request,
  );
}

abstract interface class NotificationHistoryRepository {
  Future<List<AppNotification>> getNotificationHistory({
    required bool dismissed,
    required int limit,
  });
}
