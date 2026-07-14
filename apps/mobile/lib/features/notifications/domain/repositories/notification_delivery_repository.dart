import '../entities/app_notification.dart';
import '../entities/notification_delivery.dart';

abstract interface class NotificationDeliveryRepository {
  Future<NotificationSettings> getDeliverySettings();

  Future<NotificationSettings> updateDeliverySettings(
    NotificationSettingsUpdate request,
  );

  Future<List<AppNotification>> getPendingInAppNotifications({
    required NotificationCategories categories,
  });

  Future<NotificationDeliveryReceipt> acknowledgeInAppDelivery(
    AppNotification notification,
  );
}
