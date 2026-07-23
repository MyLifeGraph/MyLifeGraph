import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/intake_response.dart';

class GuestSetupDataSource {
  const GuestSetupDataSource();

  static const storageKey = 'auth_guest_setup_v1';
  static const legacyIntakeKey = 'auth_guest_intake_response';
  static const legacyTimetableKey = 'auth_guest_timetable';
  static const guestNameKey = 'auth_guest_name';
  static const guestOnboardingDoneKey = 'auth_guest_onboarding_done';

  Future<IntakeSetupReadState> read() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(storageKey);
    if (raw != null && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('Local setup state is not an object.');
      }
      return IntakeSetupReadState.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    }
    return _readLegacy(preferences);
  }

  Future<IntakeSetupReadState> save(IntakeSetupSaveRequest request) async {
    final preferences = await SharedPreferences.getInstance();
    final current = await read();

    if (current.exists && current.requestId == request.requestId) {
      final sameBaseRevision = current.baseRevision == request.baseRevision;
      final currentResponses = current.responses;
      final sameResponses = currentResponses != null &&
          jsonEncode(currentResponses.normalized().toJson()) ==
              jsonEncode(request.responses.normalized().toJson());
      if (!sameBaseRevision || !sameResponses) {
        throw const GuestSetupIdempotencyException();
      }
      await _writeCompatibilityState(preferences, current, request);
      return current;
    }
    if (request.baseRevision != current.revision) {
      throw GuestSetupRevisionException(
        expected: current.revision,
        received: request.baseRevision,
      );
    }

    final responses = request.responses.normalized();
    final validationErrors = responses.validationErrors();
    if (validationErrors.isNotEmpty) {
      throw StateError(validationErrors.first);
    }

    final revision = current.revision + 1;
    final completedAt = DateTime.now().toUtc();
    final state = IntakeSetupReadState(
      exists: true,
      revision: revision,
      baseRevision: request.baseRevision,
      requestId: request.requestId,
      status: 'applied',
      intakeResponseId: 'local-intake-${request.requestId}',
      snapshotId: 'local-snapshot-${request.requestId}',
      completedAt: completedAt,
      responses: responses,
      summary: {
        'goal_count': responses.goals
            .where((goal) => goal.status != IntakeGoalStatus.archived)
            .length,
        'routine_candidate_count': responses.routines
            .where(
              (routine) => routine.status == IntakeRoutineStatus.candidate,
            )
            .length,
        'active_habit_count': responses.routines
            .where((routine) => routine.status == IntakeRoutineStatus.active)
            .length,
        'fixed_commitment_count': responses.fixedCommitments
            .where(
              (commitment) =>
                  commitment.status == IntakeCommitmentStatus.active,
            )
            .length,
      },
    );

    final saved = await preferences.setString(
      storageKey,
      jsonEncode(state.toJson()),
    );
    if (!saved) {
      throw StateError('Could not persist local setup.');
    }
    await _writeCompatibilityState(preferences, state, request);
    return state;
  }

  Future<void> _writeCompatibilityState(
    SharedPreferences preferences,
    IntakeSetupReadState state,
    IntakeSetupSaveRequest request,
  ) async {
    final responses = state.responses ?? request.responses;
    final name = responses.displayName?.trim();
    if (name == null || name.isEmpty) {
      await preferences.remove(guestNameKey);
    } else {
      await preferences.setString(guestNameKey, name);
    }
    await preferences.setBool(guestOnboardingDoneKey, true);
    await preferences.setString(
      legacyIntakeKey,
      jsonEncode(request.copyWith(responses: responses).toJson()),
    );
    await preferences.setString(
      legacyTimetableKey,
      jsonEncode(
        responses.fixedCommitments
            .where(
              (commitment) =>
                  commitment.status == IntakeCommitmentStatus.active,
            )
            .map(
              (commitment) => {
                'title': commitment.title,
                'location': commitment.location ?? '',
                'weekday': commitment.weekday,
                'startsAt': commitment.startsAt,
                'endsAt': commitment.endsAt,
                if (commitment.validFrom != null)
                  'validFrom': commitment.validFrom!
                      .toUtc()
                      .toIso8601String()
                      .substring(0, 10),
                if (commitment.validUntil != null)
                  'validUntil': commitment.validUntil!
                      .toUtc()
                      .toIso8601String()
                      .substring(0, 10),
              },
            )
            .toList(growable: false),
      ),
    );
  }

  IntakeSetupReadState _readLegacy(SharedPreferences preferences) {
    final raw = preferences.getString(legacyIntakeKey);
    if (raw == null || raw.trim().isEmpty) {
      return const IntakeSetupReadState.empty();
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Legacy local setup is not an object.');
    }
    final envelope = Map<String, dynamic>.from(decoded);
    final rawResponses = envelope['responses'];
    if (rawResponses is! Map) {
      throw const FormatException('Legacy local setup has no responses.');
    }
    final responses = Map<String, dynamic>.from(rawResponses);
    final goals = _legacyStringOrObjectRows(
      responses['goals'],
      kind: 'goal',
      objectBuilder: (key, title) => {
        'key': key,
        'title': title,
        'status': IntakeGoalStatus.active.name,
      },
    ).where((goal) {
      return goal['title'] != 'Build a steadier weekly routine';
    }).toList(growable: false);
    final routines = _legacyStringOrObjectRows(
      responses['routines'] ?? responses['existing_habits'],
      kind: 'routine',
      objectBuilder: (key, title) => {
        'key': key,
        'title': title,
        'status': IntakeRoutineStatus.candidate.name,
        'cadence_confirmed': false,
      },
    );
    final commitments = _legacyCommitments(responses['fixed_commitments']);
    final friction = _legacyStrings(responses['friction_points'])
        .where((item) => item != 'Unclear priorities')
        .toList(growable: false);

    final translated = <String, dynamic>{
      if (responses['display_name'] != null)
        'display_name': responses['display_name'],
      'primary_focus_areas': responses['primary_focus_areas'] ?? const [],
      'goals': goals,
      'friction_points': friction,
      if (responses['weekday_shape'] != null)
        'weekday_shape': responses['weekday_shape'],
      if (responses['best_energy_window'] != null)
        'best_energy_window': responses['best_energy_window'],
      if (responses['coaching_style'] != null)
        'coaching_style': responses['coaching_style'],
      if (responses['reminder_preference'] != null)
        'reminder_preference': responses['reminder_preference'],
      'routines': routines,
      'fixed_commitments': commitments,
      if (responses['context_note'] != null)
        'context_note': responses['context_note'],
      if (responses['calendar_connection_intent'] != null)
        'calendar_connection_intent': responses['calendar_connection_intent'],
    };
    final completedAt = DateTime.now().toUtc();
    return IntakeSetupReadState(
      exists: true,
      revision: 1,
      baseRevision: 0,
      requestId: null,
      status: 'applied',
      intakeResponseId: null,
      snapshotId: null,
      completedAt: completedAt,
      responses: IntakeResponseDraft.fromJson(translated),
      summary: const {},
    );
  }

  List<Map<String, dynamic>> _legacyStringOrObjectRows(
    Object? value, {
    required String kind,
    required Map<String, dynamic> Function(String key, String title)
        objectBuilder,
  }) {
    if (value == null) {
      return const [];
    }
    if (value is! List) {
      throw FormatException('Legacy $kind rows are not a list.');
    }
    final rows = <Map<String, dynamic>>[];
    for (var index = 0; index < value.length; index++) {
      final item = value[index];
      if (item is String && item.trim().isNotEmpty) {
        rows.add(objectBuilder(generateSetupUuid(), item.trim()));
      } else if (item is Map) {
        rows.add(Map<String, dynamic>.from(item));
      }
    }
    return rows;
  }

  List<Map<String, dynamic>> _legacyCommitments(Object? value) {
    if (value == null) {
      return const [];
    }
    if (value is! List) {
      throw const FormatException('Legacy commitments are not a list.');
    }
    final rows = <Map<String, dynamic>>[];
    for (var index = 0; index < value.length; index++) {
      final item = value[index];
      if (item is! Map) {
        continue;
      }
      final row = Map<String, dynamic>.from(item);
      final title = '${row['title'] ?? ''}'.trim();
      if (title.isEmpty) {
        continue;
      }
      final location = '${row['location'] ?? ''}'.trim();
      final weekday = _legacyWeekday(row['weekday']);
      final startsAt = _legacyTime(row['starts_at'] ?? row['startsAt']);
      final endsAt = _legacyTime(row['ends_at'] ?? row['endsAt']);
      final validFrom = _legacyDate(row['valid_from'] ?? row['validFrom']);
      final validUntil = _legacyDate(row['valid_until'] ?? row['validUntil']);
      final rawKey = row['key'];
      final hasStableKey = rawKey is String && rawKey.trim().isNotEmpty;
      final isComplete = weekday != null &&
          weekday >= 1 &&
          weekday <= 7 &&
          _isLegacyTime(startsAt) &&
          _isLegacyTime(endsAt) &&
          endsAt!.compareTo(startsAt!) > 0;
      if (!hasStableKey && !isComplete) {
        continue;
      }
      final isKnownKeylessPlaceholder = !hasStableKey &&
          title == 'Math' &&
          location == 'Room 204' &&
          weekday == 1 &&
          startsAt == '08:15' &&
          endsAt == '09:45';
      if (isKnownKeylessPlaceholder) {
        continue;
      }
      rows.add({
        'key': hasStableKey ? rawKey.trim() : generateSetupUuid(),
        'title': title,
        if (location.isNotEmpty) 'location': location,
        'weekday': weekday ?? row['weekday'],
        'starts_at': startsAt,
        'ends_at': endsAt,
        if (validFrom != null) 'valid_from': validFrom,
        if (validUntil != null) 'valid_until': validUntil,
        'status': row['status'] ?? IntakeCommitmentStatus.active.name,
      });
    }
    return rows;
  }

  int? _legacyWeekday(Object? value) {
    if (value is num && value.toInt() == value) {
      return value.toInt();
    }
    if (value is! String) {
      return null;
    }
    final normalized = value.trim().toLowerCase();
    final numeric = int.tryParse(normalized);
    if (numeric != null) {
      return numeric;
    }
    return const {
      'monday': 1,
      'mon': 1,
      'tuesday': 2,
      'tue': 2,
      'wednesday': 3,
      'wed': 3,
      'thursday': 4,
      'thu': 4,
      'friday': 5,
      'fri': 5,
      'saturday': 6,
      'sat': 6,
      'sunday': 7,
      'sun': 7,
    }[normalized];
  }

  String? _legacyTime(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    if (RegExp(r'^\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?$').hasMatch(trimmed)) {
      final normalized = trimmed.substring(0, 5);
      return _isLegacyTime(normalized) ? normalized : trimmed;
    }
    return trimmed;
  }

  String? _legacyDate(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    final candidate = trimmed.length >= 10 ? trimmed.substring(0, 10) : trimmed;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(candidate)) return null;
    final parsed = DateTime.tryParse('${candidate}T00:00:00Z');
    if (parsed == null ||
        parsed.toIso8601String().substring(0, 10) != candidate) {
      return null;
    }
    return candidate;
  }

  bool _isLegacyTime(String? value) {
    if (value == null || !RegExp(r'^\d{2}:\d{2}$').hasMatch(value)) {
      return false;
    }
    final parts = value.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
  }

  List<String> _legacyStrings(Object? value) {
    if (value == null) {
      return const [];
    }
    if (value is! List) {
      throw const FormatException('Legacy values are not a list.');
    }
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

class GuestSetupRevisionException implements Exception {
  const GuestSetupRevisionException({
    required this.expected,
    required this.received,
  });

  final int expected;
  final int received;

  @override
  String toString() {
    return 'Local setup changed (expected revision $expected, '
        'received $received). Reload setup and try again.';
  }
}

class GuestSetupIdempotencyException implements Exception {
  const GuestSetupIdempotencyException();

  @override
  String toString() {
    return 'A local setup request id was reused with different content.';
  }
}
