import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/widgets/app_header_actions.dart';
import 'package:my_life_graph/core/widgets/app_page.dart';

void main() {
  for (final count in [0, 1, 2, 3, 6]) {
    testWidgets('four slots retain all $count page actions by scrolling', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AppPage(
                title: 'Coach',
                compactHeader: true,
                actions: [
                  AppHeaderActions(
                    pageActions: [
                      for (var i = 0; i < count; i++)
                        IconButton(
                          tooltip: 'Action $i',
                          onPressed: () => calls++,
                          icon: const Icon(Icons.refresh),
                        ),
                    ],
                  ),
                ],
                children: const [],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('header-island-icons-scroll')),
      );
      expect(
        scroll.controller!.position.maxScrollExtent,
        count <= 2 ? 0 : greaterThan(0),
      );
      final title = tester.getRect(find.text('Coach'));
      for (var i = 0; i < count; i++) {
        await tester.ensureVisible(find.byTooltip('Action $i'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Action $i'));
      }
      await tester.ensureVisible(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Settings').hitTestable(), findsOneWidget);
      expect(calls, count);
      expect(tester.getRect(find.text('Coach')), title);
      expect(tester.takeException(), isNull);
    });
  }
}
