import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../auth/domain/app_session.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../application/optimization_service.dart';
import '../../data/datasources/optimization_mock_data_source.dart';
import '../../data/datasources/recommendations_api_data_source.dart';
import '../../data/repositories/optimization_repository_impl.dart';
import '../../domain/entities/recommendation_feed.dart';
import '../../domain/entities/skillset_profile.dart';
import '../../domain/repositories/optimization_repository.dart';

final optimizationMockDataSourceProvider = Provider<OptimizationMockDataSource>(
  (_) => const OptimizationMockDataSource(),
);

final recommendationsApiDataSourceProvider =
    Provider<RecommendationsApiDataSource>(
  (ref) => RecommendationsApiDataSource(ref.watch(apiClientProvider)),
);

final recommendationAccessTokenProvider = Provider<AccessTokenProvider>((ref) {
  return () {
    final config = ref.read(appConfigProvider);
    final session = ref.read(authControllerProvider).valueOrNull;
    if (usesRecommendationDemoData(config: config, session: session)) {
      return null;
    }
    return ref.read(supabaseClientProvider)?.auth.currentSession?.accessToken;
  };
});

final optimizationRepositoryProvider = Provider<OptimizationRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  final session = ref.watch(authControllerProvider).valueOrNull;
  return OptimizationRepositoryImpl(
    config: config,
    mockDataSource: ref.watch(optimizationMockDataSourceProvider),
    recommendationsApiDataSource:
        ref.watch(recommendationsApiDataSourceProvider),
    accessTokenProvider: ref.watch(recommendationAccessTokenProvider),
    allowDemoData: usesRecommendationDemoData(
      config: config,
      session: session,
    ),
  );
});

final optimizationServiceProvider = Provider<OptimizationService>(
  (ref) => OptimizationService(ref.watch(optimizationRepositoryProvider)),
);

final skillsetProfileProvider = FutureProvider<SkillsetProfile>((ref) {
  return ref.watch(optimizationServiceProvider).loadSkillsetProfile();
});

final recommendationFeedProvider = FutureProvider<RecommendationFeed>((ref) {
  return ref.watch(optimizationServiceProvider).loadActionableRecommendations();
});

bool usesRecommendationDemoData({
  required AppConfig config,
  required AppSession? session,
}) {
  if (config.useMockData) {
    return true;
  }
  if (session == null) {
    return false;
  }
  return session.isGuestSession ||
      session.profile.isGuest ||
      session.profile.authProvider == 'guest' ||
      session.profile.email.toLowerCase() == 'demo@personal-coach.local';
}
