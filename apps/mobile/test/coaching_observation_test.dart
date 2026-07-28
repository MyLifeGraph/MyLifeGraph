import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/insights/domain/entities/correlation.dart';
import 'package:my_life_graph/features/insights/domain/services/coaching_observation.dart';

void main() {
  test('defaults to honest insufficient evidence', () {
    final observation = const CoachingObservationBuilder().build(
      const CorrelationReport(
        windowDays: 14,
        metrics: correlationMetrics,
        points: [],
        results: [],
      ),
    );

    expect(observation.confidence, ObservationConfidence.insufficient);
    expect(observation.experiment, isNull);
    expect(observation.summary, contains('not yet'));
  });

  test('labels a repeated pattern without claiming causation', () {
    final observation = const CoachingObservationBuilder().build(
      CorrelationReport(
        windowDays: 30,
        metrics: correlationMetrics,
        points: const [],
        results: const [
          CorrelationResult(
            metricAId: 'sleep_hours',
            metricBId: 'energy_level',
            sampleSize: 18,
            coefficient: 0.55,
            summary: 'unused',
          ),
        ],
      ),
    );

    expect(observation.confidence, ObservationConfidence.stronger);
    expect(observation.evidenceWindow, contains('18 shared days'));
    expect(observation.summary, contains('not proof'));
    expect(observation.experiment, isNull);
  });

  test('does not promote a five-day correlation as an insight', () {
    final observation = const CoachingObservationBuilder().build(
      CorrelationReport(
        windowDays: 7,
        metrics: correlationMetrics,
        points: const [],
        results: const [
          CorrelationResult(
            metricAId: 'sleep_hours',
            metricBId: 'energy_level',
            sampleSize: 5,
            coefficient: 0.95,
            summary: 'unused',
          ),
        ],
      ),
    );

    expect(observation.confidence, ObservationConfidence.insufficient);
    expect(observation.experiment, isNull);
    expect(observation.dataQuality, contains('14 comparable days'));
  });

  test('offers an experiment only for a safe factor to outcome pair', () {
    final observation = const CoachingObservationBuilder().build(
      CorrelationReport(
        windowDays: 30,
        metrics: correlationMetrics,
        points: [],
        results: [
          CorrelationResult(
            metricAId: 'planned_focus_minutes',
            metricBId: 'useful_progress',
            sampleSize: 18,
            coefficient: 0.45,
            summary: 'unused',
          ),
        ],
      ),
    );

    expect(observation.experiment, contains('Optional 7-day experiment'));
    expect(observation.experiment, contains('planned focus time'));
    expect(observation.experiment, contains('rated useful progress'));
  });

  test('keeps outcome to outcome pairs descriptive', () {
    final observation = const CoachingObservationBuilder().build(
      CorrelationReport(
        windowDays: 30,
        metrics: correlationMetrics,
        points: [],
        results: [
          CorrelationResult(
            metricAId: 'focus_quality',
            metricBId: 'useful_progress',
            sampleSize: 18,
            coefficient: 0.6,
            summary: 'unused',
          ),
        ],
      ),
    );

    expect(observation.experiment, isNull);
  });
}
