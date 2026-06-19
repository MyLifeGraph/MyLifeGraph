import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/app_user_resolver.dart';
import '../../../core/supabase/supabase_tables.dart';

class QuickCheckInSupabaseDataSource {
  const QuickCheckInSupabaseDataSource(this._client);

  final SupabaseClient _client;

  Future<void> save(QuickCheckInDraft draft) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, now.day);
    final reflection = [
      'Quick check-in mood rating: ${draft.mood}/10.',
      'Stress rating: ${draft.stress}/10.',
      if (draft.coachNotes.trim().isNotEmpty) draft.coachNotes.trim(),
    ].join(' ');

    await _client.from(SupabaseTables.dailyLogs).upsert(
      {
        'user_id': userId,
        'entry_date': _dateOnly(date),
        'sleep_hours': draft.sleepHours,
        'energy_level': draft.energy,
        'stress_level': draft.stress,
        'mood_score': draft.mood,
        'mood_label': _moodLabel(draft.mood),
        'reflection': reflection,
        'source': 'quick_check_in',
        'updated_at': now.toIso8601String(),
      },
      onConflict: 'user_id,entry_date',
    );

    await _insertBehavioralEvents(userId, draft, now);

    if (draft.coachNotes.trim().isNotEmpty) {
      await _tryInsertMemory(userId, draft.coachNotes.trim(), now);
    }
  }

  Future<void> _insertBehavioralEvents(
    String userId,
    QuickCheckInDraft draft,
    DateTime now,
  ) async {
    try {
      await _client.from(SupabaseTables.behavioralEvents).insert([
        _event(userId, 'mood', draft.mood, 'score_0_10', now),
        _event(userId, 'energy', draft.energy, 'score_0_10', now),
        _event(userId, 'stress', draft.stress, 'score_0_10', now),
        _event(userId, 'sleep', draft.sleepHours, 'hours', now),
      ]);
    } catch (_) {
      return;
    }
  }

  Map<String, dynamic> _event(
    String userId,
    String type,
    num value,
    String unit,
    DateTime occurredAt,
  ) {
    return {
      'user_id': userId,
      'event_type': type,
      'value': value,
      'unit': unit,
      'occurred_at': occurredAt.toIso8601String(),
      'source': 'quick_check_in',
    };
  }

  Future<void> _tryInsertMemory(
    String userId,
    String notes,
    DateTime now,
  ) async {
    try {
      await _client.from(SupabaseTables.memoryEntries).insert({
        'user_id': userId,
        'type': 'pattern',
        'title': 'Quick check-in note',
        'content': notes,
        'strength': 0.55,
        'last_seen_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
    } catch (_) {
      return;
    }
  }

  String _moodLabel(int rating) {
    if (rating >= 9) {
      return 'great';
    }
    if (rating >= 7) {
      return 'good';
    }
    if (rating >= 5) {
      return 'neutral';
    }
    if (rating >= 3) {
      return 'low';
    }
    return 'very_low';
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
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
