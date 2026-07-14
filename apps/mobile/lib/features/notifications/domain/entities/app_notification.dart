import 'notification_lifecycle.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.priority,
    required this.actionUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.isRead,
    required this.readAt,
    required this.dismissedAt,
    required this.dueAt,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final String priority;
  final String? actionUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isRead;
  final DateTime? readAt;
  final DateTime? dismissedAt;
  final DateTime? dueAt;

  AppNotification applyLifecycle(NotificationLifecycleResult result) {
    if (result.notificationId != id) {
      throw const NotificationLifecycleContractException(
        'Notification lifecycle result belongs to another row.',
      );
    }
    return AppNotification(
      id: id,
      title: title,
      body: body,
      type: type,
      priority: priority,
      actionUrl: actionUrl,
      createdAt: createdAt,
      updatedAt: result.updatedAt,
      isRead: result.isRead,
      readAt: result.readAt,
      dismissedAt: result.dismissedAt,
      dueAt: dueAt,
    );
  }
}
