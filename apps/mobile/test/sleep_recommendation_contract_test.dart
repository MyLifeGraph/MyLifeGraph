import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/insights/domain/entities/sleep_recommendation.dart';

void main() {
  test('parses the complete ready contract and its warning evidence', () {
    final value = SleepRecommendation.fromJson(_response());

    expect(value.status, SleepRecommendationStatus.ready);
    expect(value.recommendation?.rawMedianDurationMinutes, 480);
    expect(value.recommendation?.medianConfirmedSleepTargetMinutes, 510);
    expect(
      value.recommendation?.warning,
      'below_confirmed_sleep_target',
    );
  });

  test('accepts a zero lower duration boundary after outward rounding', () {
    final json = _response(rawDuration: 1);
    final duration = (json['recommendation']
        as Map<String, dynamic>)['duration'] as Map<String, dynamic>;
    duration['minimum_minutes'] = 0;
    duration['maximum_minutes'] = 15;

    final value = SleepRecommendation.fromJson(json);

    expect(value.recommendation?.duration.minimumMinutes, 0);
    expect(value.recommendation?.duration.maximumMinutes, 15);
  });

  test('rejects missing or inconsistent below-target warning evidence', () {
    final missingRaw = _copy(_response());
    (missingRaw['recommendation'] as Map<String, dynamic>)
        .remove('raw_median_duration_minutes');
    final missingTarget = _copy(_response());
    (missingTarget['recommendation'] as Map<String, dynamic>)
        .remove('median_confirmed_sleep_target_minutes');
    final missingWarning = _response(warning: null);
    final unexpectedWarning = _response(
      rawDuration: 510,
      confirmedTarget: 480,
    );

    for (final json in [
      missingRaw,
      missingTarget,
      missingWarning,
      unexpectedWarning,
    ]) {
      expect(
        () => SleepRecommendation.fromJson(json),
        throwsFormatException,
      );
    }
  });

  test('rejects invalid status, window, and evidence relationships', () {
    final wrongReason = _copy(_response());
    wrongReason['reason'] = 'mixed_focus_outcomes';
    final shortWindow = _copy(_response());
    (shortWindow['window'] as Map<String, dynamic>)['starts_at'] =
        '2026-05-02T12:00:00Z';
    final invalidLocalDate = _copy(_response());
    (invalidLocalDate['window'] as Map<String, dynamic>)['local_starts_on'] =
        '2026-02-30';
    final invalidDelta = _copy(_response());
    final recommendation =
        invalidDelta['recommendation'] as Map<String, dynamic>;
    (recommendation['evidence']
        as Map<String, dynamic>)['completion_rate_delta'] = 1.1;

    for (final json in [
      wrongReason,
      shortWindow,
      invalidLocalDate,
      invalidDelta,
    ]) {
      expect(
        () => SleepRecommendation.fromJson(json),
        throwsFormatException,
      );
    }
  });
}

Map<String, dynamic> _response({
  int rawDuration = 480,
  int confirmedTarget = 510,
  String? warning = 'below_confirmed_sleep_target',
}) =>
    {
      'contract_version': sleepRecommendationContractVersion,
      'status': 'ready',
      'reason': 'ready',
      'generated_at': '2026-07-30T12:00:00Z',
      'timezone': 'Europe/Berlin',
      'window': {
        'rolling_days': 90,
        'starts_at': '2026-05-01T12:00:00Z',
        'ends_at': '2026-07-30T12:00:00Z',
        'local_starts_on': '2026-05-01',
        'local_ends_on': '2026-07-30',
      },
      'sample': {
        'valid_nights': 30,
        'eligible_focus_days': 30,
        'rated_sessions': 34,
        'required_eligible_days': 30,
        'progress': '30/30',
      },
      'recommendation': {
        'bedtime': {
          'start_local_time': '22:45',
          'end_local_time': '23:15',
          'end_day_offset': 0,
          'width_minutes': 30,
        },
        'wake_time': {
          'start_local_time': '06:45',
          'end_local_time': '07:15',
          'end_day_offset': 0,
          'width_minutes': 30,
        },
        'duration': {
          'minimum_minutes': 465,
          'maximum_minutes': 495,
        },
        'wake_day_offset': 1,
        'raw_median_duration_minutes': rawDuration,
        'median_confirmed_sleep_target_minutes': confirmedTarget,
        'warning': warning,
        'evidence': {
          'candidate_days': 15,
          'comparison_days': 15,
          'morning_readiness_median_delta': 1.0,
          'sleep_quality_median_delta': 1.0,
          'morning_energy_median_delta': 1.0,
          'useful_progress_median_delta': 1.0,
          'focus_quality_median_delta': 0.0,
          'completion_rate_delta': 0.0,
          'consistent_in_both_halves': true,
        },
        'evidence_fingerprint': List.filled(64, 'a').join(),
      },
      'summary':
          'This best-supported sleep window is associated with stronger mornings.',
      'limitations': [
        'This is an observed association, not a causal claim.',
      ],
    };

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(
      jsonDecode(jsonEncode(value)) as Map,
    );
