import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../data/datasources/insights_mock_data_source.dart';
import '../../data/datasources/insights_supabase_data_source.dart';
import '../../data/repositories/insights_repository_impl.dart';
import '../../domain/entities/insight.dart';
import '../../domain/repositories/insights_repository.dart';

final insightsMockDataSourceProvider = Provider<InsightsMockDataSource>(
  (_) => const InsightsMockDataSource(),
);

final insightsRepositoryProvider = Provider<InsightsRepository>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    final config = ref.watch(appConfigProvider);
    return InsightsRepositoryImpl(
      mockDataSource: ref.watch(insightsMockDataSourceProvider),
      supabaseDataSource:
          client == null ? null : InsightsSupabaseDataSource(client),
      useMockData: config.useMockData,
    );
  },
);

final insightsProvider = FutureProvider<List<Insight>>(
  (ref) => ref.watch(insightsRepositoryProvider).getInsights(),
);
