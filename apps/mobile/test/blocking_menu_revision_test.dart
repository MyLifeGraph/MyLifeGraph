import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/focus_protection/application/blocking_gateway.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/domain/blocking_plan.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';

import 'blocking_plans_test.dart' show snapshot;

class _Gateway extends BlockingGateway {
  int revision = 3;
  List<BlockingPlan> plans = [
    const BlockingPlan(
      id: 'one',
      name: 'Original',
      apps: {'old.app'},
      always: true,
    ),
  ];
  final saves = <Map<String, Object>>[];

  @override
  Future<BlockingSnapshot> command(
    String name, [
    Map<String, Object>? args,
  ]) async {
    if (name == 'save') {
      saves.add(args!);
      if (args['revision'] != revision) throw StateError('Revision conflict');
      plans = (args['plans'] as List)
          .map((p) => BlockingPlan.fromMap(p as Map))
          .toList();
      revision++;
    }
    return BlockingSnapshot({
      ...snapshot(),
      'revision': revision,
      'plans': plans.map((p) => p.toMap()).toList(),
    });
  }
}

Future<void> _openMenu(WidgetTester tester, _Gateway gateway) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
        home: const Scaffold(body: BlockingPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Plan options'));
  await tester.pumpAndSettle();
}

Future<void> _resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

void main() {
  for (final action in ['Pause', 'Pause 10m', 'Duplicate']) {
    testWidgets(
      '$action preserves current fields after refresh under open menu',
      (tester) async {
        final gateway = _Gateway();
        await _openMenu(tester, gateway);
        gateway.revision = 4;
        gateway.plans = [
          const BlockingPlan(
            id: 'one',
            name: 'Updated',
            apps: {'new.app'},
            focus: true,
          ),
        ];
        await _resume(tester);
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        expect(gateway.saves.single['revision'], 4);
        expect(
          gateway.plans.last.name,
          action == 'Duplicate' ? 'Updated copy' : 'Updated',
        );
        expect(gateway.plans.last.apps, {'new.app'});
        expect(gateway.plans.last.focus, isTrue);
        expect(gateway.plans.last.always, isFalse);
      },
    );
  }
  testWidgets('removed menu target cannot be duplicated after refresh', (
    tester,
  ) async {
    final gateway = _Gateway();
    await _openMenu(tester, gateway);
    gateway.revision = 4;
    gateway.plans = [];
    await _resume(tester);
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(gateway.saves, isEmpty);
    expect(gateway.plans, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
