import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/features/deadline_plans/application/deadline_plan_controller.dart';

void main() {
  test('known conflicts map to safe specific recovery guidance', () {
    final cases = {
      'Finish or abandon the active focus session first.':
          DeadlinePlanConflictKind.activeFocus,
      'Finish or abandon active focus before replanning.':
          DeadlinePlanConflictKind.activeFocus,
      'Calendar availability is no longer current.':
          DeadlinePlanConflictKind.calendarContext,
      'Calendar source changed. Replan before confirmation.':
          DeadlinePlanConflictKind.calendarContext,
      'Deadline proposal is stale or conflicts with a reservation.':
          DeadlinePlanConflictKind.stalePreview,
      'Focus progress changed; replan before confirmation.':
          DeadlinePlanConflictKind.stalePreview,
      'Daily preparation budget is exceeded. Create a fresh preview.':
          DeadlinePlanConflictKind.accountBudget,
      'You already have 50 open deadline plans.':
          DeadlinePlanConflictKind.openPlanCap,
      'Deadline plan changed. Reload before replanning.':
          DeadlinePlanConflictKind.revision,
      'Managed task is unavailable for replanning.':
          DeadlinePlanConflictKind.revision,
    };

    for (final entry in cases.entries) {
      final error = _error(entry.key);
      expect(deadlinePlanConflictKind(error), entry.value);
      expect(deadlinePlanConflictGuidance(error), isNotEmpty);
    }
    expect(
      deadlinePlanConflictGuidance(
        _error('You already have 50 open deadline plans.'),
      ),
      contains('Close or cancel one open preparation plan'),
    );
    expect(
      deadlinePlanConflictGuidance(
        _error('Finish or abandon the active focus session first.'),
      ),
      contains('Finish or abandon'),
    );
    expect(
      deadlinePlanConflictGuidance(
        _error('Daily preparation budget is exceeded. Create a fresh preview.'),
      ),
      contains('total daily preparation budget'),
    );
  });

  test('only revision and unknown conflicts force reload', () {
    expect(
      deadlinePlanMutationSuggestsReload(
        _error('Deadline plan changed. Reload before replanning.'),
      ),
      isTrue,
    );
    expect(
      deadlinePlanMutationSuggestsReload(
        _error('Calendar availability is no longer current.'),
      ),
      isFalse,
    );
    expect(
      deadlinePlanMutationSuggestsReload(
        _error(
          'Daily preparation budget is exceeded. Create a fresh preview.',
        ),
      ),
      isFalse,
    );
    expect(
      deadlinePlanMutationSuggestsReload(_error('private server detail')),
      isTrue,
    );
    expect(
      deadlinePlanConflictGuidance(_error('private server detail')),
      isNot(contains('private server detail')),
    );
  });
}

AppException _error(String detail) {
  final options = RequestOptions(path: '/v1/deadline-plans/proposals');
  return AppException(
    'Network request failed',
    cause: DioException(
      requestOptions: options,
      response: Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 409,
        data: {'detail': detail},
      ),
    ),
  );
}
