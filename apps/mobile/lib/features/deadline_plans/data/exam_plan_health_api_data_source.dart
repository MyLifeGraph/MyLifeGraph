import '../../../core/network/api_client.dart';
import '../domain/exam_plan_health.dart';

class ExamPlanHealthApiDataSource {
  const ExamPlanHealthApiDataSource(this._client);

  final ApiClient _client;

  Future<ExamPlanHealth> getHealth({required String accessToken}) async {
    final json = await _client.getJson(
      '/v1/deadline-plans/exam-plan-health',
      headers: _headers(accessToken),
    );
    return ExamPlanHealth.fromJson(json);
  }

  Future<ExamPlanHealthPreview> preview({
    required String accessToken,
    required ExamPlanHealthPreviewDraft draft,
  }) async {
    final json = await _client.postJson(
      '/v1/deadline-plans/exam-plan-health/preview',
      headers: _headers(accessToken),
      body: draft.toJson(),
    );
    return ExamPlanHealthPreview.fromJson(json);
  }

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
      };
}
