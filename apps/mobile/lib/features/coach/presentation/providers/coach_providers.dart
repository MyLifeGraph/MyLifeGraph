import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/preferences/assistant_language.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_providers.dart';
import 'package:my_life_graph/composition/auth_providers.dart';
import 'package:my_life_graph/composition/coach_credentials_providers.dart';
import 'package:my_life_graph/composition/coach_response_cancellation.dart';
import '../../application/coach_controller.dart';
import '../../application/speech_settings.dart';
import '../../domain/speech_models.dart';
import '../../application/coach_turn_notice.dart';
import '../../data/coach_api_data_source.dart';
import '../../data/coach_dictation_request_impl.dart';
import '../../data/coach_repository_impl.dart';
import '../../domain/coach.dart';
import '../../domain/coach_dictation_request.dart';
import '../../domain/coach_repository.dart';

final coachApiDataSourceProvider = Provider<CoachApiDataSource>(
  (ref) => CoachApiDataSource(ref.watch(apiClientProvider)),
);

final coachAccessTokenProvider = Provider<CoachAccessTokenProvider>(
  (ref) => () {
    final owner = ref.read(coachActiveProfileIdProvider);
    final session = ref.read(supabaseClientProvider)?.auth.currentSession;
    // The session can switch before the app finishes loading the new profile.
    // Never send the previous profile's draft/audio with the next account's token.
    if (owner == null || session == null || session.user.id != owner) {
      return null;
    }
    return session.accessToken;
  },
);

final coachDictationRequestFactoryProvider =
    Provider<CoachDictationRequest Function()>((ref) {
  return () {
    final speech = ref.read(speechSettingsProvider);
    if (speech.loading || speech.initializationFailed) throw StateError('Speech settings unavailable');
    if (speech.source != 'server') {
      return OnDeviceDictationRequest(speech.store, speechModel(speech.source));
    }
    const override = String.fromEnvironment('SPEECH_SERVICE_BASE_URL');
    return CoachDictationRequestImpl(
      baseUrl: override.isEmpty
          ? ref.read(appConfigProvider).aiServiceBaseUrl
          : override,
    );
  };
});

final coachRepositoryProvider = Provider<CoachRepository>((ref) {
  final isLocalDemo = ref.watch(
    appSurfaceCapabilitiesProvider.select((value) => value.isLocalDemo),
  );
  final canAccessCoachBackend = ref.watch(
    appSurfaceCapabilitiesProvider.select(
      (value) => value.canAccessCoachBackend,
    ),
  );
  final repository = CoachRepositoryImpl(
    config: ref.watch(appConfigProvider),
    apiDataSource: ref.watch(coachApiDataSourceProvider),
    accessTokenProvider: ref.watch(coachAccessTokenProvider),
    isLocalDemo: isLocalDemo,
    canAccessCoachBackend: canAccessCoachBackend,
    credentialsProvider: () async {
      // The first capability read must wait for the default selection and keys.
      await ref.read(coachCredentialsProvider.notifier).initialization;
      final credentials = ref.read(coachCredentialsProvider);
      final provider = credentials.provider;
      final key = credentials.activeKey;
      if (credentials.profileId == null || provider == null) {
        return null;
      }
      if (provider == CoachProviderName.operatorCodexPilot) {
        return const CoachProviderCredentials(
          provider: CoachProviderName.operatorCodexPilot,
        );
      }
      if (key == null || key.isEmpty) return null;
      return CoachProviderCredentials(
        provider: provider,
        apiKey: key,
        model: provider == CoachProviderName.gemini ? credentials.geminiModel : null,
      );
    },
  );
  final cancellation = ref.read(coachResponseCancellationAuthorityProvider);
  final registration = cancellation.register(repository.cancelActiveResponse);
  ref.onDispose(() => cancellation.unregister(registration));
  return repository;
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

// Memory-only disclosure acknowledgement for the current signed-in app session.
// Profile loss/change resets it; navigating away from Coach does not.
final coachDictationConsentProvider = StateProvider<bool>((ref) {
  ref.watch(coachActiveProfileIdProvider);
  return false;
});

// Dictation can be tested without a hosted Project Coach on the dev stack.
// A downloaded on-device model can also fill a signed-in draft while Coach is
// unavailable. This does not enable sending, guest access, or server uploads.
final coachLocalDictationProvider = Provider<bool>((ref) {
  try {
    final config = ref.watch(appConfigProvider);
    if (config.useMockData || ref.watch(coachActiveProfileIdProvider) == null) return false;
    final speech = ref.watch(speechSettingsProvider);
    final localReady = !speech.loading && !speech.initializationFailed &&
        speech.supported && speech.source != 'server' && speech.installed.contains(speech.source);
    return config.environment == 'development' || localReady;
  } on StateError {
    return false;
  }
});

final coachControllerProvider =
    StateNotifierProvider<CoachController, CoachState>((ref) {
  final profileId = ref.watch(coachActiveProfileIdProvider);
  return CoachController(
    repository: ref.watch(coachRepositoryProvider),
    profileId: profileId,
    turnNoticeController: ref.read(coachTurnNoticeProvider.notifier),
    responseLanguage: () async {
      final language = ref.read(assistantLanguageProvider('coach'));
      await language.ready;
      if (language.failed || language.loading) {
        throw const CoachInputException('Wait for the response language to load.');
      }
      return language.value;
    },
  );
});

final coachOnDeviceDictationConsentProvider = StateProvider<bool>((ref) {
  ref.watch(coachActiveProfileIdProvider);
  return false;
});
