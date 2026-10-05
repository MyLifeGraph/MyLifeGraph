import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/focus_protection/application/blocking_gateway.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';

import 'blocking_plans_test.dart' show FakeBlockingGateway, snapshot;
import 'support/ui_catalog_capture.dart';

class _Gateway extends FakeBlockingGateway {
  Object? icon;
  @override
  Future<Map> insights(int days) async => {
    'available': true,
    'daily': <Map>[],
    'apps': [
      {
        'packageName': 'test.app',
        'label': 'Example app',
        'milliseconds': 9000000,
        if (icon != null) 'icon': icon,
      },
    ],
  };
}

class _NoWebsiteGateway extends _Gateway {
  @override
  Future<BlockingSnapshot> command(
    String name, [
    Map<String, Object>? args,
  ]) async {
    await super.command(name, args);
    return BlockingSnapshot({...snapshot(), 'websiteConsent': false});
  }
}

Future<String> _png() async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawCircle(const Offset(16, 16), 14, Paint()..color = Colors.blue);
  final picture = recorder.endRecording();
  final image = await picture.toImage(32, 32);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final encoded = base64Encode(bytes!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return encoded;
}

Future<void> _open(
  WidgetTester tester,
  _Gateway gateway,
  ThemeData theme, {
  bool large = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(large ? 320 : 390, 844);
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
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(large ? 2 : 1),
          ),
          child: child!,
        ),
        home: const Scaffold(body: BlockingPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, 'Insights'));
  await tester.pumpAndSettle();
}

Finder get _row => find.widgetWithText(ListTile, 'Example app');
Future<void> _reload(WidgetTester tester) async {
  await tester
      .widget<RefreshIndicator>(find.byType(RefreshIndicator))
      .onRefresh();
  await tester.pumpAndSettle();
}

Future<void> _finishImage(WidgetTester tester) async {
  final finder = find.descendant(of: _row, matching: find.byType(Image));
  final provider = tester.widget<Image>(finder).image;
  await tester.runAsync(() => precacheImage(provider, tester.element(finder)));
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<RawImage>(
          find.descendant(of: finder, matching: find.byType(RawImage)),
        )
        .image,
    isNotNull,
  );
}

void main() {
  testWidgets(
    'Plans removes browser list but retains website consent disclosure',
    (tester) async {
      final gateway = _NoWebsiteGateway();
      await _open(tester, gateway, AppTheme.liquidGlass);
      await tester.tap(find.widgetWithText(TextButton, 'Plans'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Chrome · Edge · Brave'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Enable websites'),
        150,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Enable websites'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Read only the address bar in supported browsers'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Hidden address bars and other browsers may not be detected',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(gateway.calls, isNot(contains('consent')));
      expect(tester.takeException(), isNull);
    },
  );
  for (final theme in {
    'Glass': AppTheme.liquidGlass,
    'Dark': AppTheme.dark,
    'Light': AppTheme.light,
    'Space': AppTheme.space,
  }.entries) {
    for (final large in [false, true]) {
      testWidgets('app icon preserves row geometry ${theme.key} large=$large', (
        tester,
      ) async {
        final png = await tester.runAsync(_png);
        final gateway = _Gateway();
        await _open(tester, gateway, theme.value, large: large);
        final scroll = find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(_row, 150, scrollable: scroll);
        await tester.pumpAndSettle();
        final oldRow = tester.getRect(_row);
        final oldTitle = tester.getRect(find.text('Example app'));
        final oldDuration = tester.getRect(find.text('2h 30m'));
        final oldIcon = tester.getSize(
          find.descendant(of: _row, matching: find.byType(Icon)).first,
        );
        gateway.icon = png;
        await _reload(tester);
        final image = find.descendant(of: _row, matching: find.byType(Image));
        expect(image, findsOneWidget);
        await _finishImage(tester);
        expect(tester.getSize(image), oldIcon);
        expect(tester.getRect(_row), oldRow);
        expect(tester.getRect(find.text('Example app')), oldTitle);
        expect(tester.getRect(find.text('2h 30m')), oldDuration);
        for (final invalid in [
          '',
          '%%%not-base64',
          base64Encode([0, 1, 2]),
          42,
        ]) {
          gateway.icon = invalid;
          await _reload(tester);
          expect(
            find.descendant(of: _row, matching: find.byType(Icon)),
            findsOneWidget,
          );
          expect(tester.getRect(_row), oldRow);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
  if (captureUiCatalog) {
    testWidgets('insights app icons visual catalog', (tester) async {
      await loadCatalogFonts();
      final gateway = _Gateway()..icon = await tester.runAsync(_png);
      await _open(tester, gateway, AppTheme.liquidGlass);
      await _finishImage(tester);
      await captureCatalog(tester, 'blocking-insights-icons');
    });
  }
}
