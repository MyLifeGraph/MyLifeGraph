import 'recommendation.dart';

enum RecommendationProvenance {
  demo,
  authenticatedBackend,
}

enum RecommendationFreshness {
  current,
  missing,
  olderThanSevenDays,
  periodMismatch,
  notApplicable;

  bool get needsRefresh => switch (this) {
        RecommendationFreshness.missing ||
        RecommendationFreshness.olderThanSevenDays ||
        RecommendationFreshness.periodMismatch =>
          true,
        RecommendationFreshness.current ||
        RecommendationFreshness.notApplicable =>
          false,
      };
}

class RecommendationFeed {
  const RecommendationFeed({
    required this.items,
    required this.provenance,
    required this.freshness,
    required this.needsGeneration,
    required this.generatedAt,
    required this.periodKey,
  });

  factory RecommendationFeed.demo(List<Recommendation> items) {
    return RecommendationFeed(
      items: List.unmodifiable(items),
      provenance: RecommendationProvenance.demo,
      freshness: RecommendationFreshness.notApplicable,
      needsGeneration: false,
      generatedAt: null,
      periodKey: null,
    );
  }

  final List<Recommendation> items;
  final RecommendationProvenance provenance;
  final RecommendationFreshness freshness;
  final bool needsGeneration;
  final DateTime? generatedAt;
  final String? periodKey;
}
