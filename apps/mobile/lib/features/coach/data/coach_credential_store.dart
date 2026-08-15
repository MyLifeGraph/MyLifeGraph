import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/coach.dart';

abstract interface class CoachCredentialStore {
  Future<String?> read(String profileId, CoachProviderName provider);
  Future<void> write(String profileId, CoachProviderName provider, String key);
  Future<void> delete(String profileId, CoachProviderName provider);
  Future<void> deleteProfile(String profileId);
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

  String _name(String profileId, CoachProviderName provider) =>
      'coach_byok.$profileId.${provider.code}';

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
  ) async {
    final name = _name(profileId, provider);
    if (_web) {
      _tabMemory[name] = key;
    } else {
      await _secureStorage.write(key: name, value: key);
    }
  }

  @override
  Future<void> delete(String profileId, CoachProviderName provider) async {
    final name = _name(profileId, provider);
    if (_web) {
      _tabMemory.remove(name);
    } else {
      await _secureStorage.delete(key: name);
    }
  }

  @override
  Future<void> deleteProfile(String profileId) async {
    for (final provider in const [
      CoachProviderName.openai,
      CoachProviderName.gemini,
    ]) {
      await delete(profileId, provider);
    }
  }
}
