import 'package:flutter_test/flutter_test.dart';

/// Follows the public settings route rather than reaching a private editor.
Future<void> enterUnlockMethod(WidgetTester tester) async {
  await tester.pumpAndSettle();
  if (find.text('Unlock settings').evaluate().isNotEmpty) {
    final method = find.text('Unlock method');
    if (method.evaluate().isEmpty) {
      await tester.scrollUntilVisible(method, 150);
    }
    await tester.ensureVisible(method);
    await tester.pumpAndSettle();
    await tester.tap(method);
    await tester.pumpAndSettle();
  }
}
