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
    if (_allowMockData || _supabaseDataSource == null) {
      return _mockDataSource.getInsights();
    }

    try {
      final items = await _supabaseDataSource.getInsights();
      return items;
    } catch (_) {
      return const [];
    }
  }
}
