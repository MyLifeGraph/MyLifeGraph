import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../focus_protection/application/focus_protection_host.dart';
import '../domain/focus_session.dart';

/// Optional local status UI, independent of app-blocking and cloud push consent.
class FocusTimerGateway {
  const FocusTimerGateway({
    this.enabled = true,
    this.channel = const MethodChannel('com.mylifegraph.app/blocking_v2'),
  });
  const FocusTimerGateway.disabled()
    : enabled = false,
      channel = const MethodChannel('com.mylifegraph.app/blocking_v2');
  final bool enabled;
  final MethodChannel channel;
  Future<void> reconcile(FocusSession? session) async {
    if (!enabled) return;
    await channel.invokeMethod<void>('focusTimerSync', {
      'sessionId': session?.id,
      if (session != null)
        'startedAtEpochMs': session.startedAt.millisecondsSinceEpoch,
      if (session != null)
        'endsAtEpochMs': session.startedAt
            .add(Duration(minutes: session.plannedMinutes))
            .millisecondsSinceEpoch,
    });
  }

  Future<void> clear(String sessionId) async {
    if (enabled) {
      await channel.invokeMethod<void>('focusTimerClear', {
        'sessionId': sessionId,
      });
    }
  }

  Future<void> requestPermission() async {
    if (!enabled) return;
    try {
      await channel.invokeMethod<void>('focusTimerPermission');
    } catch (_) {
      /* Optional permission UI must not fail a committed Focus start. */
    }
  }

  Future<String?> takeOpen() async =>
      enabled ? channel.invokeMethod<String>('focusTimerTakeOpen') : null;
}

final focusTimerGatewayProvider = Provider<FocusTimerGateway>(
  (ref) => isAndroidFocusProtectionHost
      ? const FocusTimerGateway()
      : const FocusTimerGateway.disabled(),
);
