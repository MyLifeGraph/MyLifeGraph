import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      state = const AsyncValue.data(null);
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
    final repository = _requireRepository();
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(repository.continueAsGuest);
  }

  Future<void> completeOnboarding({
    required String? name,
    required List<TimetableDraft> timetable,
  }) async {
    final repository = _requireRepository();
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => repository.completeOnboarding(
        name: name,
        timetable: timetable,
      ),
    );
  }

  Future<void> signOut() async {
    final repository = _requireRepository();
    state = const AsyncValue.loading();
    await repository.signOut();
    state = const AsyncValue.data(null);
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
