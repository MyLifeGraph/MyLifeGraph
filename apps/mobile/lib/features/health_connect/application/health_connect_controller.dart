import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/health_connect_gateway.dart';
import '../domain/health_connect_state.dart';

class HealthConnectViewState {
  const HealthConnectViewState({
    this.cloud,
    this.busy = false,
    this.supported = false,
    this.granted = false,
    this.deviceId,
    this.error,
  });
  final HealthConnectState? cloud;
  final bool busy;
  final bool supported;
  final bool granted;
  final String? deviceId;
  final String? error;
}

class HealthConnectController extends StateNotifier<HealthConnectViewState> {
  HealthConnectController(this.gateway, {required this.android})
    : super(const HealthConnectViewState());
  final HealthConnectGateway gateway;
  final bool android;

  Future<void> openSettings() => gateway.openSettings();

  Future<void> load() => _run(() async {
    final cloud = await gateway.read();
    final device = android ? await gateway.deviceStatus() : <String, dynamic>{};
    if (!mounted) return;
    state = HealthConnectViewState(
      cloud: cloud,
      supported: device['supported'] == true,
      granted: device['granted'] == true,
      deviceId: device['device_id'] as String?,
    );
  });

  Future<void> connect() => _run(() async {
    final cloud = state.cloud;
    if (cloud == null || !android) return;
    final device = await gateway.deviceStatus(request: true);
    if (!mounted) return;
    if (device['granted'] != true || device['device_id'] is! String) {
      throw StateError('Permission was not granted.');
    }
    final updated = await gateway.command(
      cloud,
      'connect',
      deviceId: device['device_id'] as String,
    );
    if (!mounted) return;
    state = HealthConnectViewState(
      cloud: updated,
      supported: true,
      granted: true,
      deviceId: device['device_id'] as String,
    );
  });

  Future<void> sync() => _run(() async {
    final cloud = await gateway.read();
    if (!mounted) return;
    final device = await gateway.deviceStatus();
    if (!mounted) return;
    if (!cloud.enabled ||
        device['granted'] != true ||
        device['device_id'] != cloud.deviceId) {
      throw StateError('Reconnect this Android device before syncing.');
    }
    final data = await gateway.readDays(cloud);
    if (!mounted) return;
    final updated = await gateway.command(
      cloud,
      'sync',
      deviceId: cloud.deviceId,
      sample: data,
    );
    if (mounted) {
      state = HealthConnectViewState(
        cloud: updated,
        supported: true,
        granted: true,
        deviceId: cloud.deviceId,
      );
    }
  });

  Future<void> disconnect({bool deleteData = false}) => _run(() async {
    final cloud = state.cloud;
    if (cloud == null) return;
    final updated = await gateway.command(
      cloud,
      deleteData ? 'delete_data' : 'disconnect',
    );
    if (mounted) {
      state = HealthConnectViewState(
        cloud: updated,
        supported: state.supported,
        granted: state.granted,
        deviceId: state.deviceId,
      );
    }
  });

  Future<void> _run(Future<void> Function() operation) async {
    if (!mounted || state.busy) return;
    state = HealthConnectViewState(
      cloud: state.cloud,
      busy: true,
      supported: state.supported,
      granted: state.granted,
      deviceId: state.deviceId,
    );
    try {
      await operation();
    } catch (_) {
      if (mounted) {
        state = HealthConnectViewState(
          cloud: state.cloud,
          supported: state.supported,
          granted: state.granted,
          deviceId: state.deviceId,
          error:
              'Could not confirm Health Connect. Check access, then reload before retrying.',
        );
      }
    } finally {
      if (mounted && state.busy) {
        state = HealthConnectViewState(
          cloud: state.cloud,
          supported: state.supported,
          granted: state.granted,
          deviceId: state.deviceId,
        );
      }
    }
  }
}
