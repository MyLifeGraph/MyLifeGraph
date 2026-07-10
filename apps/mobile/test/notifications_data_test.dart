import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/notifications/data/datasources/notifications_mock_data_source.dart';
import 'package:my_life_graph/features/notifications/data/datasources/notifications_supabase_data_source.dart';
import 'package:my_life_graph/features/notifications/data/repositories/notifications_repository_impl.dart';
import 'package:my_life_graph/features/notifications/domain/entities/app_notification.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('NotificationsSupabaseRowMapper', () {
    const mapper = NotificationsSupabaseRowMapper();

    test('preserves original notification fields', () {
      final notification = mapper.fromRow({
        'id': 'notification-exact',
        'title': 'Original exact title',
        'message': 'Original exact message.',
        'type': 'deadline',
        'priority': 'critical',
        'action_url': '/dashboard',
        'created_at': '2026-07-10T08:15:30Z',
        'is_read': true,
      });

      expect(notification.id, 'notification-exact');
      expect(notification.title, 'Original exact title');
      expect(notification.body, 'Original exact message.');
      expect(notification.type, 'deadline');
      expect(notification.priority, 'critical');
      expect(notification.actionUrl, '/dashboard');
      expect(notification.createdAt, DateTime.parse('2026-07-10T08:15:30Z'));
      expect(notification.isRead, isTrue);
    });

    test('rejects an invalid source timestamp instead of inventing now', () {
      expect(
        () => mapper.fromRow({
          'id': 'notification-invalid-time',
          'title': 'Title',
          'message': 'Message',
          'type': 'reminder',
          'priority': 'medium',
          'action_url': null,
          'created_at': 'not-a-timestamp',
          'is_read': false,
        }),
        throwsFormatException,
      );
    });
  });

  group('NotificationsRepositoryImpl', () {
    test('uses mock data only when demo data is explicitly allowed', () async {
      final mock = _FakeMockDataSource([_notification('demo')]);
      final remote = _FakeSupabaseDataSource([_notification('account')]);
      final repository = NotificationsRepositoryImpl(
        mockDataSource: mock,
        supabaseDataSource: remote,
        allowMockData: true,
      );

      final notifications = await repository.getNotifications();

      expect(notifications.single.id, 'demo');
      expect(mock.calls, 1);
      expect(remote.calls, 0);
    });

    test('returns account data without consulting mock data', () async {
      final mock = _FakeMockDataSource([_notification('demo')]);
      final remote = _FakeSupabaseDataSource([_notification('account')]);
      final repository = NotificationsRepositoryImpl(
        mockDataSource: mock,
        supabaseDataSource: remote,
        allowMockData: false,
      );

      final notifications = await repository.getNotifications();

      expect(notifications.single.id, 'account');
      expect(mock.calls, 0);
      expect(remote.calls, 1);
    });

    test('propagates account read failures instead of returning empty', () {
      final repository = NotificationsRepositoryImpl(
        mockDataSource: _FakeMockDataSource([_notification('demo')]),
        supabaseDataSource: _FakeSupabaseDataSource(
          const [],
          error: StateError('account read failed'),
        ),
        allowMockData: false,
      );

      expect(repository.getNotifications(), throwsStateError);
    });

    test('missing account data source is an error, not demo data', () {
      final repository = NotificationsRepositoryImpl(
        mockDataSource: _FakeMockDataSource([_notification('demo')]),
        supabaseDataSource: null,
        allowMockData: false,
      );

      expect(repository.getNotifications(), throwsStateError);
    });
  });
}

AppNotification _notification(String id) {
  return AppNotification(
    id: id,
    title: '$id title',
    body: '$id body',
    type: 'reminder',
    priority: 'medium',
    actionUrl: null,
    createdAt: DateTime.utc(2026, 7, 10),
    isRead: false,
  );
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
    if (readError != null) {
      throw readError;
    }
    return items;
  }
}
