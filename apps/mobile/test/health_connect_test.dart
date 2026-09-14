import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/auth_providers.dart';
import 'package:my_life_graph/composition/health_connect_providers.dart';
import 'package:my_life_graph/composition/widgets/health_connect_sync_host.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:my_life_graph/features/health_connect/application/health_connect_controller.dart';
import 'package:my_life_graph/features/health_connect/data/health_connect_gateway.dart';
import 'package:my_life_graph/features/health_connect/domain/health_connect_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

HealthConnectState cloud({bool enabled = true, String device = 'device'}) =>
    HealthConnectState(
      enabled: enabled,
      revision: 1,
      timezone: 'Europe/Berlin',
      windowEnd: '2026-09-14',
      deviceId: device,
    );

class Gateway extends HealthConnectGateway {
  Gateway() : super(ApiClient(Dio()), () => 'test');
  HealthConnectState current = cloud();
  bool granted = true;
  bool failRead = false;
  int nativeReads = 0;
  int deviceReads = 0;
  final commands = <String>[];
  Completer<Map<String, dynamic>>? pending;

  @override
  Future<HealthConnectState> read() async {
    if (failRead) throw StateError('offline');
    return current;
  }

  @override
  Future<Map<String, dynamic>> deviceStatus({bool request = false}) async {
    deviceReads++;
    return {'supported': true, 'granted': granted, 'device_id': 'device'};
  }

  @override
  Future<Map<String, dynamic>> readDays(HealthConnectState state) async {
    nativeReads++;
    return pending == null
        ? {'days': [], 'captured_at': '2026-09-14T10:00:00Z'}
        : await pending!.future;
  }

  @override
  Future<HealthConnectState> command(
    HealthConnectState state,
    String command, {
    String? deviceId,
    Map<String, dynamic>? sample,
  }) async {
    commands.add(command);
    return current;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'foreground host leaves guest accounts alone',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSurfaceCapabilitiesProvider.overrideWithValue(
              const AppSurfaceCapabilities(
                isLocalDemo: true,
                canUseSyncedHabits: false,
              ),
            ),
            healthConnectProvider.overrideWith(
              (ref) => throw StateError('Guest must not create health access'),
            ),
          ],
          child: const HealthConnectSyncHost(child: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'foreground host syncs existing consent once and throttles resume',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthController(null);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      auth.state = const AsyncData(
        AppSession.authenticated(
          AppProfile(
            id: 'owner',
            email: 'health@example.test',
            name: 'Health test',
            timezone: 'Europe/Berlin',
            role: AppRole.user,
            onboardingDone: true,
            authProvider: 'google',
          ),
        ),
      );
      final gateway = Gateway();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith((ref) => auth),
            appSurfaceCapabilitiesProvider.overrideWithValue(
              const AppSurfaceCapabilities(
                isLocalDemo: false,
                canUseSyncedHabits: true,
                canUseSyncedExecution: true,
              ),
            ),
            healthConnectProvider.overrideWith(
              (ref) => HealthConnectController(gateway, android: true),
            ),
          ],
          child: const HealthConnectSyncHost(child: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();
      expect(gateway.commands, ['sync']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(gateway.commands, ['sync']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  test('state rejects enabled cloud without exact consent', () {
    expect(
      () => HealthConnectState.fromJson({
        'contract_version': healthConnectContractVersion,
        'enabled': true,
        'revision': 0,
        'timezone': 'Europe/Berlin',
        'window_end': '2026-09-14',
      }),
      throwsFormatException,
    );
  });

  test('opening settings does not enable or upload anything', () async {
    final gateway = Gateway();
    final controller = HealthConnectController(gateway, android: true);
    addTearDown(controller.dispose);
    await controller.load();
    expect(gateway.commands, isEmpty);
    expect(gateway.nativeReads, 0);
    expect(controller.state.cloud, isNotNull);
  });

  test('web can read state without native calls', () async {
    final gateway = Gateway();
    final controller = HealthConnectController(gateway, android: false);
    addTearDown(controller.dispose);
    await controller.load();
    expect(gateway.deviceReads, 0);
    expect(controller.state.supported, false);
  });

  test('permission decline does not enable cloud', () async {
    final gateway = Gateway()..granted = false;
    final controller = HealthConnectController(gateway, android: true);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.connect();
    expect(gateway.commands, isEmpty);
    expect(controller.state.error, isNotNull);
  });

  test('only active consent and the connected device may sync', () async {
    for (final current in [cloud(enabled: false), cloud(device: 'other')]) {
      final gateway = Gateway()..current = current;
      final controller = HealthConnectController(gateway, android: true);
      await controller.sync();
      expect(gateway.commands, isEmpty);
      expect(gateway.nativeReads, 0);
      expect(controller.state.error, isNotNull);
      controller.dispose();
    }
  });

  test('failed cloud read does not become a success or mock', () async {
    final gateway = Gateway()..failRead = true;
    final controller = HealthConnectController(gateway, android: true);
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.state.cloud, isNull);
    expect(controller.state.error, isNotNull);
    expect(gateway.commands, isEmpty);
  });

  test('account disposal during a native read prevents upload', () async {
    final gateway = Gateway()..pending = Completer<Map<String, dynamic>>();
    final controller = HealthConnectController(gateway, android: true);
    final sync = controller.sync();
    await Future<void>.delayed(Duration.zero);
    expect(gateway.nativeReads, 1);
    controller.dispose();
    gateway.pending!.complete({'days': []});
    await sync;
    expect(gateway.commands, isEmpty);
    await controller.sync();
    expect(gateway.commands, isEmpty);
  });

  test(
    'one deliberate sync sends once and exposes errors separately',
    () async {
      final gateway = Gateway();
      final controller = HealthConnectController(gateway, android: true);
      addTearDown(controller.dispose);
      await controller.sync();
      expect(gateway.commands, ['sync']);
      expect(controller.state.error, isNull);
    },
  );
}
