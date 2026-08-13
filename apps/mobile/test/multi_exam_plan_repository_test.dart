import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/deadline_plans/data/multi_exam_plan_api_data_source.dart';
import 'package:my_life_graph/features/deadline_plans/data/multi_exam_plan_repository_impl.dart';
import 'package:my_life_graph/features/deadline_plans/domain/multi_exam_plan.dart';

import 'support/multi_exam_plan_fixtures.dart';

void main() {
  test('all five routes use Bearer and exact strict request bodies', () async {
    final client = _TrackingApiClient(
      getResponses: {
        '/v1/deadline-plans/exam-balances': multiExamFeedEnvelope(),
        '/v1/deadline-plans/exam-balances/$multiExamBalanceId':
            multiExamBatchEnvelope(),
      },
      postResponses: {
        '/v1/deadline-plans/exam-balances/proposals':
            multiExamProposalEnvelope(),
        '/v1/deadline-plans/exam-balances/$multiExamBalanceId/confirm':
            multiExamBatchEnvelope(status: 'confirmed'),
        '/v1/deadline-plans/exam-balances/$multiExamBalanceId/cancel':
            multiExamBatchEnvelope(status: 'cancelled'),
      },
    );
    final repository = _repository(client);

    await repository.getBalances();
    await repository.getBalance(multiExamBalanceId);
    await repository.propose(
      requestId: multiExamRequestId,
      draft: const MultiExamPlanProposalDraft(
        targetPlanId: multiExamTargetId,
        expectedPlanRevision: 1,
      ),
    );
    await repository.confirm(
      balanceId: multiExamBalanceId,
      requestId: multiExamRequestId,
      expectedRevision: 1,
    );
    await repository.cancel(
      balanceId: multiExamBalanceId,
      requestId: multiExamRequestId,
      expectedRevision: 1,
    );

    expect(client.getCalls, [
      '/v1/deadline-plans/exam-balances',
      '/v1/deadline-plans/exam-balances/$multiExamBalanceId',
    ]);
    expect(client.postCalls, [
      '/v1/deadline-plans/exam-balances/proposals',
      '/v1/deadline-plans/exam-balances/$multiExamBalanceId/confirm',
      '/v1/deadline-plans/exam-balances/$multiExamBalanceId/cancel',
    ]);
    expect(
      client.bodyByPath['/v1/deadline-plans/exam-balances/proposals'],
      {
        'contract_version': 'multi-exam-plan-v1',
        'request_id': multiExamRequestId,
        'target_plan_id': multiExamTargetId,
        'expected_plan_revision': 1,
      },
    );
    for (final path in client.getCalls.followedBy(client.postCalls)) {
      expect(client.headersByPath[path], {
        'Authorization': 'Bearer account-token',
      });
    }
  });

  test('guest/mock capability and missing token make zero product calls',
      () async {
    final client = _TrackingApiClient(throwOnRequest: true);

    await expectLater(
      _repository(client, canUseSyncedPlanner: false).getBalances(),
      throwsA(isA<MultiExamPlanAccessException>()),
    );
    await expectLater(
      _repository(client, token: ' ').getBalance(multiExamBalanceId),
      throwsA(isA<MultiExamPlanAccessException>()),
    );
    expect(client.totalCalls, 0);
  });

  test('client validates ids and expected revision before network', () async {
    final client = _TrackingApiClient(throwOnRequest: true);
    final repository = _repository(client);

    await expectLater(
      repository.getBalance('not-a-uuid'),
      throwsA(isA<MultiExamPlanContractException>()),
    );
    await expectLater(
      repository.propose(
        requestId: multiExamRequestId,
        draft: const MultiExamPlanProposalDraft(
          targetPlanId: multiExamTargetId,
          expectedPlanRevision: 0,
        ),
      ),
      throwsA(isA<MultiExamPlanContractException>()),
    );
    expect(client.totalCalls, 0);
  });

  test('detail and lifecycle responses must match path, revision, and status',
      () async {
    final wrongDetail = multiExamBatchEnvelope();
    final wrongDetailBalance = wrongDetail['balance'] as Map<String, dynamic>;
    const otherId = '92000000-0000-4000-8000-000000000009';
    wrongDetailBalance['id'] = otherId;
    for (final link in wrongDetailBalance['child_links'] as List) {
      (link as Map<String, dynamic>)['balance_id'] = otherId;
    }
    final client = _TrackingApiClient(
      getResponses: {
        '/v1/deadline-plans/exam-balances/$multiExamBalanceId': wrongDetail,
      },
      postResponses: {
        '/v1/deadline-plans/exam-balances/$multiExamBalanceId/confirm':
            multiExamBatchEnvelope(status: 'cancelled'),
      },
    );
    final repository = _repository(client);

    await expectLater(
      repository.getBalance(multiExamBalanceId),
      throwsA(isA<MultiExamPlanContractException>()),
    );
    await expectLater(
      repository.confirm(
        balanceId: multiExamBalanceId,
        requestId: multiExamRequestId,
        expectedRevision: 1,
      ),
      throwsA(isA<MultiExamPlanContractException>()),
    );
  });

  test('all proposal outcomes remain bound to the selected target', () async {
    final mismatch = multiExamProposalEnvelope();
    final balance = mismatch['balance'] as Map<String, dynamic>;
    balance['target_plan_id'] = multiExamOtherId;
    final client = _TrackingApiClient(
      postResponses: {
        '/v1/deadline-plans/exam-balances/proposals': mismatch,
      },
    );

    await expectLater(
      _repository(client).propose(
        requestId: multiExamRequestId,
        draft: const MultiExamPlanProposalDraft(
          targetPlanId: multiExamTargetId,
          expectedPlanRevision: 1,
        ),
      ),
      throwsA(isA<MultiExamPlanContractException>()),
    );
  });
}

MultiExamPlanRepositoryImpl _repository(
  _TrackingApiClient client, {
  bool canUseSyncedPlanner = true,
  String? token = ' account-token ',
}) =>
    MultiExamPlanRepositoryImpl(
      apiDataSource: MultiExamPlanApiDataSource(client),
      accessTokenProvider: () => token,
      canUseSyncedPlanner: canUseSyncedPlanner,
    );

class _TrackingApiClient extends ApiClient {
  _TrackingApiClient({
    this.getResponses = const {},
    this.postResponses = const {},
    this.throwOnRequest = false,
  }) : super(Dio());

  final Map<String, Map<String, dynamic>> getResponses;
  final Map<String, Map<String, dynamic>> postResponses;
  final bool throwOnRequest;
  final List<String> getCalls = [];
  final List<String> postCalls = [];
  final Map<String, Map<String, dynamic>?> bodyByPath = {};
  final Map<String, Map<String, String>?> headersByPath = {};

  int get totalCalls => getCalls.length + postCalls.length;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    if (throwOnRequest) throw StateError('Network must not be used.');
    getCalls.add(path);
    headersByPath[path] = headers;
    return getResponses[path] ?? (throw StateError('Missing GET $path'));
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    if (throwOnRequest) throw StateError('Network must not be used.');
    postCalls.add(path);
    bodyByPath[path] = body;
    headersByPath[path] = headers;
    return postResponses[path] ?? (throw StateError('Missing POST $path'));
  }
}
