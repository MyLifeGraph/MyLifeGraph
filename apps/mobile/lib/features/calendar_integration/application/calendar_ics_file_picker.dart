import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../domain/calendar_integration.dart';

abstract interface class CalendarIcsFilePicker {
  Future<SelectedCalendarIcsFile?> pickFile();
}

class FileSelectorCalendarIcsFilePicker implements CalendarIcsFilePicker {
  const FileSelectorCalendarIcsFilePicker();

  @override
  Future<SelectedCalendarIcsFile?> pickFile() async {
    const typeGroup = XTypeGroup(
      label: 'iCalendar files',
      extensions: ['ics'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return null;

    final byteLength = await file.length();
    if (byteLength > calendarImportMaxFileBytes) {
      throw const CalendarFileSelectionException(
        'Choose an .ics file no larger than 512 KiB.',
      );
    }
    return SelectedCalendarIcsFile.fromBytes(
      name: file.name,
      bytes: await file.readAsBytes(),
    );
  }
}

class SelectedCalendarIcsFile {
  SelectedCalendarIcsFile._({
    required this.name,
    required Uint8List bytes,
    required this.calendarText,
  }) : bytes = Uint8List.fromList(bytes);

  factory SelectedCalendarIcsFile.fromBytes({
    required String name,
    required List<int> bytes,
  }) {
    final cleanName = name.trim();
    if (cleanName.isEmpty || !cleanName.toLowerCase().endsWith('.ics')) {
      throw const CalendarFileSelectionException(
        'Choose a file whose name ends in .ics.',
      );
    }
    if (bytes.isEmpty) {
      throw const CalendarFileSelectionException(
        'The selected .ics file is empty.',
      );
    }
    if (bytes.length > calendarImportMaxFileBytes) {
      throw const CalendarFileSelectionException(
        'Choose an .ics file no larger than 512 KiB.',
      );
    }

    late final String text;
    try {
      text = const Utf8Decoder(allowMalformed: false).convert(bytes);
    } on FormatException {
      throw const CalendarFileSelectionException(
        'The selected .ics file must contain valid UTF-8 text.',
      );
    }
    return SelectedCalendarIcsFile._(
      name: cleanName,
      bytes: Uint8List.fromList(bytes),
      calendarText: text,
    );
  }

  final String name;
  final Uint8List bytes;
  final String calendarText;

  int get byteLength => bytes.length;
}

class CalendarFileSelectionException implements Exception {
  const CalendarFileSelectionException(this.message);

  final String message;

  @override
  String toString() => 'CalendarFileSelectionException: $message';
}
