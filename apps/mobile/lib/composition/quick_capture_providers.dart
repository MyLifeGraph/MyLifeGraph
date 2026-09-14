import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/capabilities/app_surface_capabilities.dart';
import '../core/errors/app_exception.dart';
import '../core/network/api_client.dart';
import '../core/supabase/supabase_providers.dart';
import '../features/coach/domain/coach.dart';
import '../features/quick_action/data/quick_capture_api_data_source.dart';
import '../features/quick_action/domain/quick_capture_api.dart';
import 'auth_providers.dart';
import 'coach_credentials_providers.dart';

final quickCaptureProfileIdProvider = Provider<String?>((ref) {
  if (!ref.watch(appSurfaceCapabilitiesProvider).canUseSyncedExecution) {
    return null;
  }
  return ref.watch(authControllerProvider).valueOrNull?.profile.id;
});

final quickCaptureApiProvider = Provider<QuickCaptureApi>((ref) {
  final owner = ref.watch(quickCaptureProfileIdProvider);
  return QuickCaptureApiDataSource(ref.watch(apiClientProvider), (
    needsCoach,
  ) async {
    if (owner == null || ref.read(quickCaptureProfileIdProvider) != owner) {
      throw const AppException('Sign in to use cloud capture.');
    }
    if (needsCoach) {
      await ref.read(coachCredentialsProvider.notifier).initialization;
    }
    if (ref.read(quickCaptureProfileIdProvider) != owner) {
      throw const AppException('Your account changed.');
    }
    final session = ref.read(supabaseClientProvider)?.auth.currentSession;
    if (session == null || session.user.id != owner) {
      throw const AppException('Sign in again to continue.');
    }
    final headers = {'Authorization': 'Bearer ${session.accessToken}'};
    if (needsCoach) {
      final credentials = ref.read(coachCredentialsProvider);
      final provider = credentials.provider;
      if (credentials.profileId != owner || provider == null) {
        throw const AppException('Choose a Coach in Settings first.');
      }
      headers['X-MyLifeGraph-Coach-Provider'] = provider.code;
      if (provider != CoachProviderName.operatorCodexPilot) {
        final key = credentials.activeKey;
        if (key == null || key.isEmpty) {
          throw const AppException('Add your Coach API key in Settings first.');
        }
        headers['X-MyLifeGraph-Coach-Api-Key'] = key;
      }
    }
    return headers;
  });
});
