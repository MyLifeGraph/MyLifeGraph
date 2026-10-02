import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/focus_protection/application/blocking_gateway.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/domain/blocking_plan.dart';
import 'package:my_life_graph/features/focus_protection/domain/focus_protection.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';

import 'blocking_plans_test.dart' show snapshot;

class _ConsentGateway extends UnsupportedFocusProtectionGateway {
  _ConsentGateway({this.activeLease = false});
  final bool activeLease;
  @override
  Future<FocusProtectionStatus> readStatus() async {
    final status = await super.readStatus();
    return FocusProtectionStatus(
      platformSupported: true,
      accessibilityEnabled: true,
      notificationPolicyGranted: false,
      lease: activeLease
          ? FocusProtectionLease(
              sessionId: 'active',
              startedAt: DateTime.now(),
              endsAt: DateTime.now().add(const Duration(hours: 1)),
              state: FocusProtectionLeaseState.active,
            )
          : null,
      configuration: status.configuration.copyWith(
        consentVersions: {
          focusProtectionAppCatalogConsent: focusProtectionConsentVersion,
        },
      ),
    );
  }
}

class _Gateway extends BlockingGateway {
  _Gateway({this.delayCatalog = false, this.delayInsights = false});
  final bool delayCatalog, delayInsights;
  Map<String, Object> state = snapshot();
  final catalogs = <Completer<List<Map>>>[];
  final reads = <(int, Completer<Map>)>[];
  final calls = <String>[];
  final arguments = <Map<String, Object>>[];
  final opened = <String>[];
  Completer<BlockingSnapshot>? delayedStatus, pendingSave;
  bool failConsent = false, failStrictOnce = false;

  @override
  Future<BlockingSnapshot> command(
    String name, [
    Map<String, Object>? args,
  ]) async {
    calls.add(name);
    if (args != null) arguments.add(args);
    if (name == 'status' && delayedStatus != null) return delayedStatus!.future;
    if (name == 'save' && pendingSave != null) return pendingSave!.future;
    if (name == 'consent' && failConsent) throw StateError('Consent failed');
    if (name == 'strict' && failStrictOnce) {
      failStrictOnce = false;
      throw StateError('Strict save failed');
    }
    if (name == 'nfc') {
      state = {...state, 'revision': 4, 'nfcEnrolled': true};
    }
    return BlockingSnapshot(state);
  }

  @override
  Future<void> open(String name) async => opened.add(name);

  @override
  Future<List<Map>> catalog() async {
    final request = Completer<List<Map>>();
    catalogs.add(request);
    if (!delayCatalog) request.complete([]);
    return request.future;
  }

  @override
  Future<Map> insights(int days) async {
    final request = Completer<Map>();
    reads.add((days, request));
    if (!delayInsights) request.complete(_usage(days));
    return request.future;
  }
}

Map _usage(int days) => {
  'available': true,
  'daily': <Map>[],
  'apps': [
    {'label': 'Range $days', 'milliseconds': 60000},
  ],
};

Finder get _mainScroll => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

Future<void> _pumpPage(
  WidgetTester tester,
  _Gateway gateway, {
  bool activeFocus = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        blockingGatewayProvider.overrideWithValue(gateway),
        focusProtectionGatewayProvider.overrideWithValue(
          _ConsentGateway(activeLease: activeFocus),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.liquidGlass,
        home: const Scaffold(body: BlockingPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

Future<void> _openInsights(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Insights').last);
  await tester.pump();
}

Future<void> _retainedEditor(
  WidgetTester tester, {
  ValueChanged<BlockingPlan>? saved,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.liquidGlass,
      home: Scaffold(
        body: BlockingPlanEditor(
          plan: const BlockingPlan(
            id: 'retained',
            name: 'Study',
            apps: {'example.app'},
            focus: true,
            budget: 45,
            sites: {'x.com'},
          ),
          catalog: const [],
          usageGranted: false,
          websiteAllowed: false,
          onSave: (plan) async => saved?.call(plan),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('active Focus disables plan editing and Strict reconfiguration', (
    tester,
  ) async {
    final gateway = _Gateway();
    await _pumpPage(tester, gateway, activeFocus: true);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Add'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Strict').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Enable Strict'),
          )
          .onPressed,
      isNull,
    );
    expect(gateway.catalogs, isEmpty);
  });
  testWidgets(
    'own NFC setup advances Strict draft revision without losing fields',
    (tester) async {
      final gateway = _Gateway();
      gateway.state = {...snapshot(), 'nfcAvailable': true};
      await _pumpPage(tester, gateway);
      await tester.tap(find.widgetWithText(TextButton, 'Strict').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Enable Strict'));
      await tester.pumpAndSettle();
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .onChanged!(60);
      await tester.tap(find.text('Set up tag'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'NFC tag'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Enable');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final submitted = gateway.arguments.last;
      expect(submitted['revision'], 4);
      expect(submitted['waitSeconds'], 60);
      expect(submitted['nfc'], true);
    },
  );
  testWidgets('120 tab changes retain one page and cancel timers on disposal', (
    tester,
  ) async {
    final gateway = _Gateway();
    await _pumpPage(tester, gateway);
    for (var i = 0; i < 30; i++) {
      for (final tab in ['Strict', 'Insights', 'Customize', 'Plans']) {
        await tester.tap(find.widgetWithText(TextButton, tab).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'round $i $tab');
        expect(find.byType(BlockingPage), findsOneWidget);
      }
    }
    expect(gateway.reads.length, 30);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 90));
    expect(gateway.calls.where((v) => v == 'status').length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ten rapid Add taps while catalog pending open at most one editor',
    (tester) async {
      final gateway = _Gateway(delayCatalog: true);
      await _pumpPage(tester, gateway);
      for (var i = 0; i < 10; i++) {
        await tester.tap(find.widgetWithText(TextButton, 'Add'));
        await tester.pump();
      }
      expect(gateway.catalogs.length, 1);
      gateway.catalogs.single.complete([]);
      await tester.pumpAndSettle();
      expect(
        find.byType(BlockingPlanEditor, skipOffstage: false),
        findsOneWidget,
      );
    },
  );

  for (final staleFailure in [false, true]) {
    testWidgets(
      'new usage range survives stale ${staleFailure ? 'failure' : 'success'}',
      (tester) async {
        final gateway = _Gateway(delayInsights: true);
        await _pumpPage(tester, gateway);
        await _openInsights(tester);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Month'));
        await tester.pump();
        expect(gateway.reads.map((r) => r.$1), [7, 30]);
        gateway.reads.last.$2.complete(_usage(30));
        await tester.pumpAndSettle();
        if (staleFailure) {
          gateway.reads.first.$2.completeError(
            StateError('obsolete range request failed'),
          );
        } else {
          gateway.reads.first.$2.complete(_usage(7));
        }
        await tester.pumpAndSettle();
        expect(
          find.textContaining('obsolete range request failed'),
          findsNothing,
        );
        await tester.scrollUntilVisible(
          find.text('Range 30'),
          150,
          scrollable: _mainScroll,
        );
        expect(find.text('Range 30'), findsOneWidget);
        expect(find.text('Range 7'), findsNothing);
      },
    );
  }

  testWidgets('usage request cannot invalidate pending status refresh', (
    tester,
  ) async {
    final gateway = _Gateway();
    await _pumpPage(tester, gateway);
    gateway.delayedStatus = Completer<BlockingSnapshot>();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    await _openInsights(tester);
    gateway.delayedStatus!.complete(
      BlockingSnapshot({...snapshot(), 'attemptsToday': 42}),
    );
    await tester.pumpAndSettle();
    expect(find.text('42'), findsOneWidget);
    gateway.delayedStatus = null;
  });

  testWidgets('unavailable usage is not displayed as zero or stale data', (
    tester,
  ) async {
    final gateway = _Gateway(delayInsights: true);
    await _pumpPage(tester, gateway);
    await _openInsights(tester);
    gateway.reads.single.$2.complete({..._usage(7), 'available': false});
    await tester.pumpAndSettle();
    expect(find.text('Usage unavailable'), findsOneWidget);
    expect(find.text('Time spent'), findsNothing);
    expect(find.text('Daily usage'), findsNothing);
  });

  testWidgets('failed usage consent never launches system settings', (
    tester,
  ) async {
    final gateway = _Gateway()..failConsent = true;
    gateway.state = {
      ...snapshot(),
      'usageConsent': false,
      'usageGranted': false,
    };
    await _pumpPage(tester, gateway);
    await _openInsights(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow usage access'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Agree'));
    await tester.pumpAndSettle();
    expect(gateway.opened, isEmpty);
    expect(find.textContaining('Consent failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('strict lock disables the usage-consent handoff', (tester) async {
    final gateway = _Gateway();
    gateway.state = {...snapshot(locked: true), 'usageGranted': false};
    await _pumpPage(tester, gateway);
    await _openInsights(tester);
    await tester.pumpAndSettle();
    final button = find.widgetWithText(OutlinedButton, 'Allow usage access');
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(gateway.calls, ['status']);
  });

  testWidgets('retained daily budget can be turned Off after revoked access', (
    tester,
  ) async {
    BlockingPlan? saved;
    await _retainedEditor(tester, saved: (p) => saved = p);
    final budget = find.byType(DropdownButtonFormField<int>);
    await tester.scrollUntilVisible(budget, 200, scrollable: _mainScroll);
    final control = tester.widget<DropdownButtonFormField<int>>(budget);
    expect(control.onChanged, isNotNull);
    final dropdown = tester.widget<DropdownButton<int>>(
      find.descendant(of: budget, matching: find.byType(DropdownButton<int>)),
    );
    expect(dropdown.items!.map((i) => i.value), [0, 15, 30, 45]);
    control.onChanged!(0);
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.scrollUntilVisible(save, 200, scrollable: _mainScroll);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved!.budget, 0);
    expect(saved!.focus, isTrue);
  });

  testWidgets('retained website remains removable after revoked consent', (
    tester,
  ) async {
    await _retainedEditor(tester);
    await tester.scrollUntilVisible(
      find.textContaining('Websites ·'),
      200,
      scrollable: _mainScroll,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    final chip = find.widgetWithText(InputChip, 'x.com');
    expect(chip, findsOneWidget);
    tester.widget<InputChip>(chip).onDeleted!();
    await tester.pumpAndSettle();
    expect(chip, findsNothing);
    expect(find.widgetWithText(TextField, 'Add domain'), findsNothing);
  });

  testWidgets('Strict failure retains wait and charger draft for retry', (
    tester,
  ) async {
    final gateway = _Gateway()..failStrictOnce = true;
    await _pumpPage(tester, gateway);
    await tester.tap(find.widgetWithText(TextButton, 'Strict').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Enable Strict'));
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>),
        )
        .onChanged!(60);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Charger connected'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Enable');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Unlock method'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Strict save failed'), findsWidgets);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Unlock method'),
      ),
      findsNothing,
    );
    final strict = gateway.arguments
        .where((a) => a.containsKey('waitSeconds'))
        .toList();
    expect(strict.length, 2);
    for (final attempt in strict) {
      expect(attempt['waitSeconds'], 60);
      expect(attempt['power'], true);
      expect(attempt['revision'], 3);
    }
  });

  testWidgets('pending customization save freezes keyboard edits', (
    tester,
  ) async {
    final gateway = _Gateway()..pendingSave = Completer<BlockingSnapshot>();
    await _pumpPage(tester, gateway);
    await tester.tap(find.widgetWithText(TextButton, 'Customize').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Customize'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Saved title');
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.readOnly, isTrue);
    }
    expect(tester.testTextInput.hasAnyClients, isFalse);
    gateway.pendingSave!.complete(BlockingSnapshot(snapshot()));
    await tester.pumpAndSettle();
    expect((gateway.arguments.single['custom'] as Map)['title'], 'Saved title');
  });

  testWidgets('timer-only expired plan is not labeled Scheduled', (
    tester,
  ) async {
    final gateway = _Gateway();
    gateway.state = {
      ...snapshot(),
      'plans': [
        BlockingPlan(
          id: 'expired',
          name: 'Old timer',
          apps: const {'example.app'},
          until: DateTime.now()
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        ).toMap(),
      ],
    };
    await _pumpPage(tester, gateway);
    await tester.scrollUntilVisible(
      find.text('Expired'),
      150,
      scrollable: _mainScroll,
    );
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('Scheduled'), findsNothing);
  });

  testWidgets('timer refresh happens after boundary and is canceled on pause', (
    tester,
  ) async {
    final gateway = _Gateway();
    final until = DateTime.now()
        .add(const Duration(seconds: 10))
        .millisecondsSinceEpoch;
    gateway.state = {
      ...snapshot(),
      'plans': [
        BlockingPlan(
          id: 'timer',
          name: 'Short timer',
          apps: const {'example.app'},
          until: until,
        ).toMap(),
      ],
    };
    await _pumpPage(tester, gateway);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(
      gateway.calls.where((v) => v == 'status').length,
      greaterThanOrEqualTo(2),
    );
    final before = gateway.calls.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 2));
    expect(gateway.calls.length, before);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  });

  test('expired timer is distinct from retained recurring rules', () {
    final until = DateTime.now()
        .subtract(const Duration(minutes: 1))
        .millisecondsSinceEpoch;
    expect(
      BlockingPlan(id: 'timer', name: 'Timer', until: until).expired,
      isTrue,
    );
    expect(
      BlockingPlan(
        id: 'focus',
        name: 'Focus',
        until: until,
        focus: true,
      ).expired,
      isFalse,
    );
    expect(
      BlockingPlan(
        id: 'weekly',
        name: 'Weekly',
        until: until,
        windows: const [BlockingWindow()],
      ).expired,
      isFalse,
    );
  });
}
