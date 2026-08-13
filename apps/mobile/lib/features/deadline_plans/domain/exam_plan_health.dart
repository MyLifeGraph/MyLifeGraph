import 'dart:math' as math;

import '../../../core/contracts/strict_contract.dart';
import '../../../core/time/profile_timezone.dart';
import '../../../core/utils/local_date.dart';
import 'deadline_plan.dart';

const examPlanHealthContractVersion = 'exam-plan-health-v1';

class ExamPlanHealthContractException implements Exception {
  const ExamPlanHealthContractException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum ExamPlanHealthStatus {
  green('green'),
  yellow('yellow'),
  red('red'),
  unknown('unknown');

  const ExamPlanHealthStatus(this.code);
  final String code;

  static ExamPlanHealthStatus? fromCode(Object? value) {
    for (final status in values) {
      if (status.code == value) return status;
    }
    return null;
  }
}

const examPlanHealthReasonCodes = {
  'overdue_remaining',
  'capacity_deficit',
  'low_percentage_reserve',
  'low_session_reserve',
  'latest_safe_start_near',
  'calendar_import_unavailable',
  'calendar_window_incomplete',
  'recurring_availability_invalid',
  'higher_priority_capacity_unknown',
};

const examPlanHealthMissingSourceCodes = {
  'calendar_import',
  'calendar_horizon',
  'recurring_availability',
  'higher_priority_exam_capacity',
};

class ExamPlanHealthItem {
  ExamPlanHealthItem({
    required this.planId,
    required this.title,
    required this.deadlineAt,
    required this.localDeadlineDate,
    required this.status,
    required this.remainingMinutes,
    required this.preferredSessionMinutes,
    required this.sessionsNeeded,
    required this.futureReservedMinutes,
    required this.minutesToSchedule,
    required this.availableReplanCapacityMinutes,
    required this.reserveMinutes,
    required this.reserveFullSessions,
    required this.latestSafeStartOn,
    required this.recommendedStartOn,
    required this.recommendedStartReason,
    required List<String> reasons,
    required List<String> missingSources,
  })  : reasons = List.unmodifiable(reasons),
        missingSources = List.unmodifiable(missingSources) {
    _validate();
  }

  factory ExamPlanHealthItem.fromJson(Map<String, dynamic> json) {
    Never fail() => throw const ExamPlanHealthContractException(
          'Exam Plan Health item is invalid.',
        );
    requireStrictKeys(
      json,
      requiredKeys: const {
        'plan_id',
        'title',
        'deadline_at',
        'local_deadline_date',
        'status',
        'remaining_minutes',
        'preferred_session_minutes',
        'sessions_needed',
        'future_reserved_minutes',
        'minutes_to_schedule',
        'available_replan_capacity_minutes',
        'reserve_minutes',
        'reserve_full_sessions',
        'latest_safe_start_on',
        'recommended_start_on',
        'recommended_start_reason',
        'reasons',
        'missing_sources',
      },
      onFailure: fail,
    );
    final status = ExamPlanHealthStatus.fromCode(json['status']);
    if (status == null) fail();
    return ExamPlanHealthItem(
      planId: requireStrictUuid(json['plan_id'], onFailure: fail),
      title: requireStrictString(
        json['title'],
        maxLength: 160,
        length: StrictStringLength.runes,
        onFailure: fail,
      ),
      deadlineAt: requireStrictAwareDateTime(
        json['deadline_at'],
        maxFractionDigits: 6,
        onFailure: fail,
      ),
      localDeadlineDate: requireStrictLocalDate(
        json['local_deadline_date'],
        minimumYear: 1,
        onFailure: fail,
      ),
      status: status,
      remainingMinutes: requireStrictInt(
        json['remaining_minutes'],
        min: 0,
        max: 30000,
        onFailure: fail,
      ),
      preferredSessionMinutes: requireStrictInt(
        json['preferred_session_minutes'],
        min: 25,
        max: 180,
        onFailure: fail,
      ),
      sessionsNeeded: requireStrictInt(
        json['sessions_needed'],
        min: 0,
        max: 1200,
        onFailure: fail,
      ),
      futureReservedMinutes: requireStrictInt(
        json['future_reserved_minutes'],
        min: 0,
        max: 30000,
        onFailure: fail,
      ),
      minutesToSchedule: requireStrictInt(
        json['minutes_to_schedule'],
        min: 0,
        max: 30000,
        onFailure: fail,
      ),
      availableReplanCapacityMinutes: _optionalInt(
        json['available_replan_capacity_minutes'],
        min: 0,
        max: 200000,
        fail: fail,
      ),
      reserveMinutes: _optionalInt(
        json['reserve_minutes'],
        min: -30000,
        max: 200000,
        fail: fail,
      ),
      reserveFullSessions: _optionalInt(
        json['reserve_full_sessions'],
        min: 0,
        max: 8000,
        fail: fail,
      ),
      latestSafeStartOn: _optionalDate(json['latest_safe_start_on'], fail),
      recommendedStartOn: _optionalDate(json['recommended_start_on'], fail),
      recommendedStartReason: _optionalString(
        json['recommended_start_reason'],
        maxLength: 240,
        fail: fail,
      ),
      reasons: _codeList(
        json['reasons'],
        allowed: examPlanHealthReasonCodes,
        maxItems: 9,
        fail: fail,
      ),
      missingSources: _codeList(
        json['missing_sources'],
        allowed: examPlanHealthMissingSourceCodes,
        maxItems: 4,
        fail: fail,
      ),
    );
  }

  final String planId;
  final String title;
  final DateTime deadlineAt;
  final String localDeadlineDate;
  final ExamPlanHealthStatus status;
  final int remainingMinutes;
  final int preferredSessionMinutes;
  final int sessionsNeeded;
  final int futureReservedMinutes;
  final int minutesToSchedule;
  final int? availableReplanCapacityMinutes;
  final int? reserveMinutes;
  final int? reserveFullSessions;
  final String? latestSafeStartOn;
  final String? recommendedStartOn;
  final String? recommendedStartReason;
  final List<String> reasons;
  final List<String> missingSources;

  bool get needsAttention => status != ExamPlanHealthStatus.green;

  void validateForEnvelope({
    required DateTime generatedAt,
    required String localDate,
    required String timezone,
  }) {
    try {
      if (profileLocalDateKey(
            instant: deadlineAt,
            timezoneName: timezone,
          ) !=
          localDeadlineDate) {
        throw const ExamPlanHealthContractException(
          'Exam Plan Health deadline date is inconsistent.',
        );
      }
    } on ProfileTimezoneException {
      throw const ExamPlanHealthContractException(
        'Exam Plan Health timezone is invalid.',
      );
    }
    const authorityReason = {
      'calendar_import': 'calendar_import_unavailable',
      'calendar_horizon': 'calendar_window_incomplete',
      'recurring_availability': 'recurring_availability_invalid',
      'higher_priority_exam_capacity': 'higher_priority_capacity_unknown',
    };
    final expectedReasons = [
      for (final source in missingSources) authorityReason[source]!,
    ];
    late final ExamPlanHealthStatus expectedStatus;
    if (!deadlineAt.isAfter(generatedAt) && remainingMinutes > 0) {
      expectedStatus = ExamPlanHealthStatus.red;
      expectedReasons.insert(0, 'overdue_remaining');
    } else if (missingSources.isNotEmpty) {
      expectedStatus = ExamPlanHealthStatus.unknown;
    } else if (reserveMinutes! < 0) {
      expectedStatus = ExamPlanHealthStatus.red;
      expectedReasons
        ..clear()
        ..add('capacity_deficit');
    } else {
      if (minutesToSchedule > 0) {
        if (reserveMinutes! * 5 < minutesToSchedule) {
          expectedReasons.add('low_percentage_reserve');
        }
        if (reserveMinutes! < 2 * preferredSessionMinutes) {
          expectedReasons.add('low_session_reserve');
        }
        if (latestSafeStartOn != null &&
            civilDateDifferenceInDays(latestSafeStartOn!, localDate) <= 7) {
          expectedReasons.add('latest_safe_start_near');
        }
      }
      expectedStatus = expectedReasons.isEmpty
          ? ExamPlanHealthStatus.green
          : ExamPlanHealthStatus.yellow;
    }
    if (status != expectedStatus || !_sameStrings(reasons, expectedReasons)) {
      throw const ExamPlanHealthContractException(
        'Exam Plan Health status thresholds are inconsistent.',
      );
    }
  }

  void _validate() {
    final expectedSessions = remainingMinutes == 0
        ? 0
        : (remainingMinutes / preferredSessionMinutes).ceil();
    final capacityValues = [
      availableReplanCapacityMinutes,
      reserveMinutes,
      reserveFullSessions,
    ];
    final capacityComplete = capacityValues.every((value) => value != null);
    final capacityMissing = capacityValues.every((value) => value == null);
    final expectedUncovered = math.max(
      0,
      remainingMinutes - futureReservedMinutes,
    );
    if (title.isEmpty ||
        title != title.trim() ||
        sessionsNeeded != expectedSessions ||
        minutesToSchedule != expectedUncovered ||
        reasons.toSet().length != reasons.length ||
        missingSources.toSet().length != missingSources.length ||
        !capacityComplete && !capacityMissing ||
        missingSources.isNotEmpty && !capacityMissing ||
        missingSources.isEmpty && !capacityComplete ||
        capacityMissing && latestSafeStartOn != null ||
        capacityComplete &&
            reserveMinutes !=
                availableReplanCapacityMinutes! - minutesToSchedule ||
        capacityComplete &&
            reserveFullSessions !=
                math.max(0, reserveMinutes!) ~/ preferredSessionMinutes ||
        recommendedStartOn == null && recommendedStartReason == null ||
        recommendedStartOn != null && recommendedStartReason != null ||
        latestSafeStartOn != null &&
            recommendedStartOn != null &&
            recommendedStartOn!.compareTo(latestSafeStartOn!) > 0 ||
        status == ExamPlanHealthStatus.green && reasons.isNotEmpty ||
        status == ExamPlanHealthStatus.yellow &&
            !reasons.any(
              const {
                'low_percentage_reserve',
                'low_session_reserve',
                'latest_safe_start_near',
              }.contains,
            ) ||
        status == ExamPlanHealthStatus.red &&
            !reasons.any(
              const {'overdue_remaining', 'capacity_deficit'}.contains,
            ) ||
        status == ExamPlanHealthStatus.unknown && missingSources.isEmpty ||
        missingSources.isNotEmpty &&
            !{
              ExamPlanHealthStatus.unknown,
              ExamPlanHealthStatus.red,
            }.contains(status)) {
      throw const ExamPlanHealthContractException(
        'Exam Plan Health arithmetic is inconsistent.',
      );
    }
  }
}

class ExamPlanHealth {
  ExamPlanHealth({
    required this.generatedAt,
    required this.timezone,
    required this.localDate,
    required List<ExamPlanHealthItem> exams,
  }) : exams = List.unmodifiable(exams) {
    try {
      if (profileLocalDateKey(
            instant: generatedAt,
            timezoneName: timezone,
          ) !=
          localDate) {
        throw const ExamPlanHealthContractException(
          'Exam Plan Health local date is inconsistent.',
        );
      }
    } on ProfileTimezoneException {
      throw const ExamPlanHealthContractException(
        'Exam Plan Health timezone is invalid.',
      );
    }
    _validateOrder();
    for (final exam in this.exams) {
      exam.validateForEnvelope(
        generatedAt: generatedAt,
        localDate: localDate,
        timezone: timezone,
      );
    }
  }

  factory ExamPlanHealth.fromJson(Map<String, dynamic> json) {
    Never fail() => throw const ExamPlanHealthContractException(
          'Exam Plan Health response is invalid.',
        );
    requireStrictKeys(
      json,
      requiredKeys: const {
        'contract_version',
        'origin',
        'generated_at',
        'timezone',
        'local_date',
        'exams',
      },
      onFailure: fail,
    );
    if (json['contract_version'] != examPlanHealthContractVersion ||
        json['origin'] != 'authenticated_backend') {
      fail();
    }
    return ExamPlanHealth(
      generatedAt: requireStrictAwareDateTime(
        json['generated_at'],
        maxFractionDigits: 6,
        onFailure: fail,
      ),
      timezone: requireStrictString(
        json['timezone'],
        maxLength: 100,
        onFailure: fail,
      ),
      localDate: requireStrictLocalDate(
        json['local_date'],
        minimumYear: 1,
        onFailure: fail,
      ),
      exams: requireStrictMapList(
        json['exams'],
        maxItems: 2000,
        onFailure: fail,
      ).map(ExamPlanHealthItem.fromJson).toList(growable: false),
    );
  }

  final DateTime generatedAt;
  final String timezone;
  final String localDate;
  final List<ExamPlanHealthItem> exams;

  List<ExamPlanHealthItem> get needsAttention =>
      exams.where((item) => item.needsAttention).toList(growable: false);

  void _validateOrder() {
    final ids = <String>{};
    for (var index = 0; index < exams.length; index++) {
      final item = exams[index];
      if (!ids.add(item.planId)) {
        throw const ExamPlanHealthContractException(
          'Exam Plan Health plan identities are duplicated.',
        );
      }
      if (index == 0) continue;
      final previous = exams[index - 1];
      final deadlineOrder = previous.deadlineAt.compareTo(item.deadlineAt);
      final remainingOrder = item.remainingMinutes.compareTo(
        previous.remainingMinutes,
      );
      if (deadlineOrder > 0 ||
          deadlineOrder == 0 && remainingOrder < 0 ||
          deadlineOrder == 0 &&
              remainingOrder == 0 &&
              previous.planId.compareTo(item.planId) > 0) {
        throw const ExamPlanHealthContractException(
          'Exam Plan Health priority order is invalid.',
        );
      }
    }
  }
}

class ExamPlanHealthPreview {
  ExamPlanHealthPreview({
    required this.generatedAt,
    required this.timezone,
    required this.localDate,
    required this.exam,
  }) {
    try {
      if (profileLocalDateKey(
            instant: generatedAt,
            timezoneName: timezone,
          ) !=
          localDate) {
        throw const ExamPlanHealthContractException(
          'Exam Plan Health preview local date is inconsistent.',
        );
      }
    } on ProfileTimezoneException {
      throw const ExamPlanHealthContractException(
        'Exam Plan Health preview timezone is invalid.',
      );
    }
    exam.validateForEnvelope(
      generatedAt: generatedAt,
      localDate: localDate,
      timezone: timezone,
    );
  }

  factory ExamPlanHealthPreview.fromJson(Map<String, dynamic> json) {
    Never fail() => throw const ExamPlanHealthContractException(
          'Exam Plan Health preview response is invalid.',
        );
    requireStrictKeys(
      json,
      requiredKeys: const {
        'contract_version',
        'origin',
        'generated_at',
        'timezone',
        'local_date',
        'exam',
      },
      onFailure: fail,
    );
    if (json['contract_version'] != examPlanHealthContractVersion ||
        json['origin'] != 'authenticated_backend_preview') {
      fail();
    }
    return ExamPlanHealthPreview(
      generatedAt: requireStrictAwareDateTime(
        json['generated_at'],
        maxFractionDigits: 6,
        onFailure: fail,
      ),
      timezone: requireStrictString(
        json['timezone'],
        maxLength: 100,
        onFailure: fail,
      ),
      localDate: requireStrictLocalDate(
        json['local_date'],
        minimumYear: 1,
        onFailure: fail,
      ),
      exam: ExamPlanHealthItem.fromJson(
        requireStrictMap(json['exam'], onFailure: fail),
      ),
    );
  }

  final DateTime generatedAt;
  final String timezone;
  final String localDate;
  final ExamPlanHealthItem exam;
}

class ExamPlanHealthPreviewDraft {
  const ExamPlanHealthPreviewDraft({
    required this.planId,
    required this.baseRevision,
    required this.title,
    required this.deadlineAt,
    required this.estimatedTotalMinutes,
    required this.creditedPriorMinutes,
    required this.preferredSessionMinutes,
    required this.maxDailyMinutes,
    required this.planningStartOn,
    required this.bufferDays,
    required this.sourceKind,
    required this.sourceCalendarEventId,
    required this.sourceCalendarEventFingerprint,
    required this.useCalendarAvailability,
  });

  factory ExamPlanHealthPreviewDraft.fromProposal(
    DeadlinePlanProposalDraft draft, {
    String? activePlanId,
    int? activeBaseRevision,
  }) {
    if (draft.kind != DeadlinePlanKind.exam) {
      throw const ExamPlanHealthContractException(
        'Only an Exam can be checked with Exam Plan Health.',
      );
    }
    if ((activePlanId == null) != (activeBaseRevision == null) ||
        activePlanId != null &&
            (draft.planId != activePlanId ||
                draft.baseRevision != activeBaseRevision)) {
      throw const ExamPlanHealthContractException(
        'Active Exam preview identity is inconsistent.',
      );
    }
    return ExamPlanHealthPreviewDraft(
      planId: activePlanId,
      baseRevision: activeBaseRevision,
      title: draft.title,
      deadlineAt: draft.deadlineAt,
      estimatedTotalMinutes: draft.estimatedTotalMinutes,
      creditedPriorMinutes: draft.creditedPriorMinutes,
      preferredSessionMinutes: draft.preferredSessionMinutes,
      maxDailyMinutes: draft.maxDailyMinutes,
      planningStartOn: draft.planningStartOn,
      bufferDays: draft.bufferDays,
      sourceKind: draft.sourceKind,
      sourceCalendarEventId: draft.sourceCalendarEventId,
      sourceCalendarEventFingerprint: draft.sourceCalendarEventFingerprint,
      useCalendarAvailability: draft.useCalendarAvailability,
    );
  }

  final String? planId;
  final int? baseRevision;
  final String title;
  final DateTime deadlineAt;
  final int estimatedTotalMinutes;
  final int creditedPriorMinutes;
  final int preferredSessionMinutes;
  final int maxDailyMinutes;
  final String planningStartOn;
  final int bufferDays;
  final DeadlinePlanSourceKind sourceKind;
  final String? sourceCalendarEventId;
  final String? sourceCalendarEventFingerprint;
  final bool useCalendarAvailability;

  Map<String, dynamic> toJson() {
    Never fail() => throw const ExamPlanHealthContractException(
          'Exam Plan Health preview draft is invalid.',
        );
    if (planId != null) requireStrictUuid(planId, onFailure: fail);
    if (baseRevision != null) {
      requireStrictInt(baseRevision, min: 1, max: 500, onFailure: fail);
    }
    requireStrictString(
      title,
      maxLength: 160,
      length: StrictStringLength.runes,
      onFailure: fail,
    );
    requireStrictAwareDateTime(
      deadlineAt.toUtc().toIso8601String(),
      maxFractionDigits: 6,
      onFailure: fail,
    );
    requireStrictInt(
      estimatedTotalMinutes,
      min: 30,
      max: 30000,
      onFailure: fail,
    );
    requireStrictInt(
      creditedPriorMinutes,
      min: 0,
      max: 29999,
      onFailure: fail,
    );
    requireStrictInt(
      preferredSessionMinutes,
      min: 25,
      max: 180,
      onFailure: fail,
    );
    requireStrictInt(
      maxDailyMinutes,
      min: 25,
      max: 480,
      onFailure: fail,
    );
    requireStrictLocalDate(planningStartOn, minimumYear: 1, onFailure: fail);
    requireStrictInt(bufferDays, min: 0, max: 7, onFailure: fail);
    final calendar = sourceKind == DeadlinePlanSourceKind.calendarEvent;
    if (title != title.trim() ||
        creditedPriorMinutes >= estimatedTotalMinutes ||
        maxDailyMinutes < preferredSessionMinutes ||
        (planId == null) != (baseRevision == null) ||
        calendar != (sourceCalendarEventId != null) ||
        calendar != (sourceCalendarEventFingerprint != null)) {
      fail();
    }
    if (sourceCalendarEventId != null) {
      requireStrictUuid(sourceCalendarEventId, onFailure: fail);
    }
    if (sourceCalendarEventFingerprint case final fingerprint?) {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint)) fail();
    }
    return {
      'contract_version': examPlanHealthContractVersion,
      if (planId != null) 'plan_id': planId,
      if (baseRevision != null) 'base_revision': baseRevision,
      'kind': 'exam',
      'title': title,
      'deadline_at': deadlineAt.toUtc().toIso8601String(),
      'estimated_total_minutes': estimatedTotalMinutes,
      'credited_prior_minutes': creditedPriorMinutes,
      'preferred_session_minutes': preferredSessionMinutes,
      'max_daily_minutes': maxDailyMinutes,
      'planning_start_on': planningStartOn,
      'buffer_days': bufferDays,
      'source_kind': sourceKind.code,
      if (sourceCalendarEventId != null)
        'source_calendar_event_id': sourceCalendarEventId,
      if (sourceCalendarEventFingerprint != null)
        'source_calendar_event_fingerprint': sourceCalendarEventFingerprint,
      'use_calendar_availability': useCalendarAvailability,
    };
  }
}

int? _optionalInt(
  Object? value, {
  required int min,
  required int max,
  required Never Function() fail,
}) =>
    value == null
        ? null
        : requireStrictInt(value, min: min, max: max, onFailure: fail);

String? _optionalDate(Object? value, Never Function() fail) => value == null
    ? null
    : requireStrictLocalDate(value, minimumYear: 1, onFailure: fail);

String? _optionalString(
  Object? value, {
  required int maxLength,
  required Never Function() fail,
}) =>
    value == null
        ? null
        : requireStrictString(
            value,
            maxLength: maxLength,
            onFailure: fail,
          );

List<String> _codeList(
  Object? value, {
  required Set<String> allowed,
  required int maxItems,
  required Never Function() fail,
}) {
  final raw = requireStrictList(
    value,
    maxItems: maxItems,
    onFailure: fail,
  );
  final result = raw
      .map(
        (item) => requireStrictString(item, maxLength: 80, onFailure: fail),
      )
      .toList(growable: false);
  if (result.any((item) => !allowed.contains(item)) ||
      result.toSet().length != result.length) {
    fail();
  }
  return result;
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
