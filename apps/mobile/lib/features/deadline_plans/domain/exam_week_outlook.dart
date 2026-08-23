import '../../../core/contracts/strict_contract.dart';

class ExamWeekOutlookContractException implements Exception {
  const ExamWeekOutlookContractException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ExamWeekSleepPlan {
  const ExamWeekSleepPlan({
    required this.captureId,
    required this.entryDate,
    required this.capturedAt,
    required this.plannedSleepTime,
    required this.sleepTargetMinutes,
  });

  factory ExamWeekSleepPlan.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      const {
        'capture_id',
        'entry_date',
        'captured_at',
        'planned_sleep_time',
        'sleep_target_minutes',
      },
      'Exam-week sleep plan',
    );
    final target = _integer(json['sleep_target_minutes']);
    final planned = '${json['planned_sleep_time'] ?? ''}';
    if (target < 300 ||
        target > 720 ||
        target % 15 != 0 ||
        !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(planned)) {
      throw const ExamWeekOutlookContractException(
        'Exam-week sleep plan is invalid.',
      );
    }
    return ExamWeekSleepPlan(
      captureId: _boundedString(json['capture_id'], 160),
      entryDate: _localDate(json['entry_date']),
      capturedAt: _awareDateTime(json['captured_at']),
      plannedSleepTime: planned,
      sleepTargetMinutes: target,
    );
  }

  final String captureId;
  final String entryDate;
  final DateTime capturedAt;
  final String plannedSleepTime;
  final int sleepTargetMinutes;
}

class ExamWeekSleepNight {
  const ExamWeekSleepNight({
    required this.entryDate,
    required this.estimatedSleepMinutes,
    required this.sleepTargetMinutes,
    required this.shortfallMinutes,
    required this.atLeastOneHourShort,
  });

  factory ExamWeekSleepNight.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      const {
        'entry_date',
        'estimated_sleep_minutes',
        'sleep_target_minutes',
        'shortfall_minutes',
        'at_least_one_hour_short',
      },
      'Exam-week sleep night',
    );
    final estimated = _integer(json['estimated_sleep_minutes']);
    final target = _integer(json['sleep_target_minutes']);
    final shortfall = _integer(json['shortfall_minutes']);
    final isShort = _boolean(json['at_least_one_hour_short']);
    if (estimated < 1 ||
        estimated > 960 ||
        target < 300 ||
        target > 720 ||
        target % 15 != 0 ||
        shortfall != (target - estimated).clamp(0, target) ||
        isShort != (shortfall >= 60)) {
      throw const ExamWeekOutlookContractException(
        'Exam-week sleep-night arithmetic is invalid.',
      );
    }
    return ExamWeekSleepNight(
      entryDate: _localDate(json['entry_date']),
      estimatedSleepMinutes: estimated,
      sleepTargetMinutes: target,
      shortfallMinutes: shortfall,
      atLeastOneHourShort: isShort,
    );
  }

  final String entryDate;
  final int estimatedSleepMinutes;
  final int sleepTargetMinutes;
  final int shortfallMinutes;
  final bool atLeastOneHourShort;
}

class ExamWeekPlanOutlook {
  const ExamWeekPlanOutlook({
    required this.planId,
    required this.kind,
    required this.title,
    required this.deadlineAt,
    required this.localDeadlineDate,
    required this.daysRemaining,
    required this.activeRevision,
    required this.pendingRevision,
    required this.savedBufferDays,
    required this.recommendedBufferDays,
    required this.lastPreparationDate,
    required this.remainingMinutes,
    required this.futureScheduledMinutes,
    required this.futureMinutesAfterBuffer,
    required this.missedPreparationMinutes,
    required this.simulatedRegularMinutes,
    required this.unscheduledRegularMinutes,
    required this.simulatedSleepProtectedMinutes,
    required this.unscheduledSleepProtectedMinutes,
    required this.pendingPreviewSleepOverlap,
  });

  factory ExamWeekPlanOutlook.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      const {
        'plan_id',
        'kind',
        'title',
        'deadline_at',
        'local_deadline_date',
        'days_remaining',
        'active_revision',
        'pending_revision',
        'saved_buffer_days',
        'recommended_buffer_days',
        'last_preparation_date',
        'remaining_minutes',
        'future_scheduled_minutes',
        'future_minutes_after_buffer',
        'missed_preparation_minutes',
        'simulated_regular_minutes',
        'unscheduled_regular_minutes',
        'simulated_sleep_protected_minutes',
        'unscheduled_sleep_protected_minutes',
        'pending_preview_sleep_overlap',
      },
      'Exam-week plan',
    );
    final kind = '${json['kind'] ?? ''}';
    final remaining = _nonNegative(json['remaining_minutes']);
    final future = _nonNegative(json['future_scheduled_minutes']);
    final simulated = _nonNegative(json['simulated_regular_minutes']);
    final unscheduled = _nonNegative(json['unscheduled_regular_minutes']);
    final protected = _optionalNonNegative(
      json['simulated_sleep_protected_minutes'],
    );
    final protectedMissing = _optionalNonNegative(
      json['unscheduled_sleep_protected_minutes'],
    );
    if (!{'exam', 'assignment'}.contains(kind) ||
        simulated + unscheduled != (remaining - future).clamp(0, remaining) ||
        (protected == null) != (protectedMissing == null) ||
        (protected != null &&
            protectedMissing != null &&
            protected + protectedMissing !=
                (remaining - future).clamp(0, remaining))) {
      throw const ExamWeekOutlookContractException(
        'Exam-week plan arithmetic is invalid.',
      );
    }
    return ExamWeekPlanOutlook(
      planId: _uuid(json['plan_id']),
      kind: kind,
      title: _boundedString(json['title'], 160),
      deadlineAt: _awareDateTime(json['deadline_at']),
      localDeadlineDate: _localDate(json['local_deadline_date']),
      daysRemaining: _integer(json['days_remaining']),
      activeRevision: _positive(json['active_revision']),
      pendingRevision: _optionalPositive(json['pending_revision']),
      savedBufferDays: _nonNegative(json['saved_buffer_days']),
      recommendedBufferDays: _nonNegative(
        json['recommended_buffer_days'],
      ),
      lastPreparationDate: _localDate(json['last_preparation_date']),
      remainingMinutes: remaining,
      futureScheduledMinutes: future,
      futureMinutesAfterBuffer: _nonNegative(
        json['future_minutes_after_buffer'],
      ),
      missedPreparationMinutes: _nonNegative(
        json['missed_preparation_minutes'],
      ),
      simulatedRegularMinutes: simulated,
      unscheduledRegularMinutes: unscheduled,
      simulatedSleepProtectedMinutes: protected,
      unscheduledSleepProtectedMinutes: protectedMissing,
      pendingPreviewSleepOverlap: _boolean(
        json['pending_preview_sleep_overlap'],
      ),
    );
  }

  final String planId;
  final String kind;
  final String title;
  final DateTime deadlineAt;
  final String localDeadlineDate;
  final int daysRemaining;
  final int activeRevision;
  final int? pendingRevision;
  final int savedBufferDays;
  final int recommendedBufferDays;
  final String lastPreparationDate;
  final int remainingMinutes;
  final int futureScheduledMinutes;
  final int futureMinutesAfterBuffer;
  final int missedPreparationMinutes;
  final int simulatedRegularMinutes;
  final int unscheduledRegularMinutes;
  final int? simulatedSleepProtectedMinutes;
  final int? unscheduledSleepProtectedMinutes;
  final bool pendingPreviewSleepOverlap;
}

class ExamWeekMinuteTotals {
  const ExamWeekMinuteTotals({
    required this.remainingMinutes,
    required this.futureScheduledMinutes,
    required this.missedPreparationMinutes,
    required this.simulatedRegularMinutes,
    required this.unscheduledRegularMinutes,
    required this.simulatedSleepProtectedMinutes,
    required this.unscheduledSleepProtectedMinutes,
  });

  factory ExamWeekMinuteTotals.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      const {
        'remaining_minutes',
        'future_scheduled_minutes',
        'missed_preparation_minutes',
        'simulated_regular_minutes',
        'unscheduled_regular_minutes',
        'simulated_sleep_protected_minutes',
        'unscheduled_sleep_protected_minutes',
      },
      'Exam-week minute totals',
    );
    return ExamWeekMinuteTotals(
      remainingMinutes: _nonNegative(json['remaining_minutes']),
      futureScheduledMinutes: _nonNegative(
        json['future_scheduled_minutes'],
      ),
      missedPreparationMinutes: _nonNegative(
        json['missed_preparation_minutes'],
      ),
      simulatedRegularMinutes: _nonNegative(
        json['simulated_regular_minutes'],
      ),
      unscheduledRegularMinutes: _nonNegative(
        json['unscheduled_regular_minutes'],
      ),
      simulatedSleepProtectedMinutes: _optionalNonNegative(
        json['simulated_sleep_protected_minutes'],
      ),
      unscheduledSleepProtectedMinutes: _optionalNonNegative(
        json['unscheduled_sleep_protected_minutes'],
      ),
    );
  }

  final int remainingMinutes;
  final int futureScheduledMinutes;
  final int missedPreparationMinutes;
  final int simulatedRegularMinutes;
  final int unscheduledRegularMinutes;
  final int? simulatedSleepProtectedMinutes;
  final int? unscheduledSleepProtectedMinutes;
}

class ExamWeekOutlook {
  const ExamWeekOutlook({
    required this.generatedAt,
    required this.timezone,
    required this.localDate,
    required this.mode,
    required this.riskLevel,
    required this.capacityStatus,
    required this.currentSleepPlan,
    required this.recentSleepNights,
    required this.exams,
    required this.assignments,
    required this.warningCodes,
    required this.minutes,
  });

  factory ExamWeekOutlook.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      const {
        'contract_version',
        'origin',
        'generated_at',
        'timezone',
        'local_date',
        'mode',
        'risk_level',
        'capacity_status',
        'current_sleep_plan',
        'recent_sleep_nights',
        'exams',
        'assignments',
        'warning_codes',
        'minutes',
      },
      'Exam-week outlook',
    );
    if (json['contract_version'] != 'exam-week-outlook-v1' ||
        json['origin'] != 'authenticated_backend') {
      throw const ExamWeekOutlookContractException(
        'Exam-week outlook identity is invalid.',
      );
    }
    final mode = '${json['mode'] ?? ''}';
    final risk = '${json['risk_level'] ?? ''}';
    final capacity = '${json['capacity_status'] ?? ''}';
    final warnings = _strings(json['warning_codes']);
    if (!{'inactive', 'watch', 'exam_week', 'overdue'}.contains(mode) ||
        !{'on_track', 'attention', 'high', 'critical', 'unknown'}
            .contains(risk) ||
        !{
          'fits_with_sleep_protected',
          'fits_only_using_sleep_window',
          'does_not_fit_before_buffer',
          'unknown',
        }.contains(capacity) ||
        warnings.length != warnings.toSet().length ||
        warnings.any((value) => !_warningCodes.contains(value))) {
      throw const ExamWeekOutlookContractException(
        'Exam-week outlook state is invalid.',
      );
    }
    final exams = _objects(json['exams'])
        .map(ExamWeekPlanOutlook.fromJson)
        .toList(growable: false);
    final assignments = _objects(json['assignments'])
        .map(ExamWeekPlanOutlook.fromJson)
        .toList(growable: false);
    if (exams.any((item) => item.kind != 'exam') ||
        assignments.any((item) => item.kind != 'assignment') ||
        (mode == 'inactive' && exams.isNotEmpty)) {
      throw const ExamWeekOutlookContractException(
        'Exam-week plan groups are invalid.',
      );
    }
    final rawSleepPlan = json['current_sleep_plan'];
    return ExamWeekOutlook(
      generatedAt: _awareDateTime(json['generated_at']),
      timezone: _boundedString(json['timezone'], 100),
      localDate: _localDate(json['local_date']),
      mode: mode,
      riskLevel: risk,
      capacityStatus: capacity,
      currentSleepPlan: rawSleepPlan == null
          ? null
          : ExamWeekSleepPlan.fromJson(_object(rawSleepPlan)),
      recentSleepNights: _objects(json['recent_sleep_nights'])
          .map(ExamWeekSleepNight.fromJson)
          .toList(growable: false),
      exams: exams,
      assignments: assignments,
      warningCodes: warnings,
      minutes: ExamWeekMinuteTotals.fromJson(_object(json['minutes'])),
    );
  }

  final DateTime generatedAt;
  final String timezone;
  final String localDate;
  final String mode;
  final String riskLevel;
  final String capacityStatus;
  final ExamWeekSleepPlan? currentSleepPlan;
  final List<ExamWeekSleepNight> recentSleepNights;
  final List<ExamWeekPlanOutlook> exams;
  final List<ExamWeekPlanOutlook> assignments;
  final List<String> warningCodes;
  final ExamWeekMinuteTotals minutes;
}

const _warningCodes = {
  'exam_overdue',
  'missing_recommended_buffer',
  'missed_preparation_blocks',
  'remaining_work_does_not_fit',
  'sleep_capacity_tradeoff',
  'repeated_sleep_shortfall',
  'sleep_plan_missing',
  'capacity_incomplete',
  'pending_preview_sleep_overlap',
};

void _expectKeys(
  Map<String, dynamic> json,
  Set<String> expected,
  String label,
) {
  requireStrictKeys(
    json,
    requiredKeys: expected,
    onFailure: () => throw ExamWeekOutlookContractException(
      '$label shape is invalid.',
    ),
  );
}

Map<String, dynamic> _object(Object? value) {
  return requireStrictMap(
    value,
    onFailure: () => throw const ExamWeekOutlookContractException(
      'Expected an object.',
    ),
  );
}

List<Map<String, dynamic>> _objects(Object? value) {
  final values = requireStrictList(
    value,
    maxItems: 50,
    onFailure: () => throw const ExamWeekOutlookContractException(
      'Expected a bounded list.',
    ),
  );
  return values.map(_object).toList(growable: false);
}

List<String> _strings(Object? value) {
  final values = requireStrictList(
    value,
    maxItems: 9,
    onFailure: () => throw const ExamWeekOutlookContractException(
      'Expected a bounded string list.',
    ),
  );
  if (values.any((item) => item is! String)) {
    throw const ExamWeekOutlookContractException(
      'Expected a bounded string list.',
    );
  }
  return values.cast<String>();
}

String _boundedString(Object? value, int maximum) {
  return requireStrictString(
    value,
    maxLength: maximum,
    onFailure: () => throw const ExamWeekOutlookContractException(
      'Expected bounded text.',
    ),
  );
}

String _localDate(Object? value) {
  final raw = '$value';
  return requireStrictLocalDate(
    raw,
    onFailure: () => throw const ExamWeekOutlookContractException(
      'Expected a local date.',
    ),
  );
}

DateTime _awareDateTime(Object? value) {
  final raw = '$value';
  return requireStrictAwareDateTime(
    raw,
    exactSecondsFormat: false,
    onFailure: () => throw const ExamWeekOutlookContractException(
      'Expected a timezone-aware timestamp.',
    ),
  );
}

String _uuid(Object? value) {
  final raw = '$value';
  return requireStrictUuid(
    raw,
    minVersion: 1,
    maxVersion: 5,
    onFailure: () => throw const ExamWeekOutlookContractException(
      'Expected a UUID.',
    ),
  );
}

int _integer(Object? value) {
  return requireStrictInt(
    value,
    onFailure: () => throw const ExamWeekOutlookContractException(
      'Expected a whole number.',
    ),
  );
}

int _nonNegative(Object? value) {
  final parsed = _integer(value);
  if (parsed < 0) {
    throw const ExamWeekOutlookContractException(
      'Expected a non-negative number.',
    );
  }
  return parsed;
}

int _positive(Object? value) {
  final parsed = _integer(value);
  if (parsed < 1) {
    throw const ExamWeekOutlookContractException('Expected a positive number.');
  }
  return parsed;
}

int? _optionalPositive(Object? value) =>
    value == null ? null : _positive(value);

int? _optionalNonNegative(Object? value) =>
    value == null ? null : _nonNegative(value);

bool _boolean(Object? value) {
  return requireStrictBool(
    value,
    onFailure: () => throw const ExamWeekOutlookContractException(
      'Expected a boolean.',
    ),
  );
}
