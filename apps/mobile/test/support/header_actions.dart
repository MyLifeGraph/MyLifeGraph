import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openHeaderActions(WidgetTester tester) async {
  if (find.byKey(const ValueKey('header-island-toggle')).evaluate().isEmpty) {
    return;
  }
  if (find
      .byKey(const ValueKey('header-action-menu'))
      .hitTestable()
      .evaluate()
      .isNotEmpty) {
    return;
  }
  await tester.ensureVisible(
    find.byKey(const ValueKey('header-island-toggle')).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('header-island-toggle')).hitTestable().first,
  );
  await tester.pumpAndSettle();
}

Future<void> closeHeaderActions(WidgetTester tester) async {
  if (find.byKey(const ValueKey('header-action-menu')).evaluate().isEmpty) {
    return;
  }
  await tester.tapAt(const Offset(10, 400));
  await tester.pumpAndSettle();
}
