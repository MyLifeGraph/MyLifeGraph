import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/supabase/supabase_providers.dart';
import '../features/auth/domain/app_session.dart';
import '../features/optimization/application/optimization_service.dart';
import '../features/optimization/data/datasources/optimization_mock_data_source.dart';
import '../features/optimization/data/datasources/skillset_profile_supabase_data_source.dart';
import '../features/optimization/data/repositories/optimization_repository_impl.dart';
import '../features/optimization/domain/entities/skillset_profile.dart';
import '../features/optimization/domain/repositories/optimization_repository.dart';
import 'package:my_life_graph/composition/auth_providers.dart';

final optimizationMockDataSourceProvider = Provider<OptimizationMockDataSource>(
  (_) => const OptimizationMockDataSource(),
);

final optimizationRepositoryProvider = Provider<OptimizationRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  final session = ref.watch(authControllerProvider).valueOrNull;
  final client = ref.watch(supabaseClientProvider);
  return OptimizationRepositoryImpl(
    config: config,
    mockDataSource: ref.watch(optimizationMockDataSourceProvider),
    skillsetProfileLoader: client == null
        ? null
        : SkillsetProfileSupabaseDataSource(client).getLatestProfile,
    allowDemoData: usesOptimizationDemoData(
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

bool usesOptimizationDemoData({
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
