import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/focus_protection/application/blocking_gateway.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/domain/blocking_plan.dart';
import 'package:my_life_graph/features/focus_protection/domain/focus_protection.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';

import 'blocking_plans_test.dart' show snapshot;
import 'support/native_blocking_preview.dart';
import 'support/ui_catalog_capture.dart';

class _CatalogConsentGateway extends UnsupportedFocusProtectionGateway {
  @override
  Future<FocusProtectionStatus> readStatus() async {
    final value = await super.readStatus();
    return FocusProtectionStatus(
      platformSupported: true,
      accessibilityEnabled: true,
      notificationPolicyGranted: false,
      lease: null,
      configuration: value.configuration.copyWith(
        consentVersions: {
          focusProtectionAppCatalogConsent: focusProtectionConsentVersion,
        },
      ),
    );
  }
}

class _RevisionGateway extends BlockingGateway {
  Map<String, Object> state = snapshot();
  int statusReads = 0;
  final saves = <Map<String, Object>>[];
  Completer<List<Map>>? pendingCatalog;
  Completer<void>? pendingSaveReply;
  Completer<void>? pendingWifiReply;
  Completer<void>? pendingNfcReply;
  int wifiRequests = 0;
  int nfcRequests = 0;
  bool strictVisible = false;
  bool? nfcScreenVisible;

  @override
  Future<BlockingSnapshot> command(
    String name, [
    Map<String, Object>? args,
  ]) async {
    if (name == 'status') statusReads++;
    if (name == 'strictVisibility') strictVisible = args?['visible'] == true;
    if (name == 'wifiPermission') {
      wifiRequests++;
      await pendingWifiReply?.future;
      state = {...state, 'wifiReady': true};
    }
    if (name == 'nfc') {
      nfcRequests++;
      nfcScreenVisible = strictVisible;
      await pendingNfcReply?.future;
      state = {
        ...state,
        'revision': 4,
        'nfcEnrolled': true,
        'nfcTags': [
          {'id': 'main', 'name': args?['name'] ?? 'Main chip'},
        ],
      };
    }
    if (name == 'removeNfcTag') {
      final tags = (state['nfcTags'] as List)
          .where((tag) => (tag as Map)['id'] != args?['id'])
          .toList();
      state = {
        ...state,
        'revision': (state['revision'] as int) + 1,
        'nfcTags': tags,
        'nfcEnrolled': tags.isNotEmpty,
      };
    }
    if (name == 'save') {
      saves.add(Map<String, Object>.from(args!));
      if (args['revision'] != state['revision']) {
        throw StateError('Settings changed. Reload and try again.');
      }
      state = {
        ...state,
        'revision': (state['revision'] as int) + 1,
        'plans': args['plans']!,
        'custom': args['custom']!,
      };
      if (pendingSaveReply != null) await pendingSaveReply!.future;
    }
    return BlockingSnapshot(state);
  }

  @override
  Future<List<Map>> catalog() async {
    if (pendingCatalog != null) return pendingCatalog!.future;
    return const [
      {'packageName': 'example.app', 'label': 'Example'},
      {'packageName': 'updated.app', 'label': 'Updated'},
    ];
  }
}

Future<void> _openDetail(
  WidgetTester tester,
  _RevisionGateway gateway, {
  bool openEditor = true,
  ThemeData? theme,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1000);
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
          _CatalogConsentGateway(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? AppTheme.liquidGlass,
        home: const Scaffold(body: BlockingPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (!openEditor) return;
  final card = find
      .ancestor(of: find.text('Study'), matching: find.byType(InkWell))
      .first;
  await Scrollable.ensureVisible(tester.element(card), alignment: .5);
  await tester.pumpAndSettle();
  expect(card.hitTestable(), findsOneWidget);
  await tester.tap(card.hitTestable());
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsOneWidget);
  expect(find.byType(BlockingPlanEditor), findsOneWidget);
}

Future<void> _resumeWithState(
  WidgetTester tester,
  _RevisionGateway gateway,
  List<BlockingPlan> plans, {
  bool detailOpen = true,
}) async {
  final reads = gateway.statusReads;
  gateway.state = {
    ...gateway.state,
    'revision': 4,
    'plans': plans.map((plan) => plan.toMap()).toList(),
  };
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
  expect(gateway.statusReads, greaterThan(reads));
  if (detailOpen) expect(find.byType(BottomSheet), findsOneWidget);
}

Future<void> _attemptDetailSave(WidgetTester tester) async {
  // Card taps now open the editor directly. Its opening revision must still
  // reject an obsolete draft without replacing the current native definition.
  if (find.byType(BlockingPlanEditor).evaluate().isNotEmpty) {
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
  }
  expect(tester.takeException(), isNull);
}

void main() {
  for (final (label, theme) in [
    ('glass', AppTheme.liquidGlass),
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
    ('space', AppTheme.space),
  ]) {
    testWidgets('NFC chips fit $label theme at narrow large text', (
      tester,
    ) async {
      final gateway = _RevisionGateway();
      gateway.state = {
        ...gateway.state,
        'nfcAvailable': true,
        'nfcEnrolled': true,
        'nfcTags': [
          {'id': 'main', 'name': 'Main chip'},
          {'id': 'backup', 'name': 'Backup chip'},
        ],
      };
      if (captureUiCatalog) await loadCatalogFonts();
      await _openDetail(tester, gateway, openEditor: false, theme: theme);
      tester.view.physicalSize = const Size(390, 960);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Strict').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Unlock method'));
      await tester.tap(find.text('Unlock method'));
      await tester.pumpAndSettle();
      if (captureUiCatalog) await captureCatalog(tester, 'nfc-chips-$label');
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('+ Add chip'));
      await tester.pumpAndSettle();
      expect(find.text('+ Add chip').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('saved chips stay visible and removal requires confirmation', (
    tester,
  ) async {
    final gateway = _RevisionGateway();
    gateway.state = {
      ...gateway.state,
      'nfcAvailable': true,
      'nfcEnrolled': true,
      'nfcTags': [
        {'id': 'main', 'name': 'Main chip'},
        {'id': 'backup', 'name': 'Backup chip'},
      ],
    };
    if (captureUiCatalog) await loadCatalogFonts();
    await _openDetail(tester, gateway, openEditor: false);
    tester.view.physicalSize = const Size(390, 960);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Strict').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Unlock method'));
    await tester.tap(find.text('Unlock method'));
    await tester.pumpAndSettle();
    expect(find.text('Main chip'), findsOneWidget);
    expect(find.text('Backup chip'), findsOneWidget);
    expect(find.text('+ Add chip'), findsOneWidget);
    if (captureUiCatalog) await captureCatalog(tester, 'nfc-chips');
    await tester.ensureVisible(find.byTooltip('Remove chip').first);
    await tester.tap(find.byTooltip('Remove chip').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Main chip'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove chip').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Main chip'), findsNothing);
    expect(find.text('Backup chip'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(stubNativeBlockingPreview);

  testWidgets(
    'resumed direct editor does not roll back a renamed native plan',
    (tester) async {
      final gateway = _RevisionGateway();
      await _openDetail(tester, gateway);
      const current = BlockingPlan(
        id: 'one',
        name: 'Updated study',
        apps: {'updated.app'},
        always: true,
      );
      const unrelated = BlockingPlan(
        id: 'other',
        name: 'Another plan',
        apps: {'example.app'},
        budget: 30,
        enabled: false,
      );
      await _resumeWithState(tester, gateway, const [current, unrelated]);
      await _attemptDetailSave(tester);
      final plans = BlockingSnapshot(gateway.state).plans;
      final retained = plans.singleWhere((plan) => plan.id == current.id);
      expect(retained.toMap(), current.toMap());
      expect(
        plans.singleWhere((plan) => plan.id == unrelated.id).toMap(),
        unrelated.toMap(),
      );
    },
  );

  testWidgets('resumed direct editor cannot recreate a deleted native plan', (
    tester,
  ) async {
    final gateway = _RevisionGateway();
    await _openDetail(tester, gateway);
    await _resumeWithState(tester, gateway, const []);
    await _attemptDetailSave(tester);
    expect(BlockingSnapshot(gateway.state).plans, isEmpty);
  });

  testWidgets('direct card editor saves successfully under its own revision', (
    tester,
  ) async {
    final gateway = _RevisionGateway();
    final original = BlockingSnapshot(gateway.state).plans.single;
    await _openDetail(tester, gateway);
    await _attemptDetailSave(tester);
    expect(gateway.saves, hasLength(1));
    expect(gateway.saves.single['revision'], 3);
    expect(BlockingSnapshot(gateway.state).revision, 4);
    expect(
      BlockingSnapshot(gateway.state).plans.single.toMap(),
      original.toMap(),
    );
    expect(find.byType(BlockingPlanEditor), findsNothing);
  });

  for (final systemBack in [false, true]) {
    testWidgets(
      'refreshed direct editor ${systemBack ? 'Back' : 'Close'} keeps native plans unchanged',
      (tester) async {
        final gateway = _RevisionGateway();
        await _openDetail(tester, gateway);
        const current = BlockingPlan(
          id: 'one',
          name: 'Updated study',
          apps: {'updated.app'},
          always: true,
        );
        await _resumeWithState(tester, gateway, const [current]);
        expect(find.byType(BlockingPlanEditor), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'Unsaved draft');
        if (systemBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.byTooltip('Close'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(BlockingPlanEditor), findsNothing);
        expect(gateway.saves, isEmpty);
        expect(BlockingSnapshot(gateway.state).revision, 4);
        expect(
          BlockingSnapshot(gateway.state).plans.single.toMap(),
          current.toMap(),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'status refresh during catalog retains opening revision and draft',
    (tester) async {
      final gateway = _RevisionGateway();
      await _openDetail(tester, gateway, openEditor: false);
      gateway.pendingCatalog = Completer<List<Map>>();
      final card = find
          .ancestor(of: find.text('Study'), matching: find.byType(InkWell))
          .first;
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.byType(BlockingPlanEditor), findsNothing);
      const current = BlockingPlan(
        id: 'one',
        name: 'Changed during catalog',
        apps: {'updated.app'},
        always: true,
      );
      await _resumeWithState(tester, gateway, const [
        current,
      ], detailOpen: false);
      gateway.pendingCatalog!.complete(const []);
      await tester.pumpAndSettle();
      expect(find.byType(BlockingPlanEditor), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Keep this draft');
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(gateway.saves, hasLength(1));
      expect(gateway.saves.single['revision'], 3);
      expect(find.byType(BlockingPlanEditor), findsOneWidget);
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(
        find.textContaining('Settings changed. Reload and try again.'),
        findsWidgets,
      );
      expect(
        BlockingSnapshot(gateway.state).plans.single.toMap(),
        current.toMap(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending save survives Back, scrim tap and downward drag', (
    tester,
  ) async {
    final gateway = _RevisionGateway();
    await _openDetail(tester, gateway);
    await tester.enterText(find.byType(TextField).first, 'Confirmed draft');
    gateway.pendingSaveReply = Completer<void>();
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    expect(gateway.saves, hasLength(1));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(BlockingPlanEditor), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(find.byType(BlockingPlanEditor), findsOneWidget);
    // Saving absorbs input; send a pointer over the visible sheet rather than
    // requiring its intentionally disabled scroll child to hit-test.
    await tester.dragFrom(
      tester.getCenter(find.byType(BlockingPlanEditor)),
      const Offset(0, 600),
    );
    await tester.pump();
    expect(find.byType(BlockingPlanEditor), findsOneWidget);
    expect(gateway.saves, hasLength(1));
    gateway.pendingSaveReply!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(BlockingPlanEditor), findsNothing);
    expect(gateway.saves, hasLength(1));
    expect(
      BlockingSnapshot(gateway.state).plans.single.name,
      'Confirmed draft',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Customize pending save blocks dismissal and duplicate writes', (
    tester,
  ) async {
    final gateway = _RevisionGateway();
    await _openDetail(tester, gateway);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customize').last);
    await tester.pumpAndSettle();
    final customize = find.widgetWithText(FilledButton, 'Customize');
    await tester.ensureVisible(customize);
    await tester.tap(customize);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Keep this title');
    gateway.pendingSaveReply = Completer<void>();
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    // A second tap before a new frame must still produce one native write.
    await tester.tap(save);
    await tester.pump();
    expect(gateway.saves, hasLength(1));
    expect(find.text('Block screen'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Block screen'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(find.text('Block screen'), findsOneWidget);
    await tester.dragFrom(
      tester.getCenter(find.byType(BottomSheet)),
      const Offset(0, 600),
    );
    await tester.pump();
    expect(find.text('Block screen'), findsOneWidget);
    expect(gateway.saves, hasLength(1));
    gateway.pendingSaveReply!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Block screen'), findsNothing);
    expect(gateway.saves, hasLength(1));
    expect(BlockingSnapshot(gateway.state).custom['title'], 'Keep this title');
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets(
    'Strict Wi-Fi enrollment is single flight before the next frame',
    (tester) async {
      final gateway = _RevisionGateway();
      await _openDetail(tester, gateway);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Strict').last);
      await tester.pumpAndSettle();
      final options = find.text('Unlock method');
      await tester.ensureVisible(options);
      await tester.tap(options);
      await tester.pumpAndSettle();
      final setup = find.widgetWithText(TextButton, 'Set up Wi-Fi');
      await tester.ensureVisible(setup);
      gateway.pendingWifiReply = Completer<void>();
      await tester.tap(setup);
      await tester.tap(setup);
      await tester.pump();
      final requestsWhilePending = gateway.wifiRequests;
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(BottomSheet), findsOneWidget);
      gateway.pendingWifiReply!.complete();
      await tester.pumpAndSettle();
      expect(requestsWhilePending, 1);
      expect(find.text('Set up Wi-Fi'), findsNothing);
      expect(gateway.saves, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Strict NFC queued activations keep setup locked until scan completes',
    (tester) async {
      final gateway = _RevisionGateway();
      gateway.state = {...gateway.state, 'nfcAvailable': true};
      await _openDetail(tester, gateway);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Strict').last);
      await tester.pumpAndSettle();
      final options = find.text('Unlock method');
      await tester.ensureVisible(options);
      await tester.tap(options);
      await tester.pumpAndSettle();
      final setup = find.widgetWithText(TextButton, 'Set up tag');
      await tester.ensureVisible(setup);
      gateway.pendingNfcReply = Completer<void>();
      // Simulate already-dispatched activations before the modal is laid out.
      // A second physical tap would hit the newly inserted modal barrier.
      final activate = tester.widget<TextButton>(setup).onPressed!;
      activate();
      activate();
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Scan'));
      await tester.pump();
      final setupCanPop = tester
          .widget<PopScope>(
            find
                .descendant(
                  of: find.byType(BottomSheet),
                  matching: find.byType(PopScope),
                )
                .first,
          )
          .canPop;
      expect(gateway.nfcRequests, 1);
      expect(
        gateway.nfcScreenVisible,
        isTrue,
        reason: 'The in-app enrollment dialog must not cancel reader mode.',
      );
      expect(find.text('Hold your NFC tag nearby'), findsOneWidget);
      gateway.pendingNfcReply!.complete();
      await tester.pumpAndSettle();
      expect(setupCanPop, isFalse);
      expect(find.text('Set up tag'), findsNothing);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(gateway.saves, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('NFC failure is readable and setup remains retryable', (
    tester,
  ) async {
    final gateway = _RevisionGateway();
    gateway.state = {...gateway.state, 'nfcAvailable': true};
    await _openDetail(tester, gateway);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Strict').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Unlock method'));
    await tester.tap(find.text('Unlock method'));
    await tester.pumpAndSettle();
    final setup = find.widgetWithText(TextButton, 'Set up tag');
    await tester.ensureVisible(setup);
    gateway.pendingNfcReply = Completer<void>();
    await tester.tap(setup);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.widgetWithText(TextButton, 'Scan'));
    await tester.pump();
    gateway.pendingNfcReply!.completeError(
      PlatformException(
        code: 'blocking_error',
        message: 'Enable app blocking first.',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hold your NFC tag nearby'), findsNothing);
    expect(
      find.text('Set up app blocking in Permissions & limits.'),
      findsWidgets,
    );
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Set up protection'),
      findsOneWidget,
    );
    expect(tester.widget<TextButton>(setup).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
