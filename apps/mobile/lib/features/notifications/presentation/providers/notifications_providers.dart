import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../application/notification_delivery_controller.dart';
import '../../application/notifications_controller.dart';
import '../../data/datasources/notifications_api_data_source.dart';
import '../../data/datasources/notifications_mock_data_source.dart';
import '../../data/datasources/notifications_supabase_data_source.dart';
import '../../data/repositories/notifications_repository_impl.dart';
import '../../domain/repositories/notification_delivery_repository.dart';
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

final notificationDeliveryRepositoryProvider =
    Provider<NotificationDeliveryRepository>(
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

final notificationSettingsProvider = StateNotifierProvider.autoDispose<
    NotificationSettingsController, NotificationSettingsState>(
  (ref) => NotificationSettingsController(
    repository: ref.watch(notificationDeliveryRepositoryProvider),
  ),
);

final inAppNotificationDeliveryProvider = StateNotifierProvider.autoDispose<
    InAppNotificationDeliveryController, InAppNotificationDeliveryState>(
  (ref) {
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    return InAppNotificationDeliveryController(
      repository: ref.watch(notificationDeliveryRepositoryProvider),
      enabled: !capabilities.isLocalDemo && capabilities.canUseSyncedExecution,
    );
  },
);

final notificationsProvider = StateNotifierProvider.autoDispose<
    NotificationsController, NotificationsState>(
  (ref) {
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    return NotificationsController(
      repository: ref.watch(notificationsRepositoryProvider),
      canManageLifecycle: !capabilities.isLocalDemo,
    );
  },
);
