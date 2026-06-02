import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notifications_repository.dart';
import '../datasources/notifications_mock_data_source.dart';
import '../datasources/notifications_supabase_data_source.dart';

class NotificationsRepositoryImpl implements NotificationsRepository {
  const NotificationsRepositoryImpl({
    required NotificationsMockDataSource mockDataSource,
    NotificationsSupabaseDataSource? supabaseDataSource,
    required bool useMockData,
  })  : _mockDataSource = mockDataSource,
        _supabaseDataSource = supabaseDataSource,
        _useMockData = useMockData;

  final NotificationsMockDataSource _mockDataSource;
  final NotificationsSupabaseDataSource? _supabaseDataSource;
  final bool _useMockData;

  @override
  Future<List<AppNotification>> getNotifications() async {
    if (_useMockData || _supabaseDataSource == null) {
      return _mockDataSource.getNotifications();
    }

    try {
      final items = await _supabaseDataSource.getNotifications();
      return items.isEmpty ? _mockDataSource.getNotifications() : items;
    } catch (_) {
      return _mockDataSource.getNotifications();
    }
  }
}
