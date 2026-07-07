import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/insights/data/datasources/insights_mock_data_source.dart';
import 'package:my_life_graph/features/insights/data/datasources/insights_supabase_data_source.dart';
import 'package:my_life_graph/features/insights/data/repositories/insights_repository_impl.dart';
import 'package:my_life_graph/features/insights/domain/entities/correlation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('uses mock correlation points only when mock mode is allowed', () async {
    final repository = InsightsRepositoryImpl(
      mockDataSource: const _SentinelMockDataSource(),
      supabaseDataSource: _EmptySupabaseDataSource(),
      allowMockData: true,
    );

    final points = await repository.getCorrelationDataPoints(windowDays: 14);

    expect(points, hasLength(1));
    expect(points.single.values['sleep_hours'], 7.5);
  });

  test('does not substitute mock points for an empty real source', () async {
    final repository = InsightsRepositoryImpl(
      mockDataSource: const _SentinelMockDataSource(),
      supabaseDataSource: _EmptySupabaseDataSource(),
      allowMockData: false,
    );

    final points = await repository.getCorrelationDataPoints(windowDays: 14);

    expect(points, isEmpty);
  });

  test('does not substitute mock points when a real source fails', () async {
    final repository = InsightsRepositoryImpl(
      mockDataSource: const _SentinelMockDataSource(),
      supabaseDataSource: _ThrowingSupabaseDataSource(),
      allowMockData: false,
    );

    final points = await repository.getCorrelationDataPoints(windowDays: 14);

    expect(points, isEmpty);
  });

  test('returns empty real points when Supabase is unavailable', () async {
    final repository = InsightsRepositoryImpl(
      mockDataSource: const _SentinelMockDataSource(),
      allowMockData: false,
    );

    final points = await repository.getCorrelationDataPoints(windowDays: 14);

    expect(points, isEmpty);
  });
}

class _SentinelMockDataSource extends InsightsMockDataSource {
  const _SentinelMockDataSource();

  @override
  Future<List<CorrelationDataPoint>> getCorrelationDataPoints({
    required int windowDays,
  }) async {
    return [
      CorrelationDataPoint(
        date: DateTime(2026, 7, 7),
        values: const {'sleep_hours': 7.5},
      ),
    ];
  }
}

class _EmptySupabaseDataSource extends InsightsSupabaseDataSource {
  _EmptySupabaseDataSource() : super(_testSupabaseClient());

  @override
  Future<List<CorrelationDataPoint>> getCorrelationDataPoints({
    required int windowDays,
  }) async {
    return const [];
  }
}

class _ThrowingSupabaseDataSource extends InsightsSupabaseDataSource {
  _ThrowingSupabaseDataSource() : super(_testSupabaseClient());

  @override
  Future<List<CorrelationDataPoint>> getCorrelationDataPoints({
    required int windowDays,
  }) async {
    throw StateError('real source failed');
  }
}

SupabaseClient _testSupabaseClient() {
  return SupabaseClient('http://localhost:54321', 'test-anon-key');
}
