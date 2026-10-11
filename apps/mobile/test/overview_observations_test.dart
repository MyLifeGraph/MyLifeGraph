import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/insights/domain/entities/correlation.dart';
import 'package:my_life_graph/features/insights/domain/entities/personal_patterns.dart';
import 'package:my_life_graph/features/insights/domain/services/overview_observations.dart';

void main() {
  test(
    'disabled analysis exposes neither guidance nor personal observations',
    () {
      final result = overviewObservations(
        _report(
          _days(7, {'energy_level': 7, 'sleep_hours': 8}),
          status: PersonalPatternsStatus.disabled,
        ),
      );
      expect(result.study, isNull);
      expect(result.sleep, isNull);
    },
  );

  for (final length in [0, 6]) {
    test('$length observed days retain sourced general guidance', () {
      final result = overviewObservations(
        _report(_days(length, {'energy_level': 7, 'sleep_hours': 8})),
      );
      expect(result.study!.tier, OverviewObservationTier.general);
      expect(result.sleep!.tier, OverviewObservationTier.general);
      expect(result.study!.observedDays, length);
      expect(result.sleep!.observedDays, length);
      expect(result.study!.bullets, [
        'Space study across several days.',
        'Test yourself, not just reread.',
      ]);
      expect(
        result.study!.sourceUrls.single,
        startsWith('https://www.psychologicalscience.org/'),
      );
      expect(
        result.sleep!.sourceUrls.single,
        startsWith('https://www.nhlbi.nih.gov/'),
      );
    });
  }

  test('seven check-in days need no Focus sessions or reflections', () {
    final result = overviewObservations(
      _report(
        _days(7, {
          'energy_level': 6,
          'mood_score': 8,
          'stress_level': 2,
          'sleep_hours': 7.5,
          'sleep_quality': 9,
        }),
      ),
    );
    expect(result.study!.tier, OverviewObservationTier.preliminary);
    expect(result.study!.bullets, [
      'Energy · 6/10 median',
      'Mood · 8/10 median',
    ]);
    expect(result.sleep!.bullets, [
      'Sleep duration · 7h 30m median',
      'Sleep quality · 9/10 median',
    ]);
    expect(result.study!.observedDays, 7);
    expect(result.study!.missingSources, contains('Focus history: 0/7 days'));
    expect(result.study!.sourceUrls, isEmpty);
  });

  test('seven Focus-only days report count and whole-window completion', () {
    final result = overviewObservations(
      _report([
        ..._days(6, {'focus_count': 1, 'focus_completed': 0}),
        _point(7, {'focus_count': 4, 'focus_completed': 4}),
      ]),
    );
    expect(result.study!.title, 'Your Focus activity');
    expect(result.study!.bullets, [
      '10 terminal Focus sessions · 7 days',
      '40% completed',
    ]);
    expect(result.study!.observedDays, 7);
    expect(
      result.study!.missingSources,
      contains('Check-in history: 0/7 days'),
    );
    expect(result.sleep!.tier, OverviewObservationTier.general);
  });

  test('many sessions on six dates do not satisfy seven-day threshold', () {
    final result = overviewObservations(
      _report(_days(6, {'focus_count': 20, 'focus_completed': 20})),
    );
    expect(result.study!.tier, OverviewObservationTier.general);
    expect(result.study!.observedDays, 6);
  });

  test(
    'mixed reports prefer up to two check-in summaries without correlations',
    () {
      final result = overviewObservations(
        _report(
          _days(7, {
            'energy_level': 8,
            'stress_level': 4,
            'focus_count': 1,
            'focus_completed': 1,
          }),
          status: PersonalPatternsStatus.stable,
        ),
      );
      expect(result.study!.title, 'Your check-ins');
      expect(result.study!.tier, OverviewObservationTier.preliminary);
      expect(result.study!.bullets, [
        'Energy · 8/10 median',
        'Stress · 4/10 median',
      ]);
      expect(
        result.study!.details,
        contains('Stress is not inverted; lower means calmer.'),
      );
      expect(result.study!.missingSources, isEmpty);
    },
  );

  test('coverage is per metric, not a union of insufficient measures', () {
    final result = overviewObservations(
      _report([
        ..._days(4, {'energy_level': 8, 'sleep_hours': 8}),
        for (var day = 5; day <= 8; day++)
          _point(day, {'mood_score': 7, 'sleep_quality': 9}),
      ]),
    );
    expect(result.study!.tier, OverviewObservationTier.general);
    expect(result.sleep!.tier, OverviewObservationTier.general);
    expect(
      result.study!.missingSources,
      contains('Check-in history: 4/7 days'),
    );
    expect(result.sleep!.missingSources, contains('Sleep history: 4/7 days'));
  });

  test(
    'duplicate dates are excluded entirely, including different clock flags',
    () {
      final result = overviewObservations(
        _report([
          ..._days(7, {'energy_level': 8, 'sleep_hours': 8}),
          CorrelationDataPoint(
            date: DateTime.utc(2026, 10, 4),
            values: {'energy_level': 2},
          ),
        ]),
      );
      expect(result.study!.tier, OverviewObservationTier.general);
      expect(result.sleep!.tier, OverviewObservationTier.general);
      expect(result.study!.observedDays, 6);
    },
  );

  test('dates outside window and non-date instants cannot add coverage', () {
    final result = overviewObservations(
      _report([
        ..._days(6, {'energy_level': 8}),
        CorrelationDataPoint(
          date: DateTime(2026, 9, 30),
          values: {'energy_level': 8},
        ),
        _point(13, {'energy_level': 8}),
        CorrelationDataPoint(
          date: DateTime(2026, 10, 7, 1),
          values: {'energy_level': 8},
        ),
      ]),
    );
    expect(result.study!.tier, OverviewObservationTier.general);
    expect(result.study!.observedDays, 6);
  });

  test(
    'inclusive local window boundaries count without instant conversion',
    () {
      final points = [
        for (var day = 6; day <= 12; day++)
          CorrelationDataPoint(
            date: DateTime.utc(2026, 10, day),
            values: {'energy_level': 8},
          ),
      ];
      for (final zone in ['Europe/Berlin', 'UTC', 'America/New_York']) {
        final result = overviewObservations(_report(points, timezone: zone));
        expect(result.study!.tier, OverviewObservationTier.preliminary);
        expect(result.study!.observedDays, 7);
      }
    },
  );

  for (final invalid in [
    double.nan,
    double.infinity,
    double.negativeInfinity,
    0.0,
    -1.0,
    11.0,
  ]) {
    test('invalid rating $invalid is missing rather than zero', () {
      final result = overviewObservations(
        _report([
          ..._days(6, {'energy_level': 8, 'sleep_quality': 8}),
          _point(7, {'energy_level': invalid, 'sleep_quality': invalid}),
        ]),
      );
      expect(result.study!.tier, OverviewObservationTier.general);
      expect(result.sleep!.tier, OverviewObservationTier.general);
      expect(result.study!.observedDays, 6);
    });
  }

  for (final invalid in [0.0, -0.1, 24.1, double.nan, double.infinity]) {
    test('invalid sleep duration $invalid does not promote guidance', () {
      final result = overviewObservations(
        _report([
          ..._days(6, {'sleep_hours': 8}),
          _point(7, {'sleep_hours': invalid}),
        ]),
      );
      expect(result.sleep!.tier, OverviewObservationTier.general);
    });
  }

  test('valid scale extremes and zero completed sessions remain measured', () {
    final result = overviewObservations(
      _report(
        _days(7, {
          'mood_score': 1,
          'stress_level': 10,
          'sleep_hours': 24,
          'sleep_quality': 1,
          'focus_count': 1,
          'focus_completed': 0,
        }),
      ),
    );
    expect(result.study!.bullets, [
      'Mood · 1/10 median',
      'Stress · 10/10 median',
    ]);
    expect(result.sleep!.bullets.first, 'Sleep duration · 24h median');
    final focusOnly = overviewObservations(
      _report(_days(7, {'focus_count': 1, 'focus_completed': 0})),
    );
    expect(focusOnly.study!.bullets.last, '0% completed');
  });

  for (final invalid in <Map<String, double>>[
    {'focus_count': 0, 'focus_completed': 0},
    {'focus_count': 1.5, 'focus_completed': 1},
    {'focus_count': 2, 'focus_completed': 0.5},
    {'focus_count': 2, 'focus_completed': 3},
    {'focus_count': 2, 'focus_completed': -1},
    {'focus_count': double.infinity, 'focus_completed': 0},
    {'focus_count': 1e100, 'focus_completed': 0},
    {'focus_count': 2, 'focus_completed': double.nan},
    {'focus_count': 2},
  ]) {
    test('invalid Focus facts $invalid cannot count as a measured day', () {
      final result = overviewObservations(
        _report([
          ..._days(6, {'focus_count': 2, 'focus_completed': 1}),
          _point(7, invalid),
        ]),
      );
      expect(result.study!.tier, OverviewObservationTier.general);
      expect(result.study!.observedDays, 6);
    });
  }

  test('medians are deterministic and do not mutate source lists or maps', () {
    final points = [
      for (var day = 1; day <= 8; day++)
        _point(day, {'energy_level': day.toDouble()}),
    ].reversed.toList();
    final before = [for (final point in points) Map.of(point.values)];
    final dates = points.map((point) => point.date).toList();
    final report = _report(points);
    final first = overviewObservations(report);
    final second = overviewObservations(report);
    expect(first.study!.bullets, ['Energy · 4.5/10 median']);
    expect(second.study!.bullets, first.study!.bullets);
    expect(second.study!.details, first.study!.details);
    expect(points.map((point) => point.date).toList(), dates);
    expect(points.map((point) => point.values).toList(), before);
    expect(() => first.study!.bullets.add('mutate'), throwsUnsupportedError);
    expect(() => first.study!.details.clear(), throwsUnsupportedError);
    expect(() => first.study!.missingSources.clear(), throwsUnsupportedError);
    expect(() => first.study!.sourceUrls.add('mutate'), throwsUnsupportedError);
  });

  test('sleep summaries round minutes without changing raw observations', () {
    final points = _days(7, {'sleep_hours': 7 + 20 / 60});
    final result = overviewObservations(_report(points));
    expect(result.sleep!.bullets, ['Sleep duration · 7h 20m median']);
    expect(points.first.values['sleep_hours'], 7 + 20 / 60);
    final belowMinute = overviewObservations(
      _report(_days(7, {'sleep_hours': 0.001})),
    );
    expect(belowMinute.sleep!.bullets, ['Sleep duration · <1m median']);
  });
}

CorrelationDataPoint _point(int day, Map<String, double> values) =>
    CorrelationDataPoint(date: DateTime(2026, 10, day), values: values);

List<CorrelationDataPoint> _days(int count, Map<String, double> values) => [
  for (var day = 1; day <= count; day++) _point(day, values),
];

PersonalPatterns _report(
  List<CorrelationDataPoint> points, {
  PersonalPatternsStatus status = PersonalPatternsStatus.collecting,
  String timezone = 'Europe/Berlin',
}) => PersonalPatterns(
  status: status,
  summary: '',
  timezone: timezone,
  window: PersonalPatternsWindow(
    startsAt: DateTime.utc(2026, 7, 14),
    endsAt: DateTime.utc(2026, 10, 12, 10),
    localStartsOn: DateTime(2026, 10, 1),
    localEndsOn: DateTime(2026, 10, 12),
  ),
  sample: const PersonalPatternsSample(
    terminalSessions: 0,
    ratedSessions: 0,
    ratedLocalDays: 0,
    ratingCoverage: 0,
    firstRatedLocalDate: null,
    lastRatedLocalDate: null,
  ),
  baseline: null,
  patterns: const [],
  plannerPreference: const LearnedPlannerPreference(
    eligible: false,
    reason: 'insufficient_evidence',
    window: null,
    windowLabel: null,
    evidenceCount: 0,
  ),
  limitations: const [],
  correlationPoints: const [],
  evidenceFingerprint: null,
  skillsetPoints: points,
);
