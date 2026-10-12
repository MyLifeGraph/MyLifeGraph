import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/quick_action/presentation/widgets/capture_date_picker.dart';

void main() {
  test('calendar offsets cross months and DST without using elapsed hours', () {
    expect(captureDayOffset(DateTime(2026, 4, 1), -7), DateTime(2026, 3, 25));
    expect(
      captureDayOffset(DateTime(2026, 10, 26), -1),
      DateTime(2026, 10, 25),
    );
  });
  testWidgets('date selection is immediate and bounded without confirmation', (
    tester,
  ) async {
    DateTime? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CaptureDatePicker(
            date: DateTime(2026, 9, 25),
            today: DateTime(2026, 9, 25),
            onChanged: (date) => selected = date,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Today · Change date'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('capture-day-2026-09-17')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('capture-day-2026-09-26')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('capture-day-2026-09-24')));
    await tester.pumpAndSettle();
    expect(selected, DateTime(2026, 9, 24));
    expect(find.text('Keep editing'), findsNothing);
    expect(find.byType(CaptureCalendarDialog), findsNothing);
  });
}
