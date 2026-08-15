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
  final CoachProviderName provider;
  final Map<CoachProviderName, String> keys;
  final bool busy;
  final String? error;

  String? get activeKey => keys[provider];
  bool hasKey(CoachProviderName value) => keys[value]?.isNotEmpty ?? false;

  CoachCredentials copyWith({
    String? profileId,
    CoachProviderName? provider,
    Map<CoachProviderName, String>? keys,
    bool? busy,
    Object? error = _unchanged,
  }) =>
      CoachCredentials(
        profileId: profileId ?? this.profileId,
        provider: provider ?? this.provider,
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
            provider: CoachProviderName.openai,
            keys: {},
          ),
        );

  final CoachCredentialStore _store;
  final CoachApiDataSource _api;
  final Future<String?> Function() _accessToken;

  Future<void> setProfile(String? profileId) async {
    final previous = state.profileId;
    state = CoachCredentials(
      profileId: profileId,
      provider: CoachProviderName.openai,
      keys: const {},
    );
    try {
      if (previous != null && previous != profileId) {
        await _store.deleteProfile(previous);
      }
      if (profileId == null) return;
      final keys = <CoachProviderName, String>{};
      for (final provider in const [
        CoachProviderName.openai,
        CoachProviderName.gemini,
      ]) {
        final value = await _store.read(profileId, provider);
        if (value != null && value.isNotEmpty) keys[provider] = value;
      }
      if (state.profileId == profileId) state = state.copyWith(keys: keys);
    } catch (_) {
      if (state.profileId == profileId) {
        state = state.copyWith(
          keys: const {},
          error: 'Saved keys could not be loaded or cleared.',
        );
      }
    }
  }

  void select(CoachProviderName provider) {
    if (!const {CoachProviderName.openai, CoachProviderName.gemini}
        .contains(provider)) {
      throw ArgumentError.value(provider, 'provider');
    }
    state = state.copyWith(provider: provider, error: null);
  }

  Future<bool> testAndSave(CoachProviderName provider, String value) async {
    final profileId = state.profileId;
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
      await _store.write(profileId, provider, key);
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
