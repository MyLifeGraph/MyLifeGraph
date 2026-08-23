import 'assignment_series.dart';

abstract interface class AssignmentSeriesRepository {
  Future<AssignmentSeriesFeed> getSeries();

  Future<AssignmentSeries> propose({
    required String requestId,
    required AssignmentSeriesProposalDraft draft,
  });

  Future<AssignmentSeries> confirm({
    required String seriesId,
    required String requestId,
    required int expectedRevision,
  });

  Future<AssignmentSeries> cancelFuture({
    required String seriesId,
    required String requestId,
    required int expectedRevision,
  });
}
