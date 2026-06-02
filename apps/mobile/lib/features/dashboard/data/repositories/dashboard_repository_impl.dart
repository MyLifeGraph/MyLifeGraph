import '../../domain/entities/dashboard_snapshot.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/dashboard_mock_data_source.dart';
import '../datasources/dashboard_supabase_data_source.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  const DashboardRepositoryImpl({
    required DashboardMockDataSource mockDataSource,
    DashboardSupabaseDataSource? supabaseDataSource,
    required bool useMockData,
  })  : _mockDataSource = mockDataSource,
        _supabaseDataSource = supabaseDataSource,
        _useMockData = useMockData;

  final DashboardMockDataSource _mockDataSource;
  final DashboardSupabaseDataSource? _supabaseDataSource;
  final bool _useMockData;

  @override
  Future<DashboardSnapshot> getSnapshot() async {
    if (_useMockData || _supabaseDataSource == null) {
      return _mockDataSource.getSnapshot();
    }

    try {
      return await _supabaseDataSource.getSnapshot();
    } catch (_) {
      return _mockDataSource.getSnapshot();
    }
  }
}
