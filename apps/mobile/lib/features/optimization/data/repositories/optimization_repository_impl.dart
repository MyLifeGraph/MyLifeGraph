import '../../../../core/config/app_config.dart';
import '../../domain/entities/skillset_profile.dart';
import '../../domain/repositories/optimization_repository.dart';
import '../datasources/optimization_mock_data_source.dart';

typedef SkillsetProfileLoader = Future<SkillsetProfile> Function();

class OptimizationRepositoryImpl implements OptimizationRepository {
  const OptimizationRepositoryImpl({
    required AppConfig config,
    required OptimizationMockDataSource mockDataSource,
    SkillsetProfileLoader? skillsetProfileLoader,
    required bool allowDemoData,
  })  : _config = config,
        _mockDataSource = mockDataSource,
        _skillsetProfileLoader = skillsetProfileLoader,
        _allowDemoData = allowDemoData;

  final AppConfig _config;
  final OptimizationMockDataSource _mockDataSource;
  final SkillsetProfileLoader? _skillsetProfileLoader;
  final bool _allowDemoData;

  bool get _usesDemoData => _config.useMockData || _allowDemoData;

  @override
  Future<SkillsetProfile> getSkillsetProfile() async {
    if (_usesDemoData) {
      return _mockDataSource.getSkillsetProfile();
    }

    if (!_config.isSupabaseConfigured || _skillsetProfileLoader == null) {
      throw const SkillsetProfileAccessException(
        'Authenticated skillset profiles require Supabase configuration.',
      );
    }
    return _skillsetProfileLoader();
  }
}

class SkillsetProfileAccessException implements Exception {
  const SkillsetProfileAccessException(this.message);

  final String message;

  @override
  String toString() => 'SkillsetProfileAccessException: $message';
}
