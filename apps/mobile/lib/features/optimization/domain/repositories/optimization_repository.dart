import '../entities/recommendation_feed.dart';
import '../entities/skillset_profile.dart';

abstract interface class OptimizationRepository {
  Future<SkillsetProfile> getSkillsetProfile();

  Future<RecommendationFeed> getRecommendations();

  Future<RecommendationFeed> refreshRecommendations();
}
