import '../../domain/entities/dashboard_snapshot.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/dashboard_mock_data_source.dart';
import '../datasources/dashboard_supabase_data_source.dart';
import '../datasources/today_overview_api_data_source.dart';

typedef TodayAccessTokenProvider = Future<String?> Function();

class DashboardRepositoryImpl implements DashboardRepository {
  const DashboardRepositoryImpl({
    required DashboardMockDataSource mockDataSource,
    DashboardSupabaseDataSource? supabaseDataSource,
    TodayOverviewApiDataSource? todayApiDataSource,
    TodayAccessTokenProvider? accessTokenProvider,
    required bool allowMockData,
  })  : _mockDataSource = mockDataSource,
        _supabaseDataSource = supabaseDataSource,
        _todayApiDataSource = todayApiDataSource,
        _accessTokenProvider = accessTokenProvider,
        _allowMockData = allowMockData;

  final DashboardMockDataSource _mockDataSource;
  final DashboardSupabaseDataSource? _supabaseDataSource;
  final TodayOverviewApiDataSource? _todayApiDataSource;
  final TodayAccessTokenProvider? _accessTokenProvider;
  final bool _allowMockData;

  @override
  Future<DashboardSnapshot> getSnapshot() async {
    if (_allowMockData) {
      return _mockDataSource.getSnapshot();
    }
    final todayApi = _todayApiDataSource;
    final tokenProvider = _accessTokenProvider;
    if (todayApi != null && tokenProvider != null) {
      final token = (await tokenProvider())?.trim();
      if (token == null || token.isEmpty) {
        throw const DashboardUnavailableException(
          'Your authenticated Today session is unavailable.',
        );
      }
      return todayApi.getOverview(accessToken: token);
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
