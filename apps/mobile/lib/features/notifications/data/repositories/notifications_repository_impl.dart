import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notifications_repository.dart';
import '../datasources/notifications_mock_data_source.dart';
import '../datasources/notifications_supabase_data_source.dart';

class NotificationsRepositoryImpl implements NotificationsRepository {
  const NotificationsRepositoryImpl({
    required NotificationsMockDataSource mockDataSource,
    NotificationsSupabaseDataSource? supabaseDataSource,
    required bool allowMockData,
  })  : _mockDataSource = mockDataSource,
        _supabaseDataSource = supabaseDataSource,
        _allowMockData = allowMockData;

  final NotificationsMockDataSource _mockDataSource;
  final NotificationsSupabaseDataSource? _supabaseDataSource;
  final bool _allowMockData;

  @override
  Future<List<AppNotification>> getNotifications() async {
    if (_allowMockData) {
      return _mockDataSource.getNotifications();
    }

    final supabaseDataSource = _supabaseDataSource;
    if (supabaseDataSource == null) {
      throw StateError(
        'Authenticated notifications require a Supabase data source.',
      );
    }

    return supabaseDataSource.getNotifications();
  }
}
