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
  Future<QuickCheckInDraft?> loadToday(DateTime today) async {
    final values = await readAll();
    final date = _dateOnly(today);
    for (final value in values.reversed) {
      if (value.entryDate == date) {
        return value;
      }
    }
    return null;
  }

  Future<List<QuickCheckInDraft>> readAll() async {
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
      return QuickCheckInDraft.fromJson(value);
    }).toList();
  }

  @override
  Future<void> save(QuickCheckInDraft draft) async {
    draft.validate();
    final normalized = draft.normalized();
    List<QuickCheckInDraft> values;
    try {
      values = await readAll();
    } on FormatException {
      values = [];
    }
    values.removeWhere((value) => value.entryDate == normalized.entryDate);
    values.add(normalized);
    values.sort((left, right) => left.capturedAt.compareTo(right.capturedAt));

    final prefs = await _preferencesLoader();
    final didSave = await prefs.setString(
      storageKey,
      jsonEncode(values.map((value) => value.toJson()).toList()),
    );
    if (!didSave) {
      throw const QuickCheckInUnavailableException(
        'The local check-in could not be saved.',
      );
    }
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
