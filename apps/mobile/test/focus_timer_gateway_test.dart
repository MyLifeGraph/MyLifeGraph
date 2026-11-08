import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/focus/application/focus_timer_gateway.dart';
import 'package:my_life_graph/features/focus/application/focus_protection_reconciler.dart';
import 'package:my_life_graph/features/focus/domain/focus_session.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';

class TimerDevice extends FocusTimerGateway {
  FocusSession? canonical;
  int updates = 0;
  String? cleared;
  bool fail = false;
  @override
  Future<void> reconcile(FocusSession? session) async {
    updates++;
    canonical = session;
    if (fail) throw StateError('Notifications unavailable');
  }

  @override
  Future<void> clear(String id) async {
    cleared = id;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final start = DateTime.utc(2026, 11, 8, 9);
  final session = FocusSession(
    id: 'owned-session',
    status: FocusSessionStatus.active,
    startedAt: start,
    plannedMinutes: 45,
    updatedAt: start,
  );
  test(
    'local timer mirrors canonical Focus independently of blocking availability',
    () async {
      final timer = TimerDevice();
      final reconciler = FocusProtectionReconciler(
        gateway: UnsupportedFocusProtectionGateway(),
        platformSupported: false,
        timer: timer,
      );
      await reconciler.reconcile(canonicalSession: session);
      expect(timer.canonical, same(session));
      expect(timer.updates, 1);
      await reconciler.deactivate(sessionId: session.id);
      expect(timer.cleared, session.id);
    },
  );
  test(
    'cancelled read has no notification mutation and optional failure does not become protection failure',
    () async {
      final timer = TimerDevice()..fail = true;
      final reconciler = FocusProtectionReconciler(
        gateway: UnsupportedFocusProtectionGateway(),
        platformSupported: true,
        timer: timer,
      );
      await reconciler.reconcile(
        canonicalSession: session,
        shouldContinue: () => false,
      );
      expect(timer.updates, 0);
      final status = await reconciler.reconcile(canonicalSession: session);
      expect(timer.updates, 1);
      expect(status!.platformSupported, isFalse);
      expect(status.warnings, isEmpty);
    },
  );
  test(
    'native request contains only canonical timer fields; terminal clear is ID-bound',
    () async {
      const channel = MethodChannel('test/focus-timer');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      const gateway = FocusTimerGateway(channel: channel);
      await gateway.reconcile(session);
      await gateway.clear('owned-session');
      expect(calls.first.method, 'focusTimerSync');
      expect(calls.first.arguments, {
        'sessionId': 'owned-session',
        'startedAtEpochMs': start.millisecondsSinceEpoch,
        'endsAtEpochMs': start
            .add(const Duration(minutes: 45))
            .millisecondsSinceEpoch,
      });
      expect(calls.last.arguments, {'sessionId': 'owned-session'});
      calls.clear();
      await const FocusTimerGateway.disabled().reconcile(session);
      expect(calls, isEmpty);
    },
  );
}
