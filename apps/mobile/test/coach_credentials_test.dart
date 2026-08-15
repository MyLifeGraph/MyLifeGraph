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
}

class _Store implements CoachCredentialStore {
  final Map<String, String> values = {};
  bool failWrites = false;

  String _key(String profile, CoachProviderName provider) =>
      '$profile:${provider.code}';

  @override
  Future<String?> read(String profileId, CoachProviderName provider) async =>
      values[_key(profileId, provider)];

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
}

class _Api extends CoachApiDataSource {
  _Api() : super(ApiClient(Dio()));

  bool ready = true;
  final List<String> keys = [];

  @override
  Future<CoachCapabilities> getCapabilities({
    required String accessToken,
    CoachProviderName? provider,
    String? apiKey,
  }) async {
    keys.add(apiKey!);
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
        'remaining_requests': 20,
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
