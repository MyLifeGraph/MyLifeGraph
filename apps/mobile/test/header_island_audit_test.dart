import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/widgets/app_header_actions.dart';

void main() {
  testWidgets('open actions preserve focus, disabled state and callbacks', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: AppHeaderActions(
                pageActions: [
                  IconButton(
                    tooltip: 'Run',
                    focusNode: node,
                    onPressed: () => calls++,
                    icon: const Icon(Icons.play_arrow),
                  ),
                  const IconButton(
                    tooltip: 'Disabled',
                    onPressed: null,
                    icon: Icon(Icons.block),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(calls, 1);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == 'Disabled',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(find.byKey(const ValueKey('header-island-toggle')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
