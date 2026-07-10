import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/app_user_resolver.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../domain/quick_check_in.dart';

class QuickCheckInSupabaseDataSource implements QuickCheckInStore {
  const QuickCheckInSupabaseDataSource(
    this._client, {
    this.payloadBuilder = const QuickCheckInPayloadBuilder(),
  });

  static const source = 'quick_check_in';

  final SupabaseClient _client;
  final QuickCheckInPayloadBuilder payloadBuilder;

  @override
  QuickCheckInSaveTarget get target => QuickCheckInSaveTarget.supabase;

  @override
  Future<QuickCheckInDraft?> loadToday(DateTime today) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final row = await _client
        .from(SupabaseTables.dailyLogs)
        .select(
          'sleep_hours,energy_level,stress_level,mood_score,reflection,'
          'source,metadata,updated_at',
        )
        .eq('user_id', userId)
        .eq('entry_date', _dateOnly(today))
        .maybeSingle();

    if (row == null || row['source'] != source) {
      return null;
    }

    final metadata = Map<String, dynamic>.from(
      (row['metadata'] as Map?) ?? const <String, dynamic>{},
    );
    final capturedAt = DateTime.tryParse('${metadata['captured_at']}') ??
        DateTime.tryParse('${row['updated_at']}') ??
        today;
    final draft = QuickCheckInDraft(
      captureId:
          '${metadata['capture_id'] ?? 'daily-${capturedAt.toUtc().microsecondsSinceEpoch}'}',
      capturedAt: capturedAt,
      mood: (row['mood_score'] as num?)?.toInt(),
      energy: (row['energy_level'] as num?)?.toInt(),
      sleepHours: (row['sleep_hours'] as num?)?.toDouble(),
      stress: (row['stress_level'] as num?)?.toInt(),
      contextNote: '${metadata['context_note'] ?? row['reflection'] ?? ''}',
    );
    return draft.isComplete ? draft.normalized() : null;
  }

  @override
  Future<void> save(QuickCheckInDraft draft) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    await saveForUser(userId: userId, draft: draft);
  }

  Future<void> saveForUser({
    required String userId,
    required QuickCheckInDraft draft,
  }) async {
    draft.validate();
    final normalized = draft.normalized();
    final row = await _client
        .from(SupabaseTables.dailyLogs)
        .upsert(
          payloadBuilder.buildDailyLog(
            userId: userId,
            draft: normalized,
          ),
          onConflict: 'user_id,entry_date',
        )
        .select('id')
        .single();
    final dailyLogId = '${row['id']}';
    final dayStart = DateTime(
      normalized.capturedAt.year,
      normalized.capturedAt.month,
      normalized.capturedAt.day,
    );
    final nextDay = dayStart.add(const Duration(days: 1));

    await _client
        .from(SupabaseTables.behavioralEvents)
        .delete()
        .eq('user_id', userId)
        .eq('source', source)
        .gte('occurred_at', dayStart.toUtc().toIso8601String())
        .lt('occurred_at', nextDay.toUtc().toIso8601String());
    await _client.from(SupabaseTables.behavioralEvents).insert(
          payloadBuilder.buildBehavioralEvents(
            userId: userId,
            dailyLogId: dailyLogId,
            draft: normalized,
          ),
        );
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class QuickCheckInPayloadBuilder {
  const QuickCheckInPayloadBuilder();

  Map<String, dynamic> buildDailyLog({
    required String userId,
    required QuickCheckInDraft draft,
  }) {
    draft.validate();
    final normalized = draft.normalized();
    return {
      'user_id': userId,
      'entry_date': normalized.entryDate,
      'sleep_hours': normalized.sleepHours,
      'energy_level': normalized.energy,
      'stress_level': normalized.stress,
      'mood_score': normalized.mood,
      'mood_label': quickCheckInMoodCode(normalized.mood!),
      'steps': null,
      'activity_level': null,
      'screen_time_hours': null,
      'focus_minutes': null,
      'nutrition_notes': null,
      'day_focus': null,
      'reflection':
          normalized.contextNote.isEmpty ? null : normalized.contextNote,
      'source': QuickCheckInSupabaseDataSource.source,
      'metadata': {
        'capture_version': 'daily-check-in-v1',
        'capture_id': normalized.captureId,
        'captured_at': normalized.capturedAt.toUtc().toIso8601String(),
        'context_note': normalized.contextNote,
      },
      'updated_at': normalized.capturedAt.toUtc().toIso8601String(),
    };
  }

  List<Map<String, dynamic>> buildBehavioralEvents({
    required String userId,
    required String dailyLogId,
    required QuickCheckInDraft draft,
  }) {
    draft.validate();
    final normalized = draft.normalized();
    return [
      _event(
        userId,
        dailyLogId,
        'mood',
        normalized.mood!,
        'score_0_10',
        normalized,
      ),
      _event(
        userId,
        dailyLogId,
        'energy',
        normalized.energy!,
        'score_0_10',
        normalized,
      ),
      _event(
        userId,
        dailyLogId,
        'stress',
        normalized.stress!,
        'score_0_10',
        normalized,
      ),
      _event(
        userId,
        dailyLogId,
        'sleep',
        normalized.sleepHours!,
        'hours',
        normalized,
      ),
    ];
  }

  Map<String, dynamic> _event(
    String userId,
    String dailyLogId,
    String type,
    num value,
    String unit,
    QuickCheckInDraft draft,
  ) {
    return {
      'user_id': userId,
      'daily_log_id': dailyLogId,
      'event_type': type,
      'value': value,
      'unit': unit,
      'occurred_at': draft.capturedAt.toUtc().toIso8601String(),
      'source': QuickCheckInSupabaseDataSource.source,
      'metadata': {
        'capture_version': 'daily-check-in-v1',
        'capture_id': draft.captureId,
        'entry_date': draft.entryDate,
      },
    };
  }
}
