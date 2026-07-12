import '../../../core/network/api_client.dart';
import '../domain/daily_briefing.dart';

class BriefingApiDataSource {
  const BriefingApiDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<BriefingFeed> getToday({required String accessToken}) async {
    final json = await _apiClient.getJson(
      '/v1/briefings/today',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return BriefingFeed.fromJson(json);
  }

  Future<BriefingFeed> generateToday({
    required String accessToken,
    required bool force,
  }) async {
    final json = await _apiClient.postJson(
      '/v1/briefings/generate',
      body: {'force': force},
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return BriefingFeed.fromJson(json);
  }
}
