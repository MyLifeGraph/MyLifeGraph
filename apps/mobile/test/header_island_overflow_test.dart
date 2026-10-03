import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/widgets/app_header_actions.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/widgets/app_page.dart';

import 'support/ui_catalog_capture.dart';

void main() {
  Future<void> showHeader(
    WidgetTester tester, {
    required int pageActions,
    double width = 390,
    String title = 'Planner',
    bool reducedMotion = false,
  }) async {
    await loadCatalogFonts();
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.liquidGlass,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reducedMotion),
            child: child!,
          ),
          home: Scaffold(
            body: AppPage(
              title: title,
              compactHeader: true,
              actions: [
                AppHeaderActions(
                  pageActions: [
                    for (var i = 0; i < pageActions; i++)
                      IconButton(
                        tooltip: 'Action $i',
                        onPressed: () {},
                        icon: const Icon(Icons.refresh),
                      ),
                  ],
                ),
              ],
              children: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('header-island-toggle')));
    await tester.pumpAndSettle();
  }

  testWidgets('four fitting actions have no arrow and use full hit targets', (
    tester,
  ) async {
    await showHeader(tester, pageActions: 2);
    expect(find.byKey(const ValueKey('header-island-overflow')), findsNothing);
    final menu = tester.getRect(
      find.byKey(const ValueKey('header-action-menu')),
    );
    final title = tester.getRect(find.text('Planner'));
    expect(menu.left, greaterThanOrEqualTo(title.right + 8));
    for (final tooltip in ['Action 0', 'Action 1', 'Inbox', 'Settings']) {
      final target = tester.getRect(find.byTooltip(tooltip));
      expect(target.width, 44);
      expect(target.height, 44);
      expect(target.left, greaterThanOrEqualTo(menu.left));
      expect(target.right, lessThanOrEqualTo(menu.right));
    }
    expect(tester.takeException(), isNull);
  });

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'overflow arrow reveals last actions without closing, reduced=$reducedMotion',
      (tester) async {
        await showHeader(
          tester,
          pageActions: 6,
          width: 320,
          reducedMotion: reducedMotion,
        );
        final title = tester.getRect(find.text('Planner'));
        expect(find.byTooltip('More actions'), findsOneWidget);
        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('header-action-menu')),
          findsOneWidget,
        );
        expect(find.byTooltip('First actions'), findsOneWidget);
        expect(find.byTooltip('Settings').hitTestable(), findsOneWidget);
        expect(tester.getRect(find.text('Planner')), title);
        await tester.tap(find.byTooltip('First actions'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('More actions'), findsOneWidget);
        expect(find.byTooltip('Action 0').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('keyboard overflow activation leaves island open', (
    tester,
  ) async {
    await showHeader(tester, pageActions: 6, title: 'Coach');
      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('header-island-overflow')),
      );
    button.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('header-action-menu')), findsOneWidget);
    expect(find.byTooltip('First actions'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('header-action-menu')), findsNothing);
  });

  testWidgets('resize removes arrow when all icons fit again', (tester) async {
    await showHeader(tester, pageActions: 5, width: 320);
    expect(
      find.byKey(const ValueKey('header-island-overflow')),
      findsOneWidget,
    );
    tester.view.physicalSize = const Size(900, 844);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('header-island-overflow')), findsNothing);
    expect(find.byTooltip('Settings').hitTestable(), findsOneWidget);
    tester.view.physicalSize = const Size(320, 844);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('header-island-overflow')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  if (captureUiCatalog) {
    testWidgets('capture fitting and overflowing header polish', (
      tester,
    ) async {
      await showHeader(tester, pageActions: 2);
      await captureCatalog(tester, 'header-four-actions');
      await tester.pumpWidget(const SizedBox());
      await showHeader(tester, pageActions: 6, width: 320);
      await captureCatalog(tester, 'header-overflow');
    });
  }
}
