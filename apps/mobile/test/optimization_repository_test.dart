import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/features/optimization/data/datasources/optimization_mock_data_source.dart';
import 'package:my_life_graph/features/optimization/data/repositories/optimization_repository_impl.dart';
import 'package:my_life_graph/features/optimization/domain/entities/skillset_profile.dart';

void main() {
  group('OptimizationRepositoryImpl skillset profile', () {
    test('mock mode remains local and does not invoke the real loader',
        () async {
      var realLoads = 0;
      final repository = OptimizationRepositoryImpl(
        config: _config(useMockData: true, supabaseConfigured: true),
        mockDataSource: const OptimizationMockDataSource(),
        skillsetProfileLoader: () async {
          realLoads += 1;
          return _realProfile;
        },
        allowDemoData: false,
      );

      final profile = await repository.getSkillsetProfile();

      expect(profile.userName, 'Alex');
      expect(realLoads, 0);
    });

    test('guest mode remains local even with configured Supabase', () async {
      var realLoads = 0;
      final repository = OptimizationRepositoryImpl(
        config: _config(useMockData: false, supabaseConfigured: true),
        mockDataSource: const OptimizationMockDataSource(),
        skillsetProfileLoader: () async {
          realLoads += 1;
          return _realProfile;
        },
        allowDemoData: true,
      );

      final profile = await repository.getSkillsetProfile();

      expect(profile.userName, 'Alex');
      expect(realLoads, 0);
    });

    test('authenticated mode uses the retained skillset loader', () async {
      var realLoads = 0;
      final repository = OptimizationRepositoryImpl(
        config: _config(useMockData: false, supabaseConfigured: true),
        mockDataSource: const OptimizationMockDataSource(),
        skillsetProfileLoader: () async {
          realLoads += 1;
          return _realProfile;
        },
        allowDemoData: false,
      );

      final profile = await repository.getSkillsetProfile();

      expect(profile, same(_realProfile));
      expect(realLoads, 1);
    });

    test('authenticated mode fails closed without its Supabase seam', () async {
      final repository = OptimizationRepositoryImpl(
        config: _config(useMockData: false, supabaseConfigured: true),
        mockDataSource: const OptimizationMockDataSource(),
        allowDemoData: false,
      );

      await expectLater(
        repository.getSkillsetProfile(),
        throwsA(isA<SkillsetProfileAccessException>()),
      );
    });
  });
}

AppConfig _config({
  required bool useMockData,
  bool supabaseConfigured = false,
}) {
  return AppConfig(
    environment: 'test',
    supabaseUrl: supabaseConfigured ? 'http://127.0.0.1:54321' : '',
    supabaseAnonKey: supabaseConfigured ? 'anon-key' : '',
    aiServiceBaseUrl: 'http://localhost:8000',
    useMockData: useMockData,
  );
}

final _realProfile = SkillsetProfile(
  userName: 'Real profile',
  overallScore: 90,
  primaryArchetype: 'Focused Builder',
  updatedAt: DateTime.utc(2026, 8, 13),
  scores: const [],
);
