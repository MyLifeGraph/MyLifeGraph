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
import 'support/blocking_navigation.dart';

class _UnlockGateway extends BlockingGateway {
  _UnlockGateway({
    this.waitSeconds = 180,
    this.nfc = false,
    this.stayOnScreen = true,
  });
  final int waitSeconds;
  final bool nfc;
  final bool stayOnScreen;
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
  final nfcCalls = <Map<String, Object>>[];
  List<Map<String, String>> tags = [];

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
      if (!visible && stayOnScreen) started = false;
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
    if (name == 'cancelUnlock') started = false;
    if (name == 'nfc') {
      nfcCalls.add(Map.of(args!));
      await pendingNfc?.future;
    }
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
    'strict': {
      'enabled': enabled,
      'waitSeconds': waitSeconds,
      'nfc': nfc,
      'stayOnScreen': stayOnScreen,
    },
    'unlockStarted': started,
    'unlockMode': mode,
    'revision': 7,
    'nfcTags': tags,
    'remainingMs': remaining ?? waitSeconds * 1000,
  });
}

Future<void> _request(WidgetTester tester, {bool permanent = false}) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(permanent ? 'Turn off Discipline' : '15 minutes'));
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
        debugShowCheckedModeBanner: false,
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
  testWidgets(
    'replacement enrollment stays locked and carries recovery revision',
    (tester) async {
      final gateway = _UnlockGateway(nfc: true);
      if (captureUiCatalog) {
        await loadCatalogFonts();
      }
      await _open(tester, gateway);
      await tester.ensureVisible(find.text('Lost NFC chip?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lost NFC chip?'));
      await tester.pumpAndSettle();
      expect(find.text('Old chips stay valid.'), findsOneWidget);
      if (captureUiCatalog) {
        await captureCatalog(tester, 'nfc-replacement-dialog');
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Scan'));
      await tester.pumpAndSettle();
      expect(gateway.nfcCalls, hasLength(1));
      expect(gateway.nfcCalls.single['recovery'], true);
      expect(gateway.nfcCalls.single['enroll'], true);
      expect(gateway.nfcCalls.single['revision'], 7);
      expect(gateway.locked, true);
      expect(gateway.started, false);
      expect(gateway.calls, isNot(contains('requestUnlock')));
    },
  );

  testWidgets('cancel replacement performs no scan', (tester) async {
    final gateway = _UnlockGateway(nfc: true);
    await _open(tester, gateway);
    await tester.ensureVisible(find.text('Lost NFC chip?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lost NFC chip?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(gateway.nfcCalls, isEmpty);
    expect(gateway.locked, true);
  });

  testWidgets('full chip list requires explicit replacement selection', (
    tester,
  ) async {
    final gateway = _UnlockGateway(nfc: true)
      ..tags = List.generate(8, (i) => {'id': 'id$i', 'name': 'Chip $i'});
    await _open(tester, gateway);
    await tester.ensureVisible(find.text('Lost NFC chip?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lost NFC chip?'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Scan'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chip 2').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Scan'));
    await tester.pumpAndSettle();
    expect(gateway.nfcCalls.single['replaceId'], 'id2');
    expect(gateway.locked, true);
  });

  testWidgets('Stay focused cancels request without disabling Discipline', (
    tester,
  ) async {
    final gateway = _UnlockGateway();
    await _open(tester, gateway);
    await _request(tester);
    expect(find.text('Stay on this screen'), findsOneWidget);
    await tester.ensureVisible(find.text('Stay focused'));
    await tester.tap(find.text('Stay focused'));
    await tester.pumpAndSettle();
    expect(gateway.started, isFalse);
    expect(gateway.locked, isTrue);
    expect(gateway.enabled, isTrue);
    expect(find.text('Unblock'), findsOneWidget);
    expect(find.text('Stay on this screen'), findsNothing);
  });

  testWidgets('background option retains request across tabs and paused app', (
    tester,
  ) async {
    final gateway = _UnlockGateway(stayOnScreen: false);
    await _open(tester, gateway);
    await _request(tester);
    expect(find.text('Stay on this screen'), findsNothing);
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    expect(gateway.started, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(gateway.started, isTrue);
    await tester.tap(find.text('Discipline'));
    await tester.pumpAndSettle();
    expect(find.text('3:00'), findsOneWidget);
  });
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
    expect(find.text('2:29'), findsOneWidget);
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
      await tester.tap(
        find.text(permanent ? 'Turn off Discipline' : '15 minutes'),
      );
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
    expect(find.text('3:00'), findsNothing);
    expect(find.text('Scan tag'), findsNothing);
    expect(find.text('Unlock'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Unblock'), findsOneWidget);
    await tester.pump(const Duration(minutes: 20));
    await tester.pumpAndSettle();
    expect(gateway.calls, isNot(contains('requestUnlock')));
    expect(find.text('3:00'), findsNothing);
    await _request(tester);
    expect(find.text('3:00'), findsOneWidget);
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
      await tester.tap(find.text('Discipline'));
      await tester.pumpAndSettle();
    }
    expect(gateway.calls.where((c) => c == 'requestUnlock'), hasLength(1));
    expect(find.text('3:00'), findsNothing);
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
    await tester.tap(find.text('Discipline'));
    await tester.pump();
    gateway.pendingRequest!.complete();
    await tester.pumpAndSettle();
    expect(gateway.started, isFalse);
    expect(find.text('3:00'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Unblock'), findsOneWidget);
  });

  testWidgets('late visibility reply cannot replace newer request', (
    tester,
  ) async {
    final gateway = _UnlockGateway();
    await _open(tester, gateway);
    final stale = Completer<void>();
    gateway.pendingVisibility = stale;
    await tester.tap(find.text('Discipline'));
    await tester.pump();
    await _request(tester);
    expect(find.text('3:00'), findsOneWidget);
    stale.complete();
    await tester.pumpAndSettle();
    expect(find.text('3:00'), findsOneWidget);
  });

  testWidgets(
    'NFC dialog is part of unlock screen and completion keeps request',
    (tester) async {
      final gateway = _UnlockGateway(nfc: true)..pendingNfc = Completer<void>();
      await _open(tester, gateway);
      await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 minutes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Hold your NFC tag nearby'), findsOneWidget);
      expect(gateway.calls.where((c) => c == 'nfc'), hasLength(1));
      expect(gateway.started, isTrue);
      gateway.pendingNfc!.complete();
      await tester.pumpAndSettle();
      expect(gateway.started, isTrue);
      expect(find.text('3:00'), findsOneWidget);
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
    testWidgets('dedicated Unlock settings and method visual catalog', (
      tester,
    ) async {
      await loadCatalogFonts();
      final gateway = _UnlockGateway(nfc: true, stayOnScreen: false)
        ..enabled = false
        ..locked = false;
      await _open(tester, gateway);
      await tester.tap(find.text('Unlock method'));
      await tester.pumpAndSettle();
      await captureCatalog(tester, 'unlock-settings-navigation');
      await enterUnlockMethod(tester);
      await captureCatalog(tester, 'unlock-method');
    });
    testWidgets('NFC unlock walkthrough visual catalog', (tester) async {
      await loadCatalogFonts();
      final gateway = _UnlockGateway(waitSeconds: 0, nfc: true)
        ..pendingNfc = Completer<void>();
      await _open(tester, gateway);
      await captureCatalog(tester, 'nfc-strict-active');
      await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
      await tester.pumpAndSettle();
      await captureCatalog(tester, 'nfc-unlock-choice');
      await tester.tap(find.text('Turn off Discipline'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // The pending native scan deliberately keeps its progress indicator alive.
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../../.tools/ui-catalog/${const String.fromEnvironment('UI_CATALOG_VARIANT', defaultValue: 'before')}/nfc-scan.png',
        ),
      );
      gateway.pendingNfc!.complete();
      await tester.pumpAndSettle();
      await captureCatalog(tester, 'nfc-strict-off');
      expect(gateway.enabled, isFalse);
    });

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
