import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/shell/presentation/shell_swipe_region.dart';

void main() {
  testWidgets('only clear horizontal swipes switch pages', (tester) async {
    final directions = <bool>[];
    await tester.pumpWidget(MaterialApp(home: ShellSwipeRegion(
      onHorizontalSwipe: directions.add,
      child: const SizedBox.expand(),
    )));
    final surface = find.byType(ShellSwipeRegion);
    await tester.drag(surface, const Offset(20, -200));
    await tester.drag(surface, const Offset(-60, 0));
    await tester.drag(surface, const Offset(-160, -100));
    expect(directions, isEmpty);
    await tester.drag(surface, const Offset(-180, 5));
    await tester.drag(surface, const Offset(180, 0));
    expect(directions, [true, false]);
  });

  testWidgets('vertical scrolling and nested horizontal scrollers keep gestures', (tester) async {
    var switches = 0;
    final vertical = ScrollController();
    final horizontal = ScrollController();
    addTearDown(vertical.dispose);
    addTearDown(horizontal.dispose);
    await tester.pumpWidget(MaterialApp(home: ShellSwipeRegion(
      onHorizontalSwipe: (_) => switches++,
      child: ListView(controller: vertical, children: [
        SizedBox(height: 150, child: ListView(
          controller: horizontal, scrollDirection: Axis.horizontal,
          children: const [SizedBox(width: 2000)],
        )),
        const SizedBox(height: 2000),
      ]),
    )));
    await tester.dragFrom(const Offset(300, 80), const Offset(-180, 0));
    expect(horizontal.offset, greaterThan(0));
    await tester.dragFrom(const Offset(300, 350), const Offset(15, -180));
    expect(vertical.offset, greaterThan(0));
    expect(switches, 0);
  });

  testWidgets('upward shortcut accepts only deliberate upward drag', (tester) async {
    var opens = 0;
    await tester.pumpWidget(MaterialApp(home: Center(child: ShellSwipeRegion(
      onSwipeUp: () => opens++,
      child: const SizedBox(width: 300, height: 60),
    ))));
    final surface = find.byType(ShellSwipeRegion);
    await tester.tap(surface);
    await tester.drag(surface, const Offset(0, -30));
    await tester.drag(surface, const Offset(0, 100));
    await tester.drag(surface, const Offset(120, -100));
    expect(opens, 0);
    await tester.drag(surface, const Offset(0, -120));
    expect(opens, 1);
  });
}
