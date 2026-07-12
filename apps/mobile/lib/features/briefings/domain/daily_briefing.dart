import '../../actions/domain/executable_action_target.dart';

const dailyBriefingContractVersion = 'daily-briefing-v1';

enum BriefingOrigin { authenticatedBackend, localDemo }

enum BriefingFreshness {
  missing('missing'),
  current('current'),
  stale('stale');

  const BriefingFreshness(this.code);

  final String code;

  static BriefingFreshness? fromCode(Object? value) {
    for (final freshness in values) {
      if (freshness.code == value) {
        return freshness;
      }
    }
    return null;
  }
}

enum BriefingMode {
  push('push'),
  steady('steady'),
  recover('recover'),
  plan('plan');

  const BriefingMode(this.code);

  final String code;

  static BriefingMode? fromCode(Object? value) {
    for (final mode in values) {
      if (mode.code == value) {
        return mode;
      }
    }
    return null;
  }
}

enum BriefingDataQuality {
  missing('missing'),
  partial('partial'),
  current('current'),
  stale('stale');

  const BriefingDataQuality(this.code);

  final String code;

  static BriefingDataQuality? fromCode(Object? value) {
    for (final quality in values) {
      if (quality.code == value) {
        return quality;
      }
    }
    return null;
  }
}

class BriefingFeed {
  BriefingFeed({
    required this.origin,
    required this.briefingDate,
    required this.freshness,
    required this.needsGeneration,
    required List<String> staleReasons,
    required this.briefing,
  }) : staleReasons = List.unmodifiable(staleReasons) {
    _validate();
  }

  factory BriefingFeed.localDemo({DateTime? now}) {
    final value = now ?? DateTime.now();
    return BriefingFeed(
      origin: BriefingOrigin.localDemo,
      briefingDate: DateTime(value.year, value.month, value.day),
      freshness: BriefingFreshness.missing,
      needsGeneration: true,
      staleReasons: const [],
      briefing: null,
    );
  }

  factory BriefingFeed.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'contract_version',
        'briefing_date',
        'freshness',
        'needs_generation',
        'stale_reasons',
        'briefing',
      },
      'briefing response',
    );
    if (json['contract_version'] != dailyBriefingContractVersion) {
      throw const BriefingContractException(
        'Unsupported daily briefing contract.',
      );
    }
    final freshness = BriefingFreshness.fromCode(json['freshness']);
    final needsGeneration = json['needs_generation'];
    final staleReasons = json['stale_reasons'];
    if (freshness == null ||
        needsGeneration is! bool ||
        staleReasons is! List) {
      throw const BriefingContractException(
        'Daily briefing freshness is invalid.',
      );
    }
    if (staleReasons.length > 8 ||
        staleReasons.any(
          (reason) =>
              reason is! String || reason.isEmpty || reason != reason.trim(),
        )) {
      throw const BriefingContractException(
        'Daily briefing stale reasons are invalid.',
      );
    }
    final rawBriefing = json['briefing'];
    if (rawBriefing != null && rawBriefing is! Map) {
      throw const BriefingContractException(
        'Daily briefing payload must be an object.',
      );
    }
    return BriefingFeed(
      origin: BriefingOrigin.authenticatedBackend,
      briefingDate: _requiredDate(json['briefing_date'], 'briefing_date'),
      freshness: freshness,
      needsGeneration: needsGeneration,
      staleReasons: staleReasons.cast<String>(),
      briefing: rawBriefing == null
          ? null
          : DailyBriefing.fromJson(
              Map<String, dynamic>.from(rawBriefing),
            ),
    );
  }

  final BriefingOrigin origin;
  final DateTime briefingDate;
  final BriefingFreshness freshness;
  final bool needsGeneration;
  final List<String> staleReasons;
  final DailyBriefing? briefing;

  void _validate() {
    final hasBriefing = briefing != null;
    final validShape = switch (freshness) {
      BriefingFreshness.missing => needsGeneration && !hasBriefing,
      BriefingFreshness.current => !needsGeneration && hasBriefing,
      BriefingFreshness.stale => needsGeneration && hasBriefing,
    };
    if (!validShape) {
      throw const BriefingContractException(
        'Daily briefing freshness and payload do not match.',
      );
    }
    final value = briefing;
    if (value != null && !_sameDate(value.briefingDate, briefingDate)) {
      throw const BriefingContractException(
        'Daily briefing dates do not match.',
      );
    }
  }
}

class DailyBriefing {
  DailyBriefing({
    required this.id,
    required this.briefingDate,
    required this.mode,
    required this.dataQuality,
    required this.capacityMinutes,
    required this.capacityNote,
    required this.summary,
    required this.primaryAction,
    required List<BriefingAction> supportActions,
    required List<BriefingEvidenceRef> evidenceRefs,
    required this.provenance,
    required this.generatedAt,
    required this.updatedAt,
  })  : supportActions = List.unmodifiable(supportActions),
        evidenceRefs = List.unmodifiable(evidenceRefs) {
    if (supportActions.length > 2 || evidenceRefs.length > 20) {
      throw const BriefingContractException(
        'Daily briefing list bounds are invalid.',
      );
    }
  }

  factory DailyBriefing.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'id',
        'briefing_date',
        'mode',
        'data_quality',
        'capacity_minutes',
        'capacity_note',
        'summary',
        'primary_action',
        'support_actions',
        'evidence_refs',
        'provenance',
        'generated_at',
        'updated_at',
      },
      'daily briefing',
    );
    final mode = BriefingMode.fromCode(json['mode']);
    final dataQuality = BriefingDataQuality.fromCode(json['data_quality']);
    final capacityMinutes = json['capacity_minutes'];
    final rawPrimary = json['primary_action'];
    final rawSupport = json['support_actions'];
    final rawEvidence = json['evidence_refs'];
    final rawProvenance = json['provenance'];
    if (mode == null ||
        dataQuality == null ||
        capacityMinutes != null && capacityMinutes is! int ||
        capacityMinutes is int &&
            (capacityMinutes < 1 || capacityMinutes > 480) ||
        rawPrimary is! Map ||
        rawSupport is! List ||
        rawEvidence is! List ||
        rawProvenance is! Map) {
      throw const BriefingContractException(
        'Daily briefing fields are invalid.',
      );
    }
    return DailyBriefing(
      id: _requiredString(json['id'], 'briefing.id', maxLength: 200),
      briefingDate: _requiredDate(
        json['briefing_date'],
        'briefing.briefing_date',
      ),
      mode: mode,
      dataQuality: dataQuality,
      capacityMinutes: capacityMinutes as int?,
      capacityNote: _requiredString(
        json['capacity_note'],
        'briefing.capacity_note',
        maxLength: 240,
      ),
      summary: _requiredString(
        json['summary'],
        'briefing.summary',
        maxLength: 400,
      ),
      primaryAction: BriefingAction.fromJson(
        Map<String, dynamic>.from(rawPrimary),
      ),
      supportActions: rawSupport.map(_actionFromObject).toList(),
      evidenceRefs: rawEvidence.map(_evidenceFromObject).toList(),
      provenance: BriefingProvenance.fromJson(
        Map<String, dynamic>.from(rawProvenance),
      ),
      generatedAt: _requiredDateTime(
        json['generated_at'],
        'briefing.generated_at',
      ),
      updatedAt: _requiredDateTime(
        json['updated_at'],
        'briefing.updated_at',
      ),
    );
  }

  final String id;
  final DateTime briefingDate;
  final BriefingMode mode;
  final BriefingDataQuality dataQuality;
  final int? capacityMinutes;
  final String capacityNote;
  final String summary;
  final BriefingAction primaryAction;
  final List<BriefingAction> supportActions;
  final List<BriefingEvidenceRef> evidenceRefs;
  final BriefingProvenance provenance;
  final DateTime generatedAt;
  final DateTime updatedAt;
}

class BriefingAction {
  BriefingAction({
    required this.target,
    required this.title,
    required this.reason,
    required this.recommendationId,
    required List<BriefingEvidenceRef> evidenceRefs,
  }) : evidenceRefs = List.unmodifiable(evidenceRefs) {
    if (evidenceRefs.length > 8) {
      throw const BriefingContractException(
        'Briefing action evidence exceeds its bound.',
      );
    }
  }

  factory BriefingAction.fromJson(Map<String, dynamic> json) {
    _expectAllowedKeys(
      json,
      const {
        'target',
        'title',
        'reason',
        'recommendation_id',
        'evidence_refs',
      },
      const {'target', 'title', 'reason', 'evidence_refs'},
      'briefing action',
    );
    final rawTarget = json['target'];
    final rawEvidence = json['evidence_refs'];
    final recommendationId = json['recommendation_id'];
    if (rawTarget is! Map ||
        rawEvidence is! List ||
        recommendationId != null && recommendationId is! String) {
      throw const BriefingContractException(
        'Briefing action fields are invalid.',
      );
    }
    return BriefingAction(
      target: ExecutableActionTarget.fromJson(
        Map<String, dynamic>.from(rawTarget),
      ),
      title: _requiredString(
        json['title'],
        'briefing action title',
        maxLength: 200,
      ),
      reason: _requiredString(
        json['reason'],
        'briefing action reason',
        maxLength: 300,
      ),
      recommendationId: recommendationId as String?,
      evidenceRefs: rawEvidence.map(_evidenceFromObject).toList(),
    );
  }

  final ExecutableActionTarget target;
  final String title;
  final String reason;
  final String? recommendationId;
  final List<BriefingEvidenceRef> evidenceRefs;
}

class BriefingEvidenceRef {
  const BriefingEvidenceRef({
    required this.table,
    required this.id,
    required this.field,
  });

  factory BriefingEvidenceRef.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, const {'table', 'id', 'field'}, 'evidence ref');
    return BriefingEvidenceRef(
      table: _requiredString(json['table'], 'evidence table', maxLength: 64),
      id: _requiredString(json['id'], 'evidence id', maxLength: 200),
      field: _requiredString(json['field'], 'evidence field', maxLength: 200),
    );
  }

  final String table;
  final String id;
  final String field;
}

class BriefingProvenance {
  const BriefingProvenance({
    required this.sourceSnapshotId,
    required this.sourceSnapshotGeneratedAt,
    required this.feedbackRanking,
  });

  factory BriefingProvenance.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'engine',
        'contract_version',
        'daily_state_contract_version',
        'executable_action_contract_version',
        'source_snapshot_id',
        'source_snapshot_generated_at',
        'baseline',
        'llm_used',
        'feedback_ranking',
      },
      'briefing provenance',
    );
    if (json['engine'] != 'deterministic' ||
        json['contract_version'] != dailyBriefingContractVersion ||
        json['daily_state_contract_version'] != 'explainable-daily-state-v1' ||
        json['executable_action_contract_version'] !=
            ExecutableActionTarget.contractVersion ||
        json['baseline'] != 'none' ||
        json['llm_used'] != false ||
        json['feedback_ranking'] is! Map) {
      throw const BriefingContractException(
        'Briefing provenance is unsupported.',
      );
    }
    return BriefingProvenance(
      sourceSnapshotId: _requiredString(
        json['source_snapshot_id'],
        'source snapshot id',
        maxLength: 200,
      ),
      sourceSnapshotGeneratedAt: _requiredDateTime(
        json['source_snapshot_generated_at'],
        'source snapshot generated_at',
      ),
      feedbackRanking: FeedbackRankingProvenance.fromJson(
        Map<String, dynamic>.from(json['feedback_ranking'] as Map),
      ),
    );
  }

  final String sourceSnapshotId;
  final DateTime sourceSnapshotGeneratedAt;
  final FeedbackRankingProvenance feedbackRanking;
}

class FeedbackRankingProvenance {
  FeedbackRankingProvenance({
    required this.eventCount,
    required this.appliedCount,
    required this.primaryContribution,
    required List<String> reasons,
  }) : reasons = List.unmodifiable(reasons);

  factory FeedbackRankingProvenance.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'contract_version',
        'lookback_days',
        'event_count',
        'applied_count',
        'primary_contribution',
        'reasons',
      },
      'feedback ranking provenance',
    );
    final eventCount = json['event_count'];
    final appliedCount = json['applied_count'];
    final contribution = json['primary_contribution'];
    final reasons = json['reasons'];
    if (json['contract_version'] != 'feedback-ranking-v1' ||
        json['lookback_days'] != 28 ||
        eventCount is! int ||
        eventCount < 0 ||
        eventCount > 200 ||
        appliedCount is! int ||
        appliedCount < 0 ||
        appliedCount > eventCount ||
        contribution is! int ||
        contribution < -240 ||
        contribution > 120 ||
        reasons is! List ||
        reasons.length > 4 ||
        reasons.any((reason) => reason is! String || reason.isEmpty)) {
      throw const BriefingContractException(
        'Feedback ranking provenance is invalid.',
      );
    }
    return FeedbackRankingProvenance(
      eventCount: eventCount,
      appliedCount: appliedCount,
      primaryContribution: contribution,
      reasons: reasons.cast<String>(),
    );
  }

  final int eventCount;
  final int appliedCount;
  final int primaryContribution;
  final List<String> reasons;
}

class BriefingContractException implements Exception {
  const BriefingContractException(this.message);

  final String message;

  @override
  String toString() => 'BriefingContractException: $message';
}

BriefingAction _actionFromObject(Object? value) {
  if (value is! Map) {
    throw const BriefingContractException(
      'Briefing support action must be an object.',
    );
  }
  return BriefingAction.fromJson(Map<String, dynamic>.from(value));
}

BriefingEvidenceRef _evidenceFromObject(Object? value) {
  if (value is! Map) {
    throw const BriefingContractException(
      'Briefing evidence must be an object.',
    );
  }
  return BriefingEvidenceRef.fromJson(Map<String, dynamic>.from(value));
}

void _expectExactKeys(
  Map<String, dynamic> json,
  Set<String> expected,
  String label,
) {
  _expectAllowedKeys(json, expected, expected, label);
}

void _expectAllowedKeys(
  Map<String, dynamic> json,
  Set<String> allowed,
  Set<String> required,
  String label,
) {
  if (json.keys.any((key) => !allowed.contains(key)) ||
      required.any((key) => !json.containsKey(key))) {
    throw BriefingContractException('$label fields are invalid.');
  }
}

String _requiredString(Object? value, String field, {required int maxLength}) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > maxLength ||
      value != value.trim()) {
    throw BriefingContractException('$field is invalid.');
  }
  return value;
}

DateTime _requiredDate(Object? value, String field) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw BriefingContractException('$field is invalid.');
  }
  final parsed = DateTime.tryParse('${value}T00:00:00');
  if (parsed == null ||
      '${parsed.year.toString().padLeft(4, '0')}-'
              '${parsed.month.toString().padLeft(2, '0')}-'
              '${parsed.day.toString().padLeft(2, '0')}' !=
          value) {
    throw BriefingContractException('$field is invalid.');
  }
  return parsed;
}

DateTime _requiredDateTime(Object? value, String field) {
  if (value is! String ||
      !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value) ||
      DateTime.tryParse(value) == null) {
    throw BriefingContractException('$field is invalid.');
  }
  return DateTime.parse(value);
}

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
