import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../data/datasources/personal_patterns_api_data_source.dart';
import '../../data/datasources/sleep_recommendation_api_data_source.dart';
import '../../data/datasources/insights_mock_data_source.dart';
import '../../data/datasources/insights_supabase_data_source.dart';
import '../../data/repositories/insights_repository_impl.dart';
import '../../domain/entities/correlation.dart';
import '../../domain/entities/insight.dart';
import '../../domain/entities/personal_patterns.dart';
import '../../domain/entities/sleep_recommendation.dart';
import '../../domain/repositories/insights_repository.dart';
import '../../domain/services/correlation_analyzer.dart';

final insightsMockDataSourceProvider = Provider<InsightsMockDataSource>(
  (_) => const InsightsMockDataSource(),
);

final insightsRepositoryProvider = Provider<InsightsRepository>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    final allowMockData = ref.watch(appSurfaceCapabilitiesProvider).isLocalDemo;
    return InsightsRepositoryImpl(
      mockDataSource: ref.watch(insightsMockDataSourceProvider),
      supabaseDataSource:
          client == null ? null : InsightsSupabaseDataSource(client),
      allowMockData: allowMockData,
    );
  },
);

final insightsProvider = FutureProvider<List<Insight>>(
  (ref) => ref.watch(insightsRepositoryProvider).getInsights(),
);

final personalPatternsApiDataSourceProvider =
    Provider<PersonalPatternsApiDataSource>(
  (ref) => PersonalPatternsApiDataSource(ref.watch(apiClientProvider)),
);

final personalPatternsProvider = FutureProvider<PersonalPatterns?>((ref) async {
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  if (capabilities.isLocalDemo) return null;
  final token =
      ref.watch(supabaseClientProvider)?.auth.currentSession?.accessToken;
  if (token == null || token.isEmpty) {
    throw StateError('Personal patterns require an authenticated account.');
  }
  return ref.watch(personalPatternsApiDataSourceProvider).getPersonalPatterns(
        accessToken: token,
      );
});

final sleepRecommendationApiDataSourceProvider =
    Provider<SleepRecommendationApiDataSource>(
  (ref) => SleepRecommendationApiDataSource(ref.watch(apiClientProvider)),
);

final sleepRecommendationProvider =
    FutureProvider<SleepRecommendation?>((ref) async {
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  if (capabilities.isLocalDemo) return null;
  final token =
      ref.watch(supabaseClientProvider)?.auth.currentSession?.accessToken;
  if (token == null || token.isEmpty) {
    throw StateError('Sleep recommendations require an authenticated account.');
  }
  return ref
      .watch(sleepRecommendationApiDataSourceProvider)
      .getSleepRecommendation(accessToken: token);
});

final insightsWindowDaysProvider = StateProvider<int>((_) => 14);

final correlationAnalyzerProvider = Provider<CorrelationAnalyzer>(
  (_) => const CorrelationAnalyzer(),
);

final correlationReportProvider =
    FutureProvider<CorrelationReport>((ref) async {
  final windowDays = normalizeInsightsWindowDays(
    ref.watch(insightsWindowDaysProvider),
  );
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  final points = capabilities.isLocalDemo
      ? await ref
          .watch(insightsRepositoryProvider)
          .getCorrelationDataPoints(windowDays: windowDays)
      : ref
              .watch(personalPatternsProvider)
              .valueOrNull
              ?.correlationDataPoints(windowDays: windowDays) ??
          const <CorrelationDataPoint>[];
  return ref.watch(correlationAnalyzerProvider).analyze(
        windowDays: windowDays,
        points: points,
      );
});
