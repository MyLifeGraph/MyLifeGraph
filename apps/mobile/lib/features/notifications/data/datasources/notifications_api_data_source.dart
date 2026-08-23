import '../../../../core/network/api_client.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/entities/notification_delivery.dart';
import '../../domain/entities/notification_lifecycle.dart';

class NotificationsApiDataSource {
  const NotificationsApiDataSource(this._client);

  final ApiClient _client;

  Future<NotificationSettings> getSettings({
    required String accessToken,
  }) async {
    final json = await _client.getJson(
      '/v1/notifications/settings',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return NotificationSettings.fromJson(json);
  }

  Future<NotificationSettings> updateSettings({
    required String accessToken,
    required NotificationSettingsUpdate request,
  }) async {
    final json = await _client.patchJson(
      '/v1/notifications/settings',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: request.toJson(),
    );
    return NotificationSettings.fromJson(json);
  }

  Future<NotificationLifecycleResult> performAction({
    required String accessToken,
    required NotificationLifecycleRequest request,
  }) async {
    final json = await _client.postJson(
      '/v1/notifications/${request.notificationId}/actions',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: request.toJson(),
    );
    return NotificationLifecycleResult.fromJson(json);
  }

  Future<NotificationDeliveryReceipt> acknowledgeDelivery({
    required String accessToken,
    required AppNotification notification,
  }) async {
    final json = await _client.postJson(
      '/v1/notifications/${notification.id}/delivery',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: const {
        'contract_version': notificationDeliveryContractVersion,
      },
    );
    final result = NotificationDeliveryReceipt.fromJson(json);
    result.requireMatches(notification);
    return result;
  }
}
