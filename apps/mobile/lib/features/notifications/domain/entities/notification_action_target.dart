enum NotificationActionTarget {
  dashboard('/dashboard'),
  insights('/insights'),
  quickAction('/quick-action'),
  dailyCheckIn('/quick-mood-check-in'),
  habitCompletion('/habit-completion'),
  habitManagement('/habits'),
  weeklyReview('/weekly-review'),
  focusSession('/deep-work');

  const NotificationActionTarget(this.location);

  final String location;
}

class NotificationActionTargetResolver {
  const NotificationActionTargetResolver({
    required this.canUseSyncedHabits,
    this.canUseFocusSessions = false,
    this.canUseWeeklyReview = false,
  });

  final bool canUseSyncedHabits;
  final bool canUseFocusSessions;
  final bool canUseWeeklyReview;

  NotificationActionTarget? resolve(String? actionUrl) {
    if (actionUrl == null ||
        actionUrl.isEmpty ||
        actionUrl != actionUrl.trim() ||
        !actionUrl.startsWith('/')) {
      return null;
    }

    final uri = Uri.tryParse(actionUrl);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path != actionUrl) {
      return null;
    }

    return switch (uri.path) {
      '/dashboard' => NotificationActionTarget.dashboard,
      '/insights' => NotificationActionTarget.insights,
      '/quick-action' => NotificationActionTarget.quickAction,
      '/quick-mood-check-in' ||
      '/daily-check-in' =>
        NotificationActionTarget.dailyCheckIn,
      '/habit-completion' when canUseSyncedHabits =>
        NotificationActionTarget.habitCompletion,
      '/habits' when canUseSyncedHabits =>
        NotificationActionTarget.habitManagement,
      '/weekly-review' when canUseWeeklyReview =>
        NotificationActionTarget.weeklyReview,
      '/deep-work' when canUseFocusSessions =>
        NotificationActionTarget.focusSession,
      _ => null,
    };
  }
}
