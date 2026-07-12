import '../entities/correlation.dart';

enum ObservationConfidence { insufficient, emerging, stronger }

class CoachingObservation {
  const CoachingObservation({
    required this.title,
    required this.summary,
    required this.evidenceWindow,
    required this.confidence,
    required this.dataQuality,
    required this.experiment,
  });

  final String title;
  final String summary;
  final String evidenceWindow;
  final ObservationConfidence confidence;
  final String dataQuality;
  final String? experiment;
}

class CoachingObservationBuilder {
  const CoachingObservationBuilder();

  CoachingObservation build(CorrelationReport report) {
    final ranked = report.rankedResults;
    if (ranked.isEmpty) {
      return CoachingObservation(
        title: 'Keep gathering comparable days',
        summary:
            'There is not yet a stable enough relationship to turn into a useful experiment.',
        evidenceWindow: '${report.points.length} logged days in this window',
        confidence: ObservationConfidence.insufficient,
        dataQuality: 'Not enough shared variation',
        experiment: null,
      );
    }
    final result = ranked.first;
    final metricA = report.metricById(result.metricAId);
    final metricB = report.metricById(result.metricBId);
    final coefficient = result.coefficient!;
    final confidence = result.sampleSize >= 14 && coefficient.abs() >= 0.4
        ? ObservationConfidence.stronger
        : ObservationConfidence.emerging;
    final direction =
        coefficient >= 0 ? 'moved together' : 'moved in opposite directions';
    return CoachingObservation(
      title:
          '${metricA.label} and ${metricB.label}: ${confidence == ObservationConfidence.stronger ? 'stronger pattern' : 'emerging pattern'}',
      summary:
          '${metricA.label} and ${metricB.label} $direction across the shared days. This is an association, not proof that one caused the other.',
      evidenceWindow:
          '${result.sampleSize} shared days within the ${report.windowDays < 0 ? 'all-time' : '${report.windowDays}-day'} window',
      confidence: confidence,
      dataQuality: confidence == ObservationConfidence.stronger
          ? 'Repeated shared measurements'
          : 'Early shared measurements',
      experiment:
          'Optional 7-day experiment: make one small, consistent change to ${metricA.label.toLowerCase()} and observe ${metricB.label.toLowerCase()} without changing your plan automatically.',
    );
  }
}
