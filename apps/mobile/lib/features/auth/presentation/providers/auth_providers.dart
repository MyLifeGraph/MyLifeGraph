import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../data/auth_repository.dart';
import '../../data/guest_setup_data_source.dart';
import '../../data/intake_api_data_source.dart';
import '../../domain/app_session.dart';

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
    onPasswordRecoveryStateChanged: (active) {
      ref.read(passwordRecoveryActiveProvider.notifier).state = active;
    },
  );
});

class AuthController extends StateNotifier<AsyncValue<AppSession?>> {
  AuthController(
    this._repository, {
    void Function(bool active)? onPasswordRecoveryStateChanged,
  })  : _onPasswordRecoveryStateChanged = onPasswordRecoveryStateChanged,
        super(const AsyncValue.loading()) {
    _load();
    _subscription = _repository?.authStateChanges.listen(_handleAuthChange);
  }

  final AuthRepository? _repository;
  final void Function(bool active)? _onPasswordRecoveryStateChanged;
  StreamSubscription<dynamic>? _subscription;
  Future<void> _recoveryWriteTail = Future<void>.value();
  bool _recoveryStateRestored = false;
  bool _recoveryChangedDuringRestore = false;

  void _handleAuthChange(AuthState change) {
    if (change.event == AuthChangeEvent.passwordRecovery) {
      _recoveryChangedDuringRestore = true;
      _onPasswordRecoveryStateChanged?.call(true);
      unawaited(_persistPasswordRecoveryActive(true));
    }
    unawaited(refresh());
  }

  Future<void> _load() async {
    if (!_recoveryStateRestored) {
      await _restorePasswordRecoveryState();
      _recoveryStateRestored = true;
    }
    if (_repository == null) {
      state = AsyncValue.data(await _localGuestSession());
      return;
    }
    try {
      state = AsyncValue.data(await _repository.currentSession());
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> refresh() => _load();

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _requireRepository().signInWithEmail(
        email: email,
        password: password,
      ),
    );
  }

  Future<bool> registerWithEmail({
    required String email,
    required String password,
    String? name,
  }) async {
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(
      () => _requireRepository().registerWithEmail(
        email: email,
        password: password,
        name: name,
      ),
    );
    state = result;
    return result.valueOrNull != null;
  }

  Future<void> signInWithGoogle() async {
    final repository = _requireRepository();
    await repository.signInWithGoogle();
  }

  Future<void> requestPasswordReset({required String email}) {
    return _requireRepository().requestPasswordReset(email: email);
  }

  Future<void> resendSignupConfirmation({required String email}) {
    return _requireRepository().resendSignupConfirmation(email: email);
  }

  Future<PasswordRecoveryCompletion> completePasswordRecovery({
    required String password,
  }) async {
    await _requireRepository().updatePassword(password: password);
    await refresh();
    return !state.hasError
        ? PasswordRecoveryCompletion.updated
        : PasswordRecoveryCompletion.updatedSessionUnavailable;
  }

  Future<bool> finalizePasswordRecovery() => _setPasswordRecoveryActive(false);

  Future<void> continueAsGuest() async {
    state = const AsyncValue.loading();
    final repository = _repository;
    state = await AsyncValue.guard(
      repository == null ? _continueAsLocalGuest : repository.continueAsGuest,
    );
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
    state = AsyncValue.data(
      session.isGuestSession
          ? AppSession.guest(profile)
          : AppSession.authenticated(profile),
    );
  }

  void updateProfileTimezone(String timezone) {
    final session = state.valueOrNull;
    if (session == null || session.isGuestSession) {
      throw StateError('A synced account session is required.');
    }
    state = AsyncValue.data(
      AppSession.authenticated(
        session.profile.copyWith(timezone: timezone),
      ),
    );
  }

  void updateDailyPreparationBudget(int? minutes) {
    final session = state.valueOrNull;
    if (session == null || session.isGuestSession) {
      throw StateError('A synced account session is required.');
    }
    state = AsyncValue.data(
      AppSession.authenticated(
        session.profile.withDailyPreparationBudget(minutes),
      ),
    );
  }

  Future<void> signOut() async {
    state = const AsyncValue.loading();
    try {
      final repository = _repository;
      if (repository == null) {
        await _clearLocalGuest();
      } else {
        await repository.signOut();
      }
    } finally {
      state = const AsyncValue.data(null);
      await _setPasswordRecoveryActive(false);
    }
  }

  Future<void> finalizeDeletedAccount() async {
    state = const AsyncValue.loading();
    try {
      final repository = _repository;
      if (repository == null) {
        await _clearLocalGuest();
      } else {
        await repository.signOutAfterAccountDeletion();
      }
    } finally {
      state = const AsyncValue.data(null);
      await _setPasswordRecoveryActive(false);
    }
  }

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
