import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/quick_check_in.dart';

typedef GuestPreferencesLoader = Future<SharedPreferences> Function();

class GuestQuickCheckInDataSource implements QuickCheckInStore {
  GuestQuickCheckInDataSource({GuestPreferencesLoader? preferencesLoader})
      : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const storageKey = 'guest_quick_checkins';

  final GuestPreferencesLoader _preferencesLoader;

  @override
  QuickCheckInSaveTarget get target => QuickCheckInSaveTarget.guest;

  @override
  Future<DailyCaptureEntry?> loadToday(DateTime today) async {
    final values = await readAll();
    final date = dailyCaptureEntryDate(today);
    for (final value in values.reversed) {
      if (value.entryDate == date) {
        return value;
      }
    }
    return null;
  }

  Future<List<DailyCaptureEntry>> readAll() async {
    final prefs = await _preferencesLoader();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      throw const FormatException('Guest check-in storage is not a list.');
    }

    return decoded.map((value) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Guest check-in entry is invalid.');
      }
      return DailyCaptureEntry.fromGuestJson(value);
    }).toList();
  }

  @override
  Future<void> saveEvening(EveningShutdownDraft draft) async {
    draft.validate();
    final existing = await _loadEntryForMerge(draft.entryDate);
    await saveEntry(
      (existing ?? DailyCaptureEntry(entryDate: draft.entryDate))
          .mergeEvening(draft),
    );
  }

  @override
  Future<void> saveMorning(MorningCalibrationDraft draft) async {
    draft.validate();
    final existing = await _loadEntryForMerge(draft.entryDate);
    await saveEntry(
      (existing ?? DailyCaptureEntry(entryDate: draft.entryDate))
          .mergeMorning(draft),
    );
  }

  Future<void> saveEntry(DailyCaptureEntry entry) async {
    if (!entry.hasAnyCapture) {
      throw const FormatException('A daily capture entry cannot be empty.');
    }
    List<DailyCaptureEntry> values;
    try {
      values = await readAll();
    } on FormatException {
      values = [];
    }
    values.removeWhere((value) => value.entryDate == entry.entryDate);
    values.add(entry);
    values.sort((left, right) => left.entryDate.compareTo(right.entryDate));

    final prefs = await _preferencesLoader();
    final didSave = await prefs.setString(
      storageKey,
      jsonEncode(values.map((value) => value.toGuestJson()).toList()),
    );
    if (!didSave) {
      throw const QuickCheckInUnavailableException(
        'The local check-in could not be saved.',
      );
    }
  }

  Future<DailyCaptureEntry?> _loadEntryForMerge(String entryDate) async {
    try {
      final values = await readAll();
      for (final value in values.reversed) {
        if (value.entryDate == entryDate) {
          return value;
        }
      }
      return null;
    } on FormatException {
      return null;
    }
  }
}
