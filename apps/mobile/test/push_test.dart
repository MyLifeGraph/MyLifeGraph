import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/core/platform/push_platform.dart';
import 'package:my_life_graph/features/notifications/application/push_controller.dart';
import 'package:my_life_graph/features/notifications/domain/entities/push_settings.dart';

Map<String, dynamic> cloud({bool enabled = false, int revision = 0}) => {
  'contract_version': pushContractVersion,
  'available': true,
  'timezone': 'UTC',
  'settings': {
    'enabled': enabled,
    'revision': revision,
    'sleep': true,
    'deadlines': true,
    'patterns': true,
    'quiet_start': '22:00',
    'quiet_end': '07:00',
    if (enabled) 'consent_version': pushConsentVersion,
  },
};

class Platform extends PushPlatform {
  final calls = <String>[];
  bool granted = true;
  @override
  Future<T?> call<T>(String method, [Map<String, dynamic>? args]) async {
    calls.add(method);
    Object? value;
    if (method == 'bind') {
      value = {
        'device_id': 'device',
        'registration_id': 'registration',
        'granted': granted,
        'configured': true,
      };
    } else if (method == 'token') {
      value = 'test-device-token';
    } else if (method == 'requestPermission') {
      value = granted;
    }
    return value as T?;
  }
}

class Api extends ApiClient {
  Api() : super(Dio());
  Map<String, dynamic> current = cloud();
  final writes = <Map<String, dynamic>>[];
  bool fail = false;
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    expect(path, '/v1/push');
    expect(headers?['Authorization'], 'Bearer access');
    if (fail) throw StateError('private details');
    return current;
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    writes.add(Map.of(body!));
    if (fail) throw StateError('private details');
    if (pending != null) return pending!.future;
    current = cloud(
      enabled: body['enabled'] as bool? ?? true,
      revision: (current['settings']['revision'] as int) + 1,
    );
    if (body['command'] == 'register') {
      current['device_id'] = body['device_id'];
      current['registration_id'] = body['registration_id'];
    }
    return current;
  }
}

void main() {
  test(
    'disabled consent binds locally but never requests a Firebase token',
    () async {
      final api = Api();
      final platform = Platform();
      final controller = PushController(
        api,
        platform,
        () => 'access',
        'owner',
        'session',
        android: true,
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(platform.calls, ['bind', 'pause']);
      expect(api.writes, isEmpty);
    },
  );

  test(
    'existing consent registers before activation and does not repeat unchanged registration',
    () async {
      final api = Api()..current = cloud(enabled: true);
      final platform = Platform();
      final controller = PushController(
        api,
        platform,
        () => 'access',
        'owner',
        'session',
        android: true,
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(api.writes.single['command'], 'register');
      expect(api.writes.single.containsKey('user_id'), isFalse);
      expect(platform.calls, ['bind', 'token', 'activate']);
      await controller.refresh();
      expect(api.writes.length, 1);
    },
  );

  test('permission refusal does not save or register', () async {
    final api = Api();
    final platform = Platform()..granted = false;
    final controller = PushController(
      api,
      platform,
      () => 'access',
      'owner',
      'session',
      android: true,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.save({'enabled': true}, 0);
    expect(api.writes, isEmpty);
    expect(platform.calls, isNot(contains('token')));
    expect(controller.state.error, isNotNull);
  });

  test(
    'opt-out pauses receipt before writing and keeps the loaded draft revision',
    () async {
      final api = Api()..current = cloud(enabled: true, revision: 3);
      final platform = Platform();
      final controller = PushController(
        api,
        platform,
        () => 'access',
        'owner',
        'session',
        android: true,
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      api.writes.clear();
      platform.calls.clear();
      await controller.save({'enabled': false}, 3);
      expect(platform.calls, ['pause', 'pause']);
      expect(api.writes.single['expected_revision'], 3);
      expect(api.writes.single['consent_version'], pushConsentVersion);
      expect(controller.state.cloud!.enabled, isFalse);
    },
  );

  test(
    'registration failure never enables native receipt or exposes private errors',
    () async {
      final api = Api()..current = cloud(enabled: true);
      final platform = Platform();
      final controller = PushController(
        api,
        platform,
        () => 'access',
        'owner',
        'session',
        android: true,
      );
      addTearDown(controller.dispose);
      api.pending = Completer();
      final refresh = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      api.pending!.completeError(StateError('private token'));
      await refresh;
      expect(platform.calls, isNot(contains('activate')));
      expect(controller.state.error, isNot(contains('private')));
    },
  );

  test('disposed account cannot activate a late registration', () async {
    final api = Api()..current = cloud(enabled: true);
    final platform = Platform();
    final controller = PushController(
      api,
      platform,
      () => 'access',
      'owner',
      'session',
      android: true,
    );
    api.pending = Completer();
    final refresh = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    api.pending!.complete(cloud(enabled: true));
    await refresh;
    expect(platform.calls, isNot(contains('activate')));
  });

  test('web never touches native registration', () async {
    final api = Api()..current = cloud(enabled: true);
    final platform = Platform();
    final controller = PushController(
      api,
      platform,
      () => 'access',
      'owner',
      'session',
      android: false,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(platform.calls, isEmpty);
    expect(api.writes, isEmpty);
    await controller.save({'enabled': false}, 0);
    expect(api.writes.single['enabled'], isFalse);
  });

  test('settings reject invalid clocks and missing consent', () {
    final invalid = cloud(enabled: true);
    (invalid['settings'] as Map).remove('consent_version');
    expect(() => PushSettingsState.parse(invalid), throwsFormatException);
    final invalidClock = cloud();
    invalidClock['settings']['quiet_start'] = '26:00';
    expect(() => PushSettingsState.parse(invalidClock), throwsFormatException);
  });
}
