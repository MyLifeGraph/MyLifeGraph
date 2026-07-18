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
    expect(observation.experiment, contains('Optional 7-day experiment'));
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
}
