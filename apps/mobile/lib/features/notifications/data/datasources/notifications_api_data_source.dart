import '../../../../core/network/api_client.dart';
import '../../domain/entities/notification_lifecycle.dart';

class NotificationsApiDataSource {
  const NotificationsApiDataSource(this._client);

  final ApiClient _client;

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
}
