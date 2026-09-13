import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/planner/domain/planner.dart';
import 'package:my_life_graph/features/planner/presentation/widgets/planner_sections.dart';

import 'support/planner_fixtures.dart';

void main() {
  for (final width in [390.0, 1100.0, 320.0]) {
    testWidgets('Planner day frame stays fixed and scrolls at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = plannerOverviewEnvelope()['days'] as List<dynamic>;
      final template = Map<String, dynamic>.from(
        fixture.first['items'][1] as Map,
      );
      double? frameHeight;
      double? followingTop;
      PlannerDayItem? tapped;
      var importCalls = 0;
      for (final count in [0, 1, 3, 6]) {
        final days = [
          for (var day = 0; day < 7; day++)
            PlannerDay.fromJson({
              'local_date': fixture[day]['local_date'],
              'items': day == 0
                  ? [
                      for (var i = 0; i < count; i++)
                        {
                          ...template,
                          'id': '10000000-0000-4000-8000-00000000000$i',
                          'title': 'Appointment $i',
                        },
                    ]
                  : <dynamic>[],
            }),
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1400),
                textScaler: TextScaler.linear(width == 320 ? 2 : 1),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        PlannerSevenDaySection(
                          days: days,
                          timezone: 'Europe/Berlin',
                          onItemTap: (item) => tapped = item,
                          onImportCalendar: () => importCalls += 1,
                        ),
                        const Text(
                          'Following section',
                          key: Key('following-section'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (count == 0) {
          await tester.tap(find.byTooltip('Import calendar (.ics)'));
          expect(importCalls, 1);
        }
        final frame = find.byKey(const ValueKey('planner-day-viewport'));
        frameHeight ??= tester.getSize(frame).height;
        followingTop ??= tester
            .getTopLeft(find.byKey(const Key('following-section')))
            .dy;
        expect(tester.getSize(frame).height, frameHeight);
        expect(
          tester.getTopLeft(find.byKey(const Key('following-section'))).dy,
          followingTop,
        );
        if (count == 0) {
          expect(find.text('No planned or fixed items.'), findsOneWidget);
        }
        if (count == 6) {
          final scroll = tester
              .widget<SingleChildScrollView>(
                find.byKey(const ValueKey('planner-day-scroll')),
              )
              .controller!;
          expect(scroll.position.maxScrollExtent, greaterThan(0));
          scroll.jumpTo(scroll.position.maxScrollExtent);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Appointment 5'));
          expect(tapped?.id, '10000000-0000-4000-8000-000000000005');
          await tester.tap(find.byTooltip('Next day'));
          await tester.pumpAndSettle();
          expect(scroll.offset, 0);
          expect(tester.getSize(frame).height, frameHeight);
          expect(find.text('No planned or fixed items.'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    });
  }
}
