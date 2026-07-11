import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/app_user_resolver.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../domain/quick_check_in.dart';

class QuickCheckInSupabaseDataSource implements QuickCheckInStore {
  const QuickCheckInSupabaseDataSource(
    this._client, {
    this.payloadBuilder = const QuickCheckInPayloadBuilder(),
    this.rowMapper = const QuickCheckInDailyRowMapper(),
  });

  static const source = 'quick_check_in';

  final SupabaseClient _client;
  final QuickCheckInPayloadBuilder payloadBuilder;
  final QuickCheckInDailyRowMapper rowMapper;

  @override
  QuickCheckInSaveTarget get target => QuickCheckInSaveTarget.supabase;

  @override
  Future<DailyCaptureEntry?> loadToday(DateTime today) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final row = await _loadRowForUser(
      userId: userId,
      entryDate: dailyCaptureEntryDate(today),
    );
    if (row == null || row.source != source) {
      return null;
    }
    return row.entry;
  }

  @override
  Future<void> saveEvening(EveningShutdownDraft draft) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final existing = await _loadRowForUser(
      userId: userId,
      entryDate: draft.entryDate,
    );
    final entry =
        (existing?.entry ?? DailyCaptureEntry(entryDate: draft.entryDate))
            .mergeEvening(draft);
    await _writeForUser(userId: userId, entry: entry);
  }

  @override
  Future<void> saveMorning(MorningCalibrationDraft draft) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final existing = await _loadRowForUser(
      userId: userId,
      entryDate: draft.entryDate,
    );
    final entry =
        (existing?.entry ?? DailyCaptureEntry(entryDate: draft.entryDate))
            .mergeMorning(draft);
    await _writeForUser(userId: userId, entry: entry);
  }

  /// Used only by the best-effort guest-to-account check-in migration.
  Future<void> mergeEntryForUser({
    required String userId,
    required DailyCaptureEntry entry,
  }) async {
    final existing = await _loadRowForUser(
      userId: userId,
      entryDate: entry.entryDate,
    );
    final merged = existing == null ? entry : existing.entry.mergeEntry(entry);
    await _writeForUser(userId: userId, entry: merged);
  }

  Future<_StoredDailyCapture?> _loadRowForUser({
    required String userId,
    required String entryDate,
  }) async {
    final row = await _client
        .from(SupabaseTables.dailyLogs)
        .select(
          'id,entry_date,sleep_hours,energy_level,stress_level,mood_score,'
          'reflection,source,metadata,updated_at',
        )
        .eq('user_id', userId)
        .eq('entry_date', entryDate)
        .maybeSingle();
    if (row == null) {
      return null;
    }
    return _StoredDailyCapture(
      source: '${row['source'] ?? ''}',
      entry: rowMapper.map(Map<String, dynamic>.from(row)),
    );
  }

  Future<void> _writeForUser({
    required String userId,
    required DailyCaptureEntry entry,
  }) async {
    if (!entry.hasAnyCapture) {
      throw const FormatException('A daily capture entry cannot be empty.');
    }
    final row = await _client
        .from(SupabaseTables.dailyLogs)
        .upsert(
          payloadBuilder.buildDailyLog(userId: userId, entry: entry),
          onConflict: 'user_id,entry_date',
        )
        .select('id')
        .single();
    final dailyLogId = '${row['id']}';

    await _client
        .from(SupabaseTables.behavioralEvents)
        .delete()
        .eq('daily_log_id', dailyLogId)
        .eq('source', source);
    final events = payloadBuilder.buildBehavioralEvents(
      userId: userId,
      dailyLogId: dailyLogId,
      entry: entry,
    );
    if (events.isNotEmpty) {
      await _client.from(SupabaseTables.behavioralEvents).upsert(
            events,
            onConflict: 'id',
          );
    }
  }
}

class QuickCheckInDailyRowMapper {
  const QuickCheckInDailyRowMapper();

  DailyCaptureEntry map(Map<String, dynamic> row) {
    final entryDate = '${row['entry_date']}';
    final metadata = Map<String, dynamic>.from(
      (row['metadata'] as Map?) ?? const <String, dynamic>{},
    );
    final preservedMetadata = Map<String, dynamic>.from(metadata)
      ..remove('capture_version')
      ..remove('captures')
      ..remove('capture_id')
      ..remove('captured_at')
      ..remove('context_note');
    final capturesRaw = metadata['captures'];
    final captureVersion = metadata['capture_version'];
    if ((captureVersion == DailyCaptureEntry.captureVersion &&
            capturesRaw == null) ||
        (capturesRaw != null &&
            captureVersion != DailyCaptureEntry.captureVersion)) {
      throw const FormatException('Capture metadata version is invalid.');
    }
    if (capturesRaw != null && capturesRaw is! Map) {
      throw const FormatException('Capture metadata must be an object.');
    }
    final captures = capturesRaw is Map
        ? Map<String, dynamic>.from(capturesRaw)
        : const <String, dynamic>{};
    final eveningRaw = captures['evening'];
    final morningRaw = captures['morning'];
    final legacyCapturedAt =
        DateTime.tryParse('${metadata['captured_at'] ?? ''}') ??
            DateTime.tryParse('${row['updated_at'] ?? ''}') ??
            DateTime.parse('${entryDate}T12:00:00');
    final legacy = LegacyQuickCheckInValues(
      captureId:
          '${metadata['capture_id'] ?? 'legacy-$entryDate-${legacyCapturedAt.toUtc().microsecondsSinceEpoch}'}',
      capturedAt: legacyCapturedAt,
      mood: (row['mood_score'] as num?)?.toInt(),
      energy: (row['energy_level'] as num?)?.toInt(),
      sleepHours: (row['sleep_hours'] as num?)?.toDouble(),
      stress: (row['stress_level'] as num?)?.toInt(),
      contextNote:
          '${metadata['context_note'] ?? row['reflection'] ?? ''}'.trim(),
    );
    legacy.validatePresentValues();

    return DailyCaptureEntry(
      entryDate: entryDate,
      evening: eveningRaw == null
          ? null
          : EveningShutdownDraft.fromJson(
              _asStringMap(eveningRaw, 'evening capture'),
              entryDate: entryDate,
            ),
      morning: morningRaw == null
          ? null
          : MorningCalibrationDraft.fromJson(
              _asStringMap(morningRaw, 'morning capture'),
              entryDate: entryDate,
            ),
      legacy:
          legacy.hasAnySignal || legacy.contextNote.isNotEmpty ? legacy : null,
      preservedMetadata: preservedMetadata,
    );
  }
}

class QuickCheckInPayloadBuilder {
  const QuickCheckInPayloadBuilder();

  Map<String, dynamic> buildDailyLog({
    required String userId,
    required DailyCaptureEntry entry,
  }) {
    if (!entry.hasAnyCapture) {
      throw const FormatException('A daily capture entry cannot be empty.');
    }
    final mood = entry.mood;
    final capturedAt = entry.latestCapturedAt;
    return {
      'user_id': userId,
      'entry_date': entry.entryDate,
      'sleep_hours': entry.sleepHours,
      'energy_level': entry.energy,
      'stress_level': entry.stress,
      'mood_score': mood,
      'mood_label': mood == null ? null : quickCheckInMoodCode(mood),
      'steps': null,
      'activity_level': null,
      'screen_time_hours': null,
      'focus_minutes': null,
      'nutrition_notes': null,
      'day_focus': null,
      'reflection': entry.reflectionNote.isEmpty ? null : entry.reflectionNote,
      'source': QuickCheckInSupabaseDataSource.source,
      'metadata': entry.toCaptureMetadata(),
      'updated_at': (capturedAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
  }

  List<Map<String, dynamic>> buildBehavioralEvents({
    required String userId,
    required String dailyLogId,
    required DailyCaptureEntry entry,
  }) {
    final values = <(String, num, String)>[
      if (entry.mood != null) ('mood', entry.mood!, 'score_0_10'),
      if (entry.energy != null) ('energy', entry.energy!, 'score_0_10'),
      if (entry.stress != null) ('stress', entry.stress!, 'score_0_10'),
      if (entry.sleepHours != null) ('sleep', entry.sleepHours!, 'hours'),
    ];
    return values
        .map(
          (value) => _event(
            userId: userId,
            dailyLogId: dailyLogId,
            type: value.$1,
            value: value.$2,
            unit: value.$3,
            entry: entry,
          ),
        )
        .toList(growable: false);
  }

  Map<String, dynamic> _event({
    required String userId,
    required String dailyLogId,
    required String type,
    required num value,
    required String unit,
    required DailyCaptureEntry entry,
  }) {
    final origin = _originForEvent(entry, type);
    return {
      'id': _deterministicEventId(dailyLogId, type),
      'user_id': userId,
      'daily_log_id': dailyLogId,
      'event_type': type,
      'value': value,
      'unit': unit,
      'occurred_at':
          (origin.capturedAt ?? entry.latestCapturedAt ?? DateTime.now())
              .toUtc()
              .toIso8601String(),
      'source': QuickCheckInSupabaseDataSource.source,
      'metadata': _eventMetadata(entry: entry, type: type, origin: origin),
    };
  }

  Map<String, dynamic> _eventMetadata({
    required DailyCaptureEntry entry,
    required String type,
    required _EventOrigin origin,
  }) {
    final evening = origin.kind == 'evening' ? entry.evening : null;
    final morning = origin.kind == 'morning' ? entry.morning : null;
    return {
      'capture_version': DailyCaptureEntry.captureVersion,
      'entry_date': entry.entryDate,
      if (origin.kind != null) 'capture_kind': origin.kind,
      if (origin.captureId != null) 'capture_id': origin.captureId,
      if (origin.capturedAt != null)
        'captured_at': origin.capturedAt!.toUtc().toIso8601String(),
      if (evening != null) ...{
        'focus_band': evening.focusBand!.code,
        'main_friction': evening.mainFriction!.code,
        'tomorrow_priority': evening.tomorrowPriority,
        if (evening.makeTomorrowGentler) 'gentle_tomorrow': true,
      },
      if (evening != null && type == 'stress') ...{
        'stress_intensity_label': evening.stressIntensityLabel.code,
        'stress_source': evening.stressSource!.code,
        'stress_controllability': evening.stressControllability!.code,
      },
      if (morning != null) 'day_shape': morning.dayShape!.code,
    };
  }

  _EventOrigin _originForEvent(DailyCaptureEntry entry, String type) {
    if ((type == 'mood' || type == 'stress') && entry.evening != null) {
      return _EventOrigin.evening(entry.evening!);
    }
    if ((type == 'energy' || type == 'sleep') && entry.morning != null) {
      return _EventOrigin.morning(entry.morning!);
    }
    if (type == 'energy' && entry.evening != null) {
      return _EventOrigin.evening(entry.evening!);
    }
    final legacy = entry.legacy;
    return _EventOrigin(
      captureId: legacy?.captureId,
      capturedAt: legacy?.capturedAt,
    );
  }

  String _deterministicEventId(String dailyLogId, String eventType) {
    final hex = dailyLogId.replaceAll('-', '').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(hex)) {
      throw const FormatException('Daily log id must be a UUID.');
    }
    final suffix = switch (eventType) {
      'mood' => '6d6f6f64',
      'energy' => '656e6572',
      'stress' => '73747273',
      'sleep' => '736c6570',
      _ => throw FormatException('Unsupported event type $eventType.'),
    };
    final eventHex = '${hex.substring(0, 24)}$suffix';
    return '${eventHex.substring(0, 8)}-'
        '${eventHex.substring(8, 12)}-'
        '${eventHex.substring(12, 16)}-'
        '${eventHex.substring(16, 20)}-'
        '${eventHex.substring(20)}';
  }
}

class _StoredDailyCapture {
  const _StoredDailyCapture({required this.source, required this.entry});

  final String source;
  final DailyCaptureEntry entry;
}

class _EventOrigin {
  const _EventOrigin({this.kind, this.captureId, this.capturedAt});

  factory _EventOrigin.evening(EveningShutdownDraft draft) => _EventOrigin(
        kind: 'evening',
        captureId: draft.captureId,
        capturedAt: draft.capturedAt,
      );

  factory _EventOrigin.morning(MorningCalibrationDraft draft) => _EventOrigin(
        kind: 'morning',
        captureId: draft.captureId,
        capturedAt: draft.capturedAt,
      );

  final String? kind;
  final String? captureId;
  final DateTime? capturedAt;
}

Map<String, dynamic> _asStringMap(Object value, String field) {
  if (value is! Map) {
    throw FormatException('$field must be an object.');
  }
  return Map<String, dynamic>.from(value);
}
