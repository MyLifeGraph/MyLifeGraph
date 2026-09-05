import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/capabilities/app_surface_capabilities.dart';
import '../features/optimization/data/datasources/optimization_mock_data_source.dart';
import '../features/optimization/domain/entities/skillset_profile.dart';

final optimizationMockDataSourceProvider = Provider<OptimizationMockDataSource>(
  (_) => const OptimizationMockDataSource(),
);

final skillsetProfileProvider = FutureProvider<SkillsetProfile>((ref) {
  if (!ref.watch(appSurfaceCapabilitiesProvider).isLocalDemo) {
    throw const SkillsetProfileUnavailableException(
      'Skillset examples require local demo mode.',
    );
  }
  return ref.watch(optimizationMockDataSourceProvider).getSkillsetProfile();
});
