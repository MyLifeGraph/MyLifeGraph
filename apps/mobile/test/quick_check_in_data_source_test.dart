import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/quick_action/data/guest_quick_check_in_data_source.dart';
import 'package:my_life_graph/features/quick_action/data/quick_check_in_supabase_data_source.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('QuickCheckInPayloadBuilder', () {
    const builder = QuickCheckInPayloadBuilder();
    final capturedAt = DateTime.parse('2026-07-10T19:45:00+02:00');
    final draft = QuickCheckInDraft(
      captureId: 'capture-exact-values',
      capturedAt: capturedAt,
      mood: 2,
      energy: 9,
      sleepHours: 5.5,
      stress: 8,
      contextNote: '  Exact context note  ',
    );

    test('builds an exact daily log from selected values only', () {
      final row = builder.buildDailyLog(
        userId: 'user-123',
        draft: draft,
      );

      expect(row, {
        'user_id': 'user-123',
        'entry_date': '2026-07-10',
        'sleep_hours': 5.5,
        'energy_level': 9,
        'stress_level': 8,
        'mood_score': 2,
        'mood_label': 'very_low',
        'steps': null,
        'activity_level': null,
        'screen_time_hours': null,
        'focus_minutes': null,
        'nutrition_notes': null,
        'day_focus': null,
        'reflection': 'Exact context note',
        'source': 'quick_check_in',
        'metadata': {
          'capture_version': 'daily-check-in-v1',
          'capture_id': 'capture-exact-values',
          'captured_at': '2026-07-10T17:45:00.000Z',
          'context_note': 'Exact context note',
        },
        'updated_at': '2026-07-10T17:45:00.000Z',
      });
      expect(row['steps'], isNull);
      expect(row['activity_level'], isNull);
      expect(row['screen_time_hours'], isNull);
      expect(row['focus_minutes'], isNull);
      expect(row['nutrition_notes'], isNull);
      expect(row['day_focus'], isNull);
    });

    test('builds one linked behavioral event per selected signal', () {
      final events = builder.buildBehavioralEvents(
        userId: 'user-123',
        dailyLogId: 'daily-log-456',
        draft: draft,
      );

      expect(events, hasLength(4));
      expect(
        events.map(
          (event) => (
            event['event_type'],
            event['value'],
            event['unit'],
            event['daily_log_id'],
          ),
        ),
        [
          ('mood', 2, 'score_0_10', 'daily-log-456'),
          ('energy', 9, 'score_0_10', 'daily-log-456'),
          ('stress', 8, 'score_0_10', 'daily-log-456'),
          ('sleep', 5.5, 'hours', 'daily-log-456'),
        ],
      );
      for (final event in events) {
        expect(event['user_id'], 'user-123');
        expect(event['source'], 'quick_check_in');
        expect(event['occurred_at'], '2026-07-10T17:45:00.000Z');
        expect(event['metadata'], {
          'capture_version': 'daily-check-in-v1',
          'capture_id': 'capture-exact-values',
          'entry_date': '2026-07-10',
        });
      }
    });

    test('rejects an incomplete draft', () {
      final incomplete = QuickCheckInDraft.empty(capturedAt);

      expect(
        () => builder.buildDailyLog(
          userId: 'user-123',
          draft: incomplete,
        ),
        throwsFormatException,
      );
    });
  });

  group('GuestQuickCheckInDataSource', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('persists exact values and deduplicates retries for the day',
        () async {
      final store = GuestQuickCheckInDataSource();
      final draft = QuickCheckInDraft(
        captureId: 'guest-capture',
        capturedAt: DateTime.parse('2026-07-10T09:00:00+02:00'),
        mood: 2,
        energy: 9,
        sleepHours: 5.5,
        stress: 8,
        contextNote: '  Local exact note  ',
      );

      await store.save(draft);
      await store.save(draft);

      final values = await store.readAll();
      expect(values, hasLength(1));
      expect(values.single.toJson(), {
        'captureId': 'guest-capture',
        'createdAt': '2026-07-10T07:00:00.000Z',
        'entryDate': '2026-07-10',
        'mood': 2,
        'energy': 9,
        'sleepHours': 5.5,
        'stress': 8,
        'contextNote': 'Local exact note',
      });

      final prefs = await SharedPreferences.getInstance();
      final raw = jsonDecode(
        prefs.getString(GuestQuickCheckInDataSource.storageKey)!,
      ) as List<dynamic>;
      expect(raw, hasLength(1));
    });

    test('a new save can recover corrupted local storage', () async {
      SharedPreferences.setMockInitialValues({
        GuestQuickCheckInDataSource.storageKey: '{not-json',
      });
      final store = GuestQuickCheckInDataSource();
      final draft = QuickCheckInDraft(
        captureId: 'recovered-capture',
        capturedAt: DateTime.parse('2026-07-10T09:00:00+02:00'),
        mood: 4,
        energy: 5,
        sleepHours: 6,
        stress: 7,
        contextNote: '',
      );

      await store.save(draft);

      expect(await store.readAll(), hasLength(1));
    });
  });
}
