import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/planner/domain/planner.dart';
import 'package:my_life_graph/features/planner/presentation/widgets/planner_sections.dart';

import 'support/planner_fixtures.dart';

void main() {
  testWidgets('Planner List survives removal and recreation of the route', (tester) async {
    final showPage = ValueNotifier(true);
    addTearDown(showPage.dispose);
    final days = (plannerOverviewEnvelope()['days'] as List)
        .map((day) => PlannerDay.fromJson(day as Map<String, dynamic>)).toList();
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: ValueListenableBuilder<bool>(
        valueListenable: showPage,
        builder: (_, show, _) => show ? PlannerSevenDaySection(
          days: days, timezone: 'Europe/Berlin', onItemTap: (_) {},
        ) : const SizedBox(),
      )),
    ))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('planner-day-viewport')), findsOneWidget);
    await tester.tap(find.byTooltip('List'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('planner-day-viewport')), findsNothing);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('planner-seven-days-list'))).isSelected, isTrue);
    showPage.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(PlannerSevenDaySection), findsNothing);
    showPage.value = true;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('planner-day-viewport')), findsNothing);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('planner-seven-days-list'))).isSelected, isTrue);
    await tester.tap(find.byTooltip('Days'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('planner-day-viewport')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
