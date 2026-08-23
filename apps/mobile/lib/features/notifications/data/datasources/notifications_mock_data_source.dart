import '../../domain/entities/app_notification.dart';

class NotificationsMockDataSource {
  const NotificationsMockDataSource();

  Future<List<AppNotification>> getNotifications() async {
    await Future<void>.delayed(const Duration(milliseconds: 180));

    final now = DateTime.now();
    return [
      AppNotification(
        id: 'focus_window',
        title: 'Example focus reminder',
        body: 'This is a sample notification for the local demo.',
        type: 'reminder',
        priority: 'high',
        actionUrl: null,
        createdAt: now.subtract(const Duration(minutes: 12)),
        updatedAt: now.subtract(const Duration(minutes: 12)),
        isRead: false,
        readAt: null,
        dismissedAt: null,
        dueAt: null,
      ),
      AppNotification(
        id: 'recovery_check',
        title: 'Recovery check-in',
        body: 'A short wind-down tonight may protect tomorrow morning.',
        type: 'reminder',
        priority: 'medium',
        actionUrl: '/daily-check-in',
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now.subtract(const Duration(hours: 2)),
        isRead: false,
        readAt: null,
        dismissedAt: null,
        dueAt: null,
      ),
      AppNotification(
        id: 'weekly_profile',
        title: 'Example weekly summary',
        body: 'This sample can open the demo insights view.',
        type: 'summary',
        priority: 'low',
        actionUrl: '/insights',
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(hours: 20)),
        isRead: true,
        readAt: now.subtract(const Duration(hours: 20)),
        dismissedAt: null,
        dueAt: null,
      ),
    ];
  }
}
