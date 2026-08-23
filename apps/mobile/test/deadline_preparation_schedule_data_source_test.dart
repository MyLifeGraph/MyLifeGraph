import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/dashboard/data/datasources/deadline_preparation_schedule_data_source.dart';

import 'support/deadline_plan_fixtures.dart';

void main() {
  final range = DeadlinePreparationScheduleRange(
    startDate: DateTime(2026, 7, 20),
    endDate: DateTime(2026, 7, 26),
  );

  test('maps only active blocks on the active plan revision', () {
    final rows = [
      _blockRow(),
      _blockRow(
        id: '44444444-4444-4444-8444-444444444444',
        state: 'proposed',
      ),
      _blockRow(
        id: '55555555-5555-4555-8555-555555555555',
        planId: '66666666-6666-4666-8666-666666666666',
      ),
    ];
    final result = const DeadlinePreparationScheduleMapper().map(
      blockRows: rows,
      planRows: [
        _planRow(),
        _planRow(
          id: '66666666-6666-4666-8666-666666666666',
          status: 'completed',
        ),
      ],
    );

    expect(result, hasLength(1));
    expect(result.single.id, deadlineBlockId);
    expect(result.single.planTitle, 'Algorithms exam');
    expect(result.single.startsAt, DateTime.parse('2026-07-20T08:00:00Z'));
    expect(range.expandedUtcStart, DateTime.utc(2026, 7, 19));
    expect(range.expandedUtcEndExclusive, DateTime.utc(2026, 7, 28));
  });

  test('excludes superseded revision even if a row still says active', () {
    final result = const DeadlinePreparationScheduleMapper().map(
      blockRows: [_blockRow(revision: 1)],
      planRows: [_planRow(revision: 2)],
    );

    expect(result, isEmpty);
  });

  test('malformed active block fails the preparation overlay closed', () {
    final row = _blockRow()..['ends_at'] = '2026-07-20T08:45:00Z';

    expect(
      () => const DeadlinePreparationScheduleMapper().map(
        blockRows: [row],
        planRows: [_planRow()],
      ),
      throwsA(isA<DeadlinePreparationScheduleException>()),
    );
  });

  test('one-row sentinel rejects results beyond the strict week cap', () {
    final rows = List.generate(
      maxDashboardPreparationBlocks + 1,
      (_) => _blockRow(),
    );

    expect(
      () => const DeadlinePreparationScheduleMapper().map(
        blockRows: rows,
        planRows: [_planRow()],
      ),
      throwsA(isA<DeadlinePreparationScheduleException>()),
    );
  });
}

Map<String, dynamic> _blockRow({
  String id = deadlineBlockId,
  String planId = deadlinePlanId,
  int revision = 1,
  String state = 'active',
}) =>
    {
      'id': id,
      'plan_id': planId,
      'revision': revision,
      'sequence': 1,
      'reservation_state': state,
      'starts_at': '2026-07-20T08:00:00Z',
      'ends_at': '2026-07-20T08:50:00Z',
      'planned_minutes': 50,
    };

Map<String, dynamic> _planRow({
  String id = deadlinePlanId,
  String status = 'active',
  int revision = 1,
}) =>
    {
      'id': id,
      'title': 'Algorithms exam',
      'status': status,
      'current_revision': revision,
    };
