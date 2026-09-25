import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/quick_action/presentation/widgets/capture_date_picker.dart';

void main() {
  test('calendar offsets cross months and DST without using elapsed hours', () {
    expect(captureDayOffset(DateTime(2026, 4, 1), -7), DateTime(2026, 3, 25));
    expect(captureDayOffset(DateTime(2026, 10, 26), -1), DateTime(2026, 10, 25));
  });
  testWidgets('picker bounds dates and requires confirmation before discarding answers', (tester) async {
    DateTime? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CaptureDatePicker(
      date: DateTime(2026, 9, 25), today: DateTime(2026, 9, 25),
      onChanged: (date) => selected = date,
    ))));
    await tester.tap(find.text('Today · Change date'));
    await tester.pumpAndSettle();
    final picker = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(picker.firstDate, DateTime(2026, 9, 18));
    expect(picker.lastDate, DateTime(2026, 9, 25));
    await tester.tap(find.text('24'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    await tester.tap(find.text('Change date'));
    await tester.pumpAndSettle();
    expect(selected, DateTime(2026, 9, 24));
  });
}
