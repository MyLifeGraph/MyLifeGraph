import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/calendar_integration/application/calendar_ics_file_picker.dart';
import 'package:my_life_graph/features/calendar_integration/domain/calendar_integration.dart';

void main() {
  group('SelectedCalendarIcsFile', () {
    test('keeps the exact valid UTF-8 bytes and decoded text', () {
      final bytes =
          utf8.encode('BEGIN:VCALENDAR\nSUMMARY:Grüße\nEND:VCALENDAR');
      final file = SelectedCalendarIcsFile.fromBytes(
        name: ' calendar.ICS ',
        bytes: bytes,
      );
      bytes[0] = 0;

      expect(file.name, 'calendar.ICS');
      expect(file.calendarText, contains('Grüße'));
      expect(file.bytes.first, utf8.encode('B').single);
      expect(file.byteLength, utf8.encode(file.calendarText).length);
    });

    test('accepts exactly 512 KiB and rejects one byte more', () {
      final maximum = SelectedCalendarIcsFile.fromBytes(
        name: 'maximum.ics',
        bytes: List.filled(calendarImportMaxFileBytes, 0x41),
      );
      expect(maximum.byteLength, calendarImportMaxFileBytes);

      expect(
        () => SelectedCalendarIcsFile.fromBytes(
          name: 'too-large.ics',
          bytes: List.filled(calendarImportMaxFileBytes + 1, 0x41),
        ),
        throwsA(isA<CalendarFileSelectionException>()),
      );
    });

    test('rejects wrong extension, empty files, and malformed UTF-8', () {
      expect(
        () => SelectedCalendarIcsFile.fromBytes(
          name: 'calendar.txt',
          bytes: const [0x41],
        ),
        throwsA(isA<CalendarFileSelectionException>()),
      );
      expect(
        () => SelectedCalendarIcsFile.fromBytes(
          name: 'calendar.ics',
          bytes: const [],
        ),
        throwsA(isA<CalendarFileSelectionException>()),
      );
      expect(
        () => SelectedCalendarIcsFile.fromBytes(
          name: 'calendar.ics',
          bytes: const [0xC3, 0x28],
        ),
        throwsA(isA<CalendarFileSelectionException>()),
      );
    });
  });
}
