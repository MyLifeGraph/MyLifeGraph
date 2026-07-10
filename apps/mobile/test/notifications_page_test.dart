import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/features/notifications/domain/entities/app_notification.dart';
import 'package:my_life_graph/features/notifications/presentation/pages/notifications_page.dart';
import 'package:my_life_graph/features/notifications/presentation/providers/notifications_providers.dart';

void main() {
  testWidgets('shows original fields and source read state without fake claims',
      (tester) async {
    final items = [
      _notification(
        id: 'unread-safe',
        title: 'Original deadline title',
        body: 'Original deadline body.',
        type: 'deadline',
        priority: 'critical',
        actionUrl: '/dashboard',
        isRead: false,
      ),
      _notification(
        id: 'read-unsafe',
        title: 'Original external title',
        body: 'Original external body.',
        type: 'summary',
        priority: 'low',
        actionUrl: 'https://example.com/action',
        isRead: true,
      ),
      _notification(
        id: 'unfinished',
        title: 'Original focus title',
        body: 'Original focus body.',
        type: 'reminder',
        priority: 'high',
        actionUrl: '/deep-work',
        isRead: false,
      ),
    ];

    await _pumpPage(tester, items: items, useDemoData: false);

    expect(find.text('Original deadline title'), findsOneWidget);
    expect(find.text('Original deadline body.'), findsOneWidget);
    expect(find.text('Deadline approaching'), findsNothing);
    expect(find.text('Sleep debt warning'), findsNothing);
    expect(find.text('REMINDER AGENT'), findsNothing);
    expect(find.text('Coaching'), findsNothing);
    expect(find.text('Account data'), findsOneWidget);

    expect(
      find.byKey(const ValueKey('notification-open-unread-safe')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('notification-read-state-unread-safe'),
        ),
        matching: find.text('Unread'),
      ),
      findsOneWidget,
    );
    _expectMetricValue(tester, 'notifications-unread-count', '2');
    _expectMetricValue(tester, 'notifications-read-count', '1');
    _expectMetricValue(tester, 'notifications-action-count', '1');

    await tester.scrollUntilVisible(
      find.text('Original external title'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Original external body.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notification-open-read-unsafe')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('notification-read-state-read-unsafe'),
        ),
        matching: find.text('Read'),
      ),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('Original focus title'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Original focus body.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notification-open-unfinished')),
      findsNothing,
    );
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('labels guest content as demo and gates habit actions',
      (tester) async {
    final item = _notification(
      id: 'habit',
      title: 'Habit reminder',
      body: 'Habit body.',
      type: 'reminder',
      priority: 'medium',
      actionUrl: '/habit-completion',
      isRead: false,
    );

    await _pumpPage(
      tester,
      items: [item],
      useDemoData: true,
      canUseSyncedHabits: false,
    );

    expect(find.text('Demo data'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notification-open-habit')),
      findsNothing,
    );
    _expectMetricValue(tester, 'notifications-action-count', '0');

    await _pumpPage(
      tester,
      items: [item],
      useDemoData: false,
      canUseSyncedHabits: true,
    );

    expect(
      find.byKey(const ValueKey('notification-open-habit')),
      findsOneWidget,
    );
    _expectMetricValue(tester, 'notifications-action-count', '1');
  });

  testWidgets('distinguishes account load failure from an empty list',
      (tester) async {
    await _pumpPage(
      tester,
      useDemoData: false,
      loadError: StateError('read failed'),
    );

    expect(find.text('Could not load notifications.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No notifications yet.'), findsNothing);

    await _pumpPage(tester, items: const [], useDemoData: false);

    expect(find.text('No notifications yet.'), findsOneWidget);
    expect(find.text('Could not load notifications.'), findsNothing);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  List<AppNotification> items = const [],
  required bool useDemoData,
  bool canUseSyncedHabits = false,
  Object? loadError,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        notificationsProvider.overrideWith((ref) async {
          if (loadError != null) {
            throw loadError;
          }
          return items;
        }),
        appSurfaceCapabilitiesProvider.overrideWithValue(
          AppSurfaceCapabilities(
            isLocalDemo: useDemoData,
            canUseSyncedHabits: canUseSyncedHabits,
          ),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: NotificationsPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppNotification _notification({
  required String id,
  required String title,
  required String body,
  required String type,
  required String priority,
  required String? actionUrl,
  required bool isRead,
}) {
  return AppNotification(
    id: id,
    title: title,
    body: body,
    type: type,
    priority: priority,
    actionUrl: actionUrl,
    createdAt: DateTime.utc(2026, 7, 10, 8, 15),
    isRead: isRead,
  );
}

void _expectMetricValue(
  WidgetTester tester,
  String key,
  String value,
) {
  expect(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.text(value),
    ),
    findsOneWidget,
  );
}
