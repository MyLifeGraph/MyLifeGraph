import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/widgets/push_settings_entry.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/widgets/app_card.dart';

void main() {
  testWidgets('Push reminders uses the shared settings card', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: PushSettingsEntry()),
      ),
    );
    final tile = find.widgetWithText(ListTile, 'Push reminders');
    final card = find.ancestor(of: tile, matching: find.byType(AppCard));
    expect(card, findsOneWidget);
    expect(tester.widget<AppCard>(card).padding, EdgeInsets.zero);
    expect(tester.widget<ListTile>(tile).onTap, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
