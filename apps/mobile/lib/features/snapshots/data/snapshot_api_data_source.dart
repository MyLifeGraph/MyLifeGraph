import '../../../core/network/api_client.dart';

class SnapshotApiDataSource {
  const SnapshotApiDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<void> generateDailySnapshot({
    required String accessToken,
    int windowDays = 7,
    String? targetDate,
  }) async {
    await _apiClient.postJson(
      '/v1/snapshots/generate',
      body: {
        'scope': 'daily',
        'window_days': windowDays,
        if (targetDate != null) 'target_date': targetDate,
      },
      headers: {'Authorization': 'Bearer $accessToken'},
    );
  }
}
