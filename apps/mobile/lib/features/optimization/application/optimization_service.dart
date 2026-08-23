import '../domain/entities/skillset_profile.dart';
import '../domain/repositories/optimization_repository.dart';

class OptimizationService {
  const OptimizationService(this._repository);

  final OptimizationRepository _repository;

  Future<SkillsetProfile> loadSkillsetProfile() {
    return _repository.getSkillsetProfile();
  }
}
