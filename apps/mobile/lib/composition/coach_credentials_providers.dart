import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/capabilities/app_surface_capabilities.dart';
import '../core/network/api_client.dart';
import '../core/supabase/supabase_providers.dart';
import '../features/coach/application/coach_credentials_controller.dart';
import '../features/coach/data/coach_api_data_source.dart';
import '../features/coach/data/coach_credential_store.dart';
import 'auth_providers.dart';

final coachCredentialStoreProvider = Provider<CoachCredentialStore>(
  (_) => PlatformCoachCredentialStore(),
);

final coachCredentialProfileIdProvider = Provider<String?>((ref) {
  final profileId = ref.watch(
    authControllerProvider.select((value) => value.valueOrNull?.profile.id),
  );
  final canAccess = ref.watch(
    appSurfaceCapabilitiesProvider.select(
      (value) => value.canAccessCoachBackend,
    ),
  );
  return canAccess ? profileId : null;
});

final coachCredentialsProvider =
    StateNotifierProvider<CoachCredentialsController, CoachCredentials>((ref) {
  final controller = CoachCredentialsController(
    store: ref.watch(coachCredentialStoreProvider),
    api: CoachApiDataSource(ref.watch(apiClientProvider)),
    accessToken: () async =>
        ref.read(supabaseClientProvider)?.auth.currentSession?.accessToken,
  );
  ref.listen<String?>(
    coachCredentialProfileIdProvider,
    (_, profileId) => controller.setProfile(profileId),
    fireImmediately: true,
  );
  return controller;
});
