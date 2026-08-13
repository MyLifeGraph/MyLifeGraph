import '../../domain/entities/dashboard_full_week.dart';
import '../../domain/repositories/dashboard_full_week_repository.dart';
import '../datasources/dashboard_full_week_api_data_source.dart';

typedef DashboardFullWeekAccessTokenProvider = Future<String?> Function();

class DashboardFullWeekRepositoryImpl implements DashboardFullWeekRepository {
  const DashboardFullWeekRepositoryImpl({
    required DashboardFullWeekApiDataSource dataSource,
    required DashboardFullWeekAccessTokenProvider accessTokenProvider,
  })  : _dataSource = dataSource,
        _accessTokenProvider = accessTokenProvider;

  final DashboardFullWeekApiDataSource _dataSource;
  final DashboardFullWeekAccessTokenProvider _accessTokenProvider;

  @override
  Future<DashboardFullWeekProjection> getCurrentWeek() async {
    final token = (await _accessTokenProvider())?.trim();
    if (token == null || token.isEmpty) {
      throw const DashboardFullWeekUnavailableException(
        'Your authenticated Full-week session is unavailable.',
      );
    }
    return _dataSource.getCurrentWeek(accessToken: token);
  }
}
