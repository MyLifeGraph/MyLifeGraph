import '../../../core/network/api_client.dart';
import '../domain/planner.dart';

class PlannerApiDataSource {
  const PlannerApiDataSource(this._client);

  final ApiClient _client;

  Future<PlannerOverview> getOverview({required String accessToken}) async {
    final json = await _client.getJson(
      '/v1/planner/overview',
      headers: _headers(accessToken),
    );
    return PlannerOverview.fromJson(json);
  }

  Future<PlannerPreferences> getPreferences({
    required String accessToken,
  }) async {
    final json = await _client.getJson(
      '/v1/planner/preferences',
      headers: _headers(accessToken),
    );
    return PlannerPreferences.fromJson(json);
  }

  Future<PlannerPreferences> updatePreferences({
    required String accessToken,
    required String requestId,
    required DateTime? expectedUpdatedAt,
    required bool useCalendarBusyTime,
  }) async {
    final json = await _client.patchJson(
      '/v1/planner/preferences',
      headers: _headers(accessToken),
      body: {
        'request_id': requestId,
        'expected_updated_at': expectedUpdatedAt?.toUtc().toIso8601String(),
        'use_calendar_busy_time': useCalendarBusyTime,
      },
    );
    return PlannerPreferences.fromJson(json);
  }

  Future<PlannerActionPlan> propose({
    required String accessToken,
    required Map<String, dynamic> body,
  }) async {
    final json = await _client.postJson(
      '/v1/planner/action-plans/proposals',
      headers: _headers(accessToken),
      body: body,
    );
    return plannerActionPlanFromResponse(json);
  }

  Future<PlannerActionPlan> mutatePlan({
    required String accessToken,
    required String planId,
    required String operation,
    required String requestId,
    required int expectedRevision,
  }) async {
    final json = await _client.postJson(
      '/v1/planner/action-plans/$planId/$operation',
      headers: _headers(accessToken),
      body: {
        'request_id': requestId,
        'expected_revision': expectedRevision,
      },
    );
    return plannerActionPlanFromResponse(json);
  }

  Future<PlannerCommitment> createCommitment({
    required String accessToken,
    required Map<String, dynamic> body,
  }) async {
    final json = await _client.postJson(
      '/v1/planner/commitments',
      headers: _headers(accessToken),
      body: body,
    );
    return plannerCommitmentFromResponse(json);
  }

  Future<PlannerCommitment> updateCommitment({
    required String accessToken,
    required String commitmentId,
    required Map<String, dynamic> body,
  }) async {
    final json = await _client.patchJson(
      '/v1/planner/commitments/$commitmentId',
      headers: _headers(accessToken),
      body: body,
    );
    return plannerCommitmentFromResponse(json);
  }

  Future<PlannerCommitment> archiveCommitment({
    required String accessToken,
    required String commitmentId,
    required String requestId,
    required DateTime expectedUpdatedAt,
  }) async {
    final json = await _client.postJson(
      '/v1/planner/commitments/$commitmentId/archive',
      headers: _headers(accessToken),
      body: {
        'request_id': requestId,
        'expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
      },
    );
    return plannerCommitmentFromResponse(json);
  }

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
      };
}
