const weeklyReviewContractVersion = 'weekly-review-v1';

enum WeeklyReviewOrigin { authenticatedBackend, localDemo }

enum WeeklyReviewFreshness {
  notReady('not_ready'),
  missing('missing'),
  current('current'),
  stale('stale');

  const WeeklyReviewFreshness(this.code);

  final String code;

  static WeeklyReviewFreshness? fromCode(Object? value) {
    for (final freshness in values) {
      if (freshness.code == value) return freshness;
    }
    return null;
  }
}

enum WeeklyReviewDataQuality {
  insufficient('insufficient'),
  partial('partial'),
  sufficient('sufficient');

  const WeeklyReviewDataQuality(this.code);

  final String code;

  static WeeklyReviewDataQuality? fromCode(Object? value) {
    for (final quality in values) {
      if (quality.code == value) return quality;
    }
    return null;
  }
}

enum WeeklyReviewOperation {
  keep('keep'),
  shrink('shrink'),
  pause('pause'),
  replace('replace'),
  archive('archive'),
  defer('defer');

  const WeeklyReviewOperation(this.code);

  final String code;

  static WeeklyReviewOperation? fromCode(Object? value) {
    for (final operation in values) {
      if (operation.code == value) return operation;
    }
    return null;
  }
}

enum WeeklyReviewOwnership {
  manual('manual'),
  setup('setup');

  const WeeklyReviewOwnership(this.code);

  final String code;

  static WeeklyReviewOwnership? fromCode(Object? value) {
    for (final ownership in values) {
      if (ownership.code == value) return ownership;
    }
    return null;
  }
}

enum WeeklyReviewApplicationMode {
  directHabit('direct_habit'),
  settingsSetup('settings_setup'),
  stagedOnly('staged_only'),
  none('none');

  const WeeklyReviewApplicationMode(this.code);

  final String code;

  static WeeklyReviewApplicationMode? fromCode(Object? value) {
    for (final mode in values) {
      if (mode.code == value) return mode;
    }
    return null;
  }
}

enum WeeklyReviewHabitLifecycle {
  active('active'),
  paused('paused'),
  archived('archived');

  const WeeklyReviewHabitLifecycle(this.code);

  final String code;

  static WeeklyReviewHabitLifecycle? fromCode(Object? value) {
    for (final lifecycle in values) {
      if (lifecycle.code == value) return lifecycle;
    }
    return null;
  }
}

enum WeeklyReviewCadenceKind {
  daily('daily'),
  weekdays('weekdays'),
  weeklyTarget('weekly_target');

  const WeeklyReviewCadenceKind(this.code);

  final String code;

  static WeeklyReviewCadenceKind? fromCode(Object? value) {
    for (final kind in values) {
      if (kind.code == value) return kind;
    }
    return null;
  }
}

class WeeklyReviewFeed {
  WeeklyReviewFeed({
    required this.origin,
    required this.periodKey,
    required this.startsOn,
    required this.endsOn,
    required this.timezone,
    required this.freshness,
    required this.needsGeneration,
    required List<String> staleReasons,
    required this.review,
  }) : staleReasons = List.unmodifiable(staleReasons) {
    _validate();
  }

  factory WeeklyReviewFeed.localDemo({DateTime? now}) {
    final value = now ?? DateTime.now();
    final day = DateTime(value.year, value.month, value.day);
    final currentMonday = _addCalendarDays(
      day,
      -(day.weekday - DateTime.monday),
    );
    final startsOn = _addCalendarDays(currentMonday, -7);
    return WeeklyReviewFeed(
      origin: WeeklyReviewOrigin.localDemo,
      periodKey: _isoPeriodKey(startsOn),
      startsOn: startsOn,
      endsOn: _addCalendarDays(startsOn, 6),
      timezone: 'local-demo',
      freshness: WeeklyReviewFreshness.notReady,
      needsGeneration: false,
      staleReasons: const [],
      review: null,
    );
  }

  factory WeeklyReviewFeed.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'contract_version',
        'period_key',
        'starts_on',
        'ends_on',
        'timezone',
        'freshness',
        'needs_generation',
        'stale_reasons',
        'review',
      },
      'weekly review response',
    );
    if (json['contract_version'] != weeklyReviewContractVersion) {
      throw const WeeklyReviewContractException(
        'Unsupported weekly review contract.',
      );
    }
    final freshness = WeeklyReviewFreshness.fromCode(json['freshness']);
    final needsGeneration = json['needs_generation'];
    final staleReasons = json['stale_reasons'];
    final rawReview = json['review'];
    if (freshness == null ||
        needsGeneration is! bool ||
        staleReasons is! List ||
        rawReview != null && rawReview is! Map) {
      throw const WeeklyReviewContractException(
        'Weekly review response fields are invalid.',
      );
    }
    if (staleReasons.length > 8 ||
        staleReasons.any(
          (value) => !_isBoundedTrimmedString(value, maxLength: 200),
        )) {
      throw const WeeklyReviewContractException(
        'Weekly review stale reasons are invalid.',
      );
    }
    return WeeklyReviewFeed(
      origin: WeeklyReviewOrigin.authenticatedBackend,
      periodKey: _requiredPeriodKey(json['period_key']),
      startsOn: _requiredDate(json['starts_on'], 'starts_on'),
      endsOn: _requiredDate(json['ends_on'], 'ends_on'),
      timezone: _requiredString(json['timezone'], 'timezone', maxLength: 100),
      freshness: freshness,
      needsGeneration: needsGeneration,
      staleReasons: staleReasons.cast<String>(),
      review: rawReview == null
          ? null
          : WeeklyReview.fromJson(Map<String, dynamic>.from(rawReview)),
    );
  }

  final WeeklyReviewOrigin origin;
  final String periodKey;
  final DateTime startsOn;
  final DateTime endsOn;
  final String timezone;
  final WeeklyReviewFreshness freshness;
  final bool needsGeneration;
  final List<String> staleReasons;
  final WeeklyReview? review;

  void _validate() {
    if (startsOn.weekday != DateTime.monday ||
        !_sameDate(endsOn, _addCalendarDays(startsOn, 6)) ||
        _isoPeriodKey(startsOn) != periodKey) {
      throw const WeeklyReviewContractException(
        'Weekly review period is invalid.',
      );
    }
    final hasReview = review != null;
    final validState = switch (freshness) {
      WeeklyReviewFreshness.notReady =>
        !needsGeneration && !hasReview && staleReasons.isEmpty,
      WeeklyReviewFreshness.missing =>
        needsGeneration && !hasReview && staleReasons.isEmpty,
      WeeklyReviewFreshness.current =>
        !needsGeneration && hasReview && staleReasons.isEmpty,
      WeeklyReviewFreshness.stale =>
        needsGeneration && hasReview && staleReasons.isNotEmpty,
    };
    if (!validState) {
      throw const WeeklyReviewContractException(
        'Weekly review freshness and payload do not match.',
      );
    }
    final value = review;
    if (value != null &&
        (!_sameDate(value.provenance.evidenceWindow.startsOn, startsOn) ||
            !_sameDate(value.provenance.evidenceWindow.endsOn, endsOn))) {
      throw const WeeklyReviewContractException(
        'Weekly review evidence window does not match its period.',
      );
    }
  }
}

class WeeklyReview {
  WeeklyReview({
    required this.id,
    required this.dataQuality,
    required this.narrative,
    required this.facts,
    required List<WeeklyReviewProposal> proposals,
    required List<WeeklyReviewEvidenceRef> evidenceRefs,
    required this.provenance,
    required this.generatedAt,
    required this.updatedAt,
  })  : proposals = List.unmodifiable(proposals),
        evidenceRefs = List.unmodifiable(evidenceRefs) {
    if (proposals.length > 2 || evidenceRefs.length > 40) {
      throw const WeeklyReviewContractException(
        'Weekly review list bounds are invalid.',
      );
    }
    if (proposals.map((proposal) => proposal.id).toSet().length !=
        proposals.length) {
      throw const WeeklyReviewContractException(
        'Weekly review proposal identities must be unique.',
      );
    }
    if (proposals.map((proposal) => proposal.targetId).toSet().length !=
        proposals.length) {
      throw const WeeklyReviewContractException(
        'Weekly review proposal targets must be unique.',
      );
    }
  }

  factory WeeklyReview.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'id',
        'data_quality',
        'narrative',
        'facts',
        'proposals',
        'evidence_refs',
        'provenance',
        'generated_at',
        'updated_at',
      },
      'weekly review',
    );
    final quality = WeeklyReviewDataQuality.fromCode(json['data_quality']);
    final rawFacts = json['facts'];
    final rawProposals = json['proposals'];
    final rawEvidence = json['evidence_refs'];
    final rawProvenance = json['provenance'];
    if (quality == null ||
        rawFacts is! Map ||
        rawProposals is! List ||
        rawEvidence is! List ||
        rawProvenance is! Map) {
      throw const WeeklyReviewContractException(
        'Weekly review fields are invalid.',
      );
    }
    return WeeklyReview(
      id: _requiredString(json['id'], 'review.id', maxLength: 200),
      dataQuality: quality,
      narrative: _requiredString(
        json['narrative'],
        'review.narrative',
        maxLength: 500,
      ),
      facts: WeeklyReviewFacts.fromJson(Map<String, dynamic>.from(rawFacts)),
      proposals: rawProposals.map(_proposalFromObject).toList(),
      evidenceRefs: rawEvidence.map(_evidenceFromObject).toList(),
      provenance: WeeklyReviewProvenance.fromJson(
        Map<String, dynamic>.from(rawProvenance),
      ),
      generatedAt: _requiredDateTime(json['generated_at'], 'generated_at'),
      updatedAt: _requiredDateTime(json['updated_at'], 'updated_at'),
    );
  }

  final String id;
  final WeeklyReviewDataQuality dataQuality;
  final String narrative;
  final WeeklyReviewFacts facts;
  final List<WeeklyReviewProposal> proposals;
  final List<WeeklyReviewEvidenceRef> evidenceRefs;
  final WeeklyReviewProvenance provenance;
  final DateTime generatedAt;
  final DateTime updatedAt;
}

class WeeklyReviewFacts {
  const WeeklyReviewFacts({
    required this.tasks,
    required this.habits,
    required this.focus,
    required this.recovery,
    required this.feedback,
  });

  factory WeeklyReviewFacts.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'tasks', 'habits', 'focus', 'recovery', 'feedback'},
      'weekly review facts',
    );
    return WeeklyReviewFacts(
      tasks: WeeklyTaskFacts.fromJson(_requiredMap(json['tasks'], 'tasks')),
      habits: WeeklyHabitFacts.fromJson(_requiredMap(json['habits'], 'habits')),
      focus: WeeklyFocusFacts.fromJson(_requiredMap(json['focus'], 'focus')),
      recovery: WeeklyRecoveryFacts.fromJson(
        _requiredMap(json['recovery'], 'recovery'),
      ),
      feedback: WeeklyFeedbackFacts.fromJson(
        _requiredMap(json['feedback'], 'feedback'),
      ),
    );
  }

  final WeeklyTaskFacts tasks;
  final WeeklyHabitFacts habits;
  final WeeklyFocusFacts focus;
  final WeeklyRecoveryFacts recovery;
  final WeeklyFeedbackFacts feedback;
}

class WeeklyTaskFacts {
  const WeeklyTaskFacts({
    required this.completed,
    required this.carried,
    required this.overdueCarried,
    required this.cancelled,
    required this.goalLinkedCompleted,
  });

  factory WeeklyTaskFacts.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'completed',
        'carried',
        'overdue_carried',
        'cancelled',
        'goal_linked_completed',
      },
      'weekly task facts',
    );
    return WeeklyTaskFacts(
      completed: _nonNegativeInt(json['completed'], 'tasks.completed'),
      carried: _nonNegativeInt(json['carried'], 'tasks.carried'),
      overdueCarried: _nonNegativeInt(
        json['overdue_carried'],
        'tasks.overdue_carried',
      ),
      cancelled: _nonNegativeInt(json['cancelled'], 'tasks.cancelled'),
      goalLinkedCompleted: _nonNegativeInt(
        json['goal_linked_completed'],
        'tasks.goal_linked_completed',
      ),
    );
  }

  final int completed;
  final int carried;
  final int overdueCarried;
  final int cancelled;
  final int goalLinkedCompleted;
}

class WeeklyHabitFacts {
  const WeeklyHabitFacts({
    required this.active,
    required this.paused,
    required this.archived,
    required this.stableDefinitions,
    required this.changedDefinitions,
    required this.scheduledOpportunities,
    required this.completed,
    required this.skipped,
    required this.missed,
    required this.recoveryOpen,
    required this.unknown,
  });

  factory WeeklyHabitFacts.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'active',
        'paused',
        'archived',
        'stable_definitions',
        'changed_definitions',
        'scheduled_opportunities',
        'completed',
        'skipped',
        'missed',
        'recovery_open',
        'unknown',
      },
      'weekly habit facts',
    );
    return WeeklyHabitFacts(
      active: _nonNegativeInt(json['active'], 'habits.active'),
      paused: _nonNegativeInt(json['paused'], 'habits.paused'),
      archived: _nonNegativeInt(json['archived'], 'habits.archived'),
      stableDefinitions: _nonNegativeInt(
        json['stable_definitions'],
        'habits.stable_definitions',
      ),
      changedDefinitions: _nonNegativeInt(
        json['changed_definitions'],
        'habits.changed_definitions',
      ),
      scheduledOpportunities: _nonNegativeInt(
        json['scheduled_opportunities'],
        'habits.scheduled_opportunities',
      ),
      completed: _nonNegativeInt(json['completed'], 'habits.completed'),
      skipped: _nonNegativeInt(json['skipped'], 'habits.skipped'),
      missed: _nonNegativeInt(json['missed'], 'habits.missed'),
      recoveryOpen: _nonNegativeInt(
        json['recovery_open'],
        'habits.recovery_open',
      ),
      unknown: _nonNegativeInt(json['unknown'], 'habits.unknown'),
    );
  }

  final int active;
  final int paused;
  final int archived;
  final int stableDefinitions;
  final int changedDefinitions;
  final int scheduledOpportunities;
  final int completed;
  final int skipped;
  final int missed;
  final int recoveryOpen;
  final int unknown;
}

class WeeklyFocusFacts {
  const WeeklyFocusFacts({
    required this.completedSessions,
    required this.abandonedSessions,
    required this.activeSessions,
    required this.actualMinutes,
  });

  factory WeeklyFocusFacts.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'completed_sessions',
        'abandoned_sessions',
        'active_sessions',
        'actual_minutes',
      },
      'weekly focus facts',
    );
    return WeeklyFocusFacts(
      completedSessions: _nonNegativeInt(
        json['completed_sessions'],
        'focus.completed_sessions',
      ),
      abandonedSessions: _nonNegativeInt(
        json['abandoned_sessions'],
        'focus.abandoned_sessions',
      ),
      activeSessions: _nonNegativeInt(
        json['active_sessions'],
        'focus.active_sessions',
      ),
      actualMinutes: _nonNegativeInt(
        json['actual_minutes'],
        'focus.actual_minutes',
      ),
    );
  }

  final int completedSessions;
  final int abandonedSessions;
  final int activeSessions;
  final int actualMinutes;
}

class WeeklyRecoveryFacts {
  WeeklyRecoveryFacts({
    required this.observedDays,
    required this.recoveryDays,
  }) {
    if (recoveryDays > observedDays) {
      throw const WeeklyReviewContractException(
        'Recovery days cannot exceed observed days.',
      );
    }
  }

  factory WeeklyRecoveryFacts.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'observed_days', 'recovery_days'},
      'weekly recovery facts',
    );
    return WeeklyRecoveryFacts(
      observedDays: _boundedInt(
        json['observed_days'],
        'recovery.observed_days',
        minimum: 0,
        maximum: 7,
      ),
      recoveryDays: _boundedInt(
        json['recovery_days'],
        'recovery.recovery_days',
        minimum: 0,
        maximum: 7,
      ),
    );
  }

  final int observedDays;
  final int recoveryDays;
}

class WeeklyFeedbackFacts {
  WeeklyFeedbackFacts({
    required this.total,
    required this.done,
    required this.later,
    required this.notHelpful,
    required this.tooMuch,
    required this.doesNotFit,
  }) {
    if (done + later + notHelpful + tooMuch + doesNotFit != total) {
      throw const WeeklyReviewContractException(
        'Weekly feedback counts do not match their total.',
      );
    }
  }

  factory WeeklyFeedbackFacts.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'total',
        'done',
        'later',
        'not_helpful',
        'too_much',
        'does_not_fit',
      },
      'weekly feedback facts',
    );
    return WeeklyFeedbackFacts(
      total: _nonNegativeInt(json['total'], 'feedback.total'),
      done: _nonNegativeInt(json['done'], 'feedback.done'),
      later: _nonNegativeInt(json['later'], 'feedback.later'),
      notHelpful: _nonNegativeInt(
        json['not_helpful'],
        'feedback.not_helpful',
      ),
      tooMuch: _nonNegativeInt(json['too_much'], 'feedback.too_much'),
      doesNotFit: _nonNegativeInt(
        json['does_not_fit'],
        'feedback.does_not_fit',
      ),
    );
  }

  final int total;
  final int done;
  final int later;
  final int notHelpful;
  final int tooMuch;
  final int doesNotFit;
}

class WeeklyReviewProposal {
  WeeklyReviewProposal({
    required this.id,
    required this.operation,
    required this.targetId,
    required this.targetTitle,
    required this.ownership,
    required this.applicationMode,
    required this.expectedUpdatedAt,
    required this.reasonCode,
    required this.reason,
    required List<WeeklyReviewEvidenceRef> evidenceRefs,
    required this.change,
  }) : evidenceRefs = List.unmodifiable(evidenceRefs) {
    _validate();
  }

  factory WeeklyReviewProposal.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'id',
        'operation',
        'target_kind',
        'target_id',
        'target_title',
        'ownership',
        'application_mode',
        'expected_updated_at',
        'reason_code',
        'reason',
        'evidence_refs',
        'change',
      },
      'weekly review proposal',
    );
    if (json['target_kind'] != 'habit') {
      throw const WeeklyReviewContractException(
        'Weekly review proposals require a habit target.',
      );
    }
    final operation = WeeklyReviewOperation.fromCode(json['operation']);
    final ownership = WeeklyReviewOwnership.fromCode(json['ownership']);
    final applicationMode = WeeklyReviewApplicationMode.fromCode(
      json['application_mode'],
    );
    final rawEvidence = json['evidence_refs'];
    final rawChange = json['change'];
    if (operation == null ||
        ownership == null ||
        applicationMode == null ||
        rawEvidence is! List ||
        rawEvidence.length > 8 ||
        rawChange is! Map) {
      throw const WeeklyReviewContractException(
        'Weekly review proposal fields are invalid.',
      );
    }
    return WeeklyReviewProposal(
      id: _requiredString(json['id'], 'proposal.id', maxLength: 200),
      operation: operation,
      targetId: _requiredString(
        json['target_id'],
        'proposal.target_id',
        maxLength: 200,
      ),
      targetTitle: _requiredString(
        json['target_title'],
        'proposal.target_title',
        maxLength: 160,
      ),
      ownership: ownership,
      applicationMode: applicationMode,
      expectedUpdatedAt: _requiredDateTime(
        json['expected_updated_at'],
        'proposal.expected_updated_at',
      ),
      reasonCode: _requiredString(
        json['reason_code'],
        'proposal.reason_code',
        maxLength: 100,
      ),
      reason: _requiredString(
        json['reason'],
        'proposal.reason',
        maxLength: 300,
      ),
      evidenceRefs: rawEvidence.map(_evidenceFromObject).toList(),
      change: WeeklyReviewProposalChange.fromJson(
        Map<String, dynamic>.from(rawChange),
      ),
    );
  }

  final String id;
  final WeeklyReviewOperation operation;
  final String targetId;
  final String targetTitle;
  final WeeklyReviewOwnership ownership;
  final WeeklyReviewApplicationMode applicationMode;
  final DateTime expectedUpdatedAt;
  final String reasonCode;
  final String reason;
  final List<WeeklyReviewEvidenceRef> evidenceRefs;
  final WeeklyReviewProposalChange change;

  void _validate() {
    final before = change.before;
    final after = change.after;
    if (operation == WeeklyReviewOperation.replace ||
        operation == WeeklyReviewOperation.defer) {
      if (applicationMode != WeeklyReviewApplicationMode.stagedOnly ||
          after != null) {
        throw const WeeklyReviewContractException(
          'Replace and defer proposals must remain staged.',
        );
      }
      return;
    }
    if (after == null) {
      throw const WeeklyReviewContractException(
        'Applicable weekly review proposals require an after state.',
      );
    }
    if (operation == WeeklyReviewOperation.keep) {
      if (applicationMode != WeeklyReviewApplicationMode.none ||
          after != before) {
        throw const WeeklyReviewContractException(
          'Keep proposals must preserve the habit state.',
        );
      }
      return;
    }
    if (applicationMode == WeeklyReviewApplicationMode.directHabit) {
      if (ownership != WeeklyReviewOwnership.manual ||
          !const {
            WeeklyReviewOperation.shrink,
            WeeklyReviewOperation.pause,
            WeeklyReviewOperation.archive,
          }.contains(operation)) {
        throw const WeeklyReviewContractException(
          'Direct changes require an applicable manual habit.',
        );
      }
    } else if (applicationMode == WeeklyReviewApplicationMode.settingsSetup) {
      if (ownership != WeeklyReviewOwnership.setup) {
        throw const WeeklyReviewContractException(
          'Settings Setup is reserved for Setup-owned habits.',
        );
      }
    } else {
      throw const WeeklyReviewContractException(
        'Habit changes require an applicable command path.',
      );
    }
    switch (operation) {
      case WeeklyReviewOperation.pause:
        if (before.lifecycle != WeeklyReviewHabitLifecycle.active ||
            after.lifecycle != WeeklyReviewHabitLifecycle.paused ||
            after.cadence != before.cadence) {
          throw const WeeklyReviewContractException(
            'Pause proposals must preserve cadence and pause the habit.',
          );
        }
      case WeeklyReviewOperation.archive:
        if (before.lifecycle != WeeklyReviewHabitLifecycle.paused ||
            after.lifecycle != WeeklyReviewHabitLifecycle.archived ||
            after.cadence != before.cadence) {
          throw const WeeklyReviewContractException(
            'Archive proposals must preserve cadence and archive the habit.',
          );
        }
      case WeeklyReviewOperation.shrink:
        if (after.lifecycle != before.lifecycle ||
            before.lifecycle != WeeklyReviewHabitLifecycle.active ||
            before.cadence.kind != WeeklyReviewCadenceKind.weeklyTarget ||
            after.cadence.kind != WeeklyReviewCadenceKind.weeklyTarget ||
            before.cadence.weeklyTarget == null ||
            before.cadence.weeklyTarget! < 2 ||
            after.cadence.weeklyTarget != before.cadence.weeklyTarget! - 1) {
          throw const WeeklyReviewContractException(
            'Shrink proposals must preserve lifecycle and change cadence.',
          );
        }
      case WeeklyReviewOperation.keep:
      case WeeklyReviewOperation.replace:
      case WeeklyReviewOperation.defer:
        break;
    }
  }
}

class WeeklyReviewProposalChange {
  const WeeklyReviewProposalChange({required this.before, required this.after});

  factory WeeklyReviewProposalChange.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, const {'before', 'after'}, 'proposal change');
    final rawBefore = json['before'];
    final rawAfter = json['after'];
    if (rawBefore is! Map || rawAfter != null && rawAfter is! Map) {
      throw const WeeklyReviewContractException(
        'Weekly review proposal change is invalid.',
      );
    }
    return WeeklyReviewProposalChange(
      before: WeeklyReviewHabitState.fromJson(
        Map<String, dynamic>.from(rawBefore),
      ),
      after: rawAfter == null
          ? null
          : WeeklyReviewHabitState.fromJson(
              Map<String, dynamic>.from(rawAfter),
            ),
    );
  }

  final WeeklyReviewHabitState before;
  final WeeklyReviewHabitState? after;
}

class WeeklyReviewHabitState {
  const WeeklyReviewHabitState({
    required this.lifecycle,
    required this.cadence,
  });

  factory WeeklyReviewHabitState.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, const {'lifecycle', 'cadence'}, 'habit state');
    final lifecycle = WeeklyReviewHabitLifecycle.fromCode(json['lifecycle']);
    final rawCadence = json['cadence'];
    if (lifecycle == null || rawCadence is! Map) {
      throw const WeeklyReviewContractException(
        'Weekly review habit state is invalid.',
      );
    }
    return WeeklyReviewHabitState(
      lifecycle: lifecycle,
      cadence: WeeklyReviewHabitCadence.fromJson(
        Map<String, dynamic>.from(rawCadence),
      ),
    );
  }

  final WeeklyReviewHabitLifecycle lifecycle;
  final WeeklyReviewHabitCadence cadence;

  @override
  bool operator ==(Object other) =>
      other is WeeklyReviewHabitState &&
      lifecycle == other.lifecycle &&
      cadence == other.cadence;

  @override
  int get hashCode => Object.hash(lifecycle, cadence);
}

class WeeklyReviewHabitCadence {
  WeeklyReviewHabitCadence({
    required this.kind,
    required this.weeklyTarget,
    required List<int> scheduledWeekdays,
  }) : scheduledWeekdays = List.unmodifiable(scheduledWeekdays) {
    _validate();
  }

  factory WeeklyReviewHabitCadence.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'kind', 'weekly_target', 'scheduled_weekdays'},
      'habit cadence',
    );
    final kind = WeeklyReviewCadenceKind.fromCode(json['kind']);
    final weeklyTarget = json['weekly_target'];
    final weekdays = json['scheduled_weekdays'];
    if (kind == null ||
        weeklyTarget != null && weeklyTarget is! int ||
        weekdays is! List ||
        weekdays.any((value) => value is! int)) {
      throw const WeeklyReviewContractException(
        'Weekly review habit cadence is invalid.',
      );
    }
    return WeeklyReviewHabitCadence(
      kind: kind,
      weeklyTarget: weeklyTarget as int?,
      scheduledWeekdays: weekdays.cast<int>(),
    );
  }

  final WeeklyReviewCadenceKind kind;
  final int? weeklyTarget;
  final List<int> scheduledWeekdays;

  void _validate() {
    if (scheduledWeekdays.length > 7 ||
        scheduledWeekdays.any((day) => day < 1 || day > 7) ||
        scheduledWeekdays.toSet().length != scheduledWeekdays.length ||
        !_isSorted(scheduledWeekdays)) {
      throw const WeeklyReviewContractException(
        'Weekly review weekdays are invalid.',
      );
    }
    switch (kind) {
      case WeeklyReviewCadenceKind.daily:
        if (weeklyTarget != null || scheduledWeekdays.isNotEmpty) {
          throw const WeeklyReviewContractException(
            'Daily cadence accepts no weekly details.',
          );
        }
      case WeeklyReviewCadenceKind.weekdays:
        if (weeklyTarget != null || scheduledWeekdays.isEmpty) {
          throw const WeeklyReviewContractException(
            'Weekday cadence requires scheduled weekdays only.',
          );
        }
      case WeeklyReviewCadenceKind.weeklyTarget:
        if (weeklyTarget == null ||
            weeklyTarget! < 1 ||
            weeklyTarget! > 7 ||
            scheduledWeekdays.isNotEmpty) {
          throw const WeeklyReviewContractException(
            'Weekly target cadence requires one bounded target.',
          );
        }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is WeeklyReviewHabitCadence &&
      kind == other.kind &&
      weeklyTarget == other.weeklyTarget &&
      _listEquals(scheduledWeekdays, other.scheduledWeekdays);

  @override
  int get hashCode =>
      Object.hash(kind, weeklyTarget, Object.hashAll(scheduledWeekdays));
}

class WeeklyReviewEvidenceRef {
  const WeeklyReviewEvidenceRef({
    required this.table,
    required this.id,
    required this.field,
  });

  factory WeeklyReviewEvidenceRef.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, const {'table', 'id', 'field'}, 'evidence ref');
    return WeeklyReviewEvidenceRef(
      table: _requiredString(json['table'], 'evidence.table', maxLength: 64),
      id: _requiredString(json['id'], 'evidence.id', maxLength: 200),
      field: _requiredString(json['field'], 'evidence.field', maxLength: 200),
    );
  }

  final String table;
  final String id;
  final String field;
}

class WeeklyReviewEvidenceWindow {
  const WeeklyReviewEvidenceWindow({
    required this.startsOn,
    required this.endsOn,
    required this.days,
  });

  factory WeeklyReviewEvidenceWindow.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'starts_on', 'ends_on', 'days'},
      'evidence window',
    );
    final days = json['days'];
    if (days != 7) {
      throw const WeeklyReviewContractException(
        'Weekly review evidence window must contain seven days.',
      );
    }
    final startsOn = _requiredDate(json['starts_on'], 'evidence.starts_on');
    final endsOn = _requiredDate(json['ends_on'], 'evidence.ends_on');
    if (!_sameDate(endsOn, _addCalendarDays(startsOn, 6))) {
      throw const WeeklyReviewContractException(
        'Weekly review evidence window dates are invalid.',
      );
    }
    return WeeklyReviewEvidenceWindow(
      startsOn: startsOn,
      endsOn: endsOn,
      days: days as int,
    );
  }

  final DateTime startsOn;
  final DateTime endsOn;
  final int days;
}

class WeeklyReviewProvenance {
  WeeklyReviewProvenance({
    required this.sourceSnapshotId,
    required this.sourceSnapshotGeneratedAt,
    required this.evidenceWindow,
    required this.sourceFingerprint,
    required List<String> limitations,
  }) : limitations = List.unmodifiable(limitations);

  factory WeeklyReviewProvenance.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'engine',
        'contract_version',
        'source_snapshot_id',
        'source_snapshot_generated_at',
        'evidence_window',
        'source_fingerprint',
        'baseline',
        'limitations',
        'llm_used',
      },
      'weekly review provenance',
    );
    final rawWindow = json['evidence_window'];
    final limitations = json['limitations'];
    final fingerprint = json['source_fingerprint'];
    if (json['engine'] != 'deterministic' ||
        json['contract_version'] != weeklyReviewContractVersion ||
        json['baseline'] != 'none' ||
        json['llm_used'] != false ||
        rawWindow is! Map ||
        fingerprint is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint) ||
        limitations is! List ||
        limitations.length > 10 ||
        limitations.any(
          (value) => !_isBoundedTrimmedString(value, maxLength: 300),
        )) {
      throw const WeeklyReviewContractException(
        'Weekly review provenance is unsupported.',
      );
    }
    return WeeklyReviewProvenance(
      sourceSnapshotId: _requiredString(
        json['source_snapshot_id'],
        'provenance.source_snapshot_id',
        maxLength: 200,
      ),
      sourceSnapshotGeneratedAt: _requiredDateTime(
        json['source_snapshot_generated_at'],
        'provenance.source_snapshot_generated_at',
      ),
      evidenceWindow: WeeklyReviewEvidenceWindow.fromJson(
        Map<String, dynamic>.from(rawWindow),
      ),
      sourceFingerprint: fingerprint,
      limitations: limitations.cast<String>(),
    );
  }

  final String sourceSnapshotId;
  final DateTime sourceSnapshotGeneratedAt;
  final WeeklyReviewEvidenceWindow evidenceWindow;
  final String sourceFingerprint;
  final List<String> limitations;
}

class WeeklyReviewContractException implements Exception {
  const WeeklyReviewContractException(this.message);

  final String message;

  @override
  String toString() => 'WeeklyReviewContractException: $message';
}

WeeklyReviewProposal _proposalFromObject(Object? value) {
  if (value is! Map) {
    throw const WeeklyReviewContractException(
      'Weekly review proposal must be an object.',
    );
  }
  return WeeklyReviewProposal.fromJson(Map<String, dynamic>.from(value));
}

WeeklyReviewEvidenceRef _evidenceFromObject(Object? value) {
  if (value is! Map) {
    throw const WeeklyReviewContractException(
      'Weekly review evidence must be an object.',
    );
  }
  return WeeklyReviewEvidenceRef.fromJson(Map<String, dynamic>.from(value));
}

Map<String, dynamic> _requiredMap(Object? value, String field) {
  if (value is! Map) {
    throw WeeklyReviewContractException('$field must be an object.');
  }
  return Map<String, dynamic>.from(value);
}

void _expectExactKeys(
  Map<String, dynamic> json,
  Set<String> expected,
  String label,
) {
  if (json.length != expected.length ||
      json.keys.any((key) => !expected.contains(key)) ||
      expected.any((key) => !json.containsKey(key))) {
    throw WeeklyReviewContractException('$label fields are invalid.');
  }
}

String _requiredString(Object? value, String field, {required int maxLength}) {
  if (!_isBoundedTrimmedString(value, maxLength: maxLength)) {
    throw WeeklyReviewContractException('$field is invalid.');
  }
  return value! as String;
}

bool _isBoundedTrimmedString(Object? value, {required int maxLength}) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= maxLength &&
    value == value.trim();

int _nonNegativeInt(Object? value, String field) =>
    _boundedInt(value, field, minimum: 0);

int _boundedInt(
  Object? value,
  String field, {
  required int minimum,
  int? maximum,
}) {
  if (value is! int || value < minimum || maximum != null && value > maximum) {
    throw WeeklyReviewContractException('$field is invalid.');
  }
  return value;
}

String _requiredPeriodKey(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-W\d{2}$').hasMatch(value)) {
    throw const WeeklyReviewContractException(
      'Weekly review period key is invalid.',
    );
  }
  return value;
}

DateTime _requiredDate(Object? value, String field) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw WeeklyReviewContractException('$field is invalid.');
  }
  final parsed = DateTime.tryParse('${value}T00:00:00');
  if (parsed == null || _dateKey(parsed) != value) {
    throw WeeklyReviewContractException('$field is invalid.');
  }
  return parsed;
}

DateTime _requiredDateTime(Object? value, String field) {
  if (value is! String ||
      !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value) ||
      DateTime.tryParse(value) == null) {
    throw WeeklyReviewContractException('$field is invalid.');
  }
  return DateTime.parse(value);
}

String _isoPeriodKey(DateTime monday) {
  final utcMonday = DateTime.utc(monday.year, monday.month, monday.day);
  final thursday = utcMonday.add(
    Duration(days: DateTime.thursday - utcMonday.weekday),
  );
  final isoYear = thursday.year;
  final januaryFourth = DateTime.utc(isoYear, 1, 4);
  final firstThursday = januaryFourth.add(
    Duration(days: DateTime.thursday - januaryFourth.weekday),
  );
  final week = 1 + thursday.difference(firstThursday).inDays ~/ 7;
  return '$isoYear-W${week.toString().padLeft(2, '0')}';
}

DateTime _addCalendarDays(DateTime value, int days) =>
    DateTime(value.year, value.month, value.day + days);

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

bool _isSorted(List<int> values) {
  for (var index = 1; index < values.length; index++) {
    if (values[index - 1] >= values[index]) return false;
  }
  return true;
}

bool _listEquals(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
