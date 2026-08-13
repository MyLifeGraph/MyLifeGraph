import 'dart:async';

import '../../../core/utils/client_uuid.dart';
import '../domain/multi_exam_plan.dart';
import '../domain/multi_exam_plan_repository.dart';
import 'multi_exam_plan_api_data_source.dart';

typedef MultiExamPlanAccessTokenProvider = FutureOr<String?> Function();

class MultiExamPlanRepositoryImpl implements MultiExamPlanRepository {
  const MultiExamPlanRepositoryImpl({
    required MultiExamPlanApiDataSource apiDataSource,
    required MultiExamPlanAccessTokenProvider accessTokenProvider,
    required bool canUseSyncedPlanner,
  })  : _api = apiDataSource,
        _accessTokenProvider = accessTokenProvider,
        _canUseSyncedPlanner = canUseSyncedPlanner;

  final MultiExamPlanApiDataSource _api;
  final MultiExamPlanAccessTokenProvider _accessTokenProvider;
  final bool _canUseSyncedPlanner;

  @override
  Future<MultiExamPlanFeed> getBalances() async {
    _requireRemote();
    return _api.getBalances(accessToken: await _requireToken());
  }

  @override
  Future<MultiExamPlanBatch> getBalance(String balanceId) async {
    _requireUuid(balanceId, 'Exam balance id');
    _requireRemote();
    return _api.getBalance(
      accessToken: await _requireToken(),
      balanceId: balanceId,
    );
  }

  @override
  Future<MultiExamPlanProposalResult> propose({
    required String requestId,
    required MultiExamPlanProposalDraft draft,
  }) async {
    _requireRequestId(requestId);
    _requireUuid(draft.targetPlanId, 'Selected Exam plan id');
    if (draft.expectedPlanRevision < 1 || draft.expectedPlanRevision > 199) {
      throw const MultiExamPlanContractException(
        'Selected Exam revision is invalid.',
      );
    }
    _requireRemote();
    return _api.propose(
      accessToken: await _requireToken(),
      requestId: requestId,
      draft: draft,
    );
  }

  @override
  Future<MultiExamPlanBatch> confirm({
    required String balanceId,
    required String requestId,
    required int expectedRevision,
  }) =>
      _mutate(
        balanceId: balanceId,
        requestId: requestId,
        expectedRevision: expectedRevision,
        operation: 'confirm',
      );

  @override
  Future<MultiExamPlanBatch> cancel({
    required String balanceId,
    required String requestId,
    required int expectedRevision,
  }) =>
      _mutate(
        balanceId: balanceId,
        requestId: requestId,
        expectedRevision: expectedRevision,
        operation: 'cancel',
      );

  Future<MultiExamPlanBatch> _mutate({
    required String balanceId,
    required String requestId,
    required int expectedRevision,
    required String operation,
  }) async {
    _requireUuid(balanceId, 'Exam balance id');
    _requireRequestId(requestId);
    if (expectedRevision < 1 || expectedRevision > 200) {
      throw const MultiExamPlanContractException(
        'Exam balance revision is invalid.',
      );
    }
    _requireRemote();
    return _api.mutate(
      accessToken: await _requireToken(),
      balanceId: balanceId,
      operation: operation,
      requestId: requestId,
      expectedRevision: expectedRevision,
    );
  }

  void _requireRemote() {
    if (!_canUseSyncedPlanner) {
      throw const MultiExamPlanAccessException(
        'Exam balancing requires a signed-in synced account.',
      );
    }
  }

  Future<String> _requireToken() async {
    final token = await _accessTokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw const MultiExamPlanAccessException(
        'Exam balancing requires an authenticated session.',
      );
    }
    return token.trim();
  }

  void _requireRequestId(String value) {
    if (!isClientUuid(value)) {
      throw const MultiExamPlanContractException(
        'Exam balance request id must be a UUIDv4.',
      );
    }
  }

  void _requireUuid(String value, String label) {
    if (!isCanonicalUuid(value)) {
      throw MultiExamPlanContractException('$label is invalid.');
    }
  }
}
