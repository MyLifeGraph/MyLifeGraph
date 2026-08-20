import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/coach_api_data_source.dart';
import '../data/coach_credential_store.dart';
import '../domain/coach.dart';

class CoachCredentials {
  const CoachCredentials({
    required this.profileId,
    required this.provider,
    required this.keys,
    this.busy = false,
    this.error,
  });

  final String? profileId;
  final CoachProviderName? provider;
  final Map<CoachProviderName, String> keys;
  final bool busy;
  final String? error;

  String? get activeKey => provider == null ? null : keys[provider];
  bool get hasSelection => provider != null;
  bool get usesProjectCoach => provider == CoachProviderName.operatorCodexPilot;
  bool hasKey(CoachProviderName value) => keys[value]?.isNotEmpty ?? false;

  CoachCredentials copyWith({
    String? profileId,
    Object? provider = _unchanged,
    Map<CoachProviderName, String>? keys,
    bool? busy,
    Object? error = _unchanged,
  }) =>
      CoachCredentials(
        profileId: profileId ?? this.profileId,
        provider: identical(provider, _unchanged)
            ? this.provider
            : provider as CoachProviderName?,
        keys: keys ?? this.keys,
        busy: busy ?? this.busy,
        error: identical(error, _unchanged) ? this.error : error as String?,
      );
}

const _unchanged = Object();

class CoachCredentialsController extends StateNotifier<CoachCredentials> {
  CoachCredentialsController({
    required CoachCredentialStore store,
    required CoachApiDataSource api,
    required Future<String?> Function() accessToken,
  })  : _store = store,
        _api = api,
        _accessToken = accessToken,
        super(
          const CoachCredentials(
            profileId: null,
            provider: null,
            keys: {},
          ),
        );

  final CoachCredentialStore _store;
  final CoachApiDataSource _api;
  final Future<String?> Function() _accessToken;
  int _profileGeneration = 0;

  Future<void> setProfile(String? profileId) async {
    final generation = ++_profileGeneration;
    final previous = state.profileId;
    state = CoachCredentials(
      profileId: previous == null || previous == profileId ? profileId : null,
      provider: null,
      keys: const {},
    );
    try {
      if (previous != null && previous != profileId) {
        await _store.deleteAllCoachCredentials();
        if (generation != _profileGeneration) return;
      }
      if (profileId == null) return;
      final keys = <CoachProviderName, String>{};
      for (final provider in const [
        CoachProviderName.openai,
        CoachProviderName.gemini,
      ]) {
        final value = await _store.read(profileId, provider);
        if (generation != _profileGeneration) return;
        if (value != null && value.isNotEmpty) keys[provider] = value;
      }
      state = CoachCredentials(
        profileId: profileId,
        provider: null,
        keys: keys,
      );
    } catch (_) {
      if (generation != _profileGeneration) return;
      state = const CoachCredentials(
        profileId: null,
        provider: null,
        keys: {},
        error: 'Saved keys could not be loaded or cleared. Retry sign-out.',
      );
    }
  }

  void select(CoachProviderName provider) {
    if (!const {
      CoachProviderName.operatorCodexPilot,
      CoachProviderName.openai,
      CoachProviderName.gemini,
    }.contains(provider)) {
      throw ArgumentError.value(provider, 'provider');
    }
    state = state.copyWith(provider: provider, error: null);
  }

  Future<bool> testAndSave(CoachProviderName provider, String value) async {
    if (!const {CoachProviderName.openai, CoachProviderName.gemini}
        .contains(provider)) {
      throw ArgumentError.value(provider, 'provider');
    }
    final profileId = state.profileId;
    final profileGeneration = _profileGeneration;
    final key = value.trim();
    if (profileId == null || key.isEmpty) return false;
    state = state.copyWith(busy: true, error: null);
    try {
      final token = await _accessToken();
      if (token == null || token.isEmpty) {
        throw StateError('Session unavailable');
      }
      final capability = await _api.getCapabilities(
        accessToken: token,
        provider: provider,
        apiKey: key,
      );
      if (capability.state != CoachCapabilityState.ready) {
        state = state.copyWith(
          busy: false,
          error: 'The provider rejected this key.',
        );
        return false;
      }
      if (profileGeneration != _profileGeneration ||
          state.profileId != profileId) {
        return false;
      }
      await _store.write(profileId, provider, key);
      if (profileGeneration != _profileGeneration ||
          state.profileId != profileId) {
        return false;
      }
      state = state.copyWith(
        keys: {...state.keys, provider: key},
        provider: provider,
        busy: false,
      );
      return true;
    } catch (_) {
      state = state.copyWith(
        busy: false,
        error: 'The key could not be tested. Your previous key is unchanged.',
      );
      return false;
    }
  }

  Future<void> delete(CoachProviderName provider) async {
    final profileId = state.profileId;
    if (profileId == null) return;
    await _store.delete(profileId, provider);
    final keys = {...state.keys}..remove(provider);
    state = state.copyWith(keys: keys, error: null);
  }
}
