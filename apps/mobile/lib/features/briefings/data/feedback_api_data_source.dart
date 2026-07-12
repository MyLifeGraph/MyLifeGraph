import '../../../core/network/api_client.dart';
import '../domain/decision_feedback.dart';

class FeedbackApiDataSource {
  const FeedbackApiDataSource(this._client);
  final ApiClient _client;

  Future<DecisionFeedback> create({
    required String accessToken,
    required String requestId,
    required String briefingId,
    required String actionId,
    required DecisionFeedbackType feedbackType,
  }) async {
    final json = await _client.postJson(
      '/v1/feedback',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: {
        'request_id': requestId,
        'briefing_id': briefingId,
        'action_id': actionId,
        'feedback_type': feedbackType.code,
      },
    );
    _validateEnvelope(json, expectedKey: 'feedback');
    return DecisionFeedback.fromJson(
      Map<String, dynamic>.from(json['feedback'] as Map),
    );
  }

  Future<List<DecisionFeedback>> listRecent({
    required String accessToken,
  }) async {
    final json = await _client.getJson(
      '/v1/feedback',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    _validateEnvelope(json, expectedKey: 'feedback');
    final rows = json['feedback'];
    if (rows is! List || rows.length > 200) {
      throw const DecisionFeedbackException('Feedback list is invalid.');
    }
    return rows
        .map(
          (row) => DecisionFeedback.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<void> delete({
    required String accessToken,
    required String feedbackId,
  }) async {
    final json = await _client.deleteJson(
      '/v1/feedback/$feedbackId',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (json.keys
            .toSet()
            .difference({'contract_version', 'deleted_id'}).isNotEmpty ||
        json.length != 2 ||
        json['contract_version'] != decisionFeedbackContractVersion ||
        json['deleted_id'] != feedbackId) {
      throw const DecisionFeedbackException(
        'Feedback delete response is invalid.',
      );
    }
  }

  void _validateEnvelope(
    Map<String, dynamic> json, {
    required String expectedKey,
  }) {
    if (json.keys
            .toSet()
            .difference({'contract_version', expectedKey}).isNotEmpty ||
        json.length != 2 ||
        json['contract_version'] != decisionFeedbackContractVersion) {
      throw const DecisionFeedbackException('Feedback response is invalid.');
    }
  }
}
