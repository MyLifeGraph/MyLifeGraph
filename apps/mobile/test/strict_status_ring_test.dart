import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/focus_protection/presentation/widgets/strict_status_ring.dart';

Future<void> _open(
  WidgetTester tester, {
  bool locked = true,
  bool reduced = false,
  bool ticker = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.liquidGlass,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: TickerMode(
          enabled: ticker,
          child: Scaffold(
            body: Center(child: StrictStatusRing(locked: locked)),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Animation<double> _turns(WidgetTester tester) => tester
    .widget<RotationTransition>(
      find.byKey(const ValueKey('strict-ring-rotation')),
    )
    .turns;

void main() {
  testWidgets('active ring rotates but lock remains fixed', (tester) async {
    await _open(tester);
    final initial = _turns(tester).value;
    await tester.pump(const Duration(milliseconds: 800));
    expect(_turns(tester).value, isNot(initial));
    expect(
      find.descendant(
        of: find.byType(RotationTransition),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final (label, locked, reduced, ticker) in [
    ('off', false, false, true),
    ('Reduced Motion', true, true, true),
    ('hidden route', true, false, false),
  ]) {
    testWidgets('$label does not schedule a looping animation', (tester) async {
      await _open(tester, locked: locked, reduced: reduced, ticker: ticker);
      final initial = _turns(tester).value;
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(_turns(tester).value, initial);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  testWidgets('background stops and foreground resumes; unlocking stops', (
    tester,
  ) async {
    await _open(tester);
    await tester.pump(const Duration(milliseconds: 600));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final stopped = _turns(tester).value;
    await tester.pump(const Duration(seconds: 1));
    expect(_turns(tester).value, stopped);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(_turns(tester).value, isNot(stopped));
    await _open(tester, locked: false);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing Reduced Motion freezes immediately and can resume', (
    tester,
  ) async {
    await _open(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await _open(tester, reduced: true);
    await tester.pumpAndSettle();
    expect(_turns(tester).value, 0);
    await _open(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_turns(tester).value, greaterThan(0));
  });
}
