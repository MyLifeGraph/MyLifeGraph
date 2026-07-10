import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../data/datasources/notifications_mock_data_source.dart';
import '../../data/datasources/notifications_supabase_data_source.dart';
import '../../data/repositories/notifications_repository_impl.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notifications_repository.dart';

final notificationsMockDataSourceProvider =
    Provider<NotificationsMockDataSource>(
  (_) => const NotificationsMockDataSource(),
);

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    return NotificationsRepositoryImpl(
      mockDataSource: ref.watch(notificationsMockDataSourceProvider),
      supabaseDataSource:
          client == null ? null : NotificationsSupabaseDataSource(client),
      allowMockData: ref.watch(appSurfaceCapabilitiesProvider).isLocalDemo,
    );
  },
);

final notificationsProvider = FutureProvider<List<AppNotification>>(
  (ref) => ref.watch(notificationsRepositoryProvider).getNotifications(),
);
