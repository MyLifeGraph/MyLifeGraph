import '../../../core/network/api_client.dart';
import '../domain/assignment_series.dart';

class AssignmentSeriesApiDataSource {
  const AssignmentSeriesApiDataSource(this._client);

  final ApiClient _client;

  Future<AssignmentSeriesFeed> getSeries({required String accessToken}) async {
    final json = await _client.getJson(
      '/v1/deadline-plans/assignment-series',
      headers: _headers(accessToken),
    );
    return AssignmentSeriesFeed.fromJson(json);
  }

  Future<AssignmentSeries> propose({
    required String accessToken,
    required String requestId,
    required AssignmentSeriesProposalDraft draft,
  }) async {
    final json = await _client.postJson(
      '/v1/deadline-plans/assignment-series/proposals',
      headers: _headers(accessToken),
      body: draft.toJson(requestId: requestId),
    );
    return AssignmentSeriesResponse.fromJson(json).series;
  }

  Future<AssignmentSeries> mutate({
    required String accessToken,
    required String seriesId,
    required String operation,
    required String requestId,
    required int expectedRevision,
  }) async {
    final json = await _client.postJson(
      '/v1/deadline-plans/assignment-series/$seriesId/$operation',
      headers: _headers(accessToken),
      body: {
        'contract_version': assignmentSeriesContractVersion,
        'request_id': requestId,
        'expected_revision': expectedRevision,
      },
    );
    return AssignmentSeriesResponse.fromJson(json).series;
  }

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
      };
}
