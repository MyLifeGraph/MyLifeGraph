import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/notifications/domain/entities/notification_action_target.dart';

void main() {
  group('NotificationActionTargetResolver', () {
    const withoutHabits = NotificationActionTargetResolver(
      canUseSyncedHabits: false,
    );

    test('allows only known working internal targets', () {
      expect(
        withoutHabits.resolve('/dashboard'),
        NotificationActionTarget.dashboard,
      );
      expect(
        withoutHabits.resolve('/insights'),
        NotificationActionTarget.insights,
      );
      expect(
        withoutHabits.resolve('/quick-action'),
        NotificationActionTarget.quickAction,
      );
      expect(
        withoutHabits.resolve('/daily-check-in'),
        NotificationActionTarget.dailyCheckIn,
      );
      expect(
        withoutHabits.resolve('/quick-mood-check-in'),
        NotificationActionTarget.dailyCheckIn,
      );
    });

    test('rejects external, ambiguous, and unfinished targets', () {
      const rejected = <String?>[
        null,
        '',
        ' /dashboard',
        '/dashboard ',
        'dashboard',
        'https://example.com/dashboard',
        '//example.com/dashboard',
        '/dashboard?source=notification',
        '/dashboard#today',
        '/deep-work',
        '/coach',
        '/settings',
        '/notifications',
        '/unknown',
      ];

      for (final actionUrl in rejected) {
        expect(
          withoutHabits.resolve(actionUrl),
          isNull,
          reason: '$actionUrl must not become an enabled action',
        );
      }
    });

    test('habit targets require synced habit capability', () {
      const withHabits = NotificationActionTargetResolver(
        canUseSyncedHabits: true,
      );

      expect(withoutHabits.resolve('/habit-completion'), isNull);
      expect(withoutHabits.resolve('/habits'), isNull);
      expect(
        withHabits.resolve('/habit-completion'),
        NotificationActionTarget.habitCompletion,
      );
      expect(
        withHabits.resolve('/habits'),
        NotificationActionTarget.habitManagement,
      );
    });

    test('focus target requires the real focus-session capability', () {
      const withFocus = NotificationActionTargetResolver(
        canUseSyncedHabits: true,
        canUseFocusSessions: true,
      );

      expect(withoutHabits.resolve('/deep-work'), isNull);
      expect(
        withFocus.resolve('/deep-work'),
        NotificationActionTarget.focusSession,
      );
    });
  });
}
