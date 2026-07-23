const deadlinePlanContractVersion = 'deadline-plan-v1';
const preparationWorkloadContractVersion = 'preparation-workload-v1';
const preparationWorkloadDetailContractVersion =
    'preparation-workload-detail-v1';

enum DeadlinePlanKind {
  exam('exam'),
  assignment('assignment');

  const DeadlinePlanKind(this.code);
  final String code;

  static DeadlinePlanKind? fromCode(Object? value) => switch (value) {
        'exam' => exam,
        'assignment' => assignment,
        _ => null,
      };
}

enum DeadlinePlanSourceKind {
  manual('manual'),
  calendarEvent('calendar_event');

  const DeadlinePlanSourceKind(this.code);
  final String code;

  static DeadlinePlanSourceKind? fromCode(Object? value) => switch (value) {
        'manual' => manual,
        'calendar_event' => calendarEvent,
        _ => null,
      };
}

enum DeadlinePlanStatus {
  draft('draft'),
  active('active'),
  completed('completed'),
  cancelled('cancelled');

  const DeadlinePlanStatus(this.code);
  final String code;

  static DeadlinePlanStatus? fromCode(Object? value) {
    for (final status in values) {
      if (status.code == value) return status;
    }
    return null;
  }
}

enum DeadlinePlanRevisionState {
  proposed('proposed'),
  active('active'),
  superseded('superseded');

  const DeadlinePlanRevisionState(this.code);
  final String code;

  static DeadlinePlanRevisionState? fromCode(Object? value) {
    for (final state in values) {
      if (state.code == value) return state;
    }
    return null;
  }
}

enum DeadlinePlanSourceStatus {
  notApplicable('not_applicable'),
  current('current'),
  stale('stale'),
  unavailable('unavailable');

  const DeadlinePlanSourceStatus(this.code);
  final String code;

  static DeadlinePlanSourceStatus? fromCode(Object? value) {
    for (final status in values) {
      if (status.code == value) return status;
    }
    return null;
  }
}

enum DeadlinePlanBlockState {
  proposed('proposed'),
  upcoming('upcoming'),
  partial('partial'),
  completed('completed'),
  missed('missed');

  const DeadlinePlanBlockState(this.code);
  final String code;

  static DeadlinePlanBlockState? fromCode(Object? value) {
    for (final state in values) {
      if (state.code == value) return state;
    }
    return null;
  }
}

class PreparationWorkload {
  PreparationWorkload({
    required this.generatedAt,
    required this.timezone,
    required this.dailyPreparationBudgetMinutes,
    required List<PreparationWorkloadDay> days,
  }) : days = List.unmodifiable(days) {
    if (days.length != 7 ||
        dailyPreparationBudgetMinutes != null &&
            (dailyPreparationBudgetMinutes! < 25 ||
                dailyPreparationBudgetMinutes! > 480 ||
                dailyPreparationBudgetMinutes! % 5 != 0)) {
      throw const DeadlinePlanContractException(
        'Preparation workload values are invalid.',
      );
    }
    for (var index = 0; index < days.length; index++) {
      final day = days[index];
      if (index > 0 &&
          day.localDate.difference(days[index - 1].localDate).inDays != 1) {
        throw const DeadlinePlanContractException(
          'Preparation workload dates are invalid.',
        );
      }
      final budget = dailyPreparationBudgetMinutes;
      if (budget == null) {
        if (day.remainingBudgetMinutes != null || day.overBudgetMinutes != 0) {
          throw const DeadlinePlanContractException(
            'Preparation workload without a budget is inconsistent.',
          );
        }
      } else if (day.remainingBudgetMinutes !=
              (budget - day.reservedPreparationMinutes).clamp(0, budget) ||
          day.overBudgetMinutes !=
              (day.reservedPreparationMinutes - budget).clamp(0, 30000)) {
        throw const DeadlinePlanContractException(
          'Preparation workload arithmetic is inconsistent.',
        );
      }
    }
  }

  factory PreparationWorkload.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'contract_version',
        'origin',
        'generated_at',
        'timezone',
        'daily_preparation_budget_minutes',
        'days',
      },
      'preparation workload',
    );
    if (json['contract_version'] != preparationWorkloadContractVersion ||
        json['origin'] != 'authenticated_backend') {
      throw const DeadlinePlanContractException(
        'Preparation workload provenance is invalid.',
      );
    }
    final rawBudget = json['daily_preparation_budget_minutes'];
    if (rawBudget != null && rawBudget is! int) {
      throw const DeadlinePlanContractException(
        'Preparation workload budget is invalid.',
      );
    }
    final rawDays = json['days'];
    if (rawDays is! List || rawDays.length != 7) {
      throw const DeadlinePlanContractException(
        'Preparation workload days are invalid.',
      );
    }
    return PreparationWorkload(
      generatedAt: _requiredAwareDateTime(
        json['generated_at'],
        'workload.generated_at',
      ),
      timezone: _requiredString(
        json['timezone'],
        'workload.timezone',
        maxLength: 100,
      ),
      dailyPreparationBudgetMinutes: rawBudget as int?,
      days: rawDays
          .map(
            (value) => PreparationWorkloadDay.fromJson(
              _requiredStringMap(value, 'workload day'),
            ),
          )
          .toList(growable: false),
    );
  }

  final DateTime generatedAt;
  final String timezone;
  final int? dailyPreparationBudgetMinutes;
  final List<PreparationWorkloadDay> days;

  int get totalReservedMinutes => days.fold(
        0,
        (total, day) => total + day.reservedPreparationMinutes,
      );
  int get daysNeedingReview =>
      days.where((day) => day.overBudgetMinutes > 0).length;
}

class PreparationWorkloadDay {
  const PreparationWorkloadDay({
    required this.localDate,
    required this.reservedPreparationMinutes,
    required this.remainingBudgetMinutes,
    required this.overBudgetMinutes,
    required this.activePlanCount,
    required this.fixedCommitmentMinutes,
  });

  factory PreparationWorkloadDay.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'local_date',
        'reserved_preparation_minutes',
        'remaining_budget_minutes',
        'over_budget_minutes',
        'active_plan_count',
        'fixed_commitment_minutes',
      },
      'preparation workload day',
    );
    final dateText = _requiredDate(json['local_date'], 'workload.local_date');
    final rawRemaining = json['remaining_budget_minutes'];
    if (rawRemaining != null && rawRemaining is! int) {
      throw const DeadlinePlanContractException(
        'Preparation workload remaining budget is invalid.',
      );
    }
    final day = PreparationWorkloadDay(
      // Keep a date-only server fact independent of the device timezone. Local
      // midnight arithmetic can be 23 or 25 hours across DST and would reject
      // otherwise consecutive profile-local dates.
      localDate: DateTime.parse('${dateText}T00:00:00Z'),
      reservedPreparationMinutes: _requiredInt(
        json['reserved_preparation_minutes'],
        'workload.reserved_preparation_minutes',
      ),
      remainingBudgetMinutes: rawRemaining as int?,
      overBudgetMinutes: _requiredInt(
        json['over_budget_minutes'],
        'workload.over_budget_minutes',
      ),
      activePlanCount: _requiredInt(
        json['active_plan_count'],
        'workload.active_plan_count',
      ),
      fixedCommitmentMinutes: _requiredInt(
        json['fixed_commitment_minutes'],
        'workload.fixed_commitment_minutes',
      ),
    );
    if (day.reservedPreparationMinutes < 0 ||
        day.reservedPreparationMinutes > 30000 ||
        day.remainingBudgetMinutes != null &&
            (day.remainingBudgetMinutes! < 0 ||
                day.remainingBudgetMinutes! > 480) ||
        day.overBudgetMinutes < 0 ||
        day.overBudgetMinutes > 30000 ||
        day.activePlanCount < 0 ||
        day.activePlanCount > 50 ||
        day.fixedCommitmentMinutes < 0 ||
        day.fixedCommitmentMinutes > 1440) {
      throw const DeadlinePlanContractException(
        'Preparation workload day values are invalid.',
      );
    }
    return day;
  }

  final DateTime localDate;
  final int reservedPreparationMinutes;
  final int? remainingBudgetMinutes;
  final int overBudgetMinutes;
  final int activePlanCount;
  final int fixedCommitmentMinutes;

  String get localDateKey => _dateOnlyKey(localDate);
}

class PreparationWorkloadDetail {
  PreparationWorkloadDetail({
    required this.generatedAt,
    required this.timezone,
    required this.localDate,
    required this.dailyPreparationBudgetMinutes,
    required this.reservedPreparationMinutes,
    required this.remainingBudgetMinutes,
    required this.overBudgetMinutes,
    required List<PreparationWorkloadContribution> contributions,
  }) : contributions = List.unmodifiable(contributions) {
    final budget = dailyPreparationBudgetMinutes;
    if (budget != null && (budget < 25 || budget > 480 || budget % 5 != 0) ||
        reservedPreparationMinutes < 0 ||
        reservedPreparationMinutes > 30000 ||
        remainingBudgetMinutes != null &&
            (remainingBudgetMinutes! < 0 || remainingBudgetMinutes! > 480) ||
        overBudgetMinutes < 0 ||
        overBudgetMinutes > 30000 ||
        contributions.length > 50) {
      throw const DeadlinePlanContractException(
        'Preparation workload detail values are invalid.',
      );
    }
    if (budget == null) {
      if (remainingBudgetMinutes != null || overBudgetMinutes != 0) {
        throw const DeadlinePlanContractException(
          'Preparation workload detail without a budget is inconsistent.',
        );
      }
    } else if (remainingBudgetMinutes !=
            (budget - reservedPreparationMinutes).clamp(0, budget) ||
        overBudgetMinutes !=
            (reservedPreparationMinutes - budget).clamp(0, 30000)) {
      throw const DeadlinePlanContractException(
        'Preparation workload detail arithmetic is inconsistent.',
      );
    }
    if (contributions.map((item) => item.planId).toSet().length !=
            contributions.length ||
        contributions.fold<int>(
              0,
              (total, item) => total + item.reservedPreparationMinutes,
            ) !=
            reservedPreparationMinutes) {
      throw const DeadlinePlanContractException(
        'Preparation workload detail contributions are inconsistent.',
      );
    }
  }

  factory PreparationWorkloadDetail.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'contract_version',
        'origin',
        'generated_at',
        'timezone',
        'local_date',
        'daily_preparation_budget_minutes',
        'reserved_preparation_minutes',
        'remaining_budget_minutes',
        'over_budget_minutes',
        'contributions',
      },
      'preparation workload detail',
    );
    if (json['contract_version'] != preparationWorkloadDetailContractVersion ||
        json['origin'] != 'authenticated_backend') {
      throw const DeadlinePlanContractException(
        'Preparation workload detail provenance is invalid.',
      );
    }
    final rawBudget = json['daily_preparation_budget_minutes'];
    final rawRemaining = json['remaining_budget_minutes'];
    final rawContributions = json['contributions'];
    if (rawBudget != null && rawBudget is! int ||
        rawRemaining != null && rawRemaining is! int ||
        rawContributions is! List ||
        rawContributions.length > 50) {
      throw const DeadlinePlanContractException(
        'Preparation workload detail fields are invalid.',
      );
    }
    final dateText = _requiredDate(
      json['local_date'],
      'workload_detail.local_date',
    );
    return PreparationWorkloadDetail(
      generatedAt: _requiredAwareDateTime(
        json['generated_at'],
        'workload_detail.generated_at',
      ),
      timezone: _requiredString(
        json['timezone'],
        'workload_detail.timezone',
        maxLength: 100,
      ),
      localDate: DateTime.parse('${dateText}T00:00:00Z'),
      dailyPreparationBudgetMinutes: rawBudget as int?,
      reservedPreparationMinutes: _requiredInt(
        json['reserved_preparation_minutes'],
        'workload_detail.reserved_preparation_minutes',
      ),
      remainingBudgetMinutes: rawRemaining as int?,
      overBudgetMinutes: _requiredInt(
        json['over_budget_minutes'],
        'workload_detail.over_budget_minutes',
      ),
      contributions: rawContributions
          .map(
            (value) => PreparationWorkloadContribution.fromJson(
              _requiredStringMap(value, 'workload detail contribution'),
            ),
          )
          .toList(growable: false),
    );
  }

  final DateTime generatedAt;
  final String timezone;
  final DateTime localDate;
  final int? dailyPreparationBudgetMinutes;
  final int reservedPreparationMinutes;
  final int? remainingBudgetMinutes;
  final int overBudgetMinutes;
  final List<PreparationWorkloadContribution> contributions;

  String get localDateKey => _dateOnlyKey(localDate);
}

class PreparationWorkloadContribution {
  const PreparationWorkloadContribution({
    required this.planId,
    required this.title,
    required this.reservedPreparationMinutes,
    required this.blockCount,
  });

  factory PreparationWorkloadContribution.fromJson(
    Map<String, dynamic> json,
  ) {
    _expectExactKeys(
      json,
      const {
        'plan_id',
        'title',
        'reserved_preparation_minutes',
        'block_count',
      },
      'preparation workload contribution',
    );
    final contribution = PreparationWorkloadContribution(
      planId: _requiredUuid(json['plan_id'], 'workload_detail.plan_id'),
      title: _requiredString(
        json['title'],
        'workload_detail.title',
        maxLength: 160,
      ),
      reservedPreparationMinutes: _requiredInt(
        json['reserved_preparation_minutes'],
        'workload_detail.reserved_preparation_minutes',
      ),
      blockCount: _requiredInt(
        json['block_count'],
        'workload_detail.block_count',
      ),
    );
    if (contribution.reservedPreparationMinutes < 5 ||
        contribution.reservedPreparationMinutes > 480 ||
        contribution.blockCount < 1 ||
        contribution.blockCount > 120) {
      throw const DeadlinePlanContractException(
        'Preparation workload contribution values are invalid.',
      );
    }
    return contribution;
  }

  final String planId;
  final String title;
  final int reservedPreparationMinutes;
  final int blockCount;
}

class DeadlinePlanFeed {
  DeadlinePlanFeed({required List<DeadlinePlan> plans})
      : plans = List.unmodifiable(plans);

  factory DeadlinePlanFeed.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'contract_version', 'origin', 'plans'},
      'deadline plan feed',
    );
    _expectEnvelope(json);
    final rawPlans = json['plans'];
    if (rawPlans is! List) {
      throw const DeadlinePlanContractException(
        'Deadline plan feed plans are invalid.',
      );
    }
    if (rawPlans.length > 50) {
      throw const DeadlinePlanContractException(
        'Deadline plan feed exceeds its bounded size.',
      );
    }
    final plans = rawPlans.map((value) {
      final detail = _requiredStringMap(value, 'deadline plan feed item');
      return DeadlinePlan.fromDetailJson(detail);
    }).toList(growable: false);
    if (plans.map((plan) => plan.id).toSet().length != plans.length) {
      throw const DeadlinePlanContractException(
        'Deadline plan feed contains duplicate plans.',
      );
    }
    return DeadlinePlanFeed(plans: plans);
  }

  final List<DeadlinePlan> plans;
}

class DeadlinePlanResponse {
  const DeadlinePlanResponse({required this.plan});

  factory DeadlinePlanResponse.fromJson(Map<String, dynamic> json) {
    _expectEnvelope(json);
    final detail = Map<String, dynamic>.from(json)
      ..remove('contract_version')
      ..remove('origin');
    return DeadlinePlanResponse(plan: DeadlinePlan.fromDetailJson(detail));
  }

  final DeadlinePlan plan;
}

class DeadlinePlan {
  DeadlinePlan({
    required this.record,
    required this.activeRevision,
    required this.pendingRevision,
    required this.progress,
  }) {
    final isActivatedTerminal = record.status == DeadlinePlanStatus.completed ||
        record.status == DeadlinePlanStatus.cancelled &&
            record.currentRevision > 0;
    final isCancelledDraft = record.status == DeadlinePlanStatus.cancelled &&
        record.currentRevision == 0;
    final progressProjection = activeRevision ?? pendingRevision;
    final expectedEstimate = progressProjection?.estimatedTotalMinutes ??
        record.originalEstimatedTotalMinutes;
    final expectedPrior = progressProjection?.creditedPriorMinutes ??
        record.originalCreditedPriorMinutes;

    if (record.status == DeadlinePlanStatus.draft &&
            (activeRevision != null || pendingRevision == null) ||
        record.status == DeadlinePlanStatus.active && activeRevision == null ||
        isActivatedTerminal &&
            (activeRevision == null || pendingRevision != null) ||
        isCancelledDraft &&
            (activeRevision != null || pendingRevision != null) ||
        record.status == DeadlinePlanStatus.active &&
            record.managedTaskId == null ||
        record.managedTaskId != null && record.managedTaskId != record.id ||
        activeRevision != null &&
            (activeRevision!.planId != record.id ||
                activeRevision!.revision != record.currentRevision ||
                activeRevision!.state != DeadlinePlanRevisionState.active) ||
        pendingRevision != null &&
            (pendingRevision!.planId != record.id ||
                pendingRevision!.revision != record.latestRevision ||
                pendingRevision!.state != DeadlinePlanRevisionState.proposed) ||
        activeRevision != null &&
            pendingRevision != null &&
            pendingRevision!.revision <= activeRevision!.revision ||
        progress.estimatedTotalMinutes != expectedEstimate ||
        progress.creditedPriorMinutes != expectedPrior) {
      throw const DeadlinePlanContractException(
        'Deadline plan detail is inconsistent.',
      );
    }
  }

  factory DeadlinePlan.fromDetailJson(Map<String, dynamic> json) {
    _expectRequiredAndOptionalKeys(
      json,
      required: const {'plan', 'progress'},
      optional: const {'active_revision', 'pending_revision'},
      model: 'deadline plan detail',
    );
    return DeadlinePlan(
      record: DeadlinePlanRecord.fromJson(
        _requiredStringMap(json['plan'], 'deadline plan'),
      ),
      activeRevision: _optionalModel(
        json,
        'active_revision',
        DeadlinePlanRevision.fromJson,
      ),
      pendingRevision: _optionalModel(
        json,
        'pending_revision',
        DeadlinePlanRevision.fromJson,
      ),
      progress: DeadlinePlanProgress.fromJson(
        _requiredStringMap(json['progress'], 'deadline plan progress'),
      ),
    );
  }

  final DeadlinePlanRecord record;
  final DeadlinePlanRevision? activeRevision;
  final DeadlinePlanRevision? pendingRevision;
  final DeadlinePlanProgress progress;

  String get id => record.id;
  String get title => record.title;
  DeadlinePlanKind get kind => record.kind;
  DeadlinePlanStatus get status => record.status;
  String? get taskId => record.managedTaskId;
  int get currentRevision => record.currentRevision;
  int get latestRevision => record.latestRevision;
  bool get isDraft => status == DeadlinePlanStatus.draft;
  bool get isActive => status == DeadlinePlanStatus.active;
  bool get isTerminal =>
      status == DeadlinePlanStatus.completed ||
      status == DeadlinePlanStatus.cancelled;
  DeadlinePlanRevision? get displayedRevision =>
      pendingRevision ?? activeRevision;
}

class DeadlinePlanRecord {
  DeadlinePlanRecord({
    required this.id,
    required this.status,
    required this.kind,
    required this.title,
    required this.managedTaskId,
    required this.originalEstimatedTotalMinutes,
    required this.originalCreditedPriorMinutes,
    required this.currentRevision,
    required this.latestRevision,
    required this.createdAt,
    required this.updatedAt,
    required this.completedAt,
    required this.cancelledAt,
  }) {
    if (originalEstimatedTotalMinutes < 30 ||
        originalEstimatedTotalMinutes > 30000 ||
        originalCreditedPriorMinutes < 0 ||
        originalCreditedPriorMinutes >= originalEstimatedTotalMinutes ||
        currentRevision < 0 ||
        latestRevision < 1 ||
        latestRevision > 200 ||
        latestRevision < (currentRevision < 1 ? 1 : currentRevision) ||
        (currentRevision == 0) != (managedTaskId == null) ||
        updatedAt.isBefore(createdAt) ||
        (status == DeadlinePlanStatus.completed) != (completedAt != null) ||
        (status == DeadlinePlanStatus.cancelled) != (cancelledAt != null) ||
        completedAt != null && cancelledAt != null) {
      throw const DeadlinePlanContractException(
        'Deadline plan lifecycle or totals are invalid.',
      );
    }
  }

  factory DeadlinePlanRecord.fromJson(Map<String, dynamic> json) {
    _expectRequiredAndOptionalKeys(
      json,
      required: const {
        'id',
        'status',
        'kind',
        'title',
        'original_estimated_total_minutes',
        'original_credited_prior_minutes',
        'current_revision',
        'latest_revision',
        'created_at',
        'updated_at',
      },
      optional: const {'managed_task_id', 'completed_at', 'cancelled_at'},
      model: 'deadline plan',
    );
    final status = DeadlinePlanStatus.fromCode(json['status']);
    final kind = DeadlinePlanKind.fromCode(json['kind']);
    if (status == null || kind == null) {
      throw const DeadlinePlanContractException(
        'Deadline plan status or kind is invalid.',
      );
    }
    return DeadlinePlanRecord(
      id: _requiredUuid(json['id'], 'plan.id'),
      status: status,
      kind: kind,
      title: _requiredString(json['title'], 'plan.title', maxLength: 160),
      managedTaskId: _optionalUuid(json, 'managed_task_id'),
      originalEstimatedTotalMinutes: _requiredInt(
        json['original_estimated_total_minutes'],
        'plan.original_estimated_total_minutes',
      ),
      originalCreditedPriorMinutes: _requiredInt(
        json['original_credited_prior_minutes'],
        'plan.original_credited_prior_minutes',
      ),
      currentRevision: _requiredInt(
        json['current_revision'],
        'plan.current_revision',
      ),
      latestRevision: _requiredInt(
        json['latest_revision'],
        'plan.latest_revision',
      ),
      createdAt: _requiredAwareDateTime(json['created_at'], 'plan.created_at'),
      updatedAt: _requiredAwareDateTime(json['updated_at'], 'plan.updated_at'),
      completedAt: _optionalAwareDateTime(json, 'completed_at'),
      cancelledAt: _optionalAwareDateTime(json, 'cancelled_at'),
    );
  }

  final String id;
  final DeadlinePlanStatus status;
  final DeadlinePlanKind kind;
  final String title;
  final String? managedTaskId;
  final int originalEstimatedTotalMinutes;
  final int originalCreditedPriorMinutes;
  final int currentRevision;
  final int latestRevision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  bool get isTerminalStatus =>
      status == DeadlinePlanStatus.completed ||
      status == DeadlinePlanStatus.cancelled;
}

class DeadlinePlanProgress {
  const DeadlinePlanProgress({
    required this.estimatedTotalMinutes,
    required this.creditedPriorMinutes,
    required this.trackedFocusMinutes,
    required this.accountedMinutes,
    required this.remainingMinutes,
    required this.completionSuggested,
  });

  factory DeadlinePlanProgress.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'estimated_total_minutes',
        'credited_prior_minutes',
        'tracked_focus_minutes',
        'accounted_minutes',
        'remaining_minutes',
        'completion_suggested',
      },
      'deadline plan progress',
    );
    final estimated = _requiredInt(
      json['estimated_total_minutes'],
      'progress.estimated_total_minutes',
    );
    final prior = _requiredInt(
      json['credited_prior_minutes'],
      'progress.credited_prior_minutes',
    );
    final focus = _requiredInt(
      json['tracked_focus_minutes'],
      'progress.tracked_focus_minutes',
    );
    final accounted = _requiredInt(
      json['accounted_minutes'],
      'progress.accounted_minutes',
    );
    final remaining = _requiredInt(
      json['remaining_minutes'],
      'progress.remaining_minutes',
    );
    final suggested = json['completion_suggested'];
    if ([estimated, prior, focus, accounted, remaining]
            .any((value) => value < 0) ||
        accounted != (prior + focus).clamp(0, estimated) ||
        remaining != (estimated - accounted).clamp(0, estimated) ||
        suggested is! bool ||
        suggested != (remaining == 0)) {
      throw const DeadlinePlanContractException(
        'Deadline plan progress is inconsistent.',
      );
    }
    return DeadlinePlanProgress(
      estimatedTotalMinutes: estimated,
      creditedPriorMinutes: prior,
      trackedFocusMinutes: focus,
      accountedMinutes: accounted,
      remainingMinutes: remaining,
      completionSuggested: suggested,
    );
  }

  final int estimatedTotalMinutes;
  final int creditedPriorMinutes;
  final int trackedFocusMinutes;
  final int accountedMinutes;
  final int remainingMinutes;
  final bool completionSuggested;
}

class DeadlinePlanRevision {
  DeadlinePlanRevision({
    required this.planId,
    required this.revision,
    required this.baseRevision,
    required this.state,
    required this.kind,
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
    required this.sourceStatus,
    required this.useCalendarAvailability,
    required this.availabilityConnectionId,
    required this.availabilityImportId,
    required this.timezone,
    required this.bestEnergyWindow,
    required this.planningFingerprint,
    required this.studySetupRevision,
    required this.recoveryMinutes,
    required this.trackedFocusMinutesAtProposal,
    required this.remainingMinutesAtProposal,
    required this.plannedMinutes,
    required this.unscheduledMinutes,
    required this.createdAt,
    required this.activatedAt,
    required this.supersededAt,
    required List<DeadlinePlanBlock> blocks,
  }) : blocks = List.unmodifiable(blocks) {
    if (revision < 1 ||
        revision > 200 ||
        baseRevision < 0 ||
        baseRevision > 199 ||
        revision != baseRevision + 1 ||
        estimatedTotalMinutes < 30 ||
        estimatedTotalMinutes > 30000 ||
        creditedPriorMinutes < 0 ||
        creditedPriorMinutes >= estimatedTotalMinutes ||
        preferredSessionMinutes < 25 ||
        preferredSessionMinutes > 180 ||
        maxDailyMinutes < preferredSessionMinutes ||
        maxDailyMinutes > 480 ||
        bufferDays < 0 ||
        bufferDays > 7 ||
        trackedFocusMinutesAtProposal < 0 ||
        remainingMinutesAtProposal !=
            (estimatedTotalMinutes -
                    creditedPriorMinutes -
                    trackedFocusMinutesAtProposal)
                .clamp(0, estimatedTotalMinutes) ||
        plannedMinutes < 0 ||
        unscheduledMinutes < 0 ||
        plannedMinutes + unscheduledMinutes != remainingMinutesAtProposal ||
        blocks.fold<int>(0, (sum, block) => sum + block.plannedMinutes) !=
            plannedMinutes ||
        blocks.length > 120 ||
        blocks.map((block) => block.id).toSet().length != blocks.length ||
        blocks.map((block) => block.sequence).toSet().length != blocks.length ||
        !_hasContiguousSequences(blocks) ||
        (studySetupRevision == null
            ? recoveryMinutes != 0 ||
                blocks.any((block) => block.recoveryMinutes != 0)
            : recoveryMinutes < 5 ||
                recoveryMinutes > 60 ||
                recoveryMinutes % 5 != 0 ||
                blocks.any(
                  (block) =>
                      block.recoveryMinutes != recoveryMinutes ||
                      block.plannedMinutes > preferredSessionMinutes,
                ) ||
                blocks
                        .where(
                          (block) =>
                              block.plannedMinutes < preferredSessionMinutes,
                        )
                        .length >
                    1 ||
                blocks.indexWhere(
                          (block) =>
                              block.plannedMinutes < preferredSessionMinutes,
                        ) >=
                        0 &&
                    blocks.indexWhere(
                          (block) =>
                              block.plannedMinutes < preferredSessionMinutes,
                        ) !=
                        blocks.length - 1) ||
        sourceKind == DeadlinePlanSourceKind.manual &&
            (sourceCalendarEventId != null ||
                sourceCalendarEventFingerprint != null ||
                sourceStatus != DeadlinePlanSourceStatus.notApplicable) ||
        sourceKind == DeadlinePlanSourceKind.calendarEvent &&
            (sourceCalendarEventId == null ||
                sourceCalendarEventFingerprint == null ||
                sourceStatus == DeadlinePlanSourceStatus.notApplicable) ||
        (availabilityConnectionId == null) != (availabilityImportId == null) ||
        useCalendarAvailability != (availabilityConnectionId != null) ||
        state == DeadlinePlanRevisionState.proposed &&
            (activatedAt != null || supersededAt != null) ||
        state == DeadlinePlanRevisionState.active &&
            (activatedAt == null || supersededAt != null) ||
        state == DeadlinePlanRevisionState.superseded && supersededAt == null) {
      throw const DeadlinePlanContractException(
        'Deadline plan revision is inconsistent.',
      );
    }
  }

  factory DeadlinePlanRevision.fromJson(Map<String, dynamic> json) {
    _expectRequiredAndOptionalKeys(
      json,
      required: const {
        'plan_id',
        'revision',
        'base_revision',
        'state',
        'kind',
        'title',
        'deadline_at',
        'estimated_total_minutes',
        'credited_prior_minutes',
        'preferred_session_minutes',
        'max_daily_minutes',
        'planning_start_on',
        'buffer_days',
        'source_kind',
        'source_status',
        'use_calendar_availability',
        'timezone',
        'best_energy_window',
        'planning_fingerprint',
        'recovery_minutes',
        'tracked_focus_minutes_at_proposal',
        'remaining_minutes_at_proposal',
        'planned_minutes',
        'unscheduled_minutes',
        'created_at',
        'blocks',
      },
      optional: const {
        'source_calendar_event_id',
        'source_calendar_event_fingerprint',
        'activated_at',
        'superseded_at',
        'availability_connection_id',
        'availability_import_id',
        'study_setup_revision',
      },
      model: 'deadline plan revision',
    );
    final state = DeadlinePlanRevisionState.fromCode(json['state']);
    final kind = DeadlinePlanKind.fromCode(json['kind']);
    final sourceKind = DeadlinePlanSourceKind.fromCode(json['source_kind']);
    final sourceStatus = DeadlinePlanSourceStatus.fromCode(
      json['source_status'],
    );
    final rawBlocks = json['blocks'];
    if (state == null ||
        kind == null ||
        sourceKind == null ||
        sourceStatus == null ||
        json['use_calendar_availability'] is! bool ||
        rawBlocks is! List) {
      throw const DeadlinePlanContractException(
        'Deadline plan revision fields are invalid.',
      );
    }
    return DeadlinePlanRevision(
      planId: _requiredUuid(json['plan_id'], 'revision.plan_id'),
      revision: _requiredInt(json['revision'], 'revision.revision'),
      baseRevision:
          _requiredInt(json['base_revision'], 'revision.base_revision'),
      state: state,
      kind: kind,
      title: _requiredString(json['title'], 'revision.title', maxLength: 160),
      deadlineAt: _requiredAwareDateTime(
        json['deadline_at'],
        'revision.deadline_at',
      ),
      estimatedTotalMinutes: _requiredInt(
        json['estimated_total_minutes'],
        'revision.estimated_total_minutes',
      ),
      creditedPriorMinutes: _requiredInt(
        json['credited_prior_minutes'],
        'revision.credited_prior_minutes',
      ),
      preferredSessionMinutes: _requiredInt(
        json['preferred_session_minutes'],
        'revision.preferred_session_minutes',
      ),
      maxDailyMinutes: _requiredInt(
        json['max_daily_minutes'],
        'revision.max_daily_minutes',
      ),
      planningStartOn: _requiredDate(
        json['planning_start_on'],
        'revision.planning_start_on',
      ),
      bufferDays: _requiredInt(json['buffer_days'], 'revision.buffer_days'),
      sourceKind: sourceKind,
      sourceCalendarEventId: _optionalUuid(
        json,
        'source_calendar_event_id',
      ),
      sourceCalendarEventFingerprint: _optionalFingerprint(
        json,
        'source_calendar_event_fingerprint',
      ),
      sourceStatus: sourceStatus,
      useCalendarAvailability: json['use_calendar_availability'] as bool,
      availabilityConnectionId: _optionalUuid(
        json,
        'availability_connection_id',
      ),
      availabilityImportId: _optionalUuid(
        json,
        'availability_import_id',
      ),
      timezone: _requiredString(
        json['timezone'],
        'revision.timezone',
        maxLength: 100,
      ),
      bestEnergyWindow: _requiredEnergyWindow(json['best_energy_window']),
      planningFingerprint: _requiredFingerprint(
        json['planning_fingerprint'],
        'revision.planning_fingerprint',
      ),
      studySetupRevision: _optionalInt(json, 'study_setup_revision'),
      recoveryMinutes: _requiredInt(
        json['recovery_minutes'],
        'revision.recovery_minutes',
      ),
      trackedFocusMinutesAtProposal: _requiredInt(
        json['tracked_focus_minutes_at_proposal'],
        'revision.tracked_focus_minutes_at_proposal',
      ),
      remainingMinutesAtProposal: _requiredInt(
        json['remaining_minutes_at_proposal'],
        'revision.remaining_minutes_at_proposal',
      ),
      plannedMinutes: _requiredInt(
        json['planned_minutes'],
        'revision.planned_minutes',
      ),
      unscheduledMinutes: _requiredInt(
        json['unscheduled_minutes'],
        'revision.unscheduled_minutes',
      ),
      createdAt: _requiredAwareDateTime(
        json['created_at'],
        'revision.created_at',
      ),
      activatedAt: _optionalAwareDateTime(json, 'activated_at'),
      supersededAt: _optionalAwareDateTime(json, 'superseded_at'),
      blocks: rawBlocks.map((value) {
        return DeadlinePlanBlock.fromJson(
          _requiredStringMap(value, 'deadline plan block'),
        );
      }).toList(growable: false),
    );
  }

  final String planId;
  final int revision;
  final int baseRevision;
  final DeadlinePlanRevisionState state;
  final DeadlinePlanKind kind;
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
  final DeadlinePlanSourceStatus sourceStatus;
  final bool useCalendarAvailability;
  final String? availabilityConnectionId;
  final String? availabilityImportId;
  final String timezone;
  final String bestEnergyWindow;
  final String planningFingerprint;
  final int? studySetupRevision;
  final int recoveryMinutes;
  final int trackedFocusMinutesAtProposal;
  final int remainingMinutesAtProposal;
  final int plannedMinutes;
  final int unscheduledMinutes;
  final DateTime createdAt;
  final DateTime? activatedAt;
  final DateTime? supersededAt;
  final List<DeadlinePlanBlock> blocks;
}

bool _hasContiguousSequences(List<DeadlinePlanBlock> blocks) {
  if (blocks.isEmpty) return true;
  final sequences = blocks.map((block) => block.sequence).toList()..sort();
  for (var index = 0; index < sequences.length; index++) {
    if (sequences[index] != index + 1) return false;
  }
  return true;
}

class DeadlinePlanBlock {
  DeadlinePlanBlock({
    required this.id,
    required this.sequence,
    required this.startsAt,
    required this.endsAt,
    required this.localDate,
    required this.localStartTime,
    required this.localEndTime,
    required this.plannedMinutes,
    required this.recoveryMinutes,
    required this.reservedEndsAt,
    required this.creditedTrackedMinutes,
    required this.state,
  }) {
    if (sequence < 1 ||
        sequence > 120 ||
        !endsAt.isAfter(startsAt) ||
        endsAt.difference(startsAt) != Duration(minutes: plannedMinutes) ||
        plannedMinutes < 5 ||
        plannedMinutes > 240 ||
        recoveryMinutes < 0 ||
        recoveryMinutes > 60 ||
        recoveryMinutes % 5 != 0 ||
        reservedEndsAt.difference(endsAt) !=
            Duration(minutes: recoveryMinutes) ||
        creditedTrackedMinutes < 0 ||
        creditedTrackedMinutes > plannedMinutes) {
      throw const DeadlinePlanContractException(
        'Deadline plan block interval is invalid.',
      );
    }
  }

  factory DeadlinePlanBlock.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'id',
        'sequence',
        'starts_at',
        'ends_at',
        'local_date',
        'local_start_time',
        'local_end_time',
        'planned_minutes',
        'recovery_minutes',
        'reserved_ends_at',
        'credited_tracked_minutes',
        'state',
      },
      'deadline plan block',
    );
    final state = DeadlinePlanBlockState.fromCode(json['state']);
    if (state == null) {
      throw const DeadlinePlanContractException(
        'Deadline plan block state is invalid.',
      );
    }
    return DeadlinePlanBlock(
      id: _requiredUuid(json['id'], 'block.id'),
      sequence: _requiredInt(json['sequence'], 'block.sequence'),
      startsAt: _requiredAwareDateTime(json['starts_at'], 'block.starts_at'),
      endsAt: _requiredAwareDateTime(json['ends_at'], 'block.ends_at'),
      localDate: _requiredDate(json['local_date'], 'block.local_date'),
      localStartTime: _requiredTime(
        json['local_start_time'],
        'block.local_start_time',
      ),
      localEndTime: _requiredTime(
        json['local_end_time'],
        'block.local_end_time',
      ),
      plannedMinutes: _requiredInt(
        json['planned_minutes'],
        'block.planned_minutes',
      ),
      recoveryMinutes: _requiredInt(
        json['recovery_minutes'],
        'block.recovery_minutes',
      ),
      reservedEndsAt: _requiredAwareDateTime(
        json['reserved_ends_at'],
        'block.reserved_ends_at',
      ),
      creditedTrackedMinutes: _requiredInt(
        json['credited_tracked_minutes'],
        'block.credited_tracked_minutes',
      ),
      state: state,
    );
  }

  final String id;
  final int sequence;
  final DateTime startsAt;
  final DateTime endsAt;
  final String localDate;
  final String localStartTime;
  final String localEndTime;
  final int plannedMinutes;
  final int recoveryMinutes;
  final DateTime reservedEndsAt;
  final int creditedTrackedMinutes;
  final DeadlinePlanBlockState state;
}

String _requiredEnergyWindow(Object? value) {
  const supported = {
    'early_morning',
    'morning',
    'afternoon',
    'evening',
    'variable',
  };
  final result = _requiredString(
    value,
    'revision.best_energy_window',
    maxLength: 40,
  );
  if (!supported.contains(result)) {
    throw const DeadlinePlanContractException(
      'Deadline plan energy window is invalid.',
    );
  }
  return result;
}

class DeadlinePlanProposalDraft {
  DeadlinePlanProposalDraft({
    required this.planId,
    required this.baseRevision,
    required this.kind,
    required String title,
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
  }) : title = title.trim() {
    validate();
  }

  final String planId;
  final int baseRevision;
  final DeadlinePlanKind kind;
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

  void validate() {
    if (!isDeadlinePlanUuid(planId) ||
        baseRevision < 0 ||
        title.isEmpty ||
        title.runes.length > 160 ||
        estimatedTotalMinutes < 30 ||
        estimatedTotalMinutes > 30000 ||
        creditedPriorMinutes < 0 ||
        creditedPriorMinutes >= estimatedTotalMinutes ||
        preferredSessionMinutes < 25 ||
        preferredSessionMinutes > 180 ||
        maxDailyMinutes < preferredSessionMinutes ||
        maxDailyMinutes > 480 ||
        !_isDate(planningStartOn) ||
        bufferDays < 0 ||
        bufferDays > 7 ||
        sourceKind == DeadlinePlanSourceKind.manual &&
            (sourceCalendarEventId != null ||
                sourceCalendarEventFingerprint != null) ||
        sourceKind == DeadlinePlanSourceKind.calendarEvent &&
            (sourceCalendarEventId == null ||
                !isDeadlinePlanUuid(sourceCalendarEventId!) ||
                sourceCalendarEventFingerprint == null ||
                !_fingerprintPattern.hasMatch(
                  sourceCalendarEventFingerprint!,
                ))) {
      throw const DeadlinePlanAccessException(
        'Preparation plan values are invalid.',
      );
    }
  }

  Map<String, dynamic> toJson({required String requestId}) => {
        'request_id': requestId,
        'plan_id': planId,
        'base_revision': baseRevision,
        'kind': kind.code,
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

class DeadlinePlanContractException implements Exception {
  const DeadlinePlanContractException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DeadlinePlanAccessException implements Exception {
  const DeadlinePlanAccessException(this.message);
  final String message;
  @override
  String toString() => message;
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _fingerprintPattern = RegExp(r'^[0-9a-f]{64}$');
final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _timePattern = RegExp(
  r'^([01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,6})?$',
);
final _awarePattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$',
);

bool isDeadlinePlanUuid(String value) => _uuidPattern.hasMatch(value);

bool isDeadlinePlanDate(String value) => _isDate(value);

void _expectEnvelope(Map<String, dynamic> json) {
  if (json['contract_version'] != deadlinePlanContractVersion ||
      json['origin'] != 'authenticated_backend') {
    throw const DeadlinePlanContractException(
      'Deadline plan response provenance is invalid.',
    );
  }
}

void _expectExactKeys(
  Map<String, dynamic> json,
  Set<String> keys,
  String model,
) {
  if (json.keys.toSet().difference(keys).isNotEmpty ||
      keys.difference(json.keys.toSet()).isNotEmpty) {
    throw DeadlinePlanContractException('$model fields are invalid.');
  }
}

void _expectRequiredAndOptionalKeys(
  Map<String, dynamic> json, {
  required Set<String> required,
  required Set<String> optional,
  required String model,
}) {
  if (required.difference(json.keys.toSet()).isNotEmpty ||
      json.keys.toSet().difference({...required, ...optional}).isNotEmpty ||
      optional.any((key) => json.containsKey(key) && json[key] == null)) {
    throw DeadlinePlanContractException('$model fields are invalid.');
  }
}

Map<String, dynamic> _requiredStringMap(Object? value, String field) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw DeadlinePlanContractException('$field is invalid.');
  }
  return Map<String, dynamic>.from(value);
}

String _requiredUuid(Object? value, String field) {
  if (value is! String || !isDeadlinePlanUuid(value)) {
    throw DeadlinePlanContractException('$field is invalid.');
  }
  return value;
}

String? _optionalUuid(Map<String, dynamic> json, String key) =>
    json.containsKey(key) ? _requiredUuid(json[key], key) : null;

String _requiredFingerprint(Object? value, String field) {
  if (value is! String || !_fingerprintPattern.hasMatch(value)) {
    throw DeadlinePlanContractException('$field is invalid.');
  }
  return value;
}

String? _optionalFingerprint(Map<String, dynamic> json, String key) =>
    json.containsKey(key) ? _requiredFingerprint(json[key], key) : null;

String _requiredString(Object? value, String field, {required int maxLength}) {
  if (value is! String ||
      value.trim() != value ||
      value.isEmpty ||
      value.runes.length > maxLength) {
    throw DeadlinePlanContractException('$field is invalid.');
  }
  return value;
}

int _requiredInt(Object? value, String field) {
  if (value is! int) {
    throw DeadlinePlanContractException('$field is invalid.');
  }
  return value;
}

int? _optionalInt(Map<String, dynamic> json, String key) =>
    json.containsKey(key) ? _requiredInt(json[key], key) : null;

DateTime _requiredAwareDateTime(Object? value, String field) {
  if (value is! String || !_awarePattern.hasMatch(value)) {
    throw DeadlinePlanContractException('$field is invalid.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw DeadlinePlanContractException('$field is invalid.');
  }
  return parsed;
}

DateTime? _optionalAwareDateTime(Map<String, dynamic> json, String key) =>
    json.containsKey(key) ? _requiredAwareDateTime(json[key], key) : null;

String _requiredDate(Object? value, String field) {
  if (value is! String || !_isDate(value)) {
    throw DeadlinePlanContractException('$field is invalid.');
  }
  return value;
}

bool _isDate(String value) {
  if (!_datePattern.hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null &&
      parsed.year.toString().padLeft(4, '0') == value.substring(0, 4) &&
      parsed.month.toString().padLeft(2, '0') == value.substring(5, 7) &&
      parsed.day.toString().padLeft(2, '0') == value.substring(8, 10);
}

String _dateOnlyKey(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-$month-$day';
}

String _requiredTime(Object? value, String field) {
  if (value is! String || !_timePattern.hasMatch(value)) {
    throw DeadlinePlanContractException('$field is invalid.');
  }
  return value;
}

T? _optionalModel<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Map<String, dynamic>) parser,
) {
  if (!json.containsKey(key)) return null;
  return parser(_requiredStringMap(json[key], key));
}
