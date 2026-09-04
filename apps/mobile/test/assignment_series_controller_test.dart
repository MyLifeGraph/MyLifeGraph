import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/deadline_plans/application/assignment_series_controller.dart';
import 'package:my_life_graph/features/deadline_plans/domain/assignment_series.dart';
import 'package:my_life_graph/features/deadline_plans/domain/assignment_series_repository.dart';

import 'support/assignment_series_fixtures.dart';

void main() {
  test('series lifecycle refreshes only after proven success and exact retry',
      () async {
    final draft = AssignmentSeriesResponse.fromJson(
      assignmentSeriesEnvelope(),
    ).series;
    final active = AssignmentSeriesResponse.fromJson(
      assignmentSeriesEnvelope(status: 'active'),
    ).series;
    final cancelled = AssignmentSeriesResponse.fromJson(
      assignmentSeriesEnvelope(status: 'cancelled'),
    ).series;
    final repository = _SeriesRepository(
      initial: draft,
      confirmResults: [StateError('transport unknown'), active],
      cancelResults: [cancelled],
    );
    var refreshes = 0;
    final controller = AssignmentSeriesController(
      repository: repository,
      projectionRefresh: () async => refreshes += 1,
    );
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);

    expect(await controller.confirm(draft), isFalse);
    expect(controller.state.requiresExactRetry, isTrue);
    expect(refreshes, 0);
    final pending = controller.state.pendingMutation;
    final error = controller.state.operationError;
    final reads = repository.reads;
    await controller.load();
    controller.clearOperationError();
    expect(repository.reads, reads);
    expect(identical(controller.state.pendingMutation, pending), isTrue);
    expect(identical(controller.state.operationError, error), isTrue);

    expect(await controller.retryExact(), isTrue);
    expect(controller.state.requiresExactRetry, isFalse);
    expect(refreshes, 1);

    expect(await controller.cancelFuture(active), isTrue);
    expect(refreshes, 2);
    expect(repository.confirmRequestIds, hasLength(2));
    expect(repository.confirmRequestIds.toSet(), hasLength(1));
  });
}

class _SeriesRepository implements AssignmentSeriesRepository {
  _SeriesRepository({
    required this.initial,
    required List<Object> confirmResults,
    required List<Object> cancelResults,
  })  : confirmResults = [...confirmResults],
        cancelResults = [...cancelResults];

  final AssignmentSeries initial;
  final List<Object> confirmResults;
  final List<Object> cancelResults;
  final List<String> confirmRequestIds = [];
  int reads = 0;

  @override
  Future<AssignmentSeriesFeed> getSeries() async {
    reads += 1;
    return AssignmentSeriesFeed([initial]);
  }

  @override
  Future<AssignmentSeries> propose({
    required String requestId,
    required AssignmentSeriesProposalDraft draft,
  }) =>
      throw UnimplementedError();

  @override
  Future<AssignmentSeries> confirm({
    required String seriesId,
    required String requestId,
    required int expectedRevision,
  }) async {
    confirmRequestIds.add(requestId);
    return _next(confirmResults);
  }

  @override
  Future<AssignmentSeries> cancelFuture({
    required String seriesId,
    required String requestId,
    required int expectedRevision,
  }) async =>
      _next(cancelResults);

  AssignmentSeries _next(List<Object> results) {
    final result = results.removeAt(0);
    if (result is AssignmentSeries) return result;
    throw result;
  }
}
