import '../../../../core/network/api_client.dart';
import '../../domain/entities/sleep_recommendation.dart';

class SleepRecommendationApiDataSource {
  const SleepRecommendationApiDataSource(this._client);

  final ApiClient _client;

  Future<SleepRecommendation> getSleepRecommendation({
    required String accessToken,
  }) async {
    final json = await _client.getJson(
      '/v1/insights/sleep-recommendation',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return SleepRecommendation.fromJson(json);
  }
}
