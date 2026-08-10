import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:my_life_graph/features/quick_action/presentation/widgets/daily_capture_controls.dart';

void main() {
  testWidgets(
      'Capture information uses a 44px target, dynamic semantics, keyboard, and independent state',
      (tester) async {
    final semantics = tester.ensureSemantics();
    const firstDescription = 'The first hidden Capture explanation.';
    const secondDescription = 'The second hidden Capture explanation.';
    await _pump(
      tester,
      const Column(
        children: [
          CaptureInfoDisclosure(
            heading: 'First Capture section',
            description: firstDescription,
          ),
          CaptureInfoDisclosure(
            heading: 'Second Capture section',
            description: secondDescription,
          ),
        ],
      ),
    );

    final firstTarget = find.byKey(
      const ValueKey('capture-info-control-First Capture section'),
    );
    final firstIcon = find.descendant(
      of: firstTarget,
      matching: find.byIcon(AppIcons.infoOutline),
    );
    expect(find.text(firstDescription), findsNothing);
    expect(find.text(secondDescription), findsNothing);
    expect(find.bySemanticsLabel(firstDescription), findsNothing);
    expect(tester.getSize(firstTarget), const Size.square(44));
    expect(tester.getSize(firstIcon), const Size.square(20));
    expect(
      tester.getSemantics(
        find.bySemanticsLabel(
          'Show information about First Capture section',
        ),
      ),
      isSemantics(
        label: 'Show information about First Capture section',
        isButton: true,
        hasTapAction: true,
        hasExpandedState: true,
        isExpanded: false,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text(firstDescription), findsOneWidget);
    expect(find.text(secondDescription), findsNothing);
    expect(
      tester.getSemantics(
        find.bySemanticsLabel(
          'Hide information about First Capture section',
        ),
      ),
      isSemantics(
        label: 'Hide information about First Capture section',
        isButton: true,
        hasTapAction: true,
        hasExpandedState: true,
        isExpanded: true,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text(firstDescription), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text(firstDescription), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text(firstDescription), findsNothing);

    await tester.tap(
      find.byKey(
        const ValueKey('capture-info-control-Second Capture section'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(firstDescription), findsNothing);
    expect(find.text(secondDescription), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('Capture information changes immediately with Reduced Motion',
      (tester) async {
    const description = 'Reduced-motion Capture information.';
    await _pump(
      tester,
      const CaptureInfoDisclosure(
        heading: 'Reduced motion',
        description: description,
      ),
      disableAnimations: true,
    );

    final switcher = tester.widget<AnimatedSwitcher>(
      find.descendant(
        of: find.byType(CaptureInfoDisclosure),
        matching: find.byType(AnimatedSwitcher),
      ),
    );
    expect(switcher.duration, Duration.zero);
    await tester.tap(
      find.byKey(
        const ValueKey('capture-info-control-Reduced motion'),
      ),
    );
    await tester.pump();
    expect(find.text(description), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
          ),
          child: Scaffold(
            body: SingleChildScrollView(child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
