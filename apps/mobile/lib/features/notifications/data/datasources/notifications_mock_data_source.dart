import '../../domain/entities/app_notification.dart';

class NotificationsMockDataSource {
  const NotificationsMockDataSource();

  Future<List<AppNotification>> getNotifications() async {
    await Future<void>.delayed(const Duration(milliseconds: 180));

    final now = DateTime.now();
    return [
      AppNotification(
        id: 'focus_window',
        title: 'Focus window approaching',
        body: 'Your best deep-work window starts in 20 minutes.',
        createdAt: now.subtract(const Duration(minutes: 12)),
        isRead: false,
      ),
      AppNotification(
        id: 'recovery_check',
        title: 'Recovery check-in',
        body: 'A short wind-down tonight may protect tomorrow morning.',
        createdAt: now.subtract(const Duration(hours: 2)),
        isRead: false,
      ),
      AppNotification(
        id: 'weekly_profile',
        title: 'Skillset profile updated',
        body: 'Your planning score improved again this week.',
        createdAt: now.subtract(const Duration(days: 1)),
        isRead: true,
      ),
    ];
  }
}
