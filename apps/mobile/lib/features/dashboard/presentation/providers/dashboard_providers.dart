import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../quick_action/presentation/providers/quick_check_in_providers.dart';
import '../../data/datasources/dashboard_mock_data_source.dart';
import '../../data/datasources/dashboard_supabase_data_source.dart';
import '../../data/repositories/dashboard_repository_impl.dart';
import '../../domain/entities/dashboard_snapshot.dart';
import '../../domain/repositories/dashboard_repository.dart';

final dashboardMockDataSourceProvider = Provider<DashboardMockDataSource>(
  (ref) => DashboardMockDataSource(
    quickCheckInStore: ref.watch(quickCheckInStoreProvider),
  ),
);

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    final allowMockData = ref.watch(appSurfaceCapabilitiesProvider).isLocalDemo;
    return DashboardRepositoryImpl(
      mockDataSource: ref.watch(dashboardMockDataSourceProvider),
      supabaseDataSource:
          client == null ? null : DashboardSupabaseDataSource(client),
      allowMockData: allowMockData,
    );
  },
);

final dashboardSnapshotProvider = FutureProvider<DashboardSnapshot>(
  (ref) => ref.watch(dashboardRepositoryProvider).getSnapshot(),
);
