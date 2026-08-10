import '../../../core/contracts/strict_contract.dart';

const assignmentSeriesContractVersion = 'assignment-series-v1';

enum AssignmentSeriesStatus { draft, active, cancelled }

enum AssignmentSeriesRevisionState { proposed, active, superseded }

enum AssignmentSeriesOccurrenceAction { retain, upsert, cancel }

class AssignmentSeriesFeed {
  const AssignmentSeriesFeed(this.series);

  factory AssignmentSeriesFeed.fromJson(Map<String, dynamic> json) {
    _expectEnvelope(json);
    _expectExactKeys(
      json,
      const {'contract_version', 'origin', 'assignment_series'},
      'assignment series feed',
    );
    final rows = requireStrictList(
      json['assignment_series'],
      onFailure: () => throw const AssignmentSeriesContractException(
        'Assignment series list is invalid.',
      ),
    );
    if (rows.length > 20) {
      throw const AssignmentSeriesContractException(
        'Assignment series list exceeds its bound.',
      );
    }
    final series = rows
        .map(
          (row) => AssignmentSeries.fromJson(
            _requiredMap(row, 'assignment_series'),
          ),
        )
        .toList(growable: false);
    if (series.map((item) => item.id).toSet().length != series.length) {
      throw const AssignmentSeriesContractException(
        'Assignment series identities must be unique.',
      );
    }
    return AssignmentSeriesFeed(List.unmodifiable(series));
  }

  final List<AssignmentSeries> series;
}

class AssignmentSeriesResponse {
  const AssignmentSeriesResponse(this.series);

  factory AssignmentSeriesResponse.fromJson(Map<String, dynamic> json) {
    _expectEnvelope(json);
    _expectExactKeys(
      json,
      const {'contract_version', 'origin', 'assignment_series'},
      'assignment series response',
    );
    return AssignmentSeriesResponse(
      AssignmentSeries.fromJson(
        _requiredMap(json['assignment_series'], 'assignment_series'),
      ),
    );
  }

  final AssignmentSeries series;
}

class AssignmentSeries {
  const AssignmentSeries({
    required this.id,
    required this.status,
    required this.title,
    required this.currentRevision,
    required this.latestRevision,
    required this.createdAt,
    required this.updatedAt,
    required this.firstActivatedAt,
    required this.cancelledAt,
    required this.activeRevision,
    required this.pendingRevision,
  });

  factory AssignmentSeries.fromJson(Map<String, dynamic> json) {
    _expectRequiredAndOptionalKeys(
      json,
      required: const {'series'},
      optional: const {'active_revision', 'pending_revision'},
      model: 'assignment series detail',
    );
    final identity = _requiredMap(json['series'], 'series');
    _expectRequiredAndOptionalKeys(
      identity,
      required: const {
        'id',
        'status',
        'title',
        'current_revision',
        'latest_revision',
        'created_at',
        'updated_at',
      },
      optional: const {'first_activated_at', 'cancelled_at'},
      model: 'assignment series identity',
    );
    final id = _requiredUuid(identity['id'], 'series.id');
    final status = _status(identity['status']);
    final currentRevision = _requiredInt(
      identity['current_revision'],
      'series.current_revision',
    );
    final latestRevision = _requiredInt(
      identity['latest_revision'],
      'series.latest_revision',
    );
    final firstActivatedAt = _optionalDateTime(
      identity,
      'first_activated_at',
    );
    final cancelledAt = _optionalDateTime(identity, 'cancelled_at');
    final activeRevision = json.containsKey('active_revision')
        ? AssignmentSeriesRevision.fromJson(
            _requiredMap(json['active_revision'], 'active_revision'),
          )
        : null;
    final pendingRevision = json.containsKey('pending_revision')
        ? AssignmentSeriesRevision.fromJson(
            _requiredMap(json['pending_revision'], 'pending_revision'),
          )
        : null;
    if (currentRevision < 0 ||
        currentRevision > 200 ||
        latestRevision < (currentRevision < 1 ? 1 : currentRevision) ||
        latestRevision > 200 ||
        activeRevision != null &&
            (activeRevision.seriesId != id ||
                activeRevision.state != AssignmentSeriesRevisionState.active ||
                activeRevision.revision != currentRevision) ||
        pendingRevision != null &&
            (pendingRevision.seriesId != id ||
                pendingRevision.state !=
                    AssignmentSeriesRevisionState.proposed ||
                pendingRevision.revision != latestRevision) ||
        status == AssignmentSeriesStatus.draft &&
            (currentRevision != 0 || pendingRevision == null) ||
        status == AssignmentSeriesStatus.active &&
            (currentRevision < 1 ||
                firstActivatedAt == null ||
                activeRevision == null) ||
        status == AssignmentSeriesStatus.cancelled && cancelledAt == null ||
        status != AssignmentSeriesStatus.cancelled && cancelledAt != null) {
      throw const AssignmentSeriesContractException(
        'Assignment series lifecycle is invalid.',
      );
    }
    return AssignmentSeries(
      id: id,
      status: status,
      title: _requiredString(identity['title'], 'series.title', 160),
      currentRevision: currentRevision,
      latestRevision: latestRevision,
      createdAt: _requiredDateTime(identity['created_at'], 'series.created_at'),
      updatedAt: _requiredDateTime(identity['updated_at'], 'series.updated_at'),
      firstActivatedAt: firstActivatedAt,
      cancelledAt: cancelledAt,
      activeRevision: activeRevision,
      pendingRevision: pendingRevision,
    );
  }

  final String id;
  final AssignmentSeriesStatus status;
  final String title;
  final int currentRevision;
  final int latestRevision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? firstActivatedAt;
  final DateTime? cancelledAt;
  final AssignmentSeriesRevision? activeRevision;
  final AssignmentSeriesRevision? pendingRevision;

  AssignmentSeriesRevision? get displayedRevision =>
      pendingRevision ?? activeRevision;
  bool get isDraft => status == AssignmentSeriesStatus.draft;
  bool get isActive => status == AssignmentSeriesStatus.active;
  bool get isCancelled => status == AssignmentSeriesStatus.cancelled;
  bool get hasPendingPreview => pendingRevision != null;

  Set<String> get occurrencePlanIds => {
        ...?activeRevision?.occurrences.map((item) => item.planId),
        ...?pendingRevision?.occurrences.map((item) => item.planId),
      };
}

class AssignmentSeriesRevision {
  const AssignmentSeriesRevision({
    required this.seriesId,
    required this.revision,
    required this.baseRevision,
    required this.state,
    required this.title,
    required this.nextDeadlineAt,
    required this.remainingOccurrences,
    required this.estimatedTotalMinutes,
    required this.preferredSessionMinutes,
    required this.maxDailyMinutes,
    required this.bufferDays,
    required this.useCalendarAvailability,
    required this.timezone,
    required this.plannedMinutes,
    required this.unscheduledMinutes,
    required this.createdAt,
    required this.activatedAt,
    required this.supersededAt,
    required this.occurrences,
  });

  factory AssignmentSeriesRevision.fromJson(Map<String, dynamic> json) {
    _expectRequiredAndOptionalKeys(
      json,
      required: const {
        'series_id',
        'revision',
        'base_revision',
        'state',
        'title',
        'next_deadline_at',
        'remaining_occurrences',
        'estimated_total_minutes',
        'preferred_session_minutes',
        'max_daily_minutes',
        'buffer_days',
        'use_calendar_availability',
        'timezone',
        'planned_minutes',
        'unscheduled_minutes',
        'created_at',
        'occurrences',
      },
      optional: const {'activated_at', 'superseded_at'},
      model: 'assignment series revision',
    );
    final revision = _requiredInt(json['revision'], 'revision.revision');
    final baseRevision = _requiredInt(
      json['base_revision'],
      'revision.base_revision',
    );
    final remaining = _requiredInt(
      json['remaining_occurrences'],
      'revision.remaining_occurrences',
    );
    final estimate = _requiredInt(
      json['estimated_total_minutes'],
      'revision.estimated_total_minutes',
    );
    final preferred = _requiredInt(
      json['preferred_session_minutes'],
      'revision.preferred_session_minutes',
    );
    final daily = _requiredInt(
      json['max_daily_minutes'],
      'revision.max_daily_minutes',
    );
    final buffer = _requiredInt(json['buffer_days'], 'revision.buffer_days');
    final planned = _requiredInt(
      json['planned_minutes'],
      'revision.planned_minutes',
    );
    final unscheduled = _requiredInt(
      json['unscheduled_minutes'],
      'revision.unscheduled_minutes',
    );
    final rawOccurrences = requireStrictList(
      json['occurrences'],
      onFailure: () => throw const AssignmentSeriesContractException(
        'Assignment occurrences are invalid.',
      ),
    );
    if (rawOccurrences.length > 40) {
      throw const AssignmentSeriesContractException(
        'Assignment occurrences exceed their bound.',
      );
    }
    final occurrences = rawOccurrences
        .map(
          (item) => AssignmentSeriesOccurrence.fromJson(
            _requiredMap(item, 'occurrence'),
          ),
        )
        .toList(growable: false);
    final occurrenceKeys =
        occurrences.map((item) => '${item.position}:${item.planId}').toSet();
    final state = _revisionState(json['state']);
    final activatedAt = _optionalDateTime(json, 'activated_at');
    final supersededAt = _optionalDateTime(json, 'superseded_at');
    if (revision < 1 ||
        revision > 200 ||
        revision != baseRevision + 1 ||
        remaining < 1 ||
        remaining > 20 ||
        estimate < 30 ||
        estimate > 30000 ||
        preferred < 25 ||
        preferred > 180 ||
        daily < preferred ||
        daily > 480 ||
        buffer < 0 ||
        buffer > 7 ||
        planned < 0 ||
        planned > 600000 ||
        unscheduled < 0 ||
        unscheduled > 600000 ||
        occurrenceKeys.length != occurrences.length ||
        occurrences
                .where(
                  (item) =>
                      item.action != AssignmentSeriesOccurrenceAction.cancel,
                )
                .length <
            remaining ||
        state == AssignmentSeriesRevisionState.proposed &&
            (activatedAt != null || supersededAt != null) ||
        state == AssignmentSeriesRevisionState.active &&
            (activatedAt == null || supersededAt != null) ||
        state == AssignmentSeriesRevisionState.superseded &&
            supersededAt == null) {
      throw const AssignmentSeriesContractException(
        'Assignment series revision is invalid.',
      );
    }
    return AssignmentSeriesRevision(
      seriesId: _requiredUuid(json['series_id'], 'revision.series_id'),
      revision: revision,
      baseRevision: baseRevision,
      state: state,
      title: _requiredString(json['title'], 'revision.title', 160),
      nextDeadlineAt: _requiredDateTime(
        json['next_deadline_at'],
        'revision.next_deadline_at',
      ),
      remainingOccurrences: remaining,
      estimatedTotalMinutes: estimate,
      preferredSessionMinutes: preferred,
      maxDailyMinutes: daily,
      bufferDays: buffer,
      useCalendarAvailability: _requiredBool(
        json['use_calendar_availability'],
        'revision.use_calendar_availability',
      ),
      timezone: _requiredString(json['timezone'], 'revision.timezone', 100),
      plannedMinutes: planned,
      unscheduledMinutes: unscheduled,
      createdAt: _requiredDateTime(json['created_at'], 'revision.created_at'),
      activatedAt: activatedAt,
      supersededAt: supersededAt,
      occurrences: List.unmodifiable(occurrences),
    );
  }

  final String seriesId;
  final int revision;
  final int baseRevision;
  final AssignmentSeriesRevisionState state;
  final String title;
  final DateTime nextDeadlineAt;
  final int remainingOccurrences;
  final int estimatedTotalMinutes;
  final int preferredSessionMinutes;
  final int maxDailyMinutes;
  final int bufferDays;
  final bool useCalendarAvailability;
  final String timezone;
  final int plannedMinutes;
  final int unscheduledMinutes;
  final DateTime createdAt;
  final DateTime? activatedAt;
  final DateTime? supersededAt;
  final List<AssignmentSeriesOccurrence> occurrences;

  List<AssignmentSeriesOccurrence> get keptOccurrences => occurrences
      .where((item) => item.action != AssignmentSeriesOccurrenceAction.cancel)
      .toList(growable: false);
}

class AssignmentSeriesOccurrence {
  const AssignmentSeriesOccurrence({
    required this.position,
    required this.action,
    required this.planId,
    required this.planRevision,
    required this.deadlineAt,
  });

  factory AssignmentSeriesOccurrence.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'position', 'action', 'plan_id', 'plan_revision', 'deadline_at'},
      'assignment occurrence',
    );
    final position = _requiredInt(json['position'], 'occurrence.position');
    final revision = _requiredInt(
      json['plan_revision'],
      'occurrence.plan_revision',
    );
    if (position < 1 || position > 200 || revision < 1 || revision > 200) {
      throw const AssignmentSeriesContractException(
        'Assignment occurrence values are invalid.',
      );
    }
    return AssignmentSeriesOccurrence(
      position: position,
      action: _occurrenceAction(json['action']),
      planId: _requiredUuid(json['plan_id'], 'occurrence.plan_id'),
      planRevision: revision,
      deadlineAt: _requiredDateTime(
        json['deadline_at'],
        'occurrence.deadline_at',
      ),
    );
  }

  final int position;
  final AssignmentSeriesOccurrenceAction action;
  final String planId;
  final int planRevision;
  final DateTime deadlineAt;
}

class AssignmentSeriesProposalDraft {
  AssignmentSeriesProposalDraft({
    required this.seriesId,
    required this.baseRevision,
    required String title,
    required this.nextDeadlineAt,
    required this.remainingOccurrences,
    required this.estimatedTotalMinutes,
    required this.preferredSessionMinutes,
    required this.maxDailyMinutes,
    required this.bufferDays,
    required this.useCalendarAvailability,
  }) : title = title.trim() {
    validate();
  }

  final String seriesId;
  final int baseRevision;
  final String title;
  final DateTime nextDeadlineAt;
  final int remainingOccurrences;
  final int estimatedTotalMinutes;
  final int preferredSessionMinutes;
  final int maxDailyMinutes;
  final int bufferDays;
  final bool useCalendarAvailability;

  void validate() {
    if (!isStrictUuid(seriesId, minVersion: 1, maxVersion: 5) ||
        baseRevision < 0 ||
        baseRevision > 199 ||
        title.isEmpty ||
        title.runes.length > 160 ||
        remainingOccurrences < (baseRevision == 0 ? 2 : 1) ||
        remainingOccurrences > 20 ||
        estimatedTotalMinutes < 30 ||
        estimatedTotalMinutes > 30000 ||
        preferredSessionMinutes < 25 ||
        preferredSessionMinutes > 180 ||
        maxDailyMinutes < preferredSessionMinutes ||
        maxDailyMinutes > 480 ||
        bufferDays < 0 ||
        bufferDays > 7) {
      throw const AssignmentSeriesAccessException(
        'Assignment series values are invalid.',
      );
    }
  }

  Map<String, dynamic> toJson({required String requestId}) => {
        'contract_version': assignmentSeriesContractVersion,
        'request_id': requestId,
        'series_id': seriesId,
        'base_revision': baseRevision,
        'title': title,
        'next_deadline_at': nextDeadlineAt.toUtc().toIso8601String(),
        'remaining_occurrences': remainingOccurrences,
        'estimated_total_minutes': estimatedTotalMinutes,
        'preferred_session_minutes': preferredSessionMinutes,
        'max_daily_minutes': maxDailyMinutes,
        'buffer_days': bufferDays,
        'use_calendar_availability': useCalendarAvailability,
      };
}

class AssignmentSeriesContractException implements Exception {
  const AssignmentSeriesContractException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AssignmentSeriesAccessException implements Exception {
  const AssignmentSeriesAccessException(this.message);
  final String message;
  @override
  String toString() => message;
}

void _expectEnvelope(Map<String, dynamic> json) {
  if (json['contract_version'] != assignmentSeriesContractVersion ||
      json['origin'] != 'authenticated_backend') {
    throw const AssignmentSeriesContractException(
      'Assignment series response provenance is invalid.',
    );
  }
}

void _expectExactKeys(
  Map<String, dynamic> json,
  Set<String> keys,
  String model,
) {
  requireStrictKeys(
    json,
    requiredKeys: keys,
    onFailure: () => throw AssignmentSeriesContractException(
      '$model fields are invalid.',
    ),
  );
}

void _expectRequiredAndOptionalKeys(
  Map<String, dynamic> json, {
  required Set<String> required,
  required Set<String> optional,
  required String model,
}) {
  requireStrictKeys(
    json,
    requiredKeys: required,
    optionalKeys: optional,
    rejectExplicitNullOptionalKeys: true,
    onFailure: () => throw AssignmentSeriesContractException(
      '$model fields are invalid.',
    ),
  );
}

Map<String, dynamic> _requiredMap(Object? value, String field) =>
    requireStrictMap(
      value,
      onFailure: () =>
          throw AssignmentSeriesContractException('$field is invalid.'),
    );

String _requiredUuid(Object? value, String field) => requireStrictUuid(
      value,
      minVersion: 1,
      maxVersion: 5,
      onFailure: () =>
          throw AssignmentSeriesContractException('$field is invalid.'),
    );

String _requiredString(Object? value, String field, int maxLength) =>
    requireStrictString(
      value,
      maxLength: maxLength,
      length: StrictStringLength.runes,
      onFailure: () =>
          throw AssignmentSeriesContractException('$field is invalid.'),
    );

int _requiredInt(Object? value, String field) => requireStrictInt(
      value,
      onFailure: () =>
          throw AssignmentSeriesContractException('$field is invalid.'),
    );

bool _requiredBool(Object? value, String field) {
  if (value is! bool) {
    throw AssignmentSeriesContractException('$field is invalid.');
  }
  return value;
}

DateTime _requiredDateTime(Object? value, String field) =>
    requireStrictAwareDateTime(
      value,
      maxFractionDigits: 6,
      validateDateAndTimeComponents: false,
      onFailure: () =>
          throw AssignmentSeriesContractException('$field is invalid.'),
    );

DateTime? _optionalDateTime(Map<String, dynamic> json, String key) =>
    json.containsKey(key) ? _requiredDateTime(json[key], key) : null;

AssignmentSeriesStatus _status(Object? value) => switch (value) {
      'draft' => AssignmentSeriesStatus.draft,
      'active' => AssignmentSeriesStatus.active,
      'cancelled' => AssignmentSeriesStatus.cancelled,
      _ => throw const AssignmentSeriesContractException(
          'Assignment series status is invalid.',
        ),
    };

AssignmentSeriesRevisionState _revisionState(Object? value) => switch (value) {
      'proposed' => AssignmentSeriesRevisionState.proposed,
      'active' => AssignmentSeriesRevisionState.active,
      'superseded' => AssignmentSeriesRevisionState.superseded,
      _ => throw const AssignmentSeriesContractException(
          'Assignment series revision state is invalid.',
        ),
    };

AssignmentSeriesOccurrenceAction _occurrenceAction(Object? value) =>
    switch (value) {
      'retain' => AssignmentSeriesOccurrenceAction.retain,
      'upsert' => AssignmentSeriesOccurrenceAction.upsert,
      'cancel' => AssignmentSeriesOccurrenceAction.cancel,
      _ => throw const AssignmentSeriesContractException(
          'Assignment occurrence action is invalid.',
        ),
    };
