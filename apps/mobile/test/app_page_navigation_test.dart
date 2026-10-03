import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/composition/widgets/app_header_actions.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/navigation/app_routes.dart';
import 'package:my_life_graph/core/widgets/app_page.dart';
import 'package:my_life_graph/features/shell/presentation/main_shell.dart';

void main() {
  testWidgets('optional pull refresh ignores nested horizontal scrolling', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.liquidGlass,
        home: Scaffold(
          body: AppPage(
            title: 'Planner',
            onRefresh: () async {
              reads++;
            },
            children: [
              SizedBox(
                height: 80,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: const [
                    SizedBox(width: 1400, child: Text('Nested agenda')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final indicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    expect(
      indicator.notificationPredicate(
        ScrollUpdateNotification(
          metrics: FixedScrollMetrics(
            minScrollExtent: 0,
            maxScrollExtent: 100,
            pixels: 0,
            viewportDimension: 80,
            axisDirection: AxisDirection.right,
            devicePixelRatio: 1,
          ),
          context: tester.element(find.byType(ListView)),
          depth: 1,
        ),
      ),
      isFalse,
    );
    await tester.drag(find.byType(ListView), const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(reads, 0);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 320));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('action island fits every theme and keeps touch targets', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final theme in [
      AppTheme.dark,
      AppTheme.light,
      AppTheme.space,
      AppTheme.liquidGlass,
    ]) {
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: AppPage(
                  title: 'Planner',
                  compactHeader: true,
                  actions: [
                    AppHeaderActions(
                      pageActions: [
                        IconButton(
                          onPressed: () {},
                          tooltip: 'Reload',
                          icon: const Icon(Icons.refresh),
                        ),
                        IconButton(
                          onPressed: () {},
                          tooltip: 'Import',
                          icon: const Icon(Icons.download),
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
        final island = tester.getRect(
          find.byKey(const ValueKey('header-action-island')),
        );
        expect(island.right, lessThanOrEqualTo(320));
        final reload = find.byTooltip('Reload');
        final iconStyle = IconButtonTheme.of(tester.element(reload)).style!;
        expect(iconStyle.shape!.resolve({}), isA<CircleBorder>());
        expect(iconStyle.side!.resolve({}), BorderSide.none);
        expect(iconStyle.side!.resolve({WidgetState.focused})!.width, 2);
        const content = SizedBox(key: ValueKey('unframed-island-icon'));
        expect(
          iconStyle.backgroundBuilder!(tester.element(reload), {}, content),
          same(content),
        );
        expect(
          iconStyle.overlayColor!.resolve({WidgetState.pressed})!.a,
          greaterThan(0),
        );
        for (final key in ['global-header-inbox', 'global-header-settings']) {
          final rect = tester.getRect(find.byKey(ValueKey(key)));
          expect(rect.width, greaterThanOrEqualTo(44));
          expect(rect.height, greaterThanOrEqualTo(44));
          expect(island.contains(rect.center), isTrue);
        }
        expect(tester.takeException(), isNull);
      }
    }
  });
  for (final title in ['Planner', 'Coach']) {
    testWidgets('$title header stays fixed while Settings opens and returns', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => AppPage(
              title: title,
              compactHeader: true,
              actions: const [
                Icon(Icons.refresh),
                Icon(Icons.inbox),
                Icon(Icons.settings),
              ],
              children: const [],
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const AppPage(title: 'Settings', children: []),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      );
      await tester.pumpAndSettle();
      final titleFinder = find.text(title, skipOffstage: false);
      final original = tester.getRect(titleFinder);
      router.push('/settings');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.getRect(titleFinder).size, original.size);
      expect(
        find.descendant(
          of: find.ancestor(
            of: titleFinder,
            matching: find.byType(AppPage, skipOffstage: false),
          ),
          matching: find.byKey(
            const ValueKey('app-page-back'),
            skipOffstage: false,
          ),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('app-page-back')));
      await tester.pumpAndSettle();
      expect(tester.getRect(titleFinder), original);
      expect(find.byKey(const ValueKey('app-page-back')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact main headers align Settings at mobile and large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final scale in [1.0, 2.0]) {
      tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
      for (final title in ['Today', 'Insights', 'Planner', 'Coach']) {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.dark,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: AppPage(
                    title: title,
                    compactHeader: true,
                    actions: const [AppHeaderActions()],
                    children: const [Text('Content')],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final settings = tester.getRect(
          find.byKey(const ValueKey('global-header-settings')),
        );
        expect(settings.top, 18);
        expect(settings.right, tester.view.physicalSize.width - 20);
        expect(settings.width, greaterThanOrEqualTo(44));
        expect(settings.height, greaterThanOrEqualTo(44));
        final inbox = tester.getRect(
          find.byKey(const ValueKey('global-header-inbox')),
        );
        expect(inbox.right, lessThanOrEqualTo(settings.left));
        expect(inbox.top, settings.top);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('header Inbox opens and returns to its originating page', (
    tester,
  ) async {
    final router = _pageRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('global-header-inbox')));
    await tester.pumpAndSettle();
    expect(find.text('Inbox page'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app-page-back')));
    await tester.pumpAndSettle();
    expect(find.text('Today page'), findsOneWidget);
  });

  for (final origin in [AppRoutes.settings, AppRoutes.planner]) {
    testWidgets('native settings-style page returns to actual origin $origin', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: origin,
        routes: [
          GoRoute(
            path: origin,
            builder: (context, state) => AppPage(
              title: 'Origin',
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        body: AppPage(title: 'Integration', children: []),
                      ),
                    ),
                  ),
                  child: const Text('Open integration'),
                ),
              ],
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-page-back')), findsNothing);
      await tester.tap(find.text('Open integration'));
      await tester.pumpAndSettle();
      expect(find.text('Integration'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('app-page-back')));
      await tester.pumpAndSettle();
      expect(find.text('Origin'), findsOneWidget);
      expect(find.byKey(const ValueKey('app-page-back')), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, origin);
    });
  }

  testWidgets('Today push to Planner returns through actual history', (
    tester,
  ) async {
    final router = _pageRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Planner'));
    await tester.pumpAndSettle();
    expect(find.text('Planner page'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-page-back')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-page-back')));
    await tester.pumpAndSettle();
    expect(find.text('Today page'), findsOneWidget);

    await tester.tap(find.text('Open Planner'));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Today page'), findsOneWidget);
  });

  testWidgets('direct Planner has no meaningless back control', (tester) async {
    final router = _pageRouter(initialLocation: AppRoutes.planner);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Planner page'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-page-back')), findsNothing);
  });

  testWidgets('shell push returns through the nearest active Navigator', (
    tester,
  ) async {
    final router = _shellRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canShowCoachSurface: true,
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open shell Planner'));
    await tester.pumpAndSettle();
    expect(find.text('Planner shell page'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-page-back')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-page-back')));
    await tester.pumpAndSettle();
    expect(find.text('Today shell page'), findsOneWidget);
  });

  testWidgets('direct Preparation deep link uses its Planner fallback', (
    tester,
  ) async {
    final router = _pageRouter(initialLocation: AppRoutes.preparationPlans);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Preparation page'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app-page-back')));
    await tester.pumpAndSettle();
    expect(find.text('Planner page'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-page-back')), findsNothing);
  });

  testWidgets(
    'bottom navigation replaces history and leaves Planner root clean',
    (tester) async {
      final router = _shellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSurfaceCapabilitiesProvider.overrideWithValue(
              const AppSurfaceCapabilities(
                isLocalDemo: false,
                canUseSyncedHabits: true,
                canShowCoachSurface: true,
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('main-nav-planner-control')));
      await tester.pumpAndSettle();

      expect(find.text('Planner shell page'), findsOneWidget);
      expect(find.byKey(const ValueKey('app-page-back')), findsNothing);
      expect(router.canPop(), isFalse);
    },
  );
}

GoRouter _pageRouter({String initialLocation = AppRoutes.dashboard}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (context, state) => AppPage(
          title: 'Today page',
          actions: const [ProviderScope(child: AppHeaderActions())],
          children: [
            FilledButton(
              onPressed: () => context.push(AppRoutes.planner),
              child: const Text('Open Planner'),
            ),
          ],
        ),
      ),
      GoRoute(
        path: AppRoutes.alerts,
        builder: (context, state) =>
            const AppPage(title: 'Inbox page', children: []),
      ),
      GoRoute(
        path: AppRoutes.planner,
        builder: (context, state) => const AppPage(
          title: 'Planner page',
          backFallback: AppRoutes.dashboard,
          showBackForFallback: false,
          children: [Text('Planner root content')],
        ),
      ),
      GoRoute(
        path: AppRoutes.preparationPlans,
        builder: (context, state) => const AppPage(
          title: 'Preparation page',
          backFallback: AppRoutes.planner,
          children: [Text('Preparation content')],
        ),
      ),
    ],
  );
}

GoRouter _shellRouter() {
  return GoRouter(
    initialLocation: AppRoutes.dashboard,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            MainShell(currentPath: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (context, state) => AppPage(
              title: 'Today shell page',
              children: [
                const Text('Today shell content'),
                FilledButton(
                  onPressed: () => context.push(AppRoutes.planner),
                  child: const Text('Open shell Planner'),
                ),
              ],
            ),
          ),
          GoRoute(
            path: AppRoutes.planner,
            builder: (context, state) => const AppPage(
              title: 'Planner shell page',
              children: [Text('Planner shell content')],
            ),
          ),
          GoRoute(
            path: AppRoutes.insights,
            builder: (context, state) => const SizedBox(),
          ),
          GoRoute(
            path: AppRoutes.quickAction,
            builder: (context, state) => const SizedBox(),
          ),
          GoRoute(
            path: AppRoutes.coach,
            builder: (context, state) => const SizedBox(),
          ),
        ],
      ),
    ],
  );
}
