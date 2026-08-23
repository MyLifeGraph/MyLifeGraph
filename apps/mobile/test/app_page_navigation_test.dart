import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/navigation/app_routes.dart';
import 'package:my_life_graph/core/widgets/app_page.dart';
import 'package:my_life_graph/features/shell/presentation/main_shell.dart';

void main() {
  testWidgets('Today push to Planner returns through actual history',
      (tester) async {
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

  testWidgets('shell push returns through the nearest active Navigator',
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

    await tester.tap(find.text('Open shell Planner'));
    await tester.pumpAndSettle();
    expect(find.text('Planner shell page'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-page-back')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-page-back')));
    await tester.pumpAndSettle();
    expect(find.text('Today shell page'), findsOneWidget);
  });

  testWidgets('direct Preparation deep link uses its Planner fallback',
      (tester) async {
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

    await tester.tap(
      find.byKey(const ValueKey('main-nav-planner-control')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Planner shell page'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-page-back')), findsNothing);
    expect(router.canPop(), isFalse);
  });
}

GoRouter _pageRouter({String initialLocation = AppRoutes.dashboard}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (context, state) => AppPage(
          title: 'Today page',
          children: [
            FilledButton(
              onPressed: () => context.push(AppRoutes.planner),
              child: const Text('Open Planner'),
            ),
          ],
        ),
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
        builder: (context, state, child) => MainShell(
          currentPath: state.uri.path,
          child: child,
        ),
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
