import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../application/learning_settings_controller.dart';
import '../../data/learning_api_data_source.dart';
import '../../data/learning_repository_impl.dart';
import '../../domain/learning_repository.dart';

final learningApiDataSourceProvider = Provider<LearningApiDataSource>(
  (ref) => LearningApiDataSource(ref.watch(apiClientProvider)),
);

final learningRepositoryProvider = Provider<LearningRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  return LearningRepositoryImpl(
    config: ref.watch(appConfigProvider),
    api: ref.watch(learningApiDataSourceProvider),
    accessTokenProvider: () async => client?.auth.currentSession?.accessToken,
    canUseSyncedLearning: capabilities.canUseSyncedExecution,
  );
});

final learningSettingsProvider = StateNotifierProvider.autoDispose<
    LearningSettingsController, LearningSettingsState>(
  (ref) => LearningSettingsController(
    repository: ref.watch(learningRepositoryProvider),
  ),
);
