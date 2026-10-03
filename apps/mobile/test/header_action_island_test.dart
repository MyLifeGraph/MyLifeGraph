import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/widgets/app_header_actions.dart';
import 'package:my_life_graph/core/feedback/app_haptics.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/widgets/app_page.dart';

import 'support/ui_catalog_capture.dart';

void main() {
  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('fixed title through open/close at $width, scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var calls = 0;
        var pulses = 0;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.liquidGlass,
              builder: (context, child) => AppHaptics(
                onSelection: () => pulses++,
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
              ),
              home: Scaffold(
                body: AppPage(
                  title: 'Planner',
                  compactHeader: true,
                  actions: [
                    AppHeaderActions(
                      pageActions: [
                        IconButton(
                          tooltip: 'Reload',
                          onPressed: () => calls++,
                          icon: const Icon(Icons.refresh),
                        ),
                        IconButton(
                          tooltip: 'Import',
                          onPressed: () {},
                          icon: const Icon(Icons.download),
                        ),
                      ],
                    ),
                  ],
                  children: const [Text('This week')],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final title = tester.getRect(find.text('Planner'));
        final circle = tester.getRect(
          find.byKey(const ValueKey('header-island-toggle')),
        );
        final closedSurface = tester.getRect(
          find.byKey(const ValueKey('header-action-island')),
        );
        expect(circle.width, greaterThanOrEqualTo(44));
        expect(find.byTooltip('Reload'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('header-island-toggle')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.getRect(find.text('Planner')), title);
        await tester.pumpAndSettle();
        final menu = tester.getRect(
          find.byKey(const ValueKey('header-action-menu')),
        );
        expect(menu.right, lessThanOrEqualTo(width));
        expect(menu.left, greaterThanOrEqualTo(0));
        expect(menu.top, circle.top - 2);
        expect(menu.height, closedSurface.height);
        if (scale == 1) expect(menu.left, greaterThanOrEqualTo(title.left));
        for (final button in ['Reload', 'Import', 'Inbox', 'Settings']) {
          final target = tester.getRect(find.byTooltip(button));
          expect(target.width, greaterThanOrEqualTo(44));
          expect(target.height, greaterThanOrEqualTo(44));
        }
        if (width == 390 && scale == 1) {
          tester.view.physicalSize = const Size(320, 844);
          await tester.pumpAndSettle();
          final resizedMenu = tester.getRect(
            find.byKey(const ValueKey('header-action-menu')),
          );
          final resizedToggle = tester.getRect(
            find.byKey(const ValueKey('header-island-toggle')),
          );
          expect(resizedMenu.top, resizedToggle.top - 2);
          expect(resizedMenu.right, lessThanOrEqualTo(320));
          tester.view.physicalSize = Size(width, 844);
          await tester.pumpAndSettle();
        }
        expect(
          tester.getRect(find.byKey(const ValueKey('header-island-toggle'))),
          circle,
        );
        await tester.tap(find.byTooltip('Reload'));
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(pulses, 1);
        expect(find.byTooltip('Reload'), findsNothing);
        expect(tester.getRect(find.text('Planner')), title);
        for (var i = 0; i < 5; i++) {
          await tester.tap(find.byKey(const ValueKey('header-island-toggle')));
          await tester.pump(const Duration(milliseconds: 70));
          await tester.tapAt(const Offset(10, 400));
          await tester.pumpAndSettle();
          expect(find.byTooltip('Reload'), findsNothing);
          expect(tester.getRect(find.text('Planner')), title);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('Escape dismisses actions and reduced motion stays immediate', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const Scaffold(
            body: AppPage(
              title: 'Coach',
              compactHeader: true,
              actions: [AppHeaderActions()],
              children: [],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('header-island-toggle')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Inbox').hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Inbox'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Back closes actions without leaving the current page', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AppPage(
              title: 'Planner',
              compactHeader: true,
              actions: [AppHeaderActions()],
              children: [],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('header-island-toggle')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Inbox'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Inbox'), findsNothing);
    expect(find.text('Planner'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('outside taps and scroll dismiss without consuming page input', (
    tester,
  ) async {
    var outsideCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.liquidGlass,
          home: Scaffold(
            body: AppPage(
              title: 'Planner',
              compactHeader: true,
              actions: const [AppHeaderActions()],
              children: [
                TextButton(
                  key: const ValueKey('outside-action'),
                  onPressed: () => outsideCalls++,
                  child: const Text('Outside action'),
                ),
                const SizedBox(height: 1800),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('header-island-toggle'));
    final menu = find.byKey(const ValueKey('header-action-menu'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('outside-action')));
    await tester.pumpAndSettle();
    expect(outsideCalls, 1);
    expect(menu, findsNothing);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(10, 400), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(menu, findsNothing);
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      greaterThan(0),
    );
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    tester.binding.handlePointerEvent(
      const PointerScrollEvent(
        position: Offset(10, 400),
        scrollDelta: Offset(0, 60),
      ),
    );
    await tester.pumpAndSettle();
    expect(menu, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow inline icons scroll without closing or shrinking targets',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.liquidGlass,
            home: Scaffold(
              body: AppPage(
                title: 'Planner',
                compactHeader: true,
                actions: [
                  AppHeaderActions(
                    pageActions: [
                      for (var i = 0; i < 8; i++)
                        IconButton(
                          tooltip: 'Extra $i',
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
      final title = tester.getRect(find.text('Planner'));
      await tester.tap(find.byKey(const ValueKey('header-island-toggle')));
      await tester.pumpAndSettle();
      final menu = tester.getRect(
        find.byKey(const ValueKey('header-action-menu')),
      );
      expect(menu.left, greaterThanOrEqualTo(title.right + 6));
      await tester.drag(
        find.byKey(const ValueKey('header-island-icons-scroll')),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('header-action-menu')), findsOneWidget);
      expect(find.byTooltip('Settings').hitTestable(), findsOneWidget);
      expect(
        tester.getRect(find.byTooltip('Settings')).width,
        greaterThanOrEqualTo(44),
      );
      expect(tester.getRect(find.text('Planner')), title);
      expect(tester.takeException(), isNull);
    },
  );

  if (captureUiCatalog) {
    testWidgets('capture actual Liquid Glass island states', (tester) async {
      await loadCatalogFonts();
      tester.view.physicalSize = const Size(390, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.liquidGlass,
            home: Scaffold(
              body: AppPage(
                title: 'Planner',
                compactHeader: true,
                actions: [
                  AppHeaderActions(
                    pageActions: [
                      IconButton(
                        tooltip: 'Import',
                        onPressed: () {},
                        icon: const Icon(Icons.download),
                      ),
                    ],
                  ),
                ],
                children: const [Text('This week')],
              ),
            ),
          ),
        ),
      );
      await captureCatalog(tester, 'island-closed');
      await tester.tap(find.byKey(const ValueKey('header-island-toggle')));
      await captureCatalog(tester, 'island-open');
    });
  }
}
