import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/focus_protection/application/blocking_gateway.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/domain/blocking_plan.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';

import 'blocking_plans_test.dart' show FakeBlockingGateway, snapshot;
import 'support/ui_catalog_capture.dart';

class _Gateway extends FakeBlockingGateway {
  int statusReads = 0, usageReads = 0;
  bool failNext = false;
  Completer<BlockingSnapshot>? delayed;
  Map<String, Object> value = snapshot();

  @override
  Future<BlockingSnapshot> command(
    String name, [
    Map<String, Object>? args,
  ]) async {
    if (name == 'status') {
      statusReads++;
      if (failNext) {
        failNext = false;
        throw StateError('Temporary refresh failure');
      }
      if (delayed != null) return delayed!.future;
    }
    return BlockingSnapshot(value);
  }

  @override
  Future<Map> insights(int days) async {
    usageReads++;
    return {
      'available': true,
      'daily': <Map>[],
      'apps': [
        {'label': 'Usage read $usageReads', 'milliseconds': 60000},
      ],
    };
  }
}

Finder get _scroll => find
    .descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is ListView || widget is CustomScrollView,
      ),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _open(
  WidgetTester tester,
  _Gateway gateway,
  String tab, {
  ThemeData? theme,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1000);
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
        theme: theme ?? AppTheme.liquidGlass,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(body: BlockingPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, tab));
  await tester.pumpAndSettle();
}

Future<void> _pull(WidgetTester tester) async {
  await tester.drag(_scroll, const Offset(0, 400));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  for (final theme in {
    'Liquid Glass': AppTheme.liquidGlass,
    'Dark': AppTheme.dark,
    'Light': AppTheme.light,
    'Space': AppTheme.space,
  }.entries) {
    for (final tab in ['Plans', 'Strict', 'Insights', 'Customize']) {
      testWidgets('pull refreshes $tab in ${theme.key}', (tester) async {
        final gateway = _Gateway();
        await _open(tester, gateway, tab, theme: theme.value);
        expect(find.byTooltip('Refresh'), findsNothing);
        expect(find.byTooltip('Permissions & limits'), findsOneWidget);
        expect(
          tester.getTopLeft(find.byTooltip('Permissions & limits')).dy,
          closeTo(tester.getTopLeft(find.text('App blocking')).dy, 4),
        );
        expect(
          tester.getTopLeft(find.byTooltip('Permissions & limits')).dx,
          greaterThan(tester.getTopRight(find.text('App blocking')).dx),
        );
        expect(find.byType(RefreshIndicator), findsOneWidget);
        final reads = gateway.statusReads, usage = gateway.usageReads;
        await _pull(tester);
        await tester.pumpAndSettle();
        expect(gateway.statusReads, reads + 1);
        expect(gateway.usageReads, usage + (tab == 'Insights' ? 1 : 0));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('pending refresh shows progress and coalesces requests', (
    tester,
  ) async {
    final gateway = _Gateway();
    await _open(tester, gateway, 'Plans');
    gateway.delayed = Completer<BlockingSnapshot>();
    final before = gateway.statusReads;
    await _pull(tester);
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    final indicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final repeat = indicator.onRefresh();
    await tester.pump();
    expect(gateway.statusReads, before + 1);
    gateway.delayed!.complete(BlockingSnapshot(gateway.value));
    await repeat;
    await tester.pumpAndSettle();
    expect(find.byType(RefreshProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh is ignored while a plan is being reordered', (
    tester,
  ) async {
    final gateway = _Gateway();
    await _open(tester, gateway, 'Plans');
    final list = tester.widget<SliverReorderableList>(
      find.byType(SliverReorderableList),
    );
    final indicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final before = gateway.statusReads;
    list.onReorderStart!(0);
    await indicator.onRefresh();
    expect(gateway.statusReads, before);
    list.onReorderEnd!(0);
    await indicator.onRefresh();
    await tester.pumpAndSettle();
    expect(gateway.statusReads, before + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed refresh retains data and succeeds on retry', (
    tester,
  ) async {
    final gateway = _Gateway();
    await _open(tester, gateway, 'Insights');
    final before = gateway.usageReads;
    gateway.failNext = true;
    await _pull(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Temporary refresh failure'), findsOneWidget);
    expect(gateway.usageReads, before);
    expect(find.text('Usage read $before'), findsOneWidget);
    await _pull(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Temporary refresh failure'), findsNothing);
    expect(gateway.usageReads, before + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('downward scrolling below the top does not refresh', (
    tester,
  ) async {
    final gateway = _Gateway()
      ..value = {
        ...snapshot(),
        'plans': [
          for (var i = 0; i < 20; i++)
            BlockingPlan(
              id: '$i',
              name: 'Plan $i',
              apps: const {'example.app'},
              always: true,
            ).toMap(),
        ],
      };
    await _open(tester, gateway, 'Plans');
    await tester.drag(_scroll, const Offset(0, -900));
    await tester.pumpAndSettle();
    final before = gateway.statusReads;
    await tester.drag(_scroll, const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(gateway.statusReads, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late refresh after tab change or disposal is safe', (
    tester,
  ) async {
    final gateway = _Gateway();
    await _open(tester, gateway, 'Insights');
    final usage = gateway.usageReads;
    gateway.delayed = Completer<BlockingSnapshot>();
    await _pull(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Plans'));
    await tester.pump(const Duration(milliseconds: 300));
    gateway.delayed!.complete(BlockingSnapshot(gateway.value));
    await tester.pumpAndSettle();
    expect(gateway.usageReads, usage);
    gateway.delayed = Completer<BlockingSnapshot>();
    await _pull(tester);
    await tester.pumpWidget(const SizedBox());
    gateway.delayed!.complete(BlockingSnapshot(gateway.value));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  if (captureUiCatalog) {
    testWidgets('pull-refresh compact header visual catalog', (tester) async {
      await loadCatalogFonts();
      await _open(tester, _Gateway(), 'Strict');
      await captureCatalog(tester, 'blocking-header-pull-refresh');
    });
  }
}
