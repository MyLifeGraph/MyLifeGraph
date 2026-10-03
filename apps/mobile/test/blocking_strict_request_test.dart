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
  int? remaining;
  Completer<void>? pendingRequest;
  final calls = <String>[];

  @override
  Future<BlockingSnapshot> command(
    String name, [
    Map<String, Object>? args,
  ]) async {
    calls.add(name);
    if (name == 'requestUnlock') {
      await pendingRequest?.future;
      started = true;
    }
    if (name == 'finishUnlock') locked = false;
    return BlockingSnapshot({
      ...snapshot(locked: locked),
      'plans': <Map<String, Object>>[],
      'strict': {'enabled': true, 'waitSeconds': waitSeconds, 'nfc': nfc},
      'unlockStarted': started,
      'remainingMs': remaining ?? waitSeconds * 1000,
    });
  }
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
    await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
    await tester.pumpAndSettle();
    expect(find.text('180s'), findsOneWidget);
    expect(find.text('Scan tag'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Unlock'))
          .onPressed,
      isNull,
    );
    gateway.remaining = 0;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(gateway.calls.where((c) => c == 'finishUnlock'), hasLength(1));
    expect(find.text('Unlocked · 15m'), findsOneWidget);
  });

  testWidgets(
    'queued Unblock taps request once and returning retains request',
    (tester) async {
      final gateway = _UnlockGateway()..pendingRequest = Completer<void>();
      await _open(tester, gateway);
      final button = find.widgetWithText(FilledButton, 'Unblock');
      await tester.tap(button);
      await tester.tap(button);
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
      expect(find.text('180s'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Unblock'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Immediate still requires explicit request before completion', (
    tester,
  ) async {
    final gateway = _UnlockGateway(waitSeconds: 0);
    await _open(tester, gateway);
    expect(find.widgetWithText(OutlinedButton, 'Unlock'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
    await tester.pumpAndSettle();
    final finish = find.widgetWithText(OutlinedButton, 'Unlock');
    expect(tester.widget<OutlinedButton>(finish).onPressed, isNotNull);
    await tester.tap(finish);
    await tester.pumpAndSettle();
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
      await captureCatalog(tester, 'strict-unblock-countdown');
    });
  }
}
