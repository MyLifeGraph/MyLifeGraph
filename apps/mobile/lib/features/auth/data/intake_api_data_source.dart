import '../../../core/network/api_client.dart';
import '../domain/intake_response.dart';

class IntakeApiDataSource {
  const IntakeApiDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<IntakeSetupReadState> fetchSetup({
    required String accessToken,
  }) async {
    final response = await _apiClient.getJson(
      '/v1/intake/setup',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return IntakeSetupReadState.fromJson(response);
  }

  Future<IntakeSetupReadState> completeIntake({
    required String accessToken,
    required IntakeSetupSaveRequest request,
  }) async {
    final response = await _apiClient.postJson(
      '/v1/intake/complete',
      body: request.toJson(),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return IntakeSetupReadState.fromJson(response);
  }
}
