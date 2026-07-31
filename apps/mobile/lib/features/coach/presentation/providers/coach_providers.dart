import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_providers.dart';
import 'package:my_life_graph/composition/auth_providers.dart';
import '../../application/coach_controller.dart';
import '../../application/coach_turn_notice.dart';
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
  final isLocalDemo = ref.watch(
    appSurfaceCapabilitiesProvider.select((value) => value.isLocalDemo),
  );
  final canAccessCoachBackend = ref.watch(
    appSurfaceCapabilitiesProvider.select(
      (value) => value.canAccessCoachBackend,
    ),
  );
  return CoachRepositoryImpl(
    config: ref.watch(appConfigProvider),
    apiDataSource: ref.watch(coachApiDataSourceProvider),
    accessTokenProvider: ref.watch(coachAccessTokenProvider),
    isLocalDemo: isLocalDemo,
    canAccessCoachBackend: canAccessCoachBackend,
  );
});

final coachActiveProfileIdProvider = Provider<String?>((ref) {
  try {
    final profileId = ref.watch(
      authControllerProvider.select(
        (value) => value.valueOrNull?.profile.id,
      ),
    );
    final canAccessCoachBackend = ref.watch(
      appSurfaceCapabilitiesProvider.select(
        (value) => value.canAccessCoachBackend,
      ),
    );
    return canAccessCoachBackend ? profileId : null;
  } on StateError {
    // Standalone widget tests can render shared headers without bootstrapping
    // the whole app. The local notice fails closed in that isolated scope.
    return null;
  }
});

final coachTurnNoticeProvider =
    StateNotifierProvider<CoachTurnNoticeController, CoachTurnNotice?>((ref) {
  return CoachTurnNoticeController(
    profileId: ref.watch(coachActiveProfileIdProvider),
  );
});

final coachControllerProvider =
    StateNotifierProvider<CoachController, CoachState>((ref) {
  final profileId = ref.watch(coachActiveProfileIdProvider);
  return CoachController(
    repository: ref.watch(coachRepositoryProvider),
    profileId: profileId,
    turnNoticeController: ref.read(coachTurnNoticeProvider.notifier),
  );
});
