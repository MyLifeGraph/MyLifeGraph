import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../application/coach_controller.dart';
import '../../data/coach_api_data_source.dart';
import '../../data/coach_repository_impl.dart';
import '../../domain/coach_repository.dart';

final coachApiDataSourceProvider = Provider<CoachApiDataSource>(
  (ref) => CoachApiDataSource(ref.watch(apiClientProvider)),
);

final coachAccessTokenProvider = Provider<CoachAccessTokenProvider>(
  (ref) =>
      () => ref.read(supabaseClientProvider)?.auth.currentSession?.accessToken,
);

final coachRepositoryProvider = Provider<CoachRepository>((ref) {
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  return CoachRepositoryImpl(
    config: ref.watch(appConfigProvider),
    apiDataSource: ref.watch(coachApiDataSourceProvider),
    accessTokenProvider: ref.watch(coachAccessTokenProvider),
    isLocalDemo: capabilities.isLocalDemo,
    canAccessCoachBackend: capabilities.canAccessCoachBackend,
  );
});

final coachControllerProvider =
    StateNotifierProvider.autoDispose<CoachController, CoachState>((ref) {
  return CoachController(repository: ref.watch(coachRepositoryProvider));
});
