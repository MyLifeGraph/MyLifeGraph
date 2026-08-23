import '../../../core/network/api_client.dart';
import '../domain/weekly_review.dart';

class WeeklyReviewApiDataSource {
  const WeeklyReviewApiDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<WeeklyReviewFeed> getLatest({required String accessToken}) async {
    final json = await _apiClient.getJson(
      '/v1/weekly-reviews/latest',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return WeeklyReviewFeed.fromJson(json);
  }

  Future<WeeklyReviewFeed> generate({
    required String accessToken,
    required String periodKey,
    required bool force,
  }) async {
    final json = await _apiClient.postJson(
      '/v1/weekly-reviews/generate',
      body: {'period_key': periodKey, 'force': force},
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return WeeklyReviewFeed.fromJson(json);
  }
}
