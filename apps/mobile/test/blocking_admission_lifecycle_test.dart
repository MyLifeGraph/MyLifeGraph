import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/focus_protection/application/blocking_gateway.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';

import 'blocking_plans_test.dart' show snapshot;
import 'support/blocking_navigation.dart';

class _AdmissionGateway extends BlockingGateway {
  _AdmissionGateway({
    this.nfc = false,
    this.stayOnScreen = true,
    this.locked = true,
  });
  final bool nfc;
  final bool stayOnScreen;
  final bool locked;
  Completer<void>? nextVisibleReply;
  Completer<void>? pendingScan;
  bool visible = false;
  bool started = false;
  bool? scanVisible;
  Map<String, Object>? scanArgs;
  final calls = <String>[];

  BlockingSnapshot value() => BlockingSnapshot({
    ...snapshot(locked: locked),
    'plans': <Map<String, Object>>[],
    'strict': {
      'enabled': locked,
      'waitSeconds': 180,
      'stayOnScreen': stayOnScreen,
      'nfc': nfc,
    },
    'unlockStarted': started,
    'nfcAvailable': true,
  });

  @override
  Future<BlockingSnapshot> command(
    String name, [
    Map<String, Object>? args,
  ]) async {
    calls.add(name);
    if (name == 'strictVisibility') {
      visible = args!['visible'] == true;
      if (!visible && stayOnScreen) started = false;
      final reply = value();
      if (visible && nextVisibleReply != null) {
        final gate = nextVisibleReply!;
        nextVisibleReply = null;
        await gate.future;
      }
      return reply;
    }
    if (name == 'requestUnlock') {
      if (!visible) throw StateError('Strict screen hidden');
      started = true;
    }
    if (name == 'cancelUnlock') started = false;
    if (name == 'nfc') {
      scanVisible = visible;
      scanArgs = args;
      await pendingScan?.future;
    }
    return value();
  }
}

Future<void> _open(WidgetTester tester, _AdmissionGateway gateway) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        blockingGatewayProvider.overrideWithValue(gateway),
        focusProtectionGatewayProvider.overrideWithValue(
          UnsupportedFocusProtectionGateway(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.liquidGlass,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(body: BlockingPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Discipline'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('delayed NFC enrollment belongs to the Unlock method route', (
    tester,
  ) async {
    final gateway = _AdmissionGateway(locked: false);
    await _open(tester, gateway);
    await tester.tap(find.text('Unlock method'));
    await enterUnlockMethod(tester);
    final setup = find.widgetWithText(TextButton, 'Set up tag');
    await tester.ensureVisible(setup);
    await tester.tap(setup);
    // The method editor deliberately keeps its saving spinner active while
    // the name dialog and pending reader belong to this enrollment.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final gate = Completer<void>();
    gateway.nextVisibleReply = gate;
    gateway.pendingScan = Completer<void>();
    await tester.tap(find.widgetWithText(TextButton, 'Scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(gateway.nextVisibleReply, isNull);
    expect(gateway.calls, isNot(contains('nfc')));
    gate.complete();
    await tester.pump();
    final scanCalls = gateway.calls.where((name) => name == 'nfc').length;
    gateway.pendingScan!.complete();
    await tester.pumpAndSettle();
    expect(scanCalls, 1);
    expect(gateway.scanArgs?['enroll'], isTrue);
    expect(gateway.scanVisible, isTrue);
    expect(
      find.byKey(const ValueKey('blocking-unlock-method-page')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('opening permissions cancels delayed NFC admission', (
    tester,
  ) async {
    final gateway = _AdmissionGateway(nfc: true);
    await _open(tester, gateway);
    gateway.started = true;
    final refresh = tester
        .state<RefreshIndicatorState>(
          find.byKey(const ValueKey('blocking-pull-refresh')),
        )
        .show();
    await tester.pumpAndSettle();
    await refresh;
    final gate = Completer<void>();
    gateway.nextVisibleReply = gate;
    gateway.pendingScan = Completer<void>();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Scan tag'));
    await tester.pumpAndSettle();
    expect(gateway.nextVisibleReply, isNull);
    await tester.tap(find.byTooltip('Permissions & limits'));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pump();
    final scanCalls = gateway.calls.where((name) => name == 'nfc').length;
    gateway.pendingScan!.complete();
    await tester.pumpAndSettle();
    expect(scanCalls, 0);
    expect(gateway.started, isFalse);
    expect(find.text('Hold your NFC tag nearby'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final scan in [false, true]) {
    testWidgets(
      'ordinary refresh preserves delayed ${scan ? 'NFC' : 'unlock'} admission',
      (tester) async {
        final gateway = _AdmissionGateway(nfc: scan, stayOnScreen: false)
          ..started = scan;
        await _open(tester, gateway);
        if (!scan) {
          await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
          await tester.pumpAndSettle();
        }
        final gate = Completer<void>();
        gateway.nextVisibleReply = gate;
        gateway.pendingScan = Completer<void>();
        await tester.tap(
          scan
              ? find.widgetWithText(OutlinedButton, 'Scan tag')
              : find.text('15 minutes'),
        );
        await tester.pumpAndSettle();
        expect(gateway.nextVisibleReply, isNull);
        final refresh = tester
            .state<RefreshIndicatorState>(
              find.byKey(const ValueKey('blocking-pull-refresh')),
            )
            .show();
        await tester.pumpAndSettle();
        await refresh;
        gate.complete();
        await tester.pump();
        final command = scan ? 'nfc' : 'requestUnlock';
        final admitted = gateway.calls.where((name) => name == command).length;
        gateway.pendingScan!.complete();
        await tester.pumpAndSettle();
        expect(admitted, 1);
        expect(gateway.started, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final returnBeforeReply in [false, true]) {
    testWidgets(
      'leaving cancels delayed NFC admission (return first: $returnBeforeReply)',
      (tester) async {
        final gateway = _AdmissionGateway(nfc: true, stayOnScreen: false);
        await _open(tester, gateway);
        // A background-enabled wait can legitimately remain pending after
        // revisiting the screen. Its next physical scan still needs a fresh tap.
        gateway.started = true;
        await tester.tap(find.text('Plans'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discipline'));
        await tester.pumpAndSettle();
        final gate = Completer<void>();
        gateway.nextVisibleReply = gate;
        gateway.pendingScan = Completer<void>();
        await tester.tap(find.widgetWithText(OutlinedButton, 'Scan tag'));
        await tester.pumpAndSettle();
        expect(gateway.nextVisibleReply, isNull);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        if (returnBeforeReply) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
        }
        gate.complete();
        await tester.pump();
        final scanCalls = gateway.calls.where((name) => name == 'nfc').length;
        // Always release the test's fake reader before asserting the race.
        gateway.pendingScan!.complete();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(scanCalls, 0);
        expect(gateway.started, isTrue);
        expect(find.text('Hold your NFC tag nearby'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final leaveViaTab in [true, false]) {
    testWidgets(
      'leaving and returning cancels delayed unlock admission (${leaveViaTab ? 'tab' : 'background'})',
      (tester) async {
        final gateway = _AdmissionGateway();
        await _open(tester, gateway);
        await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
        await tester.pumpAndSettle();
        final gate = Completer<void>();
        gateway.nextVisibleReply = gate;
        await tester.tap(find.text('15 minutes'));
        await tester.pumpAndSettle();
        expect(gateway.nextVisibleReply, isNull);
        expect(gateway.calls, isNot(contains('requestUnlock')));

        if (leaveViaTab) {
          await tester.tap(find.text('Plans'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Discipline'));
          await tester.pumpAndSettle();
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
        }
        gate.complete();
        await tester.pumpAndSettle();

        expect(gateway.calls, isNot(contains('requestUnlock')));
        expect(gateway.started, isFalse);
        expect(find.widgetWithText(FilledButton, 'Unblock'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
