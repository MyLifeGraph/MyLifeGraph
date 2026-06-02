import '../entities/insight.dart';

abstract interface class InsightsRepository {
  Future<List<Insight>> getInsights();
}
