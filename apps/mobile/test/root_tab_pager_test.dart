import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/core/navigation/root_tab_pager.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';

void main() {
  testWidgets('shared backdrop remains exposed during drag and settlement', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.liquidGlass,
        home: RootTabPager(
          index: 0,
          count: 2,
          onSettled: (_) {},
          pageBuilder: (_, index) => Text('Surface $index'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    void expectBackdrop() {
      final pages = find.byType(RootTabVisibility);
      expect(pages, findsWidgets);
      for (final page in pages.evaluate()) {
        final cover = page.findAncestorWidgetOfExactType<ColoredBox>();
        expect(cover?.color, Colors.transparent);
      }
    }

    expectBackdrop();
    final gesture = await tester.startGesture(const Offset(300, 100));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();
    expectBackdrop();
    await gesture.up();
    await tester.pump();
    expectBackdrop();
    await tester.pumpAndSettle();
    expectBackdrop();
  });
  Future<GoRouter> pump(WidgetTester tester, {bool reduced = false}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/0',
      routes: [
        for (var index = 0; index < 4; index++)
          GoRoute(
            path: '/$index',
            pageBuilder: (context, state) => MaterialPage(
              key: const ValueKey('root-tabs'),
              child: RootTabPager(
                index: index,
                count: 4,
                onSettled: (next) => context.go('/$next'),
                pageBuilder: (context, item) => Material(
                  child: Column(
                    children: [
                      SizedBox(height: 100, child: Text('Page $item')),
                      const TextField(),
                      SizedBox(
                        height: 100,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: const [
                            SizedBox(
                              width: 2000,
                              child: Text('Nested horizontal'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          children: const [
                            SizedBox(height: 2000, child: Text('Vertical')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const Scaffold(body: Text('Settings')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('finger reveals adjacent page; short slow drag restores route', (
    tester,
  ) async {
    final router = await pump(tester);
    final gesture = await tester.startGesture(const Offset(250, 50));
    await gesture.moveBy(const Offset(-25, 0));
    await tester.pump();
    await gesture.moveBy(
      const Offset(-35, 0),
      timeStamp: const Duration(milliseconds: 200),
    );
    await tester.pump();
    expect(tester.getTopLeft(find.text('Page 0')).dx, lessThan(160));
    expect(find.text('Page 1'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/0');
    await tester.pump(const Duration(milliseconds: 250));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/0');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '22 percent commits after release, including slow drags and reverse',
    (tester) async {
      final router = await pump(tester);
      for (final forward in [true, false]) {
        final gesture = await tester.startGesture(const Offset(195, 50));
        await gesture.moveBy(Offset(forward ? -25 : 25, 0));
        await tester.pump(const Duration(milliseconds: 900));
        await gesture.moveBy(Offset(forward ? -95 : 95, 0));
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          router.routeInformationProvider.value.uri.path,
          forward ? '/0' : '/1',
        );
        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          forward ? '/1' : '/0',
        );
      }
    },
  );

  testWidgets('cancel, edge drag and mouse do not navigate', (tester) async {
    final router = await pump(tester);
    final gesture = await tester.startGesture(const Offset(250, 50));
    await gesture.moveBy(const Offset(-25, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-135, 0));
    await tester.pump();
    expect(find.text('Page 1'), findsOneWidget);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/0');
    await tester.dragFrom(const Offset(195, 50), const Offset(140, 0));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/0');
    await tester.dragFrom(
      const Offset(195, 50),
      const Offset(-140, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/0');
  });

  testWidgets('nested horizontal, vertical and editing preserve route', (
    tester,
  ) async {
    final router = await pump(tester);
    await tester.dragFrom(const Offset(250, 200), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Nested horizontal')).dx, lessThan(0));
    await tester.dragFrom(const Offset(195, 400), const Offset(15, -200));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/0');
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(195, 50), const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/0');
  });

  testWidgets('route buttons and settings return stay synchronized', (
    tester,
  ) async {
    final router = await pump(tester);
    for (final index in [1, 3, 2, 0]) {
      router.go('/$index');
      await tester.pumpAndSettle();
      expect(find.text('Page $index').hitTestable(), findsOneWidget);
    }
    router.push('/settings');
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Page 0').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid root changes stay synchronized through 25 cycles', (
    tester,
  ) async {
    final router = await pump(tester);
    for (var cycle = 0; cycle < 25; cycle++) {
      router.go('/1');
      await tester.pump(const Duration(milliseconds: 30));
      router.go('/3');
      await tester.pump(const Duration(milliseconds: 30));
      router.go('/2');
      await tester.pump(const Duration(milliseconds: 30));
      router.go('/0');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/0');
      expect(find.text('Page 0').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Settings pushed while a swipe settles stays open', (
    tester,
  ) async {
    final router = await pump(tester);
    final gesture = await tester.startGesture(const Offset(250, 50));
    await gesture.moveBy(const Offset(-25, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-125, 0));
    await tester.pump(const Duration(milliseconds: 250));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 20));
    final routedBeforePush = tester
        .widget<RootTabPager>(find.byType(RootTabPager))
        .index;
    router.push('/settings');
    await tester.pumpAndSettle();
    expect(find.text('Settings').hitTestable(), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/$routedBeforePush',
    );
    expect(
      tester.widget<RootTabPager>(find.byType(RootTabPager)).index,
      routedBeforePush,
    );
    expect(
      find.text('Page $routedBeforePush').hitTestable(),
      findsOneWidget,
      reason:
          'Back must restore the routed page $routedBeforePush before Settings.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('diagonal movement does not change tabs', (tester) async {
    final router = await pump(tester);
    await tester.dragFrom(const Offset(280, 30), const Offset(-150, 90));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/0');
  });

  testWidgets(
    'resizing during a swipe keeps the settled route and reverse usable',
    (tester) async {
      final router = await pump(tester);
      final gesture = await tester.startGesture(const Offset(280, 50));
      await gesture.moveBy(const Offset(-25, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump();
      tester.view.physicalSize = const Size(600, 844);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await gesture.up();
      await tester.pumpAndSettle();
      final settled = tester
          .widget<RootTabPager>(find.byType(RootTabPager))
          .index;
      expect(settled, anyOf(0, 1));
      expect(router.routeInformationProvider.value.uri.path, '/$settled');
      expect(find.text('Page $settled').hitTestable(), findsOneWidget);
      router.go('/1');
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(250, 50), const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/0');
      expect(find.text('Page 0').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion changes tabs without a slide', (tester) async {
    final router = await pump(tester, reduced: true);
    router.go('/2');
    await tester.pumpAndSettle();
    expect(find.text('Page 2').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
