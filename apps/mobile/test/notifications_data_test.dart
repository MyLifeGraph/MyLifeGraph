import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/notifications/data/datasources/notifications_api_data_source.dart';
import 'package:my_life_graph/features/notifications/data/datasources/notifications_mock_data_source.dart';
import 'package:my_life_graph/features/notifications/data/datasources/notifications_supabase_data_source.dart';
import 'package:my_life_graph/features/notifications/data/repositories/notifications_repository_impl.dart';
import 'package:my_life_graph/features/notifications/domain/entities/app_notification.dart';
import 'package:my_life_graph/features/notifications/domain/entities/notification_lifecycle.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _notificationId = '11111111-1111-4111-8111-111111111111';
const _requestId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

void main() {
  group('NotificationsSupabaseRowMapper', () {
    const mapper = NotificationsSupabaseRowMapper();

    test('strictly preserves every lifecycle timestamp and source field', () {
      final notification = mapper.fromRow(
        _row(
          id: _notificationId,
          isRead: true,
          readAt: '2026-07-10T08:20:00Z',
          dueAt: '2026-07-10T07:00:00Z',
        ),
      );

      expect(notification.id, _notificationId);
      expect(notification.title, 'Original exact title');
      expect(notification.body, 'Original exact message.');
      expect(notification.type, 'deadline');
      expect(notification.priority, 'critical');
      expect(notification.actionUrl, '/dashboard');
      expect(notification.createdAt, DateTime.parse('2026-07-10T08:15:30Z'));
      expect(notification.updatedAt, DateTime.parse('2026-07-10T08:20:00Z'));
      expect(notification.isRead, isTrue);
      expect(notification.readAt, DateTime.parse('2026-07-10T08:20:00Z'));
      expect(notification.dismissedAt, isNull);
      expect(notification.dueAt, DateTime.parse('2026-07-10T07:00:00Z'));
    });

    test('rejects unknown fields, naive timestamps, and mismatched read state',
        () {
      expect(
        () => mapper.fromRow({..._row(), 'unexpected': true}),
        throwsA(isA<NotificationLifecycleContractException>()),
      );
      expect(
        () => mapper.fromRow(
          _row()..['updated_at'] = '2026-07-10T08:15:30',
        ),
        throwsA(isA<NotificationLifecycleContractException>()),
      );
      expect(
        () => mapper.fromRow(_row(isRead: true, readAt: null)),
        throwsA(isA<NotificationLifecycleContractException>()),
      );
    });

    test('filter intent excludes dismissed and future-due rows defensively',
        () {
      final intent = NotificationsSupabaseQueryIntent.at(
        DateTime.parse('2026-07-10T10:15:30+02:00'),
      );

      expect(
        NotificationsSupabaseQueryIntent.columns,
        contains('updated_at,is_read,read_at,dismissed_at,due_at'),
      );
      expect(
        NotificationsSupabaseQueryIntent.dismissedAtColumn,
        'dismissed_at',
      );
      expect(
        intent.dueAtFilter,
        'due_at.is.null,due_at.lte.2026-07-10T08:15:30.000Z',
      );

      final visible = mapper.visibleFromRows(
        [
          _row(id: '11111111-1111-4111-8111-111111111111'),
          _row(
            id: '22222222-2222-4222-8222-222222222222',
            dueAt: '2026-07-10T08:15:31Z',
          ),
          _row(
            id: '33333333-3333-4333-8333-333333333333',
            isRead: true,
            readAt: '2026-07-10T08:15:30Z',
            dismissedAt: '2026-07-10T08:15:30Z',
          ),
          _row(
            id: '44444444-4444-4444-8444-444444444444',
            dueAt: '2026-07-10T08:15:30Z',
          ),
        ],
        now: intent.nowUtc,
      );

      expect(
        visible.map((item) => item.id),
        [
          '11111111-1111-4111-8111-111111111111',
          '44444444-4444-4444-8444-444444444444',
        ],
      );
    });
  });

  group('NotificationsApiDataSource', () {
    test('serializes every supported lifecycle command exactly', () async {
      for (final command in NotificationLifecycleCommand.values) {
        final client = _RecordingApiClient(
          response: _resultJson(
            notificationId: _notificationId,
            command: command,
          ),
        );
        final request = NotificationLifecycleRequest(
          notificationId: _notificationId,
          requestId: _requestId,
          command: command,
          expectedUpdatedAt: DateTime.parse('2026-07-10T08:15:30Z'),
        );

        final result = await NotificationsApiDataSource(client).performAction(
          accessToken: 'access-token',
          request: request,
        );

        expect(client.body?.keys.toSet(), {
          'contract_version',
          'request_id',
          'command',
          'expected_updated_at',
        });
        expect(client.body?['command'], command.wireValue);
        expect(result.command, command);
      }
    });

    test('posts the exact lifecycle command and parses the strict response',
        () async {
      final client = _RecordingApiClient(
        response: _resultJson(
          notificationId: _notificationId,
          command: NotificationLifecycleCommand.markRead,
        ),
      );
      final source = NotificationsApiDataSource(client);
      final request = NotificationLifecycleRequest(
        notificationId: _notificationId,
        requestId: _requestId,
        command: NotificationLifecycleCommand.markRead,
        expectedUpdatedAt: DateTime.parse('2026-07-10T08:15:30Z'),
      );

      final result = await source.performAction(
        accessToken: 'access-token',
        request: request,
      );

      expect(
        client.path,
        '/v1/notifications/$_notificationId/actions',
      );
      expect(client.headers, {'Authorization': 'Bearer access-token'});
      expect(client.body, {
        'contract_version': notificationLifecycleContractVersion,
        'request_id': _requestId,
        'command': 'mark_read',
        'expected_updated_at': '2026-07-10T08:15:30.000Z',
      });
      expect(result.notificationId, _notificationId);
      expect(result.isRead, isTrue);
      expect(result.readAt, isNotNull);
      expect(result.replayed, isFalse);
    });

    test('rejects unknown or command-incoherent response fields', () async {
      final unknown = _RecordingApiClient(
        response: {
          ..._resultJson(
            notificationId: _notificationId,
            command: NotificationLifecycleCommand.markRead,
          ),
          'extra': true,
        },
      );
      final incoherent = _RecordingApiClient(
        response: {
          ..._resultJson(
            notificationId: _notificationId,
            command: NotificationLifecycleCommand.markRead,
          ),
          'is_read': false,
          'read_at': null,
        },
      );
      final request = NotificationLifecycleRequest(
        notificationId: _notificationId,
        requestId: _requestId,
        command: NotificationLifecycleCommand.markRead,
        expectedUpdatedAt: DateTime.parse('2026-07-10T08:15:30Z'),
      );

      expect(
        NotificationsApiDataSource(unknown).performAction(
          accessToken: 'token',
          request: request,
        ),
        throwsA(isA<NotificationLifecycleContractException>()),
      );
      expect(
        NotificationsApiDataSource(incoherent).performAction(
          accessToken: 'token',
          request: request,
        ),
        throwsA(isA<NotificationLifecycleContractException>()),
      );
    });

    test('rejects response timestamps after updated_at and unread dismiss', () {
      final futureRead = {
        ..._resultJson(
          notificationId: _notificationId,
          command: NotificationLifecycleCommand.markRead,
        ),
        'read_at': '2026-07-10T08:17:00Z',
      };
      final futureDismiss = {
        ..._resultJson(
          notificationId: _notificationId,
          command: NotificationLifecycleCommand.dismiss,
        ),
        'dismissed_at': '2026-07-10T08:17:00Z',
      };
      final unreadDismiss = {
        ..._resultJson(
          notificationId: _notificationId,
          command: NotificationLifecycleCommand.dismiss,
        ),
        'is_read': false,
        'read_at': null,
      };

      for (final json in [futureRead, futureDismiss, unreadDismiss]) {
        expect(
          () => NotificationLifecycleResult.fromJson(json),
          throwsA(isA<NotificationLifecycleContractException>()),
        );
      }
    });
  });

  group('NotificationsRepositoryImpl', () {
    test('uses mock data only when demo data is explicitly allowed', () async {
      final mock = _FakeMockDataSource([_notification(_notificationId)]);
      final remote = _FakeSupabaseDataSource([
        _notification('22222222-2222-4222-8222-222222222222'),
      ]);
      final repository = NotificationsRepositoryImpl(
        mockDataSource: mock,
        supabaseDataSource: remote,
        allowMockData: true,
      );

      final notifications = await repository.getNotifications();

      expect(notifications.single.id, _notificationId);
      expect(mock.calls, 1);
      expect(remote.calls, 0);
    });

    test('returns account data without consulting mock data', () async {
      final mock = _FakeMockDataSource([_notification(_notificationId)]);
      final accountId = '22222222-2222-4222-8222-222222222222';
      final remote = _FakeSupabaseDataSource([_notification(accountId)]);
      final repository = NotificationsRepositoryImpl(
        mockDataSource: mock,
        supabaseDataSource: remote,
        allowMockData: false,
      );

      final notifications = await repository.getNotifications();

      expect(notifications.single.id, accountId);
      expect(mock.calls, 0);
      expect(remote.calls, 1);
    });

    test('propagates account read failures instead of returning empty', () {
      final repository = NotificationsRepositoryImpl(
        mockDataSource: _FakeMockDataSource([_notification(_notificationId)]),
        supabaseDataSource: _FakeSupabaseDataSource(
          const [],
          error: StateError('account read failed'),
        ),
        allowMockData: false,
      );

      expect(repository.getNotifications(), throwsStateError);
    });

    test('matches a real mutation response to the exact request', () async {
      final api = _FakeNotificationsApiDataSource(
        _result(
          notificationId: _notificationId,
          command: NotificationLifecycleCommand.markUnread,
        ),
      );
      var tokenCalls = 0;
      final repository = NotificationsRepositoryImpl(
        mockDataSource: const NotificationsMockDataSource(),
        apiDataSource: api,
        accessTokenProvider: () {
          tokenCalls++;
          return ' account-token ';
        },
        allowMockData: false,
      );
      final request = NotificationLifecycleRequest(
        notificationId: _notificationId,
        requestId: _requestId,
        command: NotificationLifecycleCommand.markUnread,
        expectedUpdatedAt: DateTime.parse('2026-07-10T08:15:30Z'),
      );

      final result = await repository.performLifecycleAction(request);

      expect(result.command, NotificationLifecycleCommand.markUnread);
      expect(api.calls, 1);
      expect(api.accessToken, 'account-token');
      expect(identical(api.request, request), isTrue);
      expect(tokenCalls, 1);
    });

    test('guest/demo mutation is zero-call and cannot consume a token', () {
      final api = _FakeNotificationsApiDataSource(
        _result(
          notificationId: _notificationId,
          command: NotificationLifecycleCommand.dismiss,
        ),
      );
      var tokenCalls = 0;
      final repository = NotificationsRepositoryImpl(
        mockDataSource: const NotificationsMockDataSource(),
        apiDataSource: api,
        accessTokenProvider: () {
          tokenCalls++;
          return 'must-not-be-read';
        },
        allowMockData: true,
      );
      final request = NotificationLifecycleRequest(
        notificationId: _notificationId,
        requestId: _requestId,
        command: NotificationLifecycleCommand.dismiss,
        expectedUpdatedAt: DateTime.parse('2026-07-10T08:15:30Z'),
      );

      expect(
        repository.performLifecycleAction(request),
        throwsA(isA<NotificationsLifecycleAccessException>()),
      );
      expect(api.calls, 0);
      expect(tokenCalls, 0);
    });
  });
}

Map<String, dynamic> _row({
  String id = _notificationId,
  bool isRead = false,
  String? readAt,
  String? dismissedAt,
  String? dueAt,
}) {
  return {
    'id': id,
    'title': 'Original exact title',
    'message': 'Original exact message.',
    'type': 'deadline',
    'priority': 'critical',
    'action_url': '/dashboard',
    'created_at': '2026-07-10T08:15:30Z',
    'updated_at': readAt ?? dismissedAt ?? '2026-07-10T08:15:30Z',
    'is_read': isRead,
    'read_at': readAt,
    'dismissed_at': dismissedAt,
    'due_at': dueAt,
  };
}

AppNotification _notification(String id) {
  return AppNotification(
    id: id,
    title: '$id title',
    body: '$id body',
    type: 'reminder',
    priority: 'medium',
    actionUrl: null,
    createdAt: DateTime.utc(2026, 7, 10, 8, 15, 30),
    updatedAt: DateTime.utc(2026, 7, 10, 8, 15, 30),
    isRead: false,
    readAt: null,
    dismissedAt: null,
    dueAt: null,
  );
}

Map<String, dynamic> _resultJson({
  required String notificationId,
  required NotificationLifecycleCommand command,
  bool replayed = false,
}) {
  final isRead = command != NotificationLifecycleCommand.markUnread;
  final dismissed = command == NotificationLifecycleCommand.dismiss;
  return {
    'contract_version': notificationLifecycleContractVersion,
    'notification_id': notificationId,
    'command': command.wireValue,
    'is_read': isRead,
    'read_at': isRead ? '2026-07-10T08:16:00Z' : null,
    'dismissed_at': dismissed ? '2026-07-10T08:16:00Z' : null,
    'updated_at': '2026-07-10T08:16:00Z',
    'replayed': replayed,
  };
}

NotificationLifecycleResult _result({
  required String notificationId,
  required NotificationLifecycleCommand command,
}) {
  return NotificationLifecycleResult.fromJson(
    _resultJson(notificationId: notificationId, command: command),
  );
}

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient({required this.response}) : super(Dio());

  final Map<String, dynamic> response;
  String? path;
  Map<String, dynamic>? body;
  Map<String, String>? headers;

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    this.path = path;
    this.body = body;
    this.headers = headers;
    return response;
  }
}

class _FakeMockDataSource extends NotificationsMockDataSource {
  _FakeMockDataSource(this.items);

  final List<AppNotification> items;
  int calls = 0;

  @override
  Future<List<AppNotification>> getNotifications() async {
    calls++;
    return items;
  }
}

class _FakeSupabaseDataSource extends NotificationsSupabaseDataSource {
  _FakeSupabaseDataSource(this.items, {this.error})
      : super(SupabaseClient('http://localhost:54321', 'test-anon-key'));

  final List<AppNotification> items;
  final Object? error;
  int calls = 0;

  @override
  Future<List<AppNotification>> getNotifications() async {
    calls++;
    final readError = error;
    if (readError != null) throw readError;
    return items;
  }
}

class _FakeNotificationsApiDataSource extends NotificationsApiDataSource {
  _FakeNotificationsApiDataSource(this.result) : super(ApiClient(Dio()));

  final NotificationLifecycleResult result;
  int calls = 0;
  String? accessToken;
  NotificationLifecycleRequest? request;

  @override
  Future<NotificationLifecycleResult> performAction({
    required String accessToken,
    required NotificationLifecycleRequest request,
  }) async {
    calls++;
    this.accessToken = accessToken;
    this.request = request;
    return result;
  }
}
