import '../../../core/network/api_client.dart';
import '../domain/deadline_plan.dart';

class DeadlinePlanApiDataSource {
  const DeadlinePlanApiDataSource(this._client);

  final ApiClient _client;

  Future<DeadlinePlanFeed> getPlans({required String accessToken}) async {
    final json = await _client.getJson(
      '/v1/deadline-plans',
      headers: _headers(accessToken),
    );
    return DeadlinePlanFeed.fromJson(json);
  }

  Future<DeadlinePlan> getPlan({
    required String accessToken,
    required String planId,
  }) async {
    final json = await _client.getJson(
      '/v1/deadline-plans/$planId',
      headers: _headers(accessToken),
    );
    return DeadlinePlanResponse.fromJson(json).plan;
  }

  Future<DeadlinePlan> propose({
    required String accessToken,
    required String requestId,
    required DeadlinePlanProposalDraft draft,
  }) async {
    final json = await _client.postJson(
      '/v1/deadline-plans/proposals',
      headers: _headers(accessToken),
      body: draft.toJson(requestId: requestId),
    );
    return DeadlinePlanResponse.fromJson(json).plan;
  }

  Future<DeadlinePlan> mutate({
    required String accessToken,
    required String planId,
    required String operation,
    required String requestId,
    required int expectedRevision,
  }) async {
    final json = await _client.postJson(
      '/v1/deadline-plans/$planId/$operation',
      headers: _headers(accessToken),
      body: {
        'request_id': requestId,
        'expected_revision': expectedRevision,
      },
    );
    return DeadlinePlanResponse.fromJson(json).plan;
  }

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
      };
}
