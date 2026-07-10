import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<AppSession?>>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthController(repository);
});

class AuthController extends StateNotifier<AsyncValue<AppSession?>> {
  AuthController(this._repository) : super(const AsyncValue.loading()) {
    _load();
    _subscription = _repository?.authStateChanges.listen((_) => refresh());
  }

  final AuthRepository? _repository;
  StreamSubscription<dynamic>? _subscription;

  Future<void> _load() async {
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
    final repository = _requireRepository();
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => repository.signInWithEmail(email: email, password: password),
    );
  }

  Future<bool> registerWithEmail({
    required String email,
    required String password,
    String? name,
  }) async {
    final repository = _requireRepository();
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(
      () => repository.registerWithEmail(
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

  Future<void> signOut() async {
    state = const AsyncValue.loading();
    final repository = _repository;
    if (repository == null) {
      await _clearLocalGuest();
    } else {
      await repository.signOut();
    }
    state = const AsyncValue.data(null);
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
        timezone: 'Europe/Berlin',
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
        timezone: 'Europe/Berlin',
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
      throw StateError('Supabase is not configured.');
    }
    return repository;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

class _LocalGuestPrefs {
  const _LocalGuestPrefs._();

  static const active = 'auth_guest_active';
  static const name = 'auth_guest_name';
  static const onboardingDone = 'auth_guest_onboarding_done';
}
