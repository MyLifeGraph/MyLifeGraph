import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/core/navigation/root_tab_pager.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';

// Work note: shell navigation only. Owners reviewed: mobile README root-tab
// navigation; Today Overview shared root routes; visual-system Motion and root
// pager/backdrop invariants; UI copy capability/accessibility rules; verification
// Task Base, Verification Levels and Documentation Gates. No data calls here.
void main() {
  for (final pause in [40, 130, 220]) {
    testWidgets('latest tab request wins at ${pause}ms through 20 cycles', (
      tester,
    ) async {
      final harness = await _pump(tester);
      for (var cycle = 0; cycle < 20; cycle++) {
        final requested = (cycle + 2) % 4;
        harness.router.go('/${(requested + 1) % 4}');
        await tester.pump();
        await tester.pump(Duration(milliseconds: pause));
        harness.router.go('/$requested');
        await tester.pumpAndSettle();
        _expectPage(tester, harness.router, requested);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('button request during a live drag survives pointer release', (
    tester,
  ) async {
    final harness = await _pump(tester);
    final gesture = await tester.startGesture(const Offset(290, 250));
    await gesture.moveBy(const Offset(-25, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-160, 0));
    await tester.pump();
    harness.router.go('/3');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.up();
    await tester.pumpAndSettle();
    _expectPage(tester, harness.router, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pushed page during a button transition preserves Back target', (
    tester,
  ) async {
    final harness = await _pump(tester);
    harness.router.go('/3');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    harness.router.push('/details');
    await tester.pumpAndSettle();
    expect(find.text('Details').hitTestable(), findsOneWidget);
    harness.router.pop();
    await tester.pumpAndSettle();
    _expectPage(tester, harness.router, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated settled switches keep page lifetimes bounded', (
    tester,
  ) async {
    final harness = await _pump(tester);
    var animationPumps = 0;
    for (var cycle = 0; cycle < 12; cycle++) {
      for (final index in [1, 2, 3, 2, 1, 0]) {
        harness.router.go('/$index');
        animationPumps += await tester.pumpAndSettle(
          const Duration(milliseconds: 16),
        );
        _expectPage(tester, harness.router, index);
        expect(harness.mounted - harness.disposed, inInclusiveRange(1, 4));
      }
    }
    debugPrint(
      'ROOT_NAV_STRESS: 72 settled switches; '
      'mounted=${harness.mounted}, disposed=${harness.disposed}, '
      'active=${harness.mounted - harness.disposed}, '
      '16ms virtual-frame pumps=$animationPumps. '
      'Synthetic widget workload, not device FPS or API timings.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(harness.mounted, harness.disposed);
    expect(tester.takeException(), isNull);
  });
}

void _expectPage(WidgetTester tester, GoRouter router, int index) {
  expect(router.routeInformationProvider.value.uri.path, '/$index');
  expect(find.text('Page $index').hitTestable(), findsOneWidget);
  final pager = tester.widget<RootTabPager>(find.byType(RootTabPager));
  expect(pager.index, index);
}

class _Harness {
  late final GoRouter router;
  int mounted = 0;
  int disposed = 0;
}

Future<_Harness> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = _Harness();
  harness.router = GoRouter(
    initialLocation: '/0',
    routes: [
      for (var index = 0; index < 4; index++)
        GoRoute(
          path: '/$index',
          pageBuilder: (context, state) => MaterialPage<void>(
            key: const ValueKey('root-tabs'),
            child: RootTabPager(
              index: index,
              count: 4,
              onSettled: (next) => context.go('/$next'),
              pageBuilder: (_, page) =>
                  _TrackedPage(index: page, harness: harness),
            ),
          ),
        ),
      GoRoute(
        path: '/details',
        builder: (_, _) => const Scaffold(body: Text('Details')),
      ),
    ],
  );
  addTearDown(harness.router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.dark, routerConfig: harness.router),
  );
  await tester.pumpAndSettle();
  return harness;
}

class _TrackedPage extends StatefulWidget {
  const _TrackedPage({required this.index, required this.harness});
  final int index;
  final _Harness harness;

  @override
  State<_TrackedPage> createState() => _TrackedPageState();
}

class _TrackedPageState extends State<_TrackedPage> {
  @override
  void initState() {
    super.initState();
    widget.harness.mounted++;
  }

  @override
  void dispose() {
    widget.harness.disposed++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Material(child: Center(child: Text('Page ${widget.index}')));
}
