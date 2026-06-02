import '../entities/recommendation.dart';
import '../entities/skillset_profile.dart';

abstract interface class OptimizationRepository {
  Future<SkillsetProfile> getSkillsetProfile();

  Future<List<Recommendation>> getRecommendations();
}
