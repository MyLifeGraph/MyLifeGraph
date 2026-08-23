import 'dart:async';

import '../../../core/config/app_config.dart';
import '../../../core/utils/client_uuid.dart';
import '../domain/deadline_plan.dart';
import '../domain/deadline_plan_repository.dart';
import 'deadline_plan_api_data_source.dart';

typedef DeadlinePlanAccessTokenProvider = FutureOr<String?> Function();

class DeadlinePlanRepositoryImpl implements DeadlinePlanRepository {
  const DeadlinePlanRepositoryImpl({
    required AppConfig config,
    required DeadlinePlanApiDataSource apiDataSource,
    required DeadlinePlanAccessTokenProvider accessTokenProvider,
    required bool canUseSyncedPlanner,
  })  : _config = config,
        _api = apiDataSource,
        _accessTokenProvider = accessTokenProvider,
        _canUseSyncedPlanner = canUseSyncedPlanner;

  final AppConfig _config;
  final DeadlinePlanApiDataSource _api;
  final DeadlinePlanAccessTokenProvider _accessTokenProvider;
  final bool _canUseSyncedPlanner;

  @override
  Future<DeadlinePlanFeed> getPlans() async {
    _requireRemote();
    return _api.getPlans(accessToken: await _requireToken());
  }

  @override
  Future<PreparationWorkload> getWorkload() async {
    _requireRemote();
    return _api.getWorkload(accessToken: await _requireToken());
  }

  @override
  Future<PreparationWorkloadDetail> getWorkloadDetail(String localDate) async {
    if (!isDeadlinePlanDate(localDate)) {
      throw const DeadlinePlanAccessException(
        'Preparation workload date is invalid.',
      );
    }
    _requireRemote();
    final detail = await _api.getWorkloadDetail(
      accessToken: await _requireToken(),
      localDate: localDate,
    );
    if (detail.localDateKey != localDate) {
      throw const DeadlinePlanContractException(
        'Preparation workload detail date does not match the request.',
      );
    }
    return detail;
  }

  @override
  Future<DeadlinePlan> getPlan(String planId) async {
    _requirePlanId(planId);
    _requireRemote();
    return _api.getPlan(
      accessToken: await _requireToken(),
      planId: planId,
    );
  }

  @override
  Future<DeadlinePlan> propose({
    required String requestId,
    required DeadlinePlanProposalDraft draft,
  }) async {
    _requireRequestId(requestId);
    draft.validate();
    _requireRemote();
    final result = await _api.propose(
      accessToken: await _requireToken(),
      requestId: requestId,
      draft: draft,
    );
    if (result.id != draft.planId ||
        result.latestRevision <= draft.baseRevision) {
      throw const DeadlinePlanContractException(
        'Preparation proposal response is incomplete.',
      );
    }
    return result;
  }

  @override
  Future<DeadlinePlan> confirm({
    required String planId,
    required String requestId,
    required int expectedRevision,
  }) {
    return _mutate(
      planId: planId,
      requestId: requestId,
      expectedRevision: expectedRevision,
      operation: 'confirm',
      expectedStatuses: const {
        DeadlinePlanStatus.active,
        DeadlinePlanStatus.completed,
        DeadlinePlanStatus.cancelled,
      },
    );
  }

  @override
  Future<DeadlinePlan> complete({
    required String planId,
    required String requestId,
    required int expectedRevision,
  }) {
    return _mutate(
      planId: planId,
      requestId: requestId,
      expectedRevision: expectedRevision,
      operation: 'complete',
      expectedStatuses: const {DeadlinePlanStatus.completed},
    );
  }

  @override
  Future<DeadlinePlan> cancel({
    required String planId,
    required String requestId,
    required int expectedRevision,
  }) {
    return _mutate(
      planId: planId,
      requestId: requestId,
      expectedRevision: expectedRevision,
      operation: 'cancel',
      expectedStatuses: const {DeadlinePlanStatus.cancelled},
    );
  }

  Future<DeadlinePlan> _mutate({
    required String planId,
    required String requestId,
    required int expectedRevision,
    required String operation,
    required Set<DeadlinePlanStatus> expectedStatuses,
  }) async {
    _requirePlanId(planId);
    _requireRequestId(requestId);
    if (expectedRevision < 1) {
      throw const DeadlinePlanAccessException(
        'Preparation plan revision is invalid.',
      );
    }
    _requireRemote();
    final result = await _api.mutate(
      accessToken: await _requireToken(),
      planId: planId,
      operation: operation,
      requestId: requestId,
      expectedRevision: expectedRevision,
    );
    final revisionMatches = switch (operation) {
      'confirm' => result.currentRevision >= expectedRevision &&
          result.taskId == result.id,
      'complete' => result.currentRevision == expectedRevision,
      'cancel' => result.currentRevision == expectedRevision ||
          result.currentRevision == 0 &&
              result.latestRevision >= expectedRevision,
      _ => false,
    };
    if (result.id != planId ||
        !expectedStatuses.contains(result.status) ||
        !revisionMatches) {
      throw const DeadlinePlanContractException(
        'Preparation plan mutation response is invalid.',
      );
    }
    return result;
  }

  void _requireRemote() {
    if (!_canUseSyncedPlanner) {
      throw const DeadlinePlanAccessException(
        'Preparation plans require an authenticated synced account.',
      );
    }
    if (!_config.isSupabaseConfigured) {
      throw const DeadlinePlanAccessException(
        'Preparation plans require Supabase configuration.',
      );
    }
  }

  Future<String> _requireToken() async {
    final token = await _accessTokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw const DeadlinePlanAccessException(
        'Preparation plans require an authenticated session.',
      );
    }
    return token.trim();
  }

  void _requireRequestId(String value) {
    if (!isClientUuid(value)) {
      throw const DeadlinePlanAccessException(
        'Preparation plan request identity is invalid.',
      );
    }
  }

  void _requirePlanId(String value) {
    if (!isDeadlinePlanUuid(value)) {
      throw const DeadlinePlanAccessException(
        'Preparation plan identity is invalid.',
      );
    }
  }
}
