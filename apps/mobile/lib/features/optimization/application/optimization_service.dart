import '../domain/entities/recommendation_feed.dart';
import '../domain/entities/skillset_profile.dart';
import '../domain/repositories/optimization_repository.dart';

class OptimizationService {
  const OptimizationService(this._repository);

  final OptimizationRepository _repository;

  Future<SkillsetProfile> loadSkillsetProfile() {
    return _repository.getSkillsetProfile();
  }

  Future<RecommendationFeed> loadActionableRecommendations() {
    return _repository.getRecommendations();
  }

  Future<RecommendationFeed> refreshActionableRecommendations() {
    return _repository.refreshRecommendations();
  }
}
