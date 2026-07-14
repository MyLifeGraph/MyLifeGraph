import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/features/notifications/application/notifications_controller.dart';
import 'package:my_life_graph/features/notifications/domain/entities/app_notification.dart';
import 'package:my_life_graph/features/notifications/domain/entities/notification_lifecycle.dart';
import 'package:my_life_graph/features/notifications/domain/repositories/notifications_repository.dart';

const _firstId = '11111111-1111-4111-8111-111111111111';
const _secondId = '22222222-2222-4222-8222-222222222222';

void main() {
  test('loads and applies confirmed read state without optimistic mutation',
      () async {
    final completion = Completer<NotificationLifecycleResult>();
    final repository = _FakeNotificationsRepository(
      items: [_notification(_firstId)],
      onAction: (_, __) => completion.future,
    );
    final controller = NotificationsController(
      repository: repository,
      canManageLifecycle: true,
      autoLoad: false,
    );
    addTearDown(controller.dispose);
    await controller.load();

    final action = controller.markRead(_firstId);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.items.single.isRead, isFalse);
    expect(controller.state.actionFor(_firstId)?.isPending, isTrue);

    completion.complete(
      _result(_firstId, NotificationLifecycleCommand.markRead),
    );
    expect(await action, isTrue);
    expect(controller.state.items.single.isRead, isTrue);
    expect(controller.state.items.single.readAt, isNotNull);
    expect(controller.state.actionFor(_firstId), isNull);
  });

  test('ambiguous failure retries the exact immutable request payload',
      () async {
    var attempts = 0;
    final repository = _FakeNotificationsRepository(
      items: [_notification(_firstId)],
      onAction: (_, request) async {
        attempts++;
        if (attempts == 1) throw _transportFailure();
        return _result(_firstId, NotificationLifecycleCommand.markRead);
      },
    );
    final controller = NotificationsController(
      repository: repository,
      canManageLifecycle: true,
      autoLoad: false,
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.markRead(_firstId), isFalse);
    final failedState = controller.state.actionFor(_firstId)!;
    expect(failedState.requiresExactRetry, isTrue);
    expect(controller.state.items.single.isRead, isFalse);
    final firstPayload = Map<String, dynamic>.from(
      repository.requests.single.toJson(),
    );

    expect(await controller.retry(_firstId), isTrue);

    expect(repository.requests, hasLength(2));
    expect(repository.requests[1].requestId, repository.requests[0].requestId);
    expect(repository.requests[1].toJson(), firstPayload);
    expect(controller.state.items.single.isRead, isTrue);
  });

  test(
      'exact replay reloads newer multi-client state instead of applying history',
      () async {
    var attempts = 0;
    final repository = _FakeNotificationsRepository(
      items: [_notification(_firstId)],
      onAction: (_, request) async {
        attempts++;
        if (attempts == 1) throw _transportFailure();
        return _result(
          request.notificationId,
          request.command,
          replayed: true,
        );
      },
    );
    final controller = NotificationsController(
      repository: repository,
      canManageLifecycle: true,
      autoLoad: false,
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.markRead(_firstId), isFalse);
    repository.items = [
      _notification(
        _firstId,
        updatedAt: DateTime.utc(2026, 7, 10, 8, 2),
      ),
    ];

    expect(await controller.retry(_firstId), isTrue);

    expect(repository.loadCalls, 2);
    expect(controller.state.items.single.isRead, isFalse);
    expect(
      controller.state.items.single.updatedAt,
      DateTime.utc(2026, 7, 10, 8, 2),
    );
    expect(controller.state.actionFor(_firstId), isNull);
    expect(controller.state.loadError, isNull);
  });

  test('exact dismiss replay reloads the inbox so the tombstone disappears',
      () async {
    var attempts = 0;
    final repository = _FakeNotificationsRepository(
      items: [_notification(_firstId), _notification(_secondId)],
      onAction: (_, request) async {
        attempts++;
        if (attempts == 1) throw _transportFailure();
        return _result(
          request.notificationId,
          request.command,
          replayed: true,
        );
      },
    );
    final controller = NotificationsController(
      repository: repository,
      canManageLifecycle: true,
      autoLoad: false,
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.dismiss(_firstId), isFalse);
    repository.items = [_notification(_secondId)];

    expect(await controller.retry(_firstId), isTrue);

    expect(repository.loadCalls, 2);
    expect(controller.state.items.map((item) => item.id), [_secondId]);
    expect(controller.state.actionFor(_firstId), isNull);
  });

  test(
      'replay reload failure retains the list and reports refresh failure without historical mutation',
      () async {
    var attempts = 0;
    final repository = _FakeNotificationsRepository(
      items: [_notification(_firstId)],
      onAction: (_, request) async {
        attempts++;
        if (attempts == 1) throw _transportFailure();
        return _result(
          request.notificationId,
          request.command,
          replayed: true,
        );
      },
    );
    final controller = NotificationsController(
      repository: repository,
      canManageLifecycle: true,
      autoLoad: false,
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.markRead(_firstId), isFalse);
    repository.loadError = StateError('current inbox refresh failed');

    expect(await controller.retry(_firstId), isFalse);

    expect(repository.loadCalls, 2);
    expect(controller.state.items.single.isRead, isFalse);
    expect(
      controller.state.items.single.updatedAt,
      DateTime.utc(2026, 7, 10, 8),
    );
    expect(controller.state.actionFor(_firstId), isNull);
    expect(controller.state.loadError, isA<StateError>());
    expect(controller.state.isLoading, isFalse);
  });

  test('definitive conflict requires reload before a new action identity',
      () async {
    var attempts = 0;
    final repository = _FakeNotificationsRepository(
      items: [_notification(_firstId)],
      onAction: (_, request) async {
        attempts++;
        if (attempts == 1) throw _httpFailure(409);
        return _result(
          request.notificationId,
          request.command,
          updatedAt: DateTime.utc(2026, 7, 10, 8, 3),
        );
      },
    );
    final controller = NotificationsController(
      repository: repository,
      canManageLifecycle: true,
      autoLoad: false,
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.markRead(_firstId), isFalse);
    final failedState = controller.state.actionFor(_firstId)!;
    expect(failedState.error, isNotNull);
    expect(failedState.requiresExactRetry, isFalse);
    expect(failedState.requiresReload, isTrue);
    expect(controller.state.items.single.isRead, isFalse);

    expect(await controller.retry(_firstId), isFalse);
    expect(await controller.markRead(_firstId), isFalse);
    expect(await controller.dismiss(_firstId), isFalse);
    expect(repository.requests, hasLength(1));

    repository.items = [
      _notification(
        _firstId,
        updatedAt: DateTime.utc(2026, 7, 10, 8, 2),
      ),
    ];
    await controller.load();

    expect(controller.state.actionFor(_firstId), isNull);
    expect(await controller.markRead(_firstId), isTrue);
    expect(repository.requests, hasLength(2));
    expect(
      repository.requests[1].requestId,
      isNot(repository.requests[0].requestId),
    );
    expect(
      repository.requests[1].expectedUpdatedAt,
      DateTime.utc(2026, 7, 10, 8, 2),
    );
  });

  test('owner-safe not-found requires reload and removes the missing row',
      () async {
    final repository = _FakeNotificationsRepository(
      items: [_notification(_firstId)],
      onAction: (_, __) async => throw _httpFailure(404),
    );
    final controller = NotificationsController(
      repository: repository,
      canManageLifecycle: true,
      autoLoad: false,
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.markRead(_firstId), isFalse);
    final failedState = controller.state.actionFor(_firstId)!;
    expect(failedState.requiresExactRetry, isFalse);
    expect(failedState.requiresReload, isTrue);
    expect(await controller.retry(_firstId), isFalse);
    expect(repository.requests, hasLength(1));

    repository.items = [];
    await controller.load();

    expect(repository.loadCalls, 2);
    expect(controller.state.items, isEmpty);
    expect(controller.state.actionFor(_firstId), isNull);
    expect(controller.state.loadError, isNull);
  });

  test('dismissed row remains visible through failure and leaves after success',
      () async {
    var attempts = 0;
    final repository = _FakeNotificationsRepository(
      items: [_notification(_firstId), _notification(_secondId)],
      onAction: (_, request) async {
        attempts++;
        if (attempts == 1) throw _httpFailure(503);
        return _result(_firstId, NotificationLifecycleCommand.dismiss);
      },
    );
    final controller = NotificationsController(
      repository: repository,
      canManageLifecycle: true,
      autoLoad: false,
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.dismiss(_firstId), isFalse);
    expect(
      controller.state.items.map((item) => item.id),
      [_firstId, _secondId],
    );
    expect(controller.state.actionFor(_firstId)?.error, isNotNull);
    expect(controller.state.actionFor(_secondId), isNull);

    expect(await controller.retry(_firstId), isTrue);

    expect(controller.state.items.map((item) => item.id), [_secondId]);
  });

  test(
      'refresh failure retains the last successful list and exposes load error',
      () async {
    final repository = _FakeNotificationsRepository(
      items: [_notification(_firstId)],
      onAction: (_, request) async =>
          _result(request.notificationId, request.command),
    );
    final controller = NotificationsController(
      repository: repository,
      canManageLifecycle: true,
      autoLoad: false,
    );
    addTearDown(controller.dispose);
    await controller.load();
    repository.loadError = StateError('refresh failed');

    await controller.load();

    expect(controller.state.items.single.id, _firstId);
    expect(controller.state.loadError, isA<StateError>());
    expect(controller.state.isLoading, isFalse);
  });

  test('local demo controller refuses lifecycle work without repository call',
      () async {
    final repository = _FakeNotificationsRepository(
      items: [_notification(_firstId)],
      onAction: (_, request) async =>
          _result(request.notificationId, request.command),
    );
    final controller = NotificationsController(
      repository: repository,
      canManageLifecycle: false,
      autoLoad: false,
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.markRead(_firstId), isFalse);
    expect(await controller.dismiss(_firstId), isFalse);
    expect(repository.requests, isEmpty);
    expect(controller.state.items.single.id, _firstId);
  });

  test('failure classification distinguishes 4xx from ambiguous outcomes', () {
    expect(
      notificationLifecycleFailureRequiresExactRetry(_httpFailure(400)),
      isFalse,
    );
    expect(
      notificationLifecycleFailureRequiresExactRetry(_httpFailure(404)),
      isFalse,
    );
    expect(
      notificationLifecycleFailureRequiresExactRetry(_httpFailure(409)),
      isFalse,
    );
    expect(
      notificationLifecycleFailureRequiresExactRetry(_httpFailure(500)),
      isTrue,
    );
    expect(
      notificationLifecycleFailureRequiresExactRetry(_transportFailure()),
      isTrue,
    );
    expect(
      notificationLifecycleFailureRequiresExactRetry(
        const NotificationLifecycleContractException('invalid response'),
      ),
      isTrue,
    );
    expect(
      notificationLifecycleFailureRequiresReload(_httpFailure(404)),
      isTrue,
    );
    expect(
      notificationLifecycleFailureRequiresReload(_httpFailure(409)),
      isTrue,
    );
    expect(
      notificationLifecycleFailureRequiresReload(_httpFailure(500)),
      isFalse,
    );
    expect(
      notificationLifecycleFailureRequiresReload(_transportFailure()),
      isFalse,
    );
  });
}

AppNotification _notification(
  String id, {
  DateTime? updatedAt,
}) {
  return AppNotification(
    id: id,
    title: 'Notification $id',
    body: 'Stored account item.',
    type: 'reminder',
    priority: 'medium',
    actionUrl: null,
    createdAt: DateTime.utc(2026, 7, 10, 8),
    updatedAt: updatedAt ?? DateTime.utc(2026, 7, 10, 8),
    isRead: false,
    readAt: null,
    dismissedAt: null,
    dueAt: null,
  );
}

NotificationLifecycleResult _result(
  String notificationId,
  NotificationLifecycleCommand command, {
  bool replayed = false,
  DateTime? updatedAt,
}) {
  final isRead = command != NotificationLifecycleCommand.markUnread;
  final dismissed = command == NotificationLifecycleCommand.dismiss;
  final resultUpdatedAt = updatedAt ?? DateTime.utc(2026, 7, 10, 8, 1);
  return NotificationLifecycleResult.fromJson({
    'contract_version': notificationLifecycleContractVersion,
    'notification_id': notificationId,
    'command': command.wireValue,
    'is_read': isRead,
    'read_at': isRead ? resultUpdatedAt.toIso8601String() : null,
    'dismissed_at': dismissed ? resultUpdatedAt.toIso8601String() : null,
    'updated_at': resultUpdatedAt.toIso8601String(),
    'replayed': replayed,
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

class _FakeNotificationsRepository implements NotificationsRepository {
  _FakeNotificationsRepository({required this.items, required this.onAction});

  List<AppNotification> items;
  final Future<NotificationLifecycleResult> Function(
    int attempt,
    NotificationLifecycleRequest request,
  ) onAction;
  final List<NotificationLifecycleRequest> requests = [];
  Object? loadError;
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
  ) {
    requests.add(request);
    return onAction(requests.length, request);
  }
}
