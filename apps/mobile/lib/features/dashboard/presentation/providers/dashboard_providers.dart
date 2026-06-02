import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../data/datasources/dashboard_mock_data_source.dart';
import '../../data/datasources/dashboard_supabase_data_source.dart';
import '../../data/repositories/dashboard_repository_impl.dart';
import '../../domain/entities/dashboard_snapshot.dart';
import '../../domain/repositories/dashboard_repository.dart';

final dashboardMockDataSourceProvider = Provider<DashboardMockDataSource>(
  (_) => const DashboardMockDataSource(),
);

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    final config = ref.watch(appConfigProvider);
    return DashboardRepositoryImpl(
      mockDataSource: ref.watch(dashboardMockDataSourceProvider),
      supabaseDataSource:
          client == null ? null : DashboardSupabaseDataSource(client),
      useMockData: config.useMockData,
    );
  },
);

final dashboardSnapshotProvider = FutureProvider<DashboardSnapshot>(
  (ref) => ref.watch(dashboardRepositoryProvider).getSnapshot(),
);
