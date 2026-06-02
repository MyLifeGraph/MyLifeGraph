import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../application/optimization_service.dart';
import '../../data/datasources/optimization_mock_data_source.dart';
import '../../data/repositories/optimization_repository_impl.dart';
import '../../domain/entities/recommendation.dart';
import '../../domain/entities/skillset_profile.dart';
import '../../domain/repositories/optimization_repository.dart';

final optimizationMockDataSourceProvider = Provider<OptimizationMockDataSource>(
  (_) => const OptimizationMockDataSource(),
);

final optimizationRepositoryProvider = Provider<OptimizationRepository>((ref) {
  return OptimizationRepositoryImpl(
    config: ref.watch(appConfigProvider),
    mockDataSource: ref.watch(optimizationMockDataSourceProvider),
    apiClient: ref.watch(apiClientProvider),
  );
});

final optimizationServiceProvider = Provider<OptimizationService>(
  (ref) => OptimizationService(ref.watch(optimizationRepositoryProvider)),
);

final skillsetProfileProvider = FutureProvider<SkillsetProfile>((ref) {
  return ref.watch(optimizationServiceProvider).loadSkillsetProfile();
});

final recommendationsProvider = FutureProvider<List<Recommendation>>((ref) {
  return ref.watch(optimizationServiceProvider).loadActionableRecommendations();
});
