import '../../../core/network/api_client.dart';
import '../domain/multi_exam_plan.dart';

class MultiExamPlanApiDataSource {
  const MultiExamPlanApiDataSource(this._client);

  final ApiClient _client;

  Future<MultiExamPlanFeed> getBalances({required String accessToken}) async {
    final json = await _client.getJson(
      '/v1/deadline-plans/exam-balances',
      headers: _headers(accessToken),
    );
    return MultiExamPlanFeed.fromJson(json);
  }

  Future<MultiExamPlanBatch> getBalance({
    required String accessToken,
    required String balanceId,
  }) async {
    final json = await _client.getJson(
      '/v1/deadline-plans/exam-balances/$balanceId',
      headers: _headers(accessToken),
    );
    final balance = MultiExamPlanBatchResponse.fromJson(json).balance;
    if (balance.id != balanceId) {
      throw const MultiExamPlanContractException(
        'Exam balance response does not match the requested path.',
      );
    }
    return balance;
  }

  Future<MultiExamPlanProposalResult> propose({
    required String accessToken,
    required String requestId,
    required MultiExamPlanProposalDraft draft,
  }) async {
    final json = await _client.postJson(
      '/v1/deadline-plans/exam-balances/proposals',
      headers: _headers(accessToken),
      body: draft.toJson(requestId: requestId),
    );
    final result = MultiExamPlanProposalResult.fromJson(json);
    final targetMatches = switch (result) {
      MultiExamPlanNoChange(:final targetPlanId) =>
        targetPlanId == draft.targetPlanId,
      MultiExamPlanSingle(:final plan) => plan.id == draft.targetPlanId,
      MultiExamPlanBatchProposal(:final balance) =>
        balance.targetPlanId == draft.targetPlanId,
    };
    if (!targetMatches) {
      throw const MultiExamPlanContractException(
        'Exam balance proposal does not match the selected Exam.',
      );
    }
    return result;
  }

  Future<MultiExamPlanBatch> mutate({
    required String accessToken,
    required String balanceId,
    required String operation,
    required String requestId,
    required int expectedRevision,
  }) async {
    final json = await _client.postJson(
      '/v1/deadline-plans/exam-balances/$balanceId/$operation',
      headers: _headers(accessToken),
      body: {
        'contract_version': multiExamPlanContractVersion,
        'request_id': requestId,
        'expected_revision': expectedRevision,
      },
    );
    final balance = MultiExamPlanBatchResponse.fromJson(json).balance;
    final expectedStatus = operation == 'confirm'
        ? MultiExamPlanStatus.confirmed
        : MultiExamPlanStatus.cancelled;
    if (balance.id != balanceId ||
        balance.revision != expectedRevision ||
        balance.status != expectedStatus) {
      throw const MultiExamPlanContractException(
        'Exam balance mutation response is inconsistent.',
      );
    }
    return balance;
  }

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
      };
}
