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

class _LegacyGateway extends UnsupportedFocusProtectionGateway {
  @override
  Future<FocusProtectionStatus> readStatus() async {
    final status = await super.readStatus();
    return FocusProtectionStatus(
      platformSupported: true,
      accessibilityEnabled: true,
      notificationPolicyGranted: false,
      configuration: status.configuration,
      lease: null,
    );
  }
}

class _PlansGateway extends BlockingGateway {
  Map<String, Object> state = snapshot();
  int statusReads = 0;
  final saves = <Map<String, Object>>[];

  @override
  Future<BlockingSnapshot> command(
    String name, [
    Map<String, Object>? args,
  ]) async {
    if (name == 'status') statusReads++;
    if (name == 'save') {
      saves.add(Map<String, Object>.from(args!));
      if (args['revision'] != state['revision']) {
        throw StateError('Settings changed. Reload and try again.');
      }
      state = {
        ...state,
        'revision': (state['revision'] as int) + 1,
        'plans': args['plans']!,
      };
    }
    return BlockingSnapshot(state);
  }
}

Future<void> _openOptions(WidgetTester tester, _PlansGateway gateway) async {
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
        focusProtectionGatewayProvider.overrideWithValue(_LegacyGateway()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: BlockingPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final options = find.byTooltip('Plan options');
  await tester.ensureVisible(options);
  await tester.tap(options);
  await tester.pumpAndSettle();
  expect(find.text('Pause'), findsOneWidget);
}

Future<void> _reloadPlans(
  WidgetTester tester,
  _PlansGateway gateway,
  List<BlockingPlan> plans, {
  bool optionsOpen = true,
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
  if (optionsOpen) expect(find.text('Pause'), findsOneWidget);
}

void main() {
  testWidgets('retained popup Pause preserves refreshed plan definition', (
    tester,
  ) async {
    final gateway = _PlansGateway();
    await _openOptions(tester, gateway);
    const current = BlockingPlan(
      id: 'one',
      name: 'Updated plan',
      apps: {'updated.app'},
      always: true,
    );
    await _reloadPlans(tester, gateway, const [current]);
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    final retained = BlockingSnapshot(gateway.state).plans.single;
    expect(gateway.saves, hasLength(1));
    expect(gateway.saves.single['revision'], 4);
    expect(retained.enabled, isFalse);
    expect(retained.name, current.name);
    expect(retained.apps, current.apps);
    expect(retained.always, current.always);
    expect(retained.focus, current.focus);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retained popup Pause cannot recreate deleted plan', (
    tester,
  ) async {
    final gateway = _PlansGateway();
    await _openOptions(tester, gateway);
    await _reloadPlans(tester, gateway, const []);
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(BlockingSnapshot(gateway.state).plans, isEmpty);
    expect(gateway.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Delete confirmation preserves plans refreshed while open', (
    tester,
  ) async {
    final gateway = _PlansGateway();
    await _openOptions(tester, gateway);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete plan?'), findsOneWidget);
    const current = BlockingPlan(
      id: 'one',
      name: 'Updated plan',
      apps: {'updated.app'},
      always: true,
    );
    const unrelated = BlockingPlan(
      id: 'other',
      name: 'Another plan',
      apps: {'other.app'},
      focus: true,
    );
    await _reloadPlans(tester, gateway, const [
      current,
      unrelated,
    ], optionsOpen: false);
    await tester.tap(find.widgetWithText(FilledButton, 'Agree'));
    await tester.pumpAndSettle();
    expect(gateway.saves, hasLength(1));
    expect(gateway.saves.single['revision'], 4);
    expect(
      BlockingSnapshot(gateway.state).plans.single.toMap(),
      unrelated.toMap(),
    );
    expect(tester.takeException(), isNull);
  });
}
