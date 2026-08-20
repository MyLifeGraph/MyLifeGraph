import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/coach.dart';

abstract interface class CoachCredentialStore {
  Future<String?> read(String profileId, CoachProviderName provider);
  Future<void> write(String profileId, CoachProviderName provider, String key);
  Future<void> delete(String profileId, CoachProviderName provider);
  Future<void> deleteProfile(String profileId);
  Future<void> deleteAllCoachCredentials();
}

class PlatformCoachCredentialStore implements CoachCredentialStore {
  PlatformCoachCredentialStore({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
    bool? web,
  })  : _secureStorage = secureStorage,
        _web = web ?? kIsWeb;

  final FlutterSecureStorage _secureStorage;
  final bool _web;
  final Map<String, String> _tabMemory = {};
  Future<void> _mutationTail = Future<void>.value();

  String _name(String profileId, CoachProviderName provider) =>
      'coach_byok.$profileId.${_byokProvider(provider).code}';

  @override
  Future<String?> read(String profileId, CoachProviderName provider) async {
    final name = _name(profileId, provider);
    return _web ? _tabMemory[name] : _secureStorage.read(key: name);
  }

  @override
  Future<void> write(
    String profileId,
    CoachProviderName provider,
    String key,
  ) =>
      _serializeMutation(() async {
        final name = _name(profileId, provider);
        if (_web) {
          _tabMemory[name] = key;
        } else {
          await _secureStorage.write(key: name, value: key);
        }
      });

  @override
  Future<void> delete(String profileId, CoachProviderName provider) =>
      _serializeMutation(() async {
        final name = _name(profileId, provider);
        if (_web) {
          _tabMemory.remove(name);
        } else {
          await _secureStorage.delete(key: name);
        }
      });

  @override
  Future<void> deleteProfile(String profileId) async {
    await _serializeMutation(() async {
      for (final provider in const [
        CoachProviderName.openai,
        CoachProviderName.gemini,
      ]) {
        final name = _name(profileId, provider);
        if (_web) {
          _tabMemory.remove(name);
        } else {
          await _secureStorage.delete(key: name);
        }
      }
    });
  }

  @override
  Future<void> deleteAllCoachCredentials() => _serializeMutation(() async {
        if (_web) {
          _tabMemory.clear();
          return;
        }
        final stored = await _secureStorage.readAll();
        for (final name
            in stored.keys.where((key) => key.startsWith('coach_byok.'))) {
          await _secureStorage.delete(key: name);
        }
      });

  Future<void> _serializeMutation(Future<void> Function() mutation) {
    final operation = _mutationTail.then((_) => mutation());
    _mutationTail = operation.then<void>(
      (_) {},
      onError: (_, __) {},
    );
    return operation;
  }
}

CoachProviderName _byokProvider(CoachProviderName provider) {
  if (!const {CoachProviderName.openai, CoachProviderName.gemini}
      .contains(provider)) {
    throw ArgumentError.value(provider, 'provider', 'must be a BYOK provider');
  }
  return provider;
}
