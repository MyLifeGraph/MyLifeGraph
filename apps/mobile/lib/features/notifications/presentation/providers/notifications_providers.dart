import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../application/notifications_controller.dart';
import '../../data/datasources/notifications_api_data_source.dart';
import '../../data/datasources/notifications_mock_data_source.dart';
import '../../data/datasources/notifications_supabase_data_source.dart';
import '../../data/repositories/notifications_repository_impl.dart';
import '../../domain/repositories/notifications_repository.dart';

final notificationsMockDataSourceProvider =
    Provider<NotificationsMockDataSource>(
  (_) => const NotificationsMockDataSource(),
);

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    return NotificationsRepositoryImpl(
      mockDataSource: ref.watch(notificationsMockDataSourceProvider),
      supabaseDataSource:
          client == null ? null : NotificationsSupabaseDataSource(client),
      apiDataSource: NotificationsApiDataSource(ref.watch(apiClientProvider)),
      accessTokenProvider: () async => client?.auth.currentSession?.accessToken,
      allowMockData: capabilities.isLocalDemo,
    );
  },
);

final notificationsProvider =
    StateNotifierProvider<NotificationsController, NotificationsState>(
  (ref) {
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    return NotificationsController(
      repository: ref.watch(notificationsRepositoryProvider),
      canManageLifecycle: !capabilities.isLocalDemo,
    );
  },
);
