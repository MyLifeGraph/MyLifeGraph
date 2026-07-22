import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/features/notifications/application/notification_delivery_controller.dart';
import 'package:my_life_graph/features/notifications/data/datasources/notifications_supabase_data_source.dart';
import 'package:my_life_graph/features/notifications/domain/entities/app_notification.dart';
import 'package:my_life_graph/features/notifications/domain/entities/notification_delivery.dart';
import 'package:my_life_graph/features/notifications/domain/entities/notification_lifecycle.dart';
import 'package:my_life_graph/features/notifications/domain/repositories/notification_delivery_repository.dart';
import 'package:my_life_graph/features/notifications/domain/repositories/notifications_repository.dart';
import 'package:my_life_graph/features/notifications/presentation/pages/notification_settings_page.dart';
import 'package:my_life_graph/features/notifications/presentation/pages/notifications_page.dart';
import 'package:my_life_graph/features/notifications/presentation/providers/notifications_providers.dart';
import 'package:my_life_graph/features/shell/presentation/main_shell.dart';

const _notificationId = '11111111-1111-4111-8111-111111111111';
final _updatedAt = DateTime.parse('2026-07-14T08:30:00Z');

void main() {
  group('notification delivery contracts', () {
    test('keeps reminder categories separate from explicit delivery consent',
        () {
      final settings = NotificationSettings.fromJson(
        _settingsJson(enabled: false),
      );

      expect(settings.inAppDeliveryEnabled, isFalse);
      expect(settings.consentVersion, isNull);
      expect(settings.categories.focusPrompt, isTrue);

      expect(
        () => NotificationSettings.fromJson({
          ..._settingsJson(enabled: false),
          'in_app_delivery_enabled': true,
        }),
        throwsA(isA<NotificationLifecycleContractException>()),
      );
    });

    test('settings update always sends the dedicated consent version', () {
      final request = NotificationSettingsUpdate(
        requestId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        expectedUpdatedAt: _updatedAt,
        inAppDeliveryEnabled: true,
        categories: const NotificationCategories(
          focusPrompt: true,
          recoveryPrompt: false,
          weeklySummary: true,
        ),
        quietHours: NotificationQuietHours(
          startsAt: '22:00',
          endsAt: '07:00',
        ),
        dailyLimit: 2,
      );

      expect(request.toJson(), {
        'contract_version': 'notification-settings-v1',
        'request_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'expected_updated_at': '2026-07-14T08:30:00.000Z',
        'in_app_delivery_enabled': true,
        'consent_version': 'in-app-notification-consent-v1',
        'categories': {
          'focus_prompt': true,
          'recovery_prompt': false,
          'weekly_summary': true,
        },
        'quiet_hours': {'starts_at': '22:00', 'ends_at': '07:00'},
        'daily_limit': 2,
      });
    });

    test('exposes only enabled deterministic category wire values', () {
      const categories = NotificationCategories(
        focusPrompt: false,
        recoveryPrompt: true,
        weeklySummary: true,
      );

      expect(
        categories.enabledCategoryCodes,
        ['recovery_prompt', 'weekly_summary'],
      );
      expect(categories.allows('focus_prompt'), isFalse);
      expect(categories.allows('weekly_summary'), isTrue);
      expect(categories.allows('unknown'), isFalse);
    });

    test('strictly maps deterministic provenance and pending delivery state',
        () {
      const mapper = NotificationsSupabaseRowMapper();
      final notification = mapper.fromRow(_generatedRow());

      expect(notification.isDeterministicallyGenerated, isTrue);
      expect(notification.generationCategory, 'focus_prompt');
      expect(notification.deliveryDate, '2026-07-14');
      expect(notification.generationProvenance?.sourceKind, 'daily_briefing');
      expect(notification.generationProvenance?.timezone, 'Europe/Berlin');
      expect(
        mapper
            .pendingInAppFromRows(
              [_generatedRow()],
              now: DateTime.parse('2026-07-14T08:31:00Z'),
            )
            .single
            .id,
        _notificationId,
      );

      expect(
        () => mapper.fromRow(
          _generatedRow()
            ..['metadata'] = {
              ...(_generatedRow()['metadata']! as Map<String, dynamic>),
              'llm_used': true,
            },
        ),
        throwsA(isA<NotificationLifecycleContractException>()),
      );
    });
  });

  group('delivery controllers', () {
    test('consent-off poll performs no inbox query or acknowledgement',
        () async {
      final repository = _DeliveryRepository(
        settings: NotificationSettings.fromJson(_settingsJson(enabled: false)),
        pending: [_notification()],
      );
      final controller = InAppNotificationDeliveryController(
        repository: repository,
        enabled: true,
        autoStart: false,
      );
      addTearDown(controller.dispose);

      await controller.poll();

      expect(repository.settingsCalls, 1);
      expect(repository.pendingCalls, 0);
      expect(repository.deliveryCalls, 0);
      expect(controller.state.sequence, 0);
    });

    test('acknowledges before emitting and never emits a replay', () async {
      final repository = _DeliveryRepository(
        settings: NotificationSettings.fromJson(_settingsJson(enabled: true)),
        pending: [_notification()],
      );
      final controller = InAppNotificationDeliveryController(
        repository: repository,
        enabled: true,
        autoStart: false,
      );
      addTearDown(controller.dispose);

      await controller.poll();

      expect(repository.deliveryCalls, 1);
      expect(controller.state.sequence, 1);
      expect(controller.state.notification?.id, _notificationId);

      repository.receiptReplayed = true;
      await controller.poll();
      expect(controller.state.sequence, 1);
    });

    test('disabled older categories cannot starve an allowed banner', () async {
      const weeklyId = '22222222-2222-4222-8222-222222222222';
      final repository = _DeliveryRepository(
        settings: NotificationSettings.fromJson(
          _settingsJson(
            enabled: true,
            focusPrompt: false,
            recoveryPrompt: false,
          ),
        ),
        pending: [
          _notification(),
          _notification(id: weeklyId, category: 'weekly_summary'),
        ],
      );
      final controller = InAppNotificationDeliveryController(
        repository: repository,
        enabled: true,
        autoStart: false,
      );
      addTearDown(controller.dispose);

      await controller.poll();

      expect(
        repository.lastPendingCategories?.enabledCategoryCodes,
        ['weekly_summary'],
      );
      expect(repository.deliveredIds, [weeklyId]);
      expect(controller.state.notification?.id, weeklyId);
    });

    test('ambiguous settings save retains the exact immutable retry', () async {
      final repository = _DeliveryRepository(
        settings: NotificationSettings.fromJson(_settingsJson(enabled: false)),
      )..updateErrors.add(
          AppException(
            'lost',
            cause: DioException(
              requestOptions: RequestOptions(path: '/settings'),
            ),
          ),
        );
      final controller = NotificationSettingsController(
        repository: repository,
        autoLoad: false,
      );
      addTearDown(controller.dispose);
      await controller.load();

      final first = await controller.save(
        inAppDeliveryEnabled: true,
        categories: const NotificationCategories(
          focusPrompt: true,
          recoveryPrompt: true,
          weeklySummary: true,
        ),
        quietHours: null,
        dailyLimit: 2,
      );
      final exact = controller.state.exactRetryRequest;
      final retried = await controller.retryExact();

      expect(first, isFalse);
      expect(exact, isNotNull);
      expect(retried, isTrue);
      expect(repository.updates.length, 2);
      expect(identical(repository.updates[0], repository.updates[1]), isTrue);
    });

    test('failed reload after an ambiguous save stays locked', () async {
      final repository = _DeliveryRepository(
        settings: NotificationSettings.fromJson(_settingsJson(enabled: false)),
      )..updateErrors.add(
          AppException(
            'lost',
            cause: DioException(
              requestOptions: RequestOptions(path: '/settings'),
            ),
          ),
        );
      final controller = NotificationSettingsController(
        repository: repository,
        autoLoad: false,
      );
      addTearDown(controller.dispose);
      await controller.load();
      await controller.save(
        inAppDeliveryEnabled: true,
        categories: const NotificationCategories(
          focusPrompt: true,
          recoveryPrompt: true,
          weeklySummary: true,
        ),
        quietHours: null,
        dailyLimit: 2,
      );
      repository.getErrors.add(StateError('reload failed'));

      await controller.load();

      expect(controller.state.requiresExactRetry, isFalse);
      expect(controller.state.requiresReload, isTrue);
      expect(controller.state.error, isA<StateError>());
    });

    test('definite settings conflict blocks edits until reload', () async {
      final repository = _DeliveryRepository(
        settings: NotificationSettings.fromJson(_settingsJson(enabled: false)),
      )..updateErrors.add(_httpFailure(409));
      final controller = NotificationSettingsController(
        repository: repository,
        autoLoad: false,
      );
      addTearDown(controller.dispose);
      await controller.load();

      final first = await controller.save(
        inAppDeliveryEnabled: true,
        categories: const NotificationCategories(
          focusPrompt: true,
          recoveryPrompt: true,
          weeklySummary: true,
        ),
        quietHours: null,
        dailyLimit: 2,
      );
      final blocked = await controller.save(
        inAppDeliveryEnabled: false,
        categories: const NotificationCategories(
          focusPrompt: false,
          recoveryPrompt: false,
          weeklySummary: false,
        ),
        quietHours: null,
        dailyLimit: 1,
      );

      expect(first, isFalse);
      expect(controller.state.requiresReload, isTrue);
      expect(controller.state.requiresExactRetry, isFalse);
      expect(blocked, isFalse);
      expect(repository.updates, hasLength(1));

      repository.getErrors.add(StateError('reload failed'));
      await controller.load();
      expect(controller.state.requiresReload, isTrue);
      expect(controller.state.error, isA<StateError>());

      await controller.load();
      expect(controller.state.requiresReload, isFalse);
      expect(controller.state.error, isNull);
    });
  });

  testWidgets('settings requires a separate explicit consent confirmation',
      (tester) async {
    final repository = _DeliveryRepository(
      settings: NotificationSettings.fromJson(_settingsJson(enabled: false)),
    );
    final controller = NotificationSettingsController(repository: repository);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationSettingsProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NotificationSettingsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('notification-delivery-consent')),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('notification-settings-save')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('notification-settings-save')));
    await tester.pumpAndSettle();

    expect(find.text('Allow in-app banners?'), findsOneWidget);
    expect(
      find.textContaining('Setup preference did not turn these on'),
      findsOneWidget,
    );
    expect(repository.updates, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey('notification-consent-confirm')),
    );
    await tester.pumpAndSettle();

    expect(repository.updates.single.inAppDeliveryEnabled, isTrue);
  });

  testWidgets('shell shows one acknowledged deterministic in-app banner',
      (tester) async {
    final repository = _DeliveryRepository(
      settings: NotificationSettings.fromJson(_settingsJson(enabled: true)),
      pending: [_notification()],
    );
    final controller = InAppNotificationDeliveryController(
      repository: repository,
      enabled: true,
      autoStart: false,
    );
    final inboxRepository = _InboxRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseSyncedExecution: true,
              canUseWeeklyReview: true,
            ),
          ),
          inAppNotificationDeliveryProvider.overrideWith((ref) => controller),
          notificationsRepositoryProvider.overrideWithValue(inboxRepository),
        ],
        child: const MaterialApp(
          home: MainShell(
            currentPath: '/alerts',
            child: NotificationsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your inbox is empty.'), findsOneWidget);

    inboxRepository.items = [_notification()];
    await controller.poll();
    await tester.pumpAndSettle();

    expect(repository.deliveryCalls, 1);
    expect(
      find.byKey(const ValueKey('in-app-notification-$_notificationId')),
      findsOneWidget,
    );
    expect(find.text('In-app · fixed text · not AI-written'), findsOneWidget);
    expect(find.text("Today's overview is ready"), findsWidgets);
    expect(find.text('Your inbox is empty.'), findsNothing);
    expect(inboxRepository.calls, greaterThanOrEqualTo(2));
    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Based on today\'s current plan for 2026-07-14 in Europe/Berlin.',
      ),
      findsOneWidget,
    );
  });
}

Map<String, dynamic> _settingsJson({
  required bool enabled,
  bool focusPrompt = true,
  bool recoveryPrompt = true,
  bool weeklySummary = true,
}) =>
    {
      'contract_version': 'notification-settings-v1',
      'in_app_delivery_enabled': enabled,
      'consent_version': enabled ? 'in-app-notification-consent-v1' : null,
      'consented_at': enabled ? '2026-07-14T08:30:00Z' : null,
      'disabled_at': null,
      'categories': {
        'focus_prompt': focusPrompt,
        'recovery_prompt': recoveryPrompt,
        'weekly_summary': weeklySummary,
      },
      'quiet_hours': null,
      'daily_limit': 2,
      'updated_at': '2026-07-14T08:30:00Z',
      'replayed': false,
    };

Map<String, dynamic> _generatedRow() => {
      'id': _notificationId,
      'title': "Today's overview is ready",
      'message': 'Open Today to review your schedule and actions.',
      'type': 'reminder',
      'priority': 'medium',
      'action_url': '/dashboard',
      'created_at': '2026-07-14T08:30:00Z',
      'updated_at': '2026-07-14T08:30:00Z',
      'is_read': false,
      'read_at': null,
      'dismissed_at': null,
      'due_at': '2026-07-14T08:30:00Z',
      'metadata': {
        'contract_version': 'notification-generation-v1',
        'origin': 'deterministic_backend',
        'category': 'focus_prompt',
        'reason_code': 'current_daily_briefing',
        'delivery_date': '2026-07-14',
        'timezone': 'Europe/Berlin',
        'source_kind': 'daily_briefing',
        'source_id': 'briefing-1',
        'source_generated_at': '2026-07-14T08:20:00Z',
        'sensitive_copy_excluded': true,
        'llm_used': false,
      },
      'generation_key': 'notification-generation-v1:focus_prompt:2026-07-14',
      'generation_category': 'focus_prompt',
      'delivery_date': '2026-07-14',
      'in_app_delivered_at': null,
    };

AppNotification _notification({
  String id = _notificationId,
  String category = 'focus_prompt',
}) =>
    AppNotification(
      id: id,
      title: category == 'weekly_summary'
          ? 'Your weekly review is ready'
          : "Today's overview is ready",
      body: 'Open Today to review your schedule and actions.',
      type: 'reminder',
      priority: 'medium',
      actionUrl: '/dashboard',
      createdAt: _updatedAt,
      updatedAt: _updatedAt,
      isRead: false,
      readAt: null,
      dismissedAt: null,
      dueAt: _updatedAt,
      generationKey: 'notification-generation-v1:$category:2026-07-14',
      generationCategory: category,
      deliveryDate: '2026-07-14',
      generationProvenance: NotificationGenerationProvenance(
        reasonCode: 'current_daily_briefing',
        timezone: 'Europe/Berlin',
        sourceKind: 'daily_briefing',
        sourceId: 'briefing-1',
        sourceGeneratedAt: DateTime.parse('2026-07-14T08:20:00Z'),
      ),
    );

class _DeliveryRepository implements NotificationDeliveryRepository {
  _DeliveryRepository({required this.settings, this.pending = const []});

  NotificationSettings settings;
  List<AppNotification> pending;
  bool receiptReplayed = false;
  int settingsCalls = 0;
  int pendingCalls = 0;
  int deliveryCalls = 0;
  NotificationCategories? lastPendingCategories;
  final List<String> deliveredIds = [];
  final List<NotificationSettingsUpdate> updates = [];
  final List<Object> updateErrors = [];
  final List<Object> getErrors = [];

  @override
  Future<NotificationDeliveryReceipt> acknowledgeInAppDelivery(
    AppNotification notification,
  ) async {
    deliveryCalls++;
    deliveredIds.add(notification.id);
    return NotificationDeliveryReceipt.fromJson({
      'contract_version': 'in-app-notification-delivery-v1',
      'notification_id': notification.id,
      'channel': 'in_app',
      'delivered_at': '2026-07-14T08:31:00Z',
      'replayed': receiptReplayed,
    });
  }

  @override
  Future<NotificationSettings> getDeliverySettings() async {
    settingsCalls++;
    if (getErrors.isNotEmpty) throw getErrors.removeAt(0);
    return settings;
  }

  @override
  Future<List<AppNotification>> getPendingInAppNotifications({
    required NotificationCategories categories,
  }) async {
    pendingCalls++;
    lastPendingCategories = categories;
    return pending;
  }

  @override
  Future<NotificationSettings> updateDeliverySettings(
    NotificationSettingsUpdate request,
  ) async {
    updates.add(request);
    if (updateErrors.isNotEmpty) throw updateErrors.removeAt(0);
    settings = NotificationSettings.fromJson(
      _settingsJson(enabled: request.inAppDeliveryEnabled),
    );
    return settings;
  }
}

AppException _httpFailure(int statusCode) {
  final options = RequestOptions(path: '/settings');
  return AppException(
    'request failed',
    cause: DioException(
      requestOptions: options,
      response: Response<void>(
        requestOptions: options,
        statusCode: statusCode,
      ),
    ),
  );
}

class _InboxRepository implements NotificationsRepository {
  List<AppNotification> items = const [];
  int calls = 0;

  @override
  Future<List<AppNotification>> getNotifications() async {
    calls++;
    return items;
  }

  @override
  Future<NotificationLifecycleResult> performLifecycleAction(
    NotificationLifecycleRequest request,
  ) {
    throw UnimplementedError();
  }
}
