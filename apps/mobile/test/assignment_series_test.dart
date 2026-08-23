import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/deadline_plans/domain/assignment_series.dart';

import 'support/assignment_series_fixtures.dart';

void main() {
  test('strict series envelope keeps independent weekly occurrences', () {
    final series = AssignmentSeriesResponse.fromJson(
      assignmentSeriesEnvelope(),
    ).series;

    expect(series.isDraft, isTrue);
    expect(series.pendingRevision!.remainingOccurrences, 2);
    expect(series.pendingRevision!.occurrences, hasLength(2));
    expect(
      series.pendingRevision!.occurrences.map((item) => item.planId).toSet(),
      hasLength(2),
    );
  });

  test('series parser rejects unknown fields and duplicate occurrences', () {
    final unknown = assignmentSeriesEnvelope()..['unexpected'] = true;
    expect(
      () => AssignmentSeriesResponse.fromJson(unknown),
      throwsA(isA<AssignmentSeriesContractException>()),
    );

    final duplicate = assignmentSeriesEnvelope();
    final detail = duplicate['assignment_series'] as Map<String, dynamic>;
    final revision = detail['pending_revision'] as Map<String, dynamic>;
    final occurrences = revision['occurrences'] as List<dynamic>;
    occurrences[1] = Map<String, Object>.from(
      occurrences.first as Map<String, Object>,
    );
    expect(
      () => AssignmentSeriesResponse.fromJson(duplicate),
      throwsA(isA<AssignmentSeriesContractException>()),
    );
  });

  test('new drafts require a finite series and emit zero-ambiguity transport',
      () {
    final draft = AssignmentSeriesProposalDraft(
      seriesId: assignmentSeriesId,
      baseRevision: 0,
      title: ' Weekly algorithms sheet ',
      nextDeadlineAt: DateTime.parse('2026-08-17T17:00:00+02:00'),
      remainingOccurrences: 12,
      estimatedTotalMinutes: 90,
      preferredSessionMinutes: 30,
      maxDailyMinutes: 60,
      bufferDays: 1,
      useCalendarAvailability: false,
    );

    expect(draft.title, 'Weekly algorithms sheet');
    expect(draft.toJson(requestId: assignmentSeriesRequestId), {
      'contract_version': 'assignment-series-v1',
      'request_id': assignmentSeriesRequestId,
      'series_id': assignmentSeriesId,
      'base_revision': 0,
      'title': 'Weekly algorithms sheet',
      'next_deadline_at': '2026-08-17T15:00:00.000Z',
      'remaining_occurrences': 12,
      'estimated_total_minutes': 90,
      'preferred_session_minutes': 30,
      'max_daily_minutes': 60,
      'buffer_days': 1,
      'use_calendar_availability': false,
    });

    expect(
      () => AssignmentSeriesProposalDraft(
        seriesId: assignmentSeriesId,
        baseRevision: 0,
        title: 'Single assignment',
        nextDeadlineAt: DateTime.utc(2026, 8, 17, 15),
        remainingOccurrences: 1,
        estimatedTotalMinutes: 90,
        preferredSessionMinutes: 30,
        maxDailyMinutes: 60,
        bufferDays: 1,
        useCalendarAvailability: false,
      ),
      throwsA(isA<AssignmentSeriesAccessException>()),
    );
  });
}
