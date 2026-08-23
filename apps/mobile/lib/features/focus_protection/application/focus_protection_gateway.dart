import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/focus_protection.dart';
import 'focus_protection_host.dart';

abstract interface class FocusProtectionGateway {
  Future<FocusProtectionStatus> readStatus();
  Future<List<InstalledLaunchableApp>> listLaunchableApps();
  Future<FocusProtectionStatus> saveConfiguration(
    FocusProtectionConfiguration configuration,
  );
  Future<void> openAccessibilitySettings();
  Future<void> openNotificationPolicySettings();
  Future<FocusProtectionStatus> activateLease({
    required String sessionId,
    required DateTime startedAt,
    required DateTime endsAt,
  });
  Future<FocusProtectionStatus> deactivateLease(String sessionId);
  Future<FocusProtectionStatus> emergencyRelease(String sessionId);
}

class MethodChannelFocusProtectionGateway implements FocusProtectionGateway {
  const MethodChannelFocusProtectionGateway({
    MethodChannel channel = const MethodChannel(
      'com.mylifegraph.app/focus_protection',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<FocusProtectionStatus> readStatus() => _status('readStatus');

  @override
  Future<List<InstalledLaunchableApp>> listLaunchableApps() async {
    final result = await _channel.invokeMethod<List<Object?>>(
      'listLaunchableApps',
    );
    return (result ?? const []).map((value) {
      if (value is! Map) {
        throw const FormatException('Invalid launchable app response.');
      }
      return InstalledLaunchableApp.fromMap(value);
    }).toList(growable: false);
  }

  @override
  Future<FocusProtectionStatus> saveConfiguration(
    FocusProtectionConfiguration configuration,
  ) {
    return _status('saveConfiguration', configuration.toMap());
  }

  @override
  Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod<void>('openAccessibilitySettings');

  @override
  Future<void> openNotificationPolicySettings() =>
      _channel.invokeMethod<void>('openNotificationPolicySettings');

  @override
  Future<FocusProtectionStatus> activateLease({
    required String sessionId,
    required DateTime startedAt,
    required DateTime endsAt,
  }) {
    return _status('activateLease', {
      'sessionId': sessionId,
      'startedAtEpochMs': startedAt.millisecondsSinceEpoch,
      'endsAtEpochMs': endsAt.millisecondsSinceEpoch,
    });
  }

  @override
  Future<FocusProtectionStatus> deactivateLease(String sessionId) =>
      _status('deactivateLease', {'sessionId': sessionId});

  @override
  Future<FocusProtectionStatus> emergencyRelease(String sessionId) =>
      _status('emergencyRelease', {'sessionId': sessionId});

  Future<FocusProtectionStatus> _status(
    String method, [
    Map<String, Object>? arguments,
  ]) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      method,
      arguments,
    );
    if (result == null) {
      throw const FormatException('Missing focus protection status.');
    }
    return FocusProtectionStatus.fromMap(result);
  }
}

class UnsupportedFocusProtectionGateway implements FocusProtectionGateway {
  UnsupportedFocusProtectionGateway();

  final _configuration = FocusProtectionConfiguration.disabled();

  FocusProtectionStatus get _status => FocusProtectionStatus(
        platformSupported: false,
        accessibilityEnabled: false,
        notificationPolicyGranted: false,
        configuration: _configuration,
        lease: null,
      );

  @override
  Future<FocusProtectionStatus> readStatus() async => _status;

  @override
  Future<List<InstalledLaunchableApp>> listLaunchableApps() async => const [];

  @override
  Future<FocusProtectionStatus> saveConfiguration(
    FocusProtectionConfiguration configuration,
  ) async =>
      _status;

  @override
  Future<void> openAccessibilitySettings() async {}

  @override
  Future<void> openNotificationPolicySettings() async {}

  @override
  Future<FocusProtectionStatus> activateLease({
    required String sessionId,
    required DateTime startedAt,
    required DateTime endsAt,
  }) async =>
      _status;

  @override
  Future<FocusProtectionStatus> deactivateLease(String sessionId) async =>
      _status;

  @override
  Future<FocusProtectionStatus> emergencyRelease(String sessionId) async =>
      _status;
}

final focusProtectionPlatformSupportedProvider = Provider<bool>((ref) {
  return isAndroidFocusProtectionHost;
});

final focusProtectionGatewayProvider = Provider<FocusProtectionGateway>((ref) {
  return ref.watch(focusProtectionPlatformSupportedProvider)
      ? const MethodChannelFocusProtectionGateway()
      : UnsupportedFocusProtectionGateway();
});
