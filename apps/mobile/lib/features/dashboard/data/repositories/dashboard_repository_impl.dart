import '../../domain/entities/dashboard_snapshot.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/dashboard_mock_data_source.dart';
import '../datasources/dashboard_supabase_data_source.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  const DashboardRepositoryImpl({
    required DashboardMockDataSource mockDataSource,
    DashboardSupabaseDataSource? supabaseDataSource,
    required bool allowMockData,
  })  : _mockDataSource = mockDataSource,
        _supabaseDataSource = supabaseDataSource,
        _allowMockData = allowMockData;

  final DashboardMockDataSource _mockDataSource;
  final DashboardSupabaseDataSource? _supabaseDataSource;
  final bool _allowMockData;

  @override
  Future<DashboardSnapshot> getSnapshot() async {
    if (_allowMockData) {
      return _mockDataSource.getSnapshot();
    }
    final supabaseDataSource = _supabaseDataSource;
    if (supabaseDataSource == null) {
      throw const DashboardUnavailableException(
        'Supabase is not configured for this account.',
      );
    }
    return supabaseDataSource.getSnapshot();
  }
}
