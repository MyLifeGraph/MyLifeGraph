import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/datasources/insights_mock_data_source.dart';
import '../../data/datasources/insights_supabase_data_source.dart';
import '../../data/repositories/insights_repository_impl.dart';
import '../../domain/entities/correlation.dart';
import '../../domain/entities/insight.dart';
import '../../domain/repositories/insights_repository.dart';
import '../../domain/services/correlation_analyzer.dart';

final insightsMockDataSourceProvider = Provider<InsightsMockDataSource>(
  (_) => const InsightsMockDataSource(),
);

final insightsRepositoryProvider = Provider<InsightsRepository>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    final config = ref.watch(appConfigProvider);
    final session = ref.watch(authControllerProvider).valueOrNull;
    final allowMockData = session == null
        ? config.useMockData
        : session.isGuestSession ||
            session.profile.authProvider == 'guest' ||
            session.profile.email == 'demo@personal-coach.local';
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

final insightsWindowDaysProvider = StateProvider<int>((_) => 14);

final correlationAnalyzerProvider = Provider<CorrelationAnalyzer>(
  (_) => const CorrelationAnalyzer(),
);

final correlationReportProvider =
    FutureProvider<CorrelationReport>((ref) async {
  final windowDays = ref.watch(insightsWindowDaysProvider);
  final points = await ref
      .watch(insightsRepositoryProvider)
      .getCorrelationDataPoints(windowDays: windowDays);
  return ref.watch(correlationAnalyzerProvider).analyze(
        windowDays: windowDays,
        points: points,
      );
});
