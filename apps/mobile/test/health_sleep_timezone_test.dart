import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:my_life_graph/core/time/profile_timezone.dart';
import 'package:my_life_graph/features/health_connect/domain/health_sleep_suggestion.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';

void main() {
  test('Berlin watch sleep retains Garmin wall clocks after projection', () {
    final suggestion = HealthSleepSuggestion.parse(
      {'started_at': '2026-09-26T02:39:00Z', 'woke_at': '2026-09-26T09:21:00Z'},
      '2026-09-26',
      'Europe/Berlin',
      DateTime.utc(2026, 9, 26, 12),
    )!;
    expect(suggestion.startedAt.hour, 4);
    expect(suggestion.wokeAt.hour, 11);
    expect(dailyCaptureClock(suggestion.startedAt), '04:39');
    expect(dailyCaptureClock(suggestion.wokeAt), '11:21');
  });

  for (final sample in [
    ('Europe/Berlin', '2026-01-26', '03:39', '10:21'),
    ('Europe/Berlin', '2026-09-26', '04:39', '11:21'),
    ('UTC', '2026-09-26', '02:39', '09:21'),
    ('America/New_York', '2026-09-26', '22:39', '05:21'),
    ('Asia/Kathmandu', '2026-09-26', '08:24', '15:06'),
    ('Australia/Lord_Howe', '2026-09-26', '13:09', '19:51'),
  ]) {
    test('watch clocks and exact instants survive JSON: $sample', () {
      final start = DateTime.parse('${sample.$2}T02:39:00Z');
      final wake = DateTime.parse('${sample.$2}T09:21:00Z');
      final suggestion = HealthSleepSuggestion.parse(
        {
          'started_at': start.toIso8601String(),
          'woke_at': wake.toIso8601String(),
        },
        sample.$2,
        sample.$1,
        wake.add(const Duration(hours: 1)),
      )!;
      expect(dailyCaptureClock(suggestion.startedAt), sample.$3);
      expect(dailyCaptureClock(suggestion.wokeAt), sample.$4);
      expect(suggestion.startedAt.toUtc(), start);
      expect(suggestion.wokeAt.difference(suggestion.startedAt).inMinutes, 402);
      final interval = estimatedSleepIntervalForLocalClocks(
        entryDate: sample.$2,
        estimatedSleepStartedAt: sample.$3,
        wokeAt: sample.$4,
        timezoneName: sample.$1,
      );
      expect(interval.estimatedSleepStartedAt.toUtc(), start);
      expect(interval.wokeAt.toUtc(), wake);
      final reloaded = DateTime.parse(
        interval.wokeAt.toUtc().toIso8601String(),
      );
      expect(
        dailyCaptureClock(
          profileDateTimeAt(instant: reloaded, timezoneName: sample.$1),
        ),
        sample.$4,
      );
    });
  }

  test(
    'wall-clock formatter preserves every bundled IANA zone in both seasons',
    () {
      initializeProfileTimeZones();
      for (final zone in tz.timeZoneDatabase.locations.keys) {
        for (final month in [1, 3, 7, 10]) {
          final instant = DateTime.utc(2026, month, 26, 23, 39);
          final local = profileDateTimeAt(instant: instant, timezoneName: zone);
          final clock =
              '${local.hour.toString().padLeft(2, '0')}:'
              '${local.minute.toString().padLeft(2, '0')}';
          expect(dailyCaptureClock(local), clock, reason: '$zone / $month');
          expect(local.toUtc(), instant, reason: zone);
        }
      }
    },
  );

  for (final transition in [
    ('Europe/Berlin', '2026-03-29', 420),
    ('Europe/Berlin', '2026-10-25', 540),
    ('America/New_York', '2026-03-08', 420),
    ('America/New_York', '2026-11-01', 540),
    ('Australia/Lord_Howe', '2026-10-04', 450),
    ('Australia/Lord_Howe', '2026-04-05', 510),
  ]) {
    test('sleep elapsed duration follows DST rules: $transition', () {
      final interval = estimatedSleepIntervalForLocalClocks(
        entryDate: transition.$2,
        estimatedSleepStartedAt: '23:00',
        wokeAt: '07:00',
        timezoneName: transition.$1,
      );
      expect(
        interval.wokeAt.difference(interval.estimatedSleepStartedAt).inMinutes,
        transition.$3,
      );
      final imported = HealthSleepSuggestion.parse(
        {
          'started_at': interval.estimatedSleepStartedAt
              .toUtc()
              .toIso8601String(),
          'woke_at': interval.wokeAt.toUtc().toIso8601String(),
        },
        transition.$2,
        transition.$1,
        interval.wokeAt.add(const Duration(hours: 1)),
      )!;
      expect(dailyCaptureClock(imported.startedAt), '23:00');
      expect(dailyCaptureClock(imported.wokeAt), '07:00');
    });
  }

  test(
    'manual clocks fail closed for gaps, folds and invalid profile zones',
    () {
      for (final day in ['2026-03-29', '2026-10-25']) {
        expect(
          () => dailyCaptureInstantForClock(
            entryDate: day,
            clock: '02:30',
            timezoneName: 'Europe/Berlin',
          ),
          throwsA(isA<ProfileTimezoneException>()),
        );
      }
      for (final zone in ['', 'Invalid/Zone']) {
        expect(
          () => dailyCaptureInstantForClock(
            entryDate: '2026-09-26',
            clock: '07:00',
            timezoneName: zone,
          ),
          throwsA(isA<ProfileTimezoneException>()),
        );
      }
    },
  );

  test('watch instants in repeated hour stay unambiguous and date-bound', () {
    final data = {
      'started_at': '2026-10-24T23:00:00Z',
      'woke_at': '2026-10-25T01:30:00Z',
    };
    final now = DateTime.utc(2026, 10, 25, 5);
    final watch = HealthSleepSuggestion.parse(
      data,
      '2026-10-25',
      'Europe/Berlin',
      now,
    )!;
    expect(dailyCaptureClock(watch.wokeAt), '02:30');
    expect(watch.wokeAt.toUtc(), DateTime.utc(2026, 10, 25, 1, 30));
    expect(watch.wokeAt.difference(watch.startedAt).inMinutes, 150);
    expect(
      HealthSleepSuggestion.parse(data, '2026-10-24', 'Europe/Berlin', now),
      isNull,
    );
  });
}
