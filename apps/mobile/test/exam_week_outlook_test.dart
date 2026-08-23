import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/deadline_plans/domain/exam_week_outlook.dart';

void main() {
  Map<String, dynamic> outlook() => {
        'contract_version': 'exam-week-outlook-v1',
        'origin': 'authenticated_backend',
        'generated_at': '2026-08-02T09:30:00Z',
        'timezone': 'Europe/Berlin',
        'local_date': '2026-08-02',
        'mode': 'inactive',
        'risk_level': 'unknown',
        'capacity_status': 'unknown',
        'current_sleep_plan': null,
        'recent_sleep_nights': <dynamic>[],
        'exams': <dynamic>[],
        'assignments': <dynamic>[],
        'warning_codes': <dynamic>[],
        'minutes': {
          'remaining_minutes': 0,
          'future_scheduled_minutes': 0,
          'missed_preparation_minutes': 0,
          'simulated_regular_minutes': 0,
          'unscheduled_regular_minutes': 0,
          'simulated_sleep_protected_minutes': null,
          'unscheduled_sleep_protected_minutes': null,
        },
      };

  test('inactive outlook keeps its exact nested contract', () {
    final parsed = ExamWeekOutlook.fromJson(outlook());
    expect(parsed.mode, 'inactive');
    expect(parsed.exams, isEmpty);

    final missing = outlook()..remove('minutes');
    final unknown = {...outlook(), 'unknown': true};
    final wrongNestedShape = {...outlook(), 'minutes': <dynamic>[]};
    for (final value in [missing, unknown, wrongNestedShape]) {
      expect(
        () => ExamWeekOutlook.fromJson(value),
        throwsA(isA<ExamWeekOutlookContractException>()),
      );
    }
  });

  test('outlook rejects invalid dates, timestamps, and list bounds', () {
    final tooManyWarnings = List<String>.filled(10, 'sleep_plan_missing');
    for (final value in <Map<String, dynamic>>[
      {...outlook(), 'local_date': '2026-02-30'},
      {...outlook(), 'generated_at': '2026-08-02T09:30:00'},
      {...outlook(), 'warning_codes': tooManyWarnings},
    ]) {
      expect(
        () => ExamWeekOutlook.fromJson(value),
        throwsA(isA<ExamWeekOutlookContractException>()),
      );
    }
  });

  test('sleep-night primitives reject booleans as numbers', () {
    expect(
      () => ExamWeekSleepNight.fromJson({
        'entry_date': '2026-08-01',
        'estimated_sleep_minutes': true,
        'sleep_target_minutes': 480,
        'shortfall_minutes': 0,
        'at_least_one_hour_short': false,
      }),
      throwsA(isA<ExamWeekOutlookContractException>()),
    );
  });
}
