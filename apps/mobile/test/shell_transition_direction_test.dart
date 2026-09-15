import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/navigation/app_routes.dart';
import 'package:my_life_graph/features/shell/presentation/main_shell.dart';

void main() {
  for (final useSwipe in [false, true]) {
    testWidgets('root transition follows both directions, swipe=$useSwipe', (tester) async {
      final router = await _pump(tester);
      addTearDown(router.dispose);
      for (final (path, label, forward) in [
        (AppRoutes.insights, 'Insights', true),
        (AppRoutes.planner, 'Planner', true),
        (AppRoutes.coach, 'Coach', true),
        (AppRoutes.planner, 'Planner', false),
        (AppRoutes.insights, 'Insights', false),
        (AppRoutes.dashboard, 'Today', false),
      ]) {
        if (useSwipe) {
          await tester.dragFrom(const Offset(195, 220), Offset(forward ? -140 : 140, 0));
        } else {
          await tester.tap(find.text(label));
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(router.routeInformationProvider.value.uri.path, path);
        final transition = tester.widget<SlideTransition>(find.ancestor(
          of: find.byKey(ValueKey('body-$path')),
          matching: find.byKey(const ValueKey('shell-directional-transition'))).first);
        expect(transition.position.value.dx, forward ? greaterThan(0) : lessThan(0));
        await tester.pumpAndSettle();
        expect(transition.position.value, Offset.zero);
      }
      router.push(AppRoutes.settings);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shell-directional-transition')), findsNothing);
      router.pop();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, AppRoutes.dashboard);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion has no root slide', (tester) async {
    final router = await _pump(tester, reducedMotion: true);
    addTearDown(router.dispose);
    await tester.tap(find.text('Coach'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.coach);
    expect(find.byKey(const ValueKey('shell-directional-transition')), findsNothing);
  });
}

Future<GoRouter> _pump(WidgetTester tester, {bool reducedMotion = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: AppRoutes.dashboard, routes: [
    ShellRoute(builder: (context, state, child) => MainShell(currentPath: state.uri.path, child: child), routes: [
      for (final path in [AppRoutes.dashboard, AppRoutes.insights, AppRoutes.planner, AppRoutes.coach, AppRoutes.settings])
        GoRoute(path: path, builder: (_, _) => Scaffold(body: SizedBox.expand(key: ValueKey('body-$path')))),
    ]),
  ]);
  await tester.pumpWidget(ProviderScope(overrides: [
    appSurfaceCapabilitiesProvider.overrideWithValue(const AppSurfaceCapabilities(
      isLocalDemo: false, canUseSyncedHabits: true, canUseSyncedExecution: true, canShowCoachSurface: true)),
  ], child: MaterialApp.router(routerConfig: router,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion), child: child!))));
  await tester.pumpAndSettle();
  return router;
}
