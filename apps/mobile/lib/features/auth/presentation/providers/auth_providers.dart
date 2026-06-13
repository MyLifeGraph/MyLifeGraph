import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../data/auth_repository.dart';
import '../../domain/app_session.dart';

final authRepositoryProvider = Provider<AuthRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : AuthRepository(client);
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

  Future<void> completeOnboarding({
    required String? name,
    required List<TimetableDraft> timetable,
  }) async {
    state = const AsyncValue.loading();
    final repository = _repository;
    state = await AsyncValue.guard(
      () => repository == null
          ? _completeLocalGuestOnboarding(name: name, timetable: timetable)
          : repository.completeOnboarding(name: name, timetable: timetable),
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

  Future<AppSession> _completeLocalGuestOnboarding({
    required String? name,
    required List<TimetableDraft> timetable,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanName = name?.trim();
    if (cleanName != null && cleanName.isNotEmpty) {
      await prefs.setString(_LocalGuestPrefs.name, cleanName);
    }
    await prefs.setBool(_LocalGuestPrefs.active, true);
    await prefs.setBool(_LocalGuestPrefs.onboardingDone, true);
    await prefs.setString(
      _LocalGuestPrefs.timetable,
      jsonEncode(timetable.map((draft) => draft.toJson()).toList()),
    );

    return AppSession.guest(
      AppProfile(
        id: 'local_guest',
        email: 'guest@personal-coach.local',
        name: cleanName?.isNotEmpty == true ? cleanName! : 'Guest Coach User',
        timezone: 'Europe/Berlin',
        role: AppRole.guest,
        onboardingDone: true,
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
  static const timetable = 'auth_guest_timetable';
}
