import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/insights/domain/entities/correlation.dart';
import 'package:my_life_graph/features/insights/domain/entities/personal_patterns.dart';
import 'package:my_life_graph/features/insights/domain/services/checkin_correlations.dart';
import 'package:my_life_graph/features/insights/domain/services/correlation_analyzer.dart';
import 'package:my_life_graph/features/insights/domain/services/overview_observations.dart';

void main() {
  for (final count in [14, 28]) {
    test(
      '$count rated Focus days preserve every existing coefficient and ranked pair',
      () {
        final p = fixture(28, focus: true);
        p.correlationPoints.clear();
        p.correlationPoints.addAll([
          for (var i = 0; i < count; i++)
            PersonalPatternCorrelationPoint(
              localDate: DateTime(2026, 10, i + 1),
              focusQuality: 1 + i % 5,
              usefulProgress: 1 + i % 5,
              plannedFocusMinutes: 25,
              actualFocusMinutes: 20 + i % 5,
              completed: 1,
              sleepHours: 5 + (i % 5) / 2,
              sleepTargetDeviationMinutes: null,
              sleepQuality: 5 + i % 5,
              morningEnergy: 5 + i % 5,
            ),
        ]);
        final before = const CorrelationAnalyzer().analyze(
          windowDays: 90,
          points: p.correlationDataPoints(windowDays: 90),
        );
        final after = checkInCorrelationReport(p, windowDays: 90);
        expect(before.rankedResults, isNotEmpty);
        expect(after.isCheckInFallback, isFalse);
        expect(
          after.results.map(
            (r) => [
              r.metricAId,
              r.metricBId,
              r.sampleSize,
              r.coefficient,
              r.status,
              r.summary,
            ],
          ),
          before.results.map(
            (r) => [
              r.metricAId,
              r.metricBId,
              r.sampleSize,
              r.coefficient,
              r.status,
              r.summary,
            ],
          ),
        );
        expect(
          after.rankedResults.map((r) => [r.metricAId, r.metricBId]),
          before.rankedResults.map((r) => [r.metricAId, r.metricBId]),
        );
        expect(overviewObservations(p).sleep!.isCorrelation, isFalse);
      },
    );
  }
  test('check-ins alone calculate real correlations; seven days are amber', () {
    final r = checkInCorrelationReport(fixture(7), windowDays: 90);
    expect(r.isCheckInFallback, isTrue);
    final pair = r.resultFor('sleep_hours', 'energy_level')!;
    expect(pair.coefficient, closeTo(1, 1e-10));
    expect(pair.sampleSize, 7);
    expect(pair.status, CorrelationStatus.earlyEvidence);
    expect(r.rankedResults, isNotEmpty);
    expect(overviewObservations(fixture(7)).sleep!.isCorrelation, isTrue);
  });
  test('28 paired days repeated across both halves can turn green', () {
    final r = checkInCorrelationReport(fixture(28), windowDays: 90);
    expect(
      r.resultFor('sleep_hours', 'energy_level')!.status,
      CorrelationStatus.ready,
    );
    expect(
      overviewObservations(fixture(28)).sleep!.tier,
      OverviewObservationTier.supported,
    );
  });
  test(
    '27 days remain amber; a selected short window cannot borrow old days',
    () {
      expect(
        checkInCorrelationReport(
          fixture(27),
          windowDays: 90,
        ).results.first.status,
        CorrelationStatus.earlyEvidence,
      );
      expect(
        checkInCorrelationReport(
          fixture(28),
          windowDays: 7,
        ).results.first.status,
        CorrelationStatus.earlyEvidence,
      );
    },
  );
  test('inconsistent halves do not become green', () {
    final r = checkInCorrelationReport(
      fixture(28, reverseSecond: true),
      windowDays: 90,
    );
    expect(r.results.any((p) => p.status == CorrelationStatus.ready), isFalse);
  });
  test('missing and invalid values are excluded, not converted to zero', () {
    final p = fixture(7);
    p.skillsetPoints.last.values['energy_level'] = double.nan;
    final r = checkInCorrelationReport(p, windowDays: 90);
    expect(r.resultFor('sleep_hours', 'energy_level')!.sampleSize, 6);
    expect(r.rankedResults, isEmpty);
  });
  test('duplicates and future dates cannot inflate paired sample size', () {
    final p = fixture(7);
    p.skillsetPoints.add(p.skillsetPoints.last);
    p.skillsetPoints.add(
      CorrelationDataPoint(
        date: DateTime(2026, 11, 1),
        values: {'sleep_hours': 8, 'energy_level': 9},
      ),
    );
    expect(
      checkInCorrelationReport(p, windowDays: 90).results.first.sampleSize,
      6,
    );
  });
  test(
    'constant data retains descriptive summaries, not fabricated patterns',
    () {
      final p = fixture(28);
      for (final point in p.skillsetPoints) {
        point.values['energy_level'] = 5;
      }
      expect(
        checkInCorrelationReport(p, windowDays: 90).rankedResults,
        isEmpty,
      );
      expect(overviewObservations(p).sleep!.isCorrelation, isFalse);
    },
  );
  test('ordinal zero is valid optional activity; missing is not zero', () {
    final p = fixture(7);
    for (var i = 0; i < p.skillsetPoints.length; i++) {
      p.skillsetPoints[i].values['sport_activity'] = (i % 3).toDouble();
    }
    expect(
      checkInCorrelationReport(
        p,
        windowDays: 90,
      ).resultFor('sport_activity', 'energy_level')!.sampleSize,
      7,
    );
  });
  test('analysis disabled exposes no check-in correlations', () {
    expect(
      checkInCorrelationReport(
        fixture(28, disabled: true),
        windowDays: 90,
      ).points,
      isEmpty,
    );
  });
  test('one rated session cannot suppress usable check-in comparisons', () {
    final p = fixture(28, focus: true);
    final after = checkInCorrelationReport(p, windowDays: 90);
    final pair = after.resultFor('sleep_hours', 'energy_level')!;
    expect(pair.isCheckInEvidence, isTrue);
    expect(pair.sampleSize, 28);
    expect(pair.coefficient, closeTo(1, 1e-10));
    expect(after.pointsForPair('sleep_hours', 'energy_level').length, 28);
    expect(
      after.resultFor('focus_quality', 'useful_progress')!.isCheckInEvidence,
      isFalse,
    );
    expect(after.pointsForPair('focus_quality', 'useful_progress').length, 1);
    expect(after.rankedResults, contains(pair));
    expect(overviewObservations(p).sleep!.isCorrelation, isTrue);
  });

  test(
    'mixed report preserves early Focus pairs and their exact chart source',
    () {
      final p = fixture(28, focus: true);
      p.correlationPoints.clear();
      p.correlationPoints.addAll([
        for (var i = 0; i < 7; i++)
          PersonalPatternCorrelationPoint(
            localDate: DateTime(2026, 10, i + 1),
            focusQuality: 1 + i % 5,
            usefulProgress: 1 + i % 5,
            plannedFocusMinutes: 25,
            actualFocusMinutes: 20 + i % 5,
            completed: 1,
            sleepHours: 5 + (i % 5) / 2,
            sleepTargetDeviationMinutes: null,
            sleepQuality: null,
            morningEnergy: 5 + i % 5,
          ),
      ]);
      for (final point in p.skillsetPoints) {
        point.values['mood_score'] = point.values['energy_level']!;
      }
      final legacy = const CorrelationAnalyzer().analyze(
        windowDays: 90,
        points: p.correlationDataPoints(windowDays: 90),
      );
      final result = checkInCorrelationReport(p, windowDays: 90);
      for (final pair in legacy.results.where((r) => r.isReady)) {
        final selected = result.resultFor(pair.metricAId, pair.metricBId)!;
        expect(selected.isCheckInEvidence, isFalse);
        expect(selected.coefficient, pair.coefficient);
        expect(selected.sampleSize, pair.sampleSize);
        expect(selected.status, pair.status);
        expect(result.pointsForPair(pair.metricAId, pair.metricBId).length, 7);
      }
      final added = result.resultFor('mood_score', 'energy_level')!;
      expect(added.isCheckInEvidence, isTrue);
      expect(added.sampleSize, 28);
      expect(result.pointsForPair('energy_level', 'mood_score').length, 28);
      expect(result.pointsForMetric('mood_score').length, 28);
      expect(result.rankedResults.where((r) => !r.isCheckInEvidence), isEmpty);
    },
  );

  test('Focus outside selected window cannot disable current check-ins', () {
    final result = checkInCorrelationReport(
      fixture(28, focus: true),
      windowDays: 7,
    );
    final pair = result.resultFor('sleep_hours', 'energy_level')!;
    expect(pair.isCheckInEvidence, isTrue);
    expect(pair.sampleSize, 7);
    expect(pair.status, CorrelationStatus.earlyEvidence);
  });

  test('disabled mixed report never exposes fallback observations', () {
    final result = checkInCorrelationReport(
      fixture(28, focus: true, disabled: true),
      windowDays: 90,
    );
    expect(result.points, isEmpty);
    expect(result.checkInPoints, isEmpty);
    expect(result.results, isEmpty);
  });

  test(
    'no Focus: selected window reports fewer pairs without inventing values',
    () {
      final p = fixture(28);
      for (final point in p.skillsetPoints.skip(21)) {
        point.values.remove('energy_level');
      }
      final short = checkInCorrelationReport(p, windowDays: 7);
      expect(short.rankedResults, isEmpty);
      final longer = checkInCorrelationReport(p, windowDays: 90);
      expect(longer.resultFor('sleep_hours', 'energy_level')!.sampleSize, 21);
      expect(longer.rankedResults, isNotEmpty);
    },
  );
}

PersonalPatterns fixture(
  int count, {
  bool focus = false,
  bool disabled = false,
  bool reverseSecond = false,
}) => PersonalPatterns(
  status: disabled
      ? PersonalPatternsStatus.disabled
      : PersonalPatternsStatus.collecting,
  summary: '',
  timezone: 'Europe/Berlin',
  window: PersonalPatternsWindow(
    startsAt: DateTime.utc(2026, 8, 1),
    endsAt: DateTime.utc(2026, 10, 29),
    localStartsOn: DateTime(2026, 8, 1),
    localEndsOn: DateTime(2026, 10, count),
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
  evidenceFingerprint: null,
  correlationPoints: focus
      ? [
          PersonalPatternCorrelationPoint(
            localDate: DateTime(2026, 10, 1),
            focusQuality: 4,
            usefulProgress: 4,
            plannedFocusMinutes: 25,
            actualFocusMinutes: 25,
            completed: 1,
            sleepHours: null,
            sleepTargetDeviationMinutes: null,
            sleepQuality: null,
            morningEnergy: null,
          ),
        ]
      : [],
  skillsetPoints: [
    for (var i = 0; i < count; i++)
      CorrelationDataPoint(
        date: DateTime(2026, 10, i + 1),
        values: {
          'sleep_hours': 5 + (i % 7) / 2,
          'energy_level': reverseSecond && i >= count ~/ 2
              ? 10 - (i % 7).toDouble()
              : 3 + (i % 7).toDouble(),
        },
      ),
  ],
);
