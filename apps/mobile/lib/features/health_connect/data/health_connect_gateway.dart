import 'package:flutter/services.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/client_uuid.dart';
import '../domain/health_connect_state.dart';

class HealthConnectGateway {
  HealthConnectGateway(
    this.client,
    this.accessToken, {
    this.channel = const MethodChannel('com.mylifegraph.app/health_connect'),
  });

  final ApiClient client;
  final String Function() accessToken;
  final MethodChannel channel;

  Future<Map<String, dynamic>> deviceStatus({bool request = false}) async =>
      Map<String, dynamic>.from(
        await channel.invokeMapMethod<String, dynamic>(
              request ? 'requestPermission' : 'status',
            ) ??
            {},
      );

  Future<void> openSettings() => channel.invokeMethod<void>('openSettings');

  Future<HealthConnectState> read() async => HealthConnectState.fromJson(
    await client.getJson('/v1/health-connect', headers: _headers()),
  );

  Future<HealthConnectState> command(
    HealthConnectState state,
    String command, {
    String? deviceId,
    Map<String, dynamic>? sample,
  }) async {
    return HealthConnectState.fromJson(
      await client.postJson(
        '/v1/health-connect',
        headers: _headers(),
        body: {
          'contract_version': healthConnectContractVersion,
          'request_id': newClientUuid(),
          'expected_revision': state.revision,
          'command': command,
          'device_id': deviceId,
          'consent_version': command == 'connect'
              ? healthConnectConsentVersion
              : null,
          'timezone': sample == null ? null : state.timezone,
          'captured_at': sample?['captured_at'],
          'days': sample?['days'] ?? [],
        },
      ),
    );
  }

  Future<Map<String, dynamic>> readDays(HealthConnectState state) async =>
      Map<String, dynamic>.from(
        await channel.invokeMapMethod<String, dynamic>('readDays', {
              'timezone': state.timezone,
              'window_end': state.windowEnd,
            }) ??
            {},
      );

  Map<String, String> _headers() => {
    'Authorization': 'Bearer ${accessToken()}',
  };
}
