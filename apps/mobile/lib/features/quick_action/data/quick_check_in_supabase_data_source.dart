import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/api_client.dart';
import '../../../core/supabase/app_user_resolver.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../core/utils/client_uuid.dart';
import '../domain/quick_check_in.dart';

class QuickCheckInSupabaseDataSource implements QuickCheckInStore {
  QuickCheckInSupabaseDataSource(
    this._client, {
    ApiClient? apiClient,
    this.payloadBuilder = const QuickCheckInPayloadBuilder(),
    this.rowMapper = const QuickCheckInDailyRowMapper(),
  }) : _apiClient = apiClient;

  static const source = 'quick_check_in';

  final SupabaseClient _client;
  final ApiClient? _apiClient;
  final QuickCheckInPayloadBuilder payloadBuilder;
  final QuickCheckInDailyRowMapper rowMapper;
  final Map<String, _PendingCaptureWrite> _pendingWrites = {};

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
  Future<EveningShutdownDraft?> loadLatestEvening() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final rows = await _client
        .from(SupabaseTables.dailyLogs)
        .select(
          'id,entry_date,sleep_hours,energy_level,stress_level,mood_score,'
          'reflection,source,metadata,updated_at',
        )
        .eq('user_id', userId)
        .eq('source', source)
        .order('entry_date', ascending: false)
        .limit(30);
    for (final raw in rows) {
      try {
        final evening =
            rowMapper.map(Map<String, dynamic>.from(raw as Map)).evening;
        if (evening?.hasPreciseSleepPlan == true) {
          return evening;
        }
      } on FormatException {
        // A malformed older row cannot become the current sleep plan.
      }
    }
    return null;
  }

  @override
  Future<void> saveEvening(EveningShutdownDraft draft) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final existing = await _loadRowForUser(
      userId: userId,
      entryDate: draft.entryDate,
    );
    await _writeBranch(
      entryDate: draft.entryDate,
      branch: 'evening',
      capture: draft.toMetadataJson(preservingCompatibility: false),
      expected: existing?.entry.evening,
    );
  }

  @override
  Future<void> saveMorning(MorningCalibrationDraft draft) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final existing = await _loadRowForUser(
      userId: userId,
      entryDate: draft.entryDate,
    );
    await _writeBranch(
      entryDate: draft.entryDate,
      branch: 'morning',
      capture: draft.toMetadataJson(preservingCompatibility: false),
      expected: existing?.entry.morning,
    );
  }

  /// Used only by the best-effort guest-to-account check-in migration.
  Future<void> mergeEntryForUser({
    required String userId,
    required DailyCaptureEntry entry,
  }) async {
    final currentUserId = await AppUserResolver(_client).resolveUserId();
    if (currentUserId != userId) {
      throw const QuickCheckInUnavailableException(
        'Daily Capture account identity changed.',
      );
    }
    final migrationEntry = entry.forAuthenticatedMigration();
    if (migrationEntry.evening != null) {
      await saveEvening(migrationEntry.evening!);
    }
    if (migrationEntry.morning != null) {
      await saveMorning(migrationEntry.morning!);
    }
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

  Future<void> _writeBranch({
    required String entryDate,
    required String branch,
    required Map<String, dynamic> capture,
    required dynamic expected,
  }) async {
    final apiClient = _apiClient;
    final accessToken = _client.auth.currentSession?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      throw const QuickCheckInUnavailableException(
        'Daily Capture sync is unavailable. Keep this draft and retry.',
      );
    }
    final expectedCapture = switch (expected) {
      EveningShutdownDraft value => {
          'capture_id': value.captureId,
          'captured_at': value.capturedAt.toUtc().toIso8601String(),
        },
      MorningCalibrationDraft value => {
          'capture_id': value.captureId,
          'captured_at': value.capturedAt.toUtc().toIso8601String(),
        },
      _ => null,
    };
    final requestKey = '$entryDate:$branch:${jsonEncode(capture)}';
    final pending = _pendingWrites.putIfAbsent(
      requestKey,
      () => _PendingCaptureWrite(
        requestId: newClientUuid(),
        expectedCapture: expectedCapture,
      ),
    );
    final response = await apiClient.putJson(
      '/v1/daily-capture/$entryDate/$branch',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: {
        'contract_version': 'daily-capture-write-v1',
        'request_id': pending.requestId,
        'expected_capture': pending.expectedCapture,
        'capture': capture,
      },
    );
    final returnedCapturedAt =
        DateTime.tryParse('${response['captured_at'] ?? ''}');
    final requestedCapturedAt =
        DateTime.tryParse('${capture['captured_at'] ?? ''}');
    final returnedUpdatedAt =
        DateTime.tryParse('${response['updated_at'] ?? ''}');
    if (response['contract_version'] != 'daily-capture-write-v1' ||
        response['entry_date'] != entryDate ||
        response['branch'] != branch ||
        response['capture_id'] != capture['capture_id'] ||
        returnedCapturedAt == null ||
        requestedCapturedAt == null ||
        returnedCapturedAt.toUtc() != requestedCapturedAt.toUtc() ||
        returnedUpdatedAt == null ||
        returnedUpdatedAt.toUtc().isBefore(returnedCapturedAt.toUtc()) ||
        response['replayed'] is! bool) {
      throw const QuickCheckInUnavailableException(
        'Daily Capture save could not be confirmed. Keep this draft and retry.',
      );
    }
    _pendingWrites.remove(requestKey);
  }
}

class _PendingCaptureWrite {
  const _PendingCaptureWrite({
    required this.requestId,
    required this.expectedCapture,
  });

  final String requestId;
  final Map<String, dynamic>? expectedCapture;
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
      ..remove('context_note')
      ..remove('main_friction')
      ..remove('additional_frictions');
    final capturesRaw = metadata['captures'];
    final captureVersion = metadata['capture_version'];
    final supportedCaptureVersion =
        DailyCaptureEntry.supportedCaptureVersions.contains(captureVersion);
    if ((supportedCaptureVersion && capturesRaw == null) ||
        (capturesRaw != null && !supportedCaptureVersion)) {
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
              containerVersion: '$captureVersion',
            ),
      morning: morningRaw == null
          ? null
          : MorningCalibrationDraft.fromJson(
              _asStringMap(morningRaw, 'morning capture'),
              entryDate: entryDate,
              containerVersion: '$captureVersion',
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
        if (evening.focusBand != null) 'focus_band': evening.focusBand!.code,
        if (evening.tomorrowPriority.isNotEmpty)
          'tomorrow_priority': evening.tomorrowPriority,
      },
      if (evening != null && type == 'stress') ...{
        'stress_intensity_label': evening.stressIntensityLabel.code,
        if (evening.stressSource != null)
          'stress_source': evening.stressSource!.code,
        if (evening.stressControllability != null)
          'stress_controllability': evening.stressControllability!.code,
      },
      if (morning != null) ...{
        if (morning.sleepQuality != null) 'sleep_quality': morning.sleepQuality,
      },
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
