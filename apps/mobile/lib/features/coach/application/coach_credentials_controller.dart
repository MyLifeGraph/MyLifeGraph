import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    this.geminiModel = coachDefaultGeminiModel,
  });

  final String? profileId;
  final CoachProviderName? provider;
  final Map<CoachProviderName, String> keys;
  final bool busy;
  final String? error;
  final String geminiModel;

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
    String? geminiModel,
  }) =>
      CoachCredentials(
        profileId: profileId ?? this.profileId,
        provider: identical(provider, _unchanged)
            ? this.provider
            : provider as CoachProviderName?,
        keys: keys ?? this.keys,
        busy: busy ?? this.busy,
        error: identical(error, _unchanged) ? this.error : error as String?,
        geminiModel: geminiModel ?? this.geminiModel,
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
  Future<void> _initialization = Future<void>.value();
  Future<void> _selectionSave = Future<void>.value();

  static String _selectionKey(String profileId) =>
      'coach_provider_v1:$profileId';
  static String _modelKey(String profileId) => 'coach_gemini_model_v1:$profileId';

  Future<void> get initialization => _initialization;

  Future<void> setProfile(String? profileId) =>
      _initialization = _loadProfile(profileId);

  Future<void> _loadProfile(String? profileId) async {
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
      await _selectionSave;
      final preferences = await SharedPreferences.getInstance();
      if (generation != _profileGeneration) return;
      final savedProvider = preferences.getString(_selectionKey(profileId));
      final savedModel = preferences.getString(_modelKey(profileId));
      final provider = const [
        CoachProviderName.operatorCodexPilot,
        CoachProviderName.openai,
        CoachProviderName.gemini,
      ].where((value) => value.name == savedProvider).firstOrNull;
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
        provider: provider ?? CoachProviderName.operatorCodexPilot,
        keys: keys,
        geminiModel: coachGeminiModels.containsKey(savedModel)
            ? savedModel! : coachDefaultGeminiModel,
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

  Future<void> select(CoachProviderName provider) {
    if (!const {
      CoachProviderName.operatorCodexPilot,
      CoachProviderName.openai,
      CoachProviderName.gemini,
    }.contains(provider)) {
      throw ArgumentError.value(provider, 'provider');
    }
    state = state.copyWith(provider: provider, error: null);
    final profileId = state.profileId;
    final generation = _profileGeneration;
    if (profileId == null) return Future<void>.value();
    return _selectionSave = _selectionSave.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        if (!await preferences.setString(_selectionKey(profileId), provider.name)) {
          throw StateError('Selection was not saved');
        }
      } catch (_) {
        if (mounted && generation == _profileGeneration) {
          state = state.copyWith(error: 'Coach choice could not be saved. Try again.');
        }
      }
    });
  }

  Future<void> selectGeminiModel(String model) {
    if (!coachGeminiModels.containsKey(model)) throw ArgumentError.value(model, 'model');
    if (state.busy) return Future<void>.value();
    state = state.copyWith(geminiModel: model, error: null);
    final profileId = state.profileId;
    final generation = _profileGeneration;
    if (profileId == null) return Future<void>.value();
    return _selectionSave = _selectionSave.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        if (!await preferences.setString(_modelKey(profileId), model)) {
          throw StateError('Model was not saved');
        }
      } catch (_) {
        if (mounted && generation == _profileGeneration) {
          state = state.copyWith(error: 'Model choice could not be saved. Try again.');
        }
      }
    });
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
        model: provider == CoachProviderName.gemini ? state.geminiModel : null,
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
      await select(provider);
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
