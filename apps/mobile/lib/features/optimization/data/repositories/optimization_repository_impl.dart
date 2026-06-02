import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/recommendation.dart';
import '../../domain/entities/skillset_profile.dart';
import '../../domain/repositories/optimization_repository.dart';
import '../datasources/optimization_mock_data_source.dart';

class OptimizationRepositoryImpl implements OptimizationRepository {
  const OptimizationRepositoryImpl({
    required AppConfig config,
    required OptimizationMockDataSource mockDataSource,
    required ApiClient apiClient,
  })  : _config = config,
        _mockDataSource = mockDataSource,
        _apiClient = apiClient;

  final AppConfig _config;
  final OptimizationMockDataSource _mockDataSource;
  final ApiClient _apiClient;

  @override
  Future<SkillsetProfile> getSkillsetProfile() {
    if (_config.useMockData) {
      return _mockDataSource.getSkillsetProfile();
    }

    // The endpoint contract is intentionally isolated here. The UI and domain
    // layers do not need to know whether data came from Supabase or FastAPI.
    return _mockDataSource.getSkillsetProfile();
  }

  @override
  Future<List<Recommendation>> getRecommendations() async {
    if (_config.useMockData) {
      return _mockDataSource.getRecommendations();
    }

    await _apiClient.postJson('/v1/recommendations/preview');
    return _mockDataSource.getRecommendations();
  }
}
