import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/focus_protection/application/blocking_gateway.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';

import 'blocking_plans_test.dart' show snapshot;
import 'support/ui_catalog_capture.dart';

class _UnlockGateway extends BlockingGateway {
  _UnlockGateway({this.waitSeconds = 180, this.nfc = false});
  final int waitSeconds;
  final bool nfc;
  bool started = false, locked = true;
  bool conditionsReady = true, enabled = true;
  String mode = 'temporary';
  bool failNextStatus = false;
  int? remaining;
  Completer<void>? pendingRequest;
  Completer<void>? pendingNfc;
  Completer<void>? pendingVisibility;
  Completer<void>? pendingRequestVisibility;
  bool visible = false;
  final calls = <String>[];

  @override
  Future<BlockingSnapshot> command(
    String name, [
    Map<String, Object>? args,
  ]) async {
    calls.add(name);
    if (name == 'status' && failNextStatus) {
      failNextStatus = false;
      throw StateError('Temporary read failure');
    }
    if (name == 'strictVisibility') {
      visible = args!['visible'] == true;
      if (!visible) started = false;
      final result = value();
      final pending = pendingVisibility;
      pendingVisibility = null;
      await pending?.future;
      if (visible) {
        final requestVisibility = pendingRequestVisibility;
        pendingRequestVisibility = null;
        await requestVisibility?.future;
      }
      return result;
    }
    if (name == 'requestUnlock') {
      if (!visible) throw StateError('Strict screen hidden');
      mode = args!['mode'] as String;
      started = true;
      final result = value();
      await pendingRequest?.future;
      return result;
    }
    if (name == 'nfc') await pendingNfc?.future;
    if (name == 'tryFinishUnlock' &&
        conditionsReady &&
        (remaining ?? waitSeconds * 1000) == 0) {
      locked = false;
      enabled = mode != 'off';
      started = false;
    }
    return value();
  }

  BlockingSnapshot value() => BlockingSnapshot({
    ...snapshot(locked: locked),
    'plans': <Map<String, Object>>[],
    'strict': {'enabled': enabled, 'waitSeconds': waitSeconds, 'nfc': nfc},
    'unlockStarted': started,
    'unlockMode': mode,
    'remainingMs': remaining ?? waitSeconds * 1000,
  });
}

Future<void> _request(WidgetTester tester, {bool permanent = false}) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(permanent ? 'Turn off Strict' : '15 minutes'));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, _UnlockGateway gateway) async {
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
  await tester.tap(find.text('Strict'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pull refresh preserves the active Strict unlock request', (
    tester,
  ) async {
    final gateway = _UnlockGateway();
    await _open(tester, gateway);
    await _request(tester);
    gateway.remaining = 149000;
    final visibilityCalls = gateway.calls
        .where((c) => c == 'strictVisibility')
        .length;
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(gateway.started, isTrue);
    expect(gateway.visible, isTrue);
    expect(find.text('149s'), findsOneWidget);
    expect(gateway.calls.where((c) => c == 'requestUnlock'), hasLength(1));
    expect(
      gateway.calls.where((c) => c == 'strictVisibility'),
      hasLength(visibilityCalls),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('choice remains single flight during delayed visibility sync', (
    tester,
  ) async {
    final gateway = _UnlockGateway();
    await _open(tester, gateway);
    await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
    await tester.pumpAndSettle();
    final delayed = Completer<void>();
    gateway.pendingRequestVisibility = delayed;
    await tester.tap(find.text('15 minutes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    delayed.complete();
    await tester.pumpAndSettle();
    expect(gateway.calls.where((c) => c == 'requestUnlock'), hasLength(1));
    expect(gateway.started, isTrue);
  });
  testWidgets('transient status failure resumes polling and auto completion', (
    tester,
  ) async {
    final gateway = _UnlockGateway();
    await _open(tester, gateway);
    await _request(tester);
    gateway.failNextStatus = true;
    gateway.remaining = 0;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(gateway.locked, isTrue);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(gateway.locked, isFalse);
    expect(find.textContaining('Temporary read failure'), findsNothing);
  });
  for (final permanent in [false, true]) {
    testWidgets('choice starts wait then auto completes ($permanent)', (
      tester,
    ) async {
      final gateway = _UnlockGateway(waitSeconds: 10);
      await _open(tester, gateway);
      await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
      await tester.pumpAndSettle();
      expect(gateway.started, isFalse);
      expect(gateway.calls, isNot(contains('requestUnlock')));
      await tester.tap(find.text(permanent ? 'Turn off Strict' : '15 minutes'));
      await tester.pumpAndSettle();
      expect(
        gateway.calls,
        contains('requestUnlock'),
        reason: gateway.calls.toString(),
      );
      expect(gateway.mode, permanent ? 'off' : 'temporary');
      expect(gateway.locked, isTrue);
      gateway.remaining = 0;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(gateway.locked, isFalse);
      expect(gateway.enabled, !permanent);
      expect(find.text(permanent ? 'Off' : 'Unlocked · 15m'), findsOneWidget);
      expect(gateway.calls.where((c) => c == 'tryFinishUnlock'), hasLength(1));
      await tester.pump(const Duration(seconds: 10));
      expect(gateway.calls.where((c) => c == 'tryFinishUnlock'), hasLength(1));
    });
  }
  testWidgets('cancel choice creates no unlock request', (tester) async {
    final gateway = _UnlockGateway();
    await _open(tester, gateway);
    await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(gateway.started, isFalse);
    expect(gateway.calls, isNot(contains('requestUnlock')));
  });
  testWidgets('zero wait still rechecks conditions and retries without error', (
    tester,
  ) async {
    final gateway = _UnlockGateway(waitSeconds: 0)..conditionsReady = false;
    await _open(tester, gateway);
    await _request(tester);
    expect(gateway.locked, isTrue);
    expect(find.text('Waiting for conditions'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(gateway.locked, isTrue);
    gateway.conditionsReady = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(gateway.locked, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('shade suspends completion until returning to focused screen', (
    tester,
  ) async {
    final gateway = _UnlockGateway();
    await _open(tester, gateway);
    await _request(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    gateway.remaining = 0;
    await tester.pump(const Duration(seconds: 5));
    expect(gateway.calls, isNot(contains('tryFinishUnlock')));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(gateway.locked, isFalse);
  });
  testWidgets('notification shade preserves the pending Strict request', (
    tester,
  ) async {
    final gateway = _UnlockGateway();
    await _open(tester, gateway);
    await _request(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(gateway.started, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(gateway.started, isTrue);
  });
  testWidgets('Strict stays locked without countdown until explicit Unblock', (
    tester,
  ) async {
    final gateway = _UnlockGateway(nfc: true);
    await _open(tester, gateway);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('180s'), findsNothing);
    expect(find.text('Scan tag'), findsNothing);
    expect(find.text('Unlock'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Unblock'), findsOneWidget);
    await tester.pump(const Duration(minutes: 20));
    await tester.pumpAndSettle();
    expect(gateway.calls, isNot(contains('requestUnlock')));
    expect(find.text('180s'), findsNothing);
    await _request(tester);
    expect(find.text('180s'), findsOneWidget);
    expect(find.text('Scan tag'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Unlock'), findsNothing);
    gateway.remaining = 0;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(gateway.calls.where((c) => c == 'tryFinishUnlock'), hasLength(1));
    expect(find.text('Unlocked · 15m'), findsOneWidget);
  });

  testWidgets('queued Unblock taps request once and leaving resets request', (
    tester,
  ) async {
    final gateway = _UnlockGateway()..pendingRequest = Completer<void>();
    await _open(tester, gateway);
    final button = find.widgetWithText(FilledButton, 'Unblock');
    final onPressed = tester.widget<FilledButton>(button).onPressed!;
    onPressed();
    onPressed();
    await tester.pumpAndSettle();
    expect(find.text('15 minutes'), findsOneWidget);
    await tester.tap(find.text('15 minutes'));
    await tester.pump();
    expect(gateway.calls.where((c) => c == 'requestUnlock'), hasLength(1));
    gateway.pendingRequest!.complete();
    await tester.pumpAndSettle();
    for (var i = 0; i < 20; i++) {
      await tester.tap(find.text('Plans'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Strict'));
      await tester.pumpAndSettle();
    }
    expect(gateway.calls.where((c) => c == 'requestUnlock'), hasLength(1));
    expect(find.text('180s'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Unblock'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late request reply cannot restore countdown after leaving', (
    tester,
  ) async {
    final gateway = _UnlockGateway()..pendingRequest = Completer<void>();
    await _open(tester, gateway);
    await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15 minutes'));
    await tester.pump();
    await tester.tap(find.text('Plans'));
    await tester.pump();
    await tester.tap(find.text('Strict'));
    await tester.pump();
    gateway.pendingRequest!.complete();
    await tester.pumpAndSettle();
    expect(gateway.started, isFalse);
    expect(find.text('180s'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Unblock'), findsOneWidget);
  });

  testWidgets('late visibility reply cannot replace newer request', (
    tester,
  ) async {
    final gateway = _UnlockGateway();
    await _open(tester, gateway);
    final stale = Completer<void>();
    gateway.pendingVisibility = stale;
    await tester.tap(find.text('Strict'));
    await tester.pump();
    await _request(tester);
    expect(find.text('180s'), findsOneWidget);
    stale.complete();
    await tester.pumpAndSettle();
    expect(find.text('180s'), findsOneWidget);
  });

  testWidgets(
    'NFC dialog is part of unlock screen and completion keeps request',
    (tester) async {
      final gateway = _UnlockGateway(nfc: true)..pendingNfc = Completer<void>();
      await _open(tester, gateway);
      await _request(tester);
      await tester.tap(find.text('Scan tag'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Hold your NFC tag nearby'), findsOneWidget);
      expect(gateway.started, isTrue);
      gateway.pendingNfc!.complete();
      await tester.pumpAndSettle();
      expect(gateway.started, isTrue);
      expect(find.text('180s'), findsOneWidget);
    },
  );

  testWidgets('background and screen lock reset and require new Unblock', (
    tester,
  ) async {
    final gateway = _UnlockGateway();
    await _open(tester, gateway);
    for (final state in [AppLifecycleState.paused, AppLifecycleState.hidden]) {
      await _request(tester);
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(gateway.started, isFalse);
      expect(find.widgetWithText(FilledButton, 'Unblock'), findsOneWidget);
    }
  });

  testWidgets('Immediate still requires explicit request before completion', (
    tester,
  ) async {
    final gateway = _UnlockGateway(waitSeconds: 0);
    await _open(tester, gateway);
    expect(find.widgetWithText(OutlinedButton, 'Unlock'), findsNothing);
    await _request(tester);
    expect(gateway.calls.where((c) => c == 'tryFinishUnlock'), hasLength(1));
    expect(find.text('Unlocked · 15m'), findsOneWidget);
  });

  if (captureUiCatalog) {
    testWidgets('Strict request states visual catalog', (tester) async {
      await loadCatalogFonts();
      final gateway = _UnlockGateway();
      await _open(tester, gateway);
      await captureCatalog(tester, 'strict-active-before-unblock');
      await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
      await tester.pumpAndSettle();
      await captureCatalog(tester, 'strict-unlock-choice');
      await tester.tap(find.text('15 minutes'));
      await tester.pumpAndSettle();
      await captureCatalog(tester, 'strict-unblock-countdown');
    });
  }
}
