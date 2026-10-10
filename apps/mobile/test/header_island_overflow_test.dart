import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/widgets/app_header_actions.dart';
import 'package:my_life_graph/core/widgets/app_page.dart';

void main() {
  testWidgets('Coach restores the existing full-size overflow control', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AppPage(
              title: 'Coach',
              compactHeader: true,
              actions: [
                AppHeaderActions(
                  showOverflowControl: true,
                  pageActions: [
                    for (var i = 0; i < 6; i++)
                      IconButton(
                        tooltip: 'Extra $i',
                        onPressed: () {},
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
    final title = tester.getRect(find.text('Coach'));
    expect(
      tester.getSize(find.byKey(const ValueKey('header-island-overflow'))),
      const Size(44, 44),
    );
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Settings').hitTestable(), findsOneWidget);
    expect(find.byTooltip('First actions'), findsOneWidget);
    await tester.tap(find.byTooltip('First actions'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Extra 0').hitTestable(), findsOneWidget);
    expect(tester.getRect(find.text('Coach')), title);
    expect(tester.takeException(), isNull);
  });
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
      expect(
        find.byKey(const ValueKey('header-island-overflow')),
        findsNothing,
      );
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
