enum RecommendationCategory {
  focus,
  recovery,
  nutrition,
  movement,
  planning,
}

class Recommendation {
  const Recommendation({
    required this.id,
    required this.title,
    required this.reason,
    required this.actionLabel,
    required this.category,
    required this.confidence,
  });

  final String id;
  final String title;
  final String reason;
  final String actionLabel;
  final RecommendationCategory category;
  final double confidence;
}
