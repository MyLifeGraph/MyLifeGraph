import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/contracts/account_deletion.dart';
import '../core/network/api_client.dart';
import '../core/supabase/supabase_providers.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/data/guest_setup_data_source.dart';
import '../features/auth/data/intake_api_data_source.dart';
import '../features/auth/data/pilot_participation_api_data_source.dart';
import '../features/auth/domain/app_session.dart';
import '../features/quick_action/data/guest_quick_check_in_data_source.dart';
import '../features/quick_action/data/quick_check_in_supabase_data_source.dart';
import 'coach_credential_store_provider.dart';
import 'coach_response_cancellation.dart';
import 'account_deletion_providers.dart';

Future<void> _noSecretCleanup() async {}
void _noCoachCancellation() {}

final intakeApiDataSourceProvider = Provider<IntakeApiDataSource>(
  (ref) => IntakeApiDataSource(ref.watch(apiClientProvider)),
);

final authRepositoryProvider = Provider<AuthRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? null
      : AuthRepository(
          client,
          useMockData: ref.watch(appConfigProvider).useMockData,
          guestSetupDataSource: const GuestSetupDataSource(),
          pilotParticipationGateway: PilotParticipationApiDataSource(
            ref.watch(apiClientProvider),
          ),
          requiresPilotParticipation:
              ref.watch(appConfigProvider).requiresPilotParticipation,
          requiresAuthCaptcha: ref.watch(appConfigProvider).requiresAuthCaptcha,
          pendingAccountDeletionResolver: ({
            required userId,
            required accessToken,
          }) =>
              ref.read(accountDeletionCoordinatorProvider).resume(
                    userId: userId,
                    accessToken: accessToken,
                  ),
          guestCheckInMigrator: (userId) async {
            final local = GuestQuickCheckInDataSource();
            final entries = await local.readAll();
            final remote = QuickCheckInSupabaseDataSource(
              client,
              apiClient: ref.read(apiClientProvider),
            );
            for (final entry in entries) {
              if (entry.evening == null && entry.morning == null) {
                return;
              }
              await remote.mergeEntryForUser(
                userId: userId,
                entry: entry,
              );
            }
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove(GuestQuickCheckInDataSource.storageKey);
          },
        );
});

const passwordRecoveryActivePreferenceKey = 'auth_password_recovery_active';

final passwordRecoveryActiveProvider = StateProvider<bool>((_) => false);
final authNoticeProvider = StateProvider<AuthNotice?>((_) => null);

class AuthNotice {
  const AuthNotice(this.message, {this.isError = false});

  final String message;
  final bool isError;
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<AppSession?>>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthController(
    repository,
    clearCoachCredentials: () =>
        ref.read(coachCredentialStoreProvider).deleteAllCoachCredentials(),
    cancelCoachResponse: () =>
        ref.read(coachResponseCancellationAuthorityProvider).cancel(),
    onPasswordRecoveryStateChanged: (active) {
      ref.read(passwordRecoveryActiveProvider.notifier).state = active;
    },
  );
});

class AuthController extends StateNotifier<AsyncValue<AppSession?>> {
  AuthController(
    this._repository, {
    void Function(bool active)? onPasswordRecoveryStateChanged,
    Future<void> Function()? clearCoachCredentials,
    void Function()? cancelCoachResponse,
  })  : _onPasswordRecoveryStateChanged = onPasswordRecoveryStateChanged,
        _clearCoachCredentials = clearCoachCredentials ?? _noSecretCleanup,
        _cancelCoachResponse = cancelCoachResponse ?? _noCoachCancellation,
        super(const AsyncValue.loading()) {
    unawaited(_load());
    _subscription = _repository?.authStateChanges.listen(_handleAuthChange);
  }

  final AuthRepository? _repository;
  final void Function(bool active)? _onPasswordRecoveryStateChanged;
  final Future<void> Function() _clearCoachCredentials;
  final void Function() _cancelCoachResponse;
  StreamSubscription<dynamic>? _subscription;
  Future<void> _recoveryWriteTail = Future<void>.value();
  bool _recoveryStateRestored = false;
  bool _recoveryChangedDuringRestore = false;
  int _authGeneration = 0;
  int? _terminalTransitionGeneration;

  void _handleAuthChange(AuthState change) {
    if (change.event == AuthChangeEvent.passwordRecovery) {
      _recoveryChangedDuringRestore = true;
      _onPasswordRecoveryStateChanged?.call(true);
      unawaited(_persistPasswordRecoveryActive(true));
    }
    if (_terminalTransitionGeneration == null) {
      unawaited(refresh());
    }
  }

  Future<void> _load() async {
    final generation = ++_authGeneration;
    if (!_recoveryStateRestored) {
      await _restorePasswordRecoveryState();
      _recoveryStateRestored = true;
    }
    if (_repository == null) {
      final session = await _localGuestSession();
      if (_canCommit(generation)) state = AsyncValue.data(session);
      return;
    }
    try {
      final session = await _repository.currentSession();
      if (_canCommit(generation)) state = AsyncValue.data(session);
    } catch (error, stackTrace) {
      if (_canCommit(generation)) {
        state = AsyncValue.error(error, stackTrace);
      }
    }
  }

  Future<void> refresh() => _load();

  Future<void> signInWithEmail({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    final generation = ++_authGeneration;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(
      () => _requireRepository().signInWithEmail(
        email: email,
        password: password,
        captchaToken: captchaToken,
      ),
    );
    if (_canCommit(generation)) state = result;
  }

  Future<bool> registerWithEmail({
    required String email,
    required String password,
    String? name,
    bool confirmed18OrOlder = false,
    String? captchaToken,
  }) async {
    final generation = ++_authGeneration;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(
      () => _requireRepository().registerWithEmail(
        email: email,
        password: password,
        name: name,
        confirmed18OrOlder: confirmed18OrOlder,
        captchaToken: captchaToken,
      ),
    );
    if (!_canCommit(generation)) return false;
    state = result;
    return result.valueOrNull != null;
  }

  Future<void> signInWithGoogle({bool confirmed18OrOlder = false}) async {
    _authGeneration += 1;
    final repository = _requireRepository();
    await repository.signInWithGoogle(
      confirmed18OrOlder: confirmed18OrOlder,
    );
  }

  Future<void> acceptCurrentPilotParticipation() async {
    final session = state.valueOrNull;
    if (session == null || session.isGuestSession) {
      throw StateError('A synced account session is required.');
    }
    final generation = ++_authGeneration;
    final profile =
        await _requireRepository().acceptCurrentPilotParticipation();
    if (_canCommit(generation)) {
      state = AsyncValue.data(AppSession.authenticated(profile));
    }
  }

  Future<void> requestPasswordReset({
    required String email,
    String? captchaToken,
  }) {
    return _requireRepository().requestPasswordReset(
      email: email,
      captchaToken: captchaToken,
    );
  }

  Future<void> resendSignupConfirmation({
    required String email,
    String? captchaToken,
  }) {
    return _requireRepository().resendSignupConfirmation(
      email: email,
      captchaToken: captchaToken,
    );
  }

  Future<PasswordRecoveryCompletion> completePasswordRecovery({
    required String password,
  }) async {
    final generation = ++_authGeneration;
    await _requireRepository().updatePassword(password: password);
    if (!_canCommit(generation)) {
      return PasswordRecoveryCompletion.updatedSessionUnavailable;
    }
    await refresh();
    return !state.hasError
        ? PasswordRecoveryCompletion.updated
        : PasswordRecoveryCompletion.updatedSessionUnavailable;
  }

  Future<bool> finalizePasswordRecovery() => _setPasswordRecoveryActive(false);

  Future<void> continueAsGuest() async {
    final generation = ++_authGeneration;
    state = const AsyncValue.loading();
    final repository = _repository;
    final result = await AsyncValue.guard(
      repository == null ? _continueAsLocalGuest : repository.continueAsGuest,
    );
    if (_canCommit(generation)) state = result;
  }

  void markOnboardingComplete({String? displayName}) {
    final session = state.valueOrNull;
    if (session == null) {
      throw StateError('No active session.');
    }
    final cleanName = displayName?.trim();
    final profile = session.profile.copyWith(
      name: cleanName?.isNotEmpty == true ? cleanName : null,
      onboardingDone: true,
    );
    _authGeneration += 1;
    state = AsyncValue.data(
      session.isGuestSession
          ? AppSession.guest(profile)
          : AppSession.authenticated(profile),
    );
  }

  void updateProfileTimezone(String timezone, {required int revision}) {
    final session = state.valueOrNull;
    if (session == null || session.isGuestSession) {
      throw StateError('A synced account session is required.');
    }
    _authGeneration += 1;
    state = AsyncValue.data(
      AppSession.authenticated(
        session.profile.copyWith(
          timezone: timezone,
          timezoneRevision: revision,
        ),
      ),
    );
  }

  void updateDailyPreparationBudget(int? minutes, {required int revision}) {
    final session = state.valueOrNull;
    if (session == null || session.isGuestSession) {
      throw StateError('A synced account session is required.');
    }
    _authGeneration += 1;
    state = AsyncValue.data(
      AppSession.authenticated(
        session.profile.withDailyPreparationBudget(
          minutes,
          revision: revision,
        ),
      ),
    );
  }

  Future<void> signOut() async {
    final generation = ++_authGeneration;
    _terminalTransitionGeneration = generation;
    final previous = state;
    state = const AsyncValue.loading();
    try {
      await _clearCurrentCoachCredentials(previous.valueOrNull);
    } catch (_) {
      if (_canCommit(generation)) state = previous;
      if (_terminalTransitionGeneration == generation) {
        _terminalTransitionGeneration = null;
      }
      rethrow;
    }
    try {
      final repository = _repository;
      if (repository == null) {
        await _clearLocalGuest();
      } else {
        await repository.signOut();
      }
    } finally {
      if (_canCommit(generation)) state = const AsyncValue.data(null);
      if (_terminalTransitionGeneration == generation) {
        _terminalTransitionGeneration = null;
      }
      await _setPasswordRecoveryActive(false);
    }
  }

  Future<void> finalizeDeletedAccount({
    bool coachCredentialsAlreadyCleared = false,
  }) async {
    final generation = ++_authGeneration;
    _terminalTransitionGeneration = generation;
    final previous = state;
    state = const AsyncValue.loading();
    try {
      if (!coachCredentialsAlreadyCleared) {
        await _clearCurrentCoachCredentials(previous.valueOrNull);
      }
    } catch (_) {
      if (_canCommit(generation)) state = previous;
      if (_terminalTransitionGeneration == generation) {
        _terminalTransitionGeneration = null;
      }
      rethrow;
    }
    try {
      final repository = _repository;
      if (repository == null) {
        await _clearLocalGuest();
      } else {
        await repository.signOutAfterAccountDeletion();
      }
    } finally {
      if (_canCommit(generation)) state = const AsyncValue.data(null);
      if (_terminalTransitionGeneration == generation) {
        _terminalTransitionGeneration = null;
      }
      await _setPasswordRecoveryActive(false);
    }
  }

  Future<void> prepareAccountDeletion() async {
    final session = state.valueOrNull;
    if (session == null || session.isGuestSession) return;
    _cancelCoachResponse();
    await _clearCurrentCoachCredentials(session);
  }

  void enterAccountDeletionRecovery(AccountDeletionResult result) {
    final session = state.valueOrNull;
    if (session == null || session.isGuestSession) {
      throw StateError('A synced account session is required.');
    }
    _authGeneration += 1;
    state = AsyncValue.data(
      AppSession.deletionRecovery(
        session.profile,
        AccountDeletionRecovery(
          deletionId: result.deletionId,
          result: result,
        ),
      ),
    );
  }

  Future<AccountDeletionRecovery?> retryAccountDeletion() async {
    await refresh();
    return state.valueOrNull?.deletionRecovery;
  }

  Future<void> _clearCurrentCoachCredentials(AppSession? session) async {
    if (session == null || session.isGuestSession) return;
    await _clearCoachCredentials();
  }

  bool _canCommit(int generation) => mounted && generation == _authGeneration;

  Future<void> _restorePasswordRecoveryState() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final active =
          preferences.getBool(passwordRecoveryActivePreferenceKey) ?? false;
      if (!_recoveryChangedDuringRestore) {
        _onPasswordRecoveryStateChanged?.call(active);
      }
    } catch (_) {
      if (!_recoveryChangedDuringRestore) {
        _onPasswordRecoveryStateChanged?.call(false);
      }
    }
  }

  Future<bool> _setPasswordRecoveryActive(bool active) async {
    _recoveryChangedDuringRestore = true;
    _onPasswordRecoveryStateChanged?.call(active);
    return _persistPasswordRecoveryActive(active);
  }

  Future<bool> _persistPasswordRecoveryActive(bool active) {
    final operation = _recoveryWriteTail.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        return preferences.setBool(
          passwordRecoveryActivePreferenceKey,
          active,
        );
      } catch (_) {
        return false;
      }
    });
    _recoveryWriteTail = operation.then<void>((_) {});
    return operation;
  }

  Future<AppSession?> _localGuestSession() async {
    final prefs = await SharedPreferences.getInstance();
    final guestActive = prefs.getBool(_LocalGuestPrefs.active) ?? false;
    if (!guestActive) {
      return null;
    }
    return AppSession.guest(
      AppProfile(
        id: 'local_guest',
        email: 'guest@personal-coach.local',
        name: prefs.getString(_LocalGuestPrefs.name) ?? 'Guest Coach User',
        timezone: localDeviceTimezoneMarker,
        role: AppRole.guest,
        onboardingDone: prefs.getBool(_LocalGuestPrefs.onboardingDone) ?? false,
        authProvider: 'guest',
      ),
    );
  }

  Future<AppSession> _continueAsLocalGuest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_LocalGuestPrefs.active, true);
    return AppSession.guest(
      AppProfile(
        id: 'local_guest',
        email: 'guest@personal-coach.local',
        name: prefs.getString(_LocalGuestPrefs.name) ?? 'Guest Coach User',
        timezone: localDeviceTimezoneMarker,
        role: AppRole.guest,
        onboardingDone: prefs.getBool(_LocalGuestPrefs.onboardingDone) ?? false,
        authProvider: 'guest',
      ),
    );
  }

  Future<void> _clearLocalGuest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_LocalGuestPrefs.active, false);
  }

  AuthRepository _requireRepository() {
    final repository = _repository;
    if (repository == null) {
      throw const AuthConfigurationException();
    }
    return repository;
  }

  @override
  void dispose() {
    _authGeneration += 1;
    _terminalTransitionGeneration = null;
    _subscription?.cancel();
    super.dispose();
  }
}

class AuthConfigurationException implements Exception {
  const AuthConfigurationException();

  @override
  String toString() => 'Synced authentication is not configured.';
}

enum PasswordRecoveryCompletion { updated, updatedSessionUnavailable }

class _LocalGuestPrefs {
  const _LocalGuestPrefs._();

  static const active = 'auth_guest_active';
  static const name = 'auth_guest_name';
  static const onboardingDone = 'auth_guest_onboarding_done';
}
