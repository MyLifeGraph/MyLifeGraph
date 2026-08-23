import 'dart:async';

import '../../../core/config/app_config.dart';
import '../../../core/contracts/strict_contract.dart';
import '../../../core/utils/client_uuid.dart';
import '../domain/assignment_series.dart';
import '../domain/assignment_series_repository.dart';
import 'assignment_series_api_data_source.dart';

typedef AssignmentSeriesAccessTokenProvider = FutureOr<String?> Function();

class AssignmentSeriesRepositoryImpl implements AssignmentSeriesRepository {
  const AssignmentSeriesRepositoryImpl({
    required AppConfig config,
    required AssignmentSeriesApiDataSource apiDataSource,
    required AssignmentSeriesAccessTokenProvider accessTokenProvider,
    required bool canUseSyncedPlanner,
  })  : _config = config,
        _api = apiDataSource,
        _accessTokenProvider = accessTokenProvider,
        _canUseSyncedPlanner = canUseSyncedPlanner;

  final AppConfig _config;
  final AssignmentSeriesApiDataSource _api;
  final AssignmentSeriesAccessTokenProvider _accessTokenProvider;
  final bool _canUseSyncedPlanner;

  @override
  Future<AssignmentSeriesFeed> getSeries() async {
    _requireRemote();
    return _api.getSeries(accessToken: await _requireToken());
  }

  @override
  Future<AssignmentSeries> propose({
    required String requestId,
    required AssignmentSeriesProposalDraft draft,
  }) async {
    _requireRequestId(requestId);
    draft.validate();
    _requireRemote();
    final result = await _api.propose(
      accessToken: await _requireToken(),
      requestId: requestId,
      draft: draft,
    );
    if (result.id != draft.seriesId ||
        result.latestRevision <= draft.baseRevision ||
        result.pendingRevision == null) {
      throw const AssignmentSeriesContractException(
        'Assignment series proposal response is incomplete.',
      );
    }
    return result;
  }

  @override
  Future<AssignmentSeries> confirm({
    required String seriesId,
    required String requestId,
    required int expectedRevision,
  }) =>
      _mutate(
        seriesId: seriesId,
        requestId: requestId,
        expectedRevision: expectedRevision,
        operation: 'confirm',
      );

  @override
  Future<AssignmentSeries> cancelFuture({
    required String seriesId,
    required String requestId,
    required int expectedRevision,
  }) =>
      _mutate(
        seriesId: seriesId,
        requestId: requestId,
        expectedRevision: expectedRevision,
        operation: 'cancel-future',
      );

  Future<AssignmentSeries> _mutate({
    required String seriesId,
    required String requestId,
    required int expectedRevision,
    required String operation,
  }) async {
    if (!isStrictUuid(seriesId, minVersion: 1, maxVersion: 5) ||
        expectedRevision < 1 ||
        expectedRevision > 200) {
      throw const AssignmentSeriesAccessException(
        'Assignment series mutation values are invalid.',
      );
    }
    _requireRequestId(requestId);
    _requireRemote();
    final result = await _api.mutate(
      accessToken: await _requireToken(),
      seriesId: seriesId,
      operation: operation,
      requestId: requestId,
      expectedRevision: expectedRevision,
    );
    if (result.id != seriesId ||
        operation == 'confirm' &&
            (result.status != AssignmentSeriesStatus.active ||
                result.currentRevision != expectedRevision) ||
        operation == 'cancel-future' &&
            result.status != AssignmentSeriesStatus.cancelled) {
      throw const AssignmentSeriesContractException(
        'Assignment series mutation response is invalid.',
      );
    }
    return result;
  }

  void _requireRemote() {
    if (!_canUseSyncedPlanner || !_config.isSupabaseConfigured) {
      throw const AssignmentSeriesAccessException(
        'Assignment series require an authenticated synced account.',
      );
    }
  }

  Future<String> _requireToken() async {
    final token = await _accessTokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw const AssignmentSeriesAccessException(
        'Assignment series require an authenticated session.',
      );
    }
    return token.trim();
  }

  void _requireRequestId(String value) {
    if (!isClientUuid(value)) {
      throw const AssignmentSeriesAccessException(
        'Assignment series request identity is invalid.',
      );
    }
  }
}
