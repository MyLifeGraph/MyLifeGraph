import '../entities/correlation.dart';
import '../entities/insight.dart';

abstract interface class InsightsRepository {
  Future<List<Insight>> getInsights();

  Future<List<CorrelationDataPoint>> getCorrelationDataPoints({
    required int windowDays,
  });
}
