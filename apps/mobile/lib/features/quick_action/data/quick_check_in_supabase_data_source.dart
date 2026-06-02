import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/app_user_resolver.dart';
import '../../../core/supabase/supabase_tables.dart';

class QuickCheckInSupabaseDataSource {
  const QuickCheckInSupabaseDataSource(this._client);

  final SupabaseClient _client;

  Future<void> save(QuickCheckInDraft draft) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final now = DateTime.now();
    final dailyLogId = 'quick_daily_${now.microsecondsSinceEpoch}';
    final date = DateTime(now.year, now.month, now.day).toIso8601String();
    final reflection = [
      'Quick check-in mood rating: ${draft.mood}/10.',
      'Stress rating: ${draft.stress}/10.',
      if (draft.coachNotes.trim().isNotEmpty) draft.coachNotes.trim(),
    ].join(' ');

    await _client.from(SupabaseTables.dailyLogs).insert({
      'id': dailyLogId,
      'userId': userId,
      'date': date,
      'sleepHours': draft.sleepHours,
      'energyLevel': draft.energy,
      'reflection': reflection,
      'updatedAt': now.toIso8601String(),
    });

    await _tryInsertMoodLog(
      userId: userId,
      dailyLogId: dailyLogId,
      date: date,
      draft: draft,
    );

    await _tryInsertSleepLog(
      userId: userId,
      dailyLogId: dailyLogId,
      date: date,
      draft: draft,
    );

    if (draft.coachNotes.trim().isNotEmpty) {
      await _tryInsertMemory(userId, draft.coachNotes.trim(), now);
    }
  }

  Future<void> _tryInsertMoodLog({
    required String userId,
    required String dailyLogId,
    required String date,
    required QuickCheckInDraft draft,
  }) async {
    try {
      await _client.from(SupabaseTables.moodLogs).insert({
        'id': 'quick_mood_${DateTime.now().microsecondsSinceEpoch}',
        'userId': userId,
        'dailyLogId': dailyLogId,
        'date': date,
        'mood': _moodEnumValue(draft.mood),
        'energyLevel': draft.energy,
        'stressLevel': draft.stress,
        'notes':
            draft.coachNotes.trim().isEmpty ? null : draft.coachNotes.trim(),
      });
    } catch (_) {
      return;
    }
  }

  Future<void> _tryInsertSleepLog({
    required String userId,
    required String dailyLogId,
    required String date,
    required QuickCheckInDraft draft,
  }) async {
    try {
      await _client.from(SupabaseTables.sleepLogs).insert({
        'id': 'quick_sleep_${DateTime.now().microsecondsSinceEpoch}',
        'userId': userId,
        'dailyLogId': dailyLogId,
        'date': date,
        'hours': draft.sleepHours,
      });
    } catch (_) {
      return;
    }
  }

  Future<void> _tryInsertMemory(
    String userId,
    String notes,
    DateTime now,
  ) async {
    try {
      await _client.from(SupabaseTables.memoryEntries).insert({
        'id': 'quick_memory_${now.microsecondsSinceEpoch}',
        'userId': userId,
        'type': 'PATTERN',
        'title': 'Quick check-in note',
        'content': notes,
        'strength': 0.55,
        'lastSeenAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });
    } catch (_) {
      return;
    }
  }

  String _moodEnumValue(int rating) {
    if (rating >= 9) {
      return 'GREAT';
    }
    if (rating >= 7) {
      return 'GOOD';
    }
    if (rating >= 5) {
      return 'NEUTRAL';
    }
    if (rating >= 3) {
      return 'BAD';
    }
    return 'VERY_BAD';
  }
}

class QuickCheckInDraft {
  const QuickCheckInDraft({
    required this.mood,
    required this.energy,
    required this.sleepHours,
    required this.stress,
    required this.coachNotes,
  });

  final int mood;
  final int energy;
  final double sleepHours;
  final int stress;
  final String coachNotes;
}
