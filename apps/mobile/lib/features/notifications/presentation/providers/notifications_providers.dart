import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
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
    final config = ref.watch(appConfigProvider);
    return NotificationsRepositoryImpl(
      mockDataSource: ref.watch(notificationsMockDataSourceProvider),
      supabaseDataSource:
          client == null ? null : NotificationsSupabaseDataSource(client),
      useMockData: config.useMockData,
    );
  },
);

final notificationsProvider = FutureProvider<List<AppNotification>>(
  (ref) => ref.watch(notificationsRepositoryProvider).getNotifications(),
);
