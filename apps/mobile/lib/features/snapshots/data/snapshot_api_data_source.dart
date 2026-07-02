import '../../../core/network/api_client.dart';

class SnapshotApiDataSource {
  const SnapshotApiDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<void> generateDailySnapshot({
    required String accessToken,
    int windowDays = 7,
  }) async {
    await _apiClient.postJson(
      '/v1/snapshots/generate',
      body: {
        'scope': 'daily',
        'window_days': windowDays,
      },
      headers: {'Authorization': 'Bearer $accessToken'},
    );
  }
}
