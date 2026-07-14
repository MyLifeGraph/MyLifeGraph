import '../../domain/entities/correlation.dart';
import '../../domain/entities/insight.dart';
import '../../domain/repositories/insights_repository.dart';
import '../datasources/insights_mock_data_source.dart';
import '../datasources/insights_supabase_data_source.dart';

class InsightsRepositoryImpl implements InsightsRepository {
  const InsightsRepositoryImpl({
    required InsightsMockDataSource mockDataSource,
    InsightsSupabaseDataSource? supabaseDataSource,
    required bool allowMockData,
  })  : _mockDataSource = mockDataSource,
        _supabaseDataSource = supabaseDataSource,
        _allowMockData = allowMockData;

  final InsightsMockDataSource _mockDataSource;
  final InsightsSupabaseDataSource? _supabaseDataSource;
  final bool _allowMockData;

  @override
  Future<List<Insight>> getInsights() async {
    if (_allowMockData) {
      return _mockDataSource.getInsights();
    }
    final source = _supabaseDataSource;
    if (source == null) {
      throw StateError('Account insights are not configured.');
    }

    return source.getInsights();
  }

  @override
  Future<List<CorrelationDataPoint>> getCorrelationDataPoints({
    required int windowDays,
  }) async {
    final boundedWindowDays = normalizeInsightsWindowDays(windowDays);
    if (_allowMockData) {
      return _mockDataSource.getCorrelationDataPoints(
        windowDays: boundedWindowDays,
      );
    }
    final source = _supabaseDataSource;
    if (source == null) {
      throw StateError('Account insight correlations are not configured.');
    }

    return source.getCorrelationDataPoints(windowDays: boundedWindowDays);
  }
}
