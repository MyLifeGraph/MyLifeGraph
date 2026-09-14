import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capabilities/app_surface_capabilities.dart';
import '../auth_providers.dart';
import '../health_connect_providers.dart';

/// A foreground refresh, not a background worker or a source of consent.
class HealthConnectSyncHost extends ConsumerStatefulWidget {
  const HealthConnectSyncHost({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<HealthConnectSyncHost> createState() =>
      _HealthConnectSyncHostState();
}

class _HealthConnectSyncHostState extends ConsumerState<HealthConnectSyncHost>
    with WidgetsBindingObserver {
  String? _owner;
  DateTime? _lastAttempt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted || _owner == null) return;
    final now = DateTime.now();
    if (_lastAttempt != null &&
        now.difference(_lastAttempt!) < const Duration(minutes: 15)) {
      return;
    }
    final controller = ref.read(healthConnectProvider.notifier);
    if (ref.read(healthConnectProvider).busy) return;
    _lastAttempt = now;
    final owner = _owner;
    await controller.load();
    if (!mounted || owner != _owner || !controller.mounted) return;
    final view = ref.read(healthConnectProvider);
    if (view.error == null &&
        view.cloud?.enabled == true &&
        view.granted &&
        view.deviceId != null &&
        view.deviceId == view.cloud?.deviceId) {
      await controller.sync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final allowed =
        android &&
        ref.watch(appSurfaceCapabilitiesProvider).canUseSyncedExecution;
    final owner = allowed
        ? ref.watch(authControllerProvider).valueOrNull?.profile.id
        : null;
    if (allowed) ref.watch(healthConnectProvider);
    if (owner != _owner) {
      _owner = owner;
      _lastAttempt = null;
      if (owner != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(_refresh()),
        );
      }
    }
    return widget.child;
  }
}
