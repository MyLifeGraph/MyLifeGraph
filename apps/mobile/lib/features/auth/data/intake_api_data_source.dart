import '../../../core/network/api_client.dart';
import '../domain/intake_response.dart';

class IntakeApiDataSource {
  const IntakeApiDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<void> completeIntake({
    required String accessToken,
    required IntakeResponseDraft intake,
  }) async {
    await _apiClient.postJson(
      '/v1/intake/complete',
      body: intake.toJson(),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
  }
}
