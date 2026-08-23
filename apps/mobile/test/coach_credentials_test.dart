import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/coach/application/coach_credentials_controller.dart';
import 'package:my_life_graph/features/coach/data/coach_api_data_source.dart';
import 'package:my_life_graph/features/coach/data/coach_credential_store.dart';
import 'package:my_life_graph/features/coach/domain/coach.dart';

void main() {
  test('web keys are tab-memory only and a new store represents reload',
      () async {
    final tab = PlatformCoachCredentialStore(web: true);
    await tab.write('profile-a', CoachProviderName.openai, 'secret-a');
    expect(
      await tab.read('profile-a', CoachProviderName.openai),
      'secret-a',
    );
    expect(
      await PlatformCoachCredentialStore(web: true)
          .read('profile-a', CoachProviderName.openai),
      isNull,
    );
    await tab.deleteAllCoachCredentials();
    expect(
      await tab.read('profile-a', CoachProviderName.openai),
      isNull,
    );
  });

  test('replacement becomes active only after a ready capability test',
      () async {
    final store = _Store()..values['profile-a:openai'] = 'previous-secret';
    final api = _Api()..ready = false;
    final controller = CoachCredentialsController(
      store: store,
      api: api,
      accessToken: () async => 'access-token',
    );
    await controller.setProfile('profile-a');
    controller.select(CoachProviderName.openai);

    expect(
      await controller.testAndSave(CoachProviderName.openai, 'bad-secret'),
      isFalse,
    );
    expect(controller.state.activeKey, 'previous-secret');
    expect(store.values['profile-a:openai'], 'previous-secret');

    api.ready = true;
    expect(
      await controller.testAndSave(CoachProviderName.openai, 'new-secret'),
      isTrue,
    );
    expect(controller.state.activeKey, 'new-secret');
    expect(api.keys, ['bad-secret', 'new-secret']);
  });

  test('profile switch clears memory first and deletes both old keys',
      () async {
    final store = _Store()
      ..values.addAll({
        'profile-a:openai': 'secret-a',
        'profile-a:gemini': 'secret-b',
      });
    final controller = CoachCredentialsController(
      store: store,
      api: _Api(),
      accessToken: () async => 'access-token',
    );
    await controller.setProfile('profile-a');
    final switching = controller.setProfile('profile-b');
    expect(controller.state.keys, isEmpty);
    await switching;
    expect(store.values.keys, isNot(contains(startsWith('profile-a:'))));
    expect(store.deleteAllCalls, 1);
  });

  test('profile switch fails closed when secure storage cannot be cleared',
      () async {
    final store = _Store()..values['profile-a:openai'] = 'secret-a';
    final controller = CoachCredentialsController(
      store: store,
      api: _Api(),
      accessToken: () async => 'access-token',
    );
    await controller.setProfile('profile-a');
    store.failDeleteAll = true;

    await controller.setProfile('profile-b');

    expect(controller.state.profileId, isNull);
    expect(controller.state.keys, isEmpty);
    expect(controller.state.error, isNotNull);
  });

  test('a stale profile load cannot overwrite a newer profile', () async {
    final firstRead = Completer<void>();
    final store = _Store()
      ..values['profile-a:openai'] = 'stale-secret'
      ..readBarriers['profile-a:openai'] = firstRead;
    final controller = CoachCredentialsController(
      store: store,
      api: _Api(),
      accessToken: () async => 'access-token',
    );

    final staleLoad = controller.setProfile('profile-a');
    await Future<void>.delayed(Duration.zero);
    final currentLoad = controller.setProfile('profile-b');
    firstRead.complete();
    await Future.wait([staleLoad, currentLoad]);

    expect(controller.state.profileId, 'profile-b');
    expect(controller.state.keys, isEmpty);
  });

  test('secure-storage write failure keeps the prior active key', () async {
    final store = _Store()..values['profile-a:gemini'] = 'previous-secret';
    final controller = CoachCredentialsController(
      store: store,
      api: _Api()..ready = true,
      accessToken: () async => 'access-token',
    );
    await controller.setProfile('profile-a');
    controller.select(CoachProviderName.gemini);
    store.failWrites = true;

    expect(
      await controller.testAndSave(CoachProviderName.gemini, 'new-secret'),
      isFalse,
    );
    expect(controller.state.activeKey, 'previous-secret');
  });

  test('an in-flight key test cannot write after sign-out', () async {
    final capability = Completer<void>();
    final store = _Store();
    final api = _Api()
      ..ready = true
      ..capabilityBarrier = capability;
    final controller = CoachCredentialsController(
      store: store,
      api: api,
      accessToken: () async => 'access-token',
    );
    await controller.setProfile('profile-a');

    final save = controller.testAndSave(
      CoachProviderName.openai,
      'new-secret',
    );
    await Future<void>.delayed(Duration.zero);
    await controller.setProfile(null);
    capability.complete();

    expect(await save, isFalse);
    expect(store.values, isEmpty);
    expect(controller.state.profileId, isNull);
  });

  test('Project Coach selection never reads or stores an API key', () async {
    final store = _Store();
    final api = _Api();
    final controller = CoachCredentialsController(
      store: store,
      api: api,
      accessToken: () async => 'access-token',
    );
    await controller.setProfile('profile-a');

    controller.select(CoachProviderName.operatorCodexPilot);

    expect(controller.state.usesProjectCoach, isTrue);
    expect(controller.state.activeKey, isNull);
    expect(api.keys, isEmpty);
    expect(
      store.values.keys,
      everyElement(isNot(contains('operator_codex_pilot'))),
    );
    await expectLater(
      PlatformCoachCredentialStore(web: true).write(
        'profile-a',
        CoachProviderName.operatorCodexPilot,
        'must-not-be-stored',
      ),
      throwsArgumentError,
    );
  });
}

class _Store implements CoachCredentialStore {
  final Map<String, String> values = {};
  final Map<String, Completer<void>> readBarriers = {};
  bool failWrites = false;
  bool failDeleteAll = false;
  int deleteAllCalls = 0;

  String _key(String profile, CoachProviderName provider) =>
      '$profile:${provider.code}';

  @override
  Future<String?> read(String profileId, CoachProviderName provider) async {
    final key = _key(profileId, provider);
    await readBarriers[key]?.future;
    return values[key];
  }

  @override
  Future<void> write(
    String profileId,
    CoachProviderName provider,
    String key,
  ) async {
    if (failWrites) throw StateError('secure storage failed');
    values[_key(profileId, provider)] = key;
  }

  @override
  Future<void> delete(String profileId, CoachProviderName provider) async {
    values.remove(_key(profileId, provider));
  }

  @override
  Future<void> deleteProfile(String profileId) async {
    values.removeWhere((key, _) => key.startsWith('$profileId:'));
  }

  @override
  Future<void> deleteAllCoachCredentials() async {
    deleteAllCalls += 1;
    if (failDeleteAll) throw StateError('secure storage delete failed');
    values.clear();
  }
}

class _Api extends CoachApiDataSource {
  _Api() : super(ApiClient(Dio()));

  bool ready = true;
  Completer<void>? capabilityBarrier;
  final List<String> keys = [];

  @override
  Future<CoachCapabilities> getCapabilities({
    required String accessToken,
    CoachProviderName? provider,
    String? apiKey,
  }) async {
    keys.add(apiKey!);
    await capabilityBarrier?.future;
    final model = provider == CoachProviderName.openai
        ? 'gpt-5.6-terra'
        : 'gemini-3.6-flash';
    return CoachCapabilities.fromJson({
      'contract_version': coachCapabilitiesContractVersion,
      'state': ready ? 'ready' : 'unavailable',
      'provider': provider!.code,
      'provider_mode': 'user_supplied_key',
      'model_requested': model,
      'model_source': 'explicit',
      'service_tier': 'not_applicable',
      'fast_mode': false,
      'reason_code': ready ? 'ready' : 'invalid_api_key',
      'tools': ['inspect_data', 'query_data'],
      'limits': {
        'message_codepoints': 2000,
        'reply_codepoints': 4000,
        'requests_per_local_day': 20,
        'request_period': 'profile_local_day',
        'remaining_requests': 20,
        'global_requests_per_utc_day': null,
        'global_remaining_requests': null,
        'max_tool_calls': 12,
        'turn_timeout_seconds': 180,
        'sql_timeout_seconds': 5,
        'python_timeout_seconds': 30,
        'snapshot_max_rows': 50000,
        'snapshot_max_bytes': 8388608,
      },
    });
  }
}
