import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/notifications/domain/entities/app_notification.dart';
import 'package:my_life_graph/features/notifications/domain/entities/notification_lifecycle.dart';
import 'package:my_life_graph/features/notifications/domain/repositories/notifications_repository.dart';
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
    expect(
      find.byKey(const ValueKey('notification-read-toggle-habit')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('notification-dismiss-habit')),
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
    expect(
      find.byKey(const ValueKey('notification-read-toggle-habit')),
      findsOneWidget,
    );
    _expectMetricValue(tester, 'notifications-action-count', '1');
  });

  testWidgets('exposes labeled lifecycle controls and applies confirmed state',
      (tester) async {
    const id = '11111111-1111-4111-8111-111111111111';
    final repository = _PageNotificationsRepository(
      items: [
        _notification(
          id: id,
          title: 'Accessible reminder',
          body: 'A durable account item.',
          type: 'reminder',
          priority: 'medium',
          actionUrl: null,
          isRead: false,
        ),
      ],
    );
    final semantics = tester.ensureSemantics();

    await _pumpPage(
      tester,
      repository: repository,
      useDemoData: false,
    );

    expect(
      find.bySemanticsLabel('Mark read notification Accessible reminder'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Dismiss notification Accessible reminder'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('notification-read-toggle-$id')),
    );
    await tester.pumpAndSettle();

    expect(
      repository.requests.single.command,
      NotificationLifecycleCommand.markRead,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('notification-read-state-$id')),
        matching: find.text('Read'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('notification-dismiss-$id')));
    await tester.pumpAndSettle();

    expect(
      repository.requests.last.command,
      NotificationLifecycleCommand.dismiss,
    );
    expect(find.byKey(const ValueKey('notification-$id')), findsNothing);
    semantics.dispose();
  });

  testWidgets('shows honest row retry and keeps dismiss visible until success',
      (tester) async {
    const id = '11111111-1111-4111-8111-111111111111';
    var attempts = 0;
    final repository = _PageNotificationsRepository(
      items: [
        _notification(
          id: id,
          title: 'Retry reminder',
          body: 'Keep this visible while uncertain.',
          type: 'reminder',
          priority: 'high',
          actionUrl: null,
          isRead: false,
        ),
      ],
      action: (request) async {
        attempts++;
        if (attempts == 1) throw _transportFailure();
        return _lifecycleResult(request);
      },
    );
    await _pumpPage(
      tester,
      repository: repository,
      useDemoData: false,
    );

    await tester.tap(find.byKey(const ValueKey('notification-dismiss-$id')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('notification-$id')), findsOneWidget);
    expect(
      find.text(
        'The action result is unknown. Retry sends the exact same request.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('notification-action-retry-$id')),
      findsOneWidget,
    );
    final firstPayload = repository.requests.single.toJson();

    final retry = find.byKey(
      const ValueKey('notification-action-retry-$id'),
    );
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(repository.requests, hasLength(2));
    expect(repository.requests.last.toJson(), firstPayload);
    expect(find.byKey(const ValueKey('notification-$id')), findsNothing);
  });

  testWidgets('definitive 4xx offers reload only and blocks stale actions',
      (tester) async {
    const id = '11111111-1111-4111-8111-111111111111';
    final semantics = tester.ensureSemantics();
    final repository = _PageNotificationsRepository(
      items: [
        _notification(
          id: id,
          title: 'Changed elsewhere',
          body: 'Reload before acting again.',
          type: 'reminder',
          priority: 'medium',
          actionUrl: null,
          isRead: false,
        ),
      ],
      action: (_) async => throw _httpFailure(409),
    );
    await _pumpPage(
      tester,
      repository: repository,
      useDemoData: false,
    );

    await tester.tap(
      find.byKey(const ValueKey('notification-read-toggle-$id')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This inbox item changed or is no longer available. Reload the inbox before acting again.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('notification-action-retry-$id')),
      findsNothing,
    );
    expect(find.text('Retry action'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('Reload inbox for Changed elsewhere')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('notification-read-toggle-$id')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('notification-dismiss-$id')),
          )
          .onPressed,
      isNull,
    );
    expect(repository.requests, hasLength(1));

    repository.items = [
      _notification(
        id: id,
        title: 'Changed elsewhere',
        body: 'Reload before acting again.',
        type: 'reminder',
        priority: 'medium',
        actionUrl: null,
        isRead: false,
        updatedAt: DateTime.utc(2026, 7, 10, 8, 16),
      ),
    ];
    final reload = find.byKey(const ValueKey('notification-action-reload-$id'));
    tester.widget<OutlinedButton>(reload).onPressed!();
    await tester.pumpAndSettle();

    expect(repository.loadCalls, 2);
    expect(
      find.byKey(const ValueKey('notification-action-error-$id')),
      findsNothing,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('notification-read-toggle-$id')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('notification-dismiss-$id')),
          )
          .onPressed,
      isNotNull,
    );
    expect(repository.requests, hasLength(1));
    semantics.dispose();
  });

  testWidgets('light summary icons meet non-text contrast', (tester) async {
    await _pumpPage(
      tester,
      items: [
        _notification(
          id: 'contrast',
          title: 'Contrast check',
          body: 'Metric colors remain visible.',
          type: 'summary',
          priority: 'medium',
          actionUrl: '/dashboard',
          isRead: true,
        ),
      ],
      useDemoData: false,
      theme: AppTheme.light,
    );

    final background = AppTheme.light.colorScheme.surfaceContainerLow;
    for (final entry in <(String, IconData)>[
      ('notifications-unread-count', Icons.mark_email_unread_outlined),
      ('notifications-read-count', Icons.drafts_outlined),
      ('notifications-action-count', Icons.arrow_forward),
    ]) {
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(ValueKey(entry.$1)),
          matching: find.byIcon(entry.$2),
        ),
      );
      expect(
        _contrastRatio(icon.color!, background),
        greaterThanOrEqualTo(3),
        reason: '${entry.$1}: ${icon.color} on $background',
      );
    }
  });

  testWidgets('distinguishes account load failure from an empty list',
      (tester) async {
    await _pumpPage(
      tester,
      useDemoData: false,
      loadError: StateError('read failed'),
    );

    expect(find.text('Could not load inbox.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Your inbox is empty.'), findsNothing);

    await _pumpPage(tester, items: const [], useDemoData: false);

    expect(find.text('Your inbox is empty.'), findsOneWidget);
    expect(find.text('Could not load inbox.'), findsNothing);
  });

  testWidgets('uses an overflow-free compact summary at 320 pixels',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpPage(tester, items: const [], useDemoData: false);

    expect(find.text('Inbox'), findsOneWidget);
    expect(
      find.text(
        'Stored inbox items can be marked read or dismissed here. In-app banners require separate consent and appear only while the app is open; no push delivery is enabled. Up to the latest 30 items are shown.',
      ),
      findsOneWidget,
    );
    expect(find.text('Account data'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notifications-unread-count')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('notifications-read-count')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('notifications-action-count')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses compact summary at 390 pixels with 2x text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsRepositoryProvider.overrideWithValue(
            _PageNotificationsRepository(items: const []),
          ),
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: false,
            ),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const Scaffold(body: NotificationsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -340),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('notifications-unread-count')),
        matching: find.byType(Row),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification card and actions do not overflow at 320px and 2x',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpPage(
      tester,
      items: [
        _notification(
          id: '11111111-1111-4111-8111-111111111111',
          title: 'A reminder with a deliberately longer title',
          body:
              'Longer stored body content remains readable on a small screen.',
          type: 'reminder',
          priority: 'medium',
          actionUrl: null,
          isRead: false,
        ),
      ],
      useDemoData: false,
      textScale: 2,
    );

    await tester.scrollUntilVisible(
      find.text('A reminder with a deliberately longer title'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(
        const ValueKey(
          'notification-read-toggle-11111111-1111-4111-8111-111111111111',
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  List<AppNotification> items = const [],
  _PageNotificationsRepository? repository,
  required bool useDemoData,
  bool canUseSyncedHabits = false,
  Object? loadError,
  ThemeData? theme,
  double textScale = 1,
}) async {
  final source = repository ??
      _PageNotificationsRepository(items: items, loadError: loadError);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        notificationsRepositoryProvider.overrideWithValue(source),
        appSurfaceCapabilitiesProvider.overrideWithValue(
          AppSurfaceCapabilities(
            isLocalDemo: useDemoData,
            canUseSyncedHabits: canUseSyncedHabits,
          ),
        ),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const Scaffold(body: NotificationsPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _contrastRatio(Color a, Color b) {
  final luminanceA = a.computeLuminance();
  final luminanceB = b.computeLuminance();
  return (luminanceA > luminanceB ? luminanceA + 0.05 : luminanceB + 0.05) /
      (luminanceA > luminanceB ? luminanceB + 0.05 : luminanceA + 0.05);
}

AppNotification _notification({
  required String id,
  required String title,
  required String body,
  required String type,
  required String priority,
  required String? actionUrl,
  required bool isRead,
  DateTime? updatedAt,
}) {
  final sourceUpdatedAt = updatedAt ?? DateTime.utc(2026, 7, 10, 8, 15);
  return AppNotification(
    id: id,
    title: title,
    body: body,
    type: type,
    priority: priority,
    actionUrl: actionUrl,
    createdAt: DateTime.utc(2026, 7, 10, 8, 15),
    updatedAt: sourceUpdatedAt,
    isRead: isRead,
    readAt: isRead ? sourceUpdatedAt : null,
    dismissedAt: null,
    dueAt: null,
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

NotificationLifecycleResult _lifecycleResult(
  NotificationLifecycleRequest request,
) {
  final updatedAt = request.expectedUpdatedAt.add(const Duration(minutes: 1));
  final isRead = request.command != NotificationLifecycleCommand.markUnread;
  final dismissed = request.command == NotificationLifecycleCommand.dismiss;
  return NotificationLifecycleResult.fromJson({
    'contract_version': notificationLifecycleContractVersion,
    'notification_id': request.notificationId,
    'command': request.command.wireValue,
    'is_read': isRead,
    'read_at': isRead ? updatedAt.toIso8601String() : null,
    'dismissed_at': dismissed ? updatedAt.toIso8601String() : null,
    'updated_at': updatedAt.toIso8601String(),
    'replayed': false,
  });
}

AppException _transportFailure() {
  return AppException(
    'Network request failed',
    cause: DioException(
      requestOptions: RequestOptions(path: '/v1/notifications'),
      type: DioExceptionType.connectionError,
    ),
  );
}

AppException _httpFailure(int statusCode) {
  final options = RequestOptions(path: '/v1/notifications');
  return AppException(
    'Network request failed',
    cause: DioException(
      requestOptions: options,
      response: Response<void>(requestOptions: options, statusCode: statusCode),
      type: DioExceptionType.badResponse,
    ),
  );
}

class _PageNotificationsRepository implements NotificationsRepository {
  _PageNotificationsRepository({
    required this.items,
    this.loadError,
    this.action,
  });

  List<AppNotification> items;
  final Object? loadError;
  final Future<NotificationLifecycleResult> Function(
    NotificationLifecycleRequest request,
  )? action;
  final List<NotificationLifecycleRequest> requests = [];
  int loadCalls = 0;

  @override
  Future<List<AppNotification>> getNotifications() async {
    loadCalls++;
    final error = loadError;
    if (error != null) throw error;
    return items;
  }

  @override
  Future<NotificationLifecycleResult> performLifecycleAction(
    NotificationLifecycleRequest request,
  ) async {
    requests.add(request);
    final handler = action;
    if (handler != null) return handler(request);
    return _lifecycleResult(request);
  }
}
