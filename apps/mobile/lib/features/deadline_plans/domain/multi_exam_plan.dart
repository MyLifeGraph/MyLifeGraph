import '../../../core/contracts/strict_contract.dart';
import '../../../core/time/profile_timezone.dart';
import 'deadline_plan.dart';

const multiExamPlanContractVersion = 'multi-exam-plan-v1';

class MultiExamPlanContractException implements Exception {
  const MultiExamPlanContractException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MultiExamPlanAccessException implements Exception {
  const MultiExamPlanAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum MultiExamPlanStatus {
  proposed('proposed'),
  confirmed('confirmed'),
  cancelled('cancelled');

  const MultiExamPlanStatus(this.code);

  final String code;

  static MultiExamPlanStatus? fromCode(Object? value) => switch (value) {
        'proposed' => proposed,
        'confirmed' => confirmed,
        'cancelled' => cancelled,
        _ => null,
      };
}

class MultiExamPlanProposalDraft {
  const MultiExamPlanProposalDraft({
    required this.targetPlanId,
    required this.expectedPlanRevision,
  });

  final String targetPlanId;
  final int expectedPlanRevision;

  Map<String, dynamic> toJson({required String requestId}) => {
        'contract_version': multiExamPlanContractVersion,
        'request_id': requestId,
        'target_plan_id': targetPlanId,
        'expected_plan_revision': expectedPlanRevision,
      };
}

class MultiExamPlanBlock {
  MultiExamPlanBlock({
    required this.id,
    required this.sequence,
    required this.startsAt,
    required this.endsAt,
    required this.reservedEndsAt,
    required this.localDate,
    required this.plannedMinutes,
    required this.recoveryMinutes,
    required this.creditedMinutes,
  }) {
    if (sequence < 1 ||
        sequence > 120 ||
        plannedMinutes < 5 ||
        plannedMinutes > 240 ||
        recoveryMinutes < 0 ||
        recoveryMinutes > 60 ||
        creditedMinutes < 0 ||
        creditedMinutes > plannedMinutes ||
        endsAt.difference(startsAt) != Duration(minutes: plannedMinutes) ||
        reservedEndsAt.difference(endsAt) !=
            Duration(minutes: recoveryMinutes)) {
      throw const MultiExamPlanContractException(
        'Exam balance block interval is invalid.',
      );
    }
  }

  factory MultiExamPlanBlock.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'id',
        'sequence',
        'starts_at',
        'ends_at',
        'reserved_ends_at',
        'local_date',
        'planned_minutes',
        'recovery_minutes',
        'credited_minutes',
      },
      'exam balance block',
    );
    return MultiExamPlanBlock(
      id: _uuid(json['id'], 'block.id'),
      sequence: _integer(json['sequence'], 'block.sequence'),
      startsAt: _instant(json['starts_at'], 'block.starts_at'),
      endsAt: _instant(json['ends_at'], 'block.ends_at'),
      reservedEndsAt: _instant(
        json['reserved_ends_at'],
        'block.reserved_ends_at',
      ),
      localDate: _date(json['local_date'], 'block.local_date'),
      plannedMinutes: _integer(
        json['planned_minutes'],
        'block.planned_minutes',
      ),
      recoveryMinutes: _integer(
        json['recovery_minutes'],
        'block.recovery_minutes',
      ),
      creditedMinutes: _integer(
        json['credited_minutes'],
        'block.credited_minutes',
      ),
    );
  }

  final String id;
  final int sequence;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime reservedEndsAt;
  final String localDate;
  final int plannedMinutes;
  final int recoveryMinutes;
  final int creditedMinutes;

  int get effectiveMinutes => plannedMinutes - creditedMinutes;

  String get scheduleSignature => [
        startsAt.toUtc().toIso8601String(),
        endsAt.toUtc().toIso8601String(),
        reservedEndsAt.toUtc().toIso8601String(),
        plannedMinutes,
        recoveryMinutes,
      ].join('|');
}

class MultiExamPlanItem {
  MultiExamPlanItem({
    required this.position,
    required this.planId,
    required this.title,
    required this.deadlineAt,
    required this.remainingMinutes,
    required this.activeRevision,
    required this.baseRevision,
    required this.proposedRevision,
    required List<MultiExamPlanBlock> currentBlocks,
    required List<MultiExamPlanBlock> proposedBlocks,
    required this.retainedMinutes,
    required this.addedMinutes,
    required this.shiftedMinutes,
    required this.removedMinutes,
    required this.retainedBlockCount,
    required this.addedBlockCount,
    required this.shiftedBlockCount,
    required this.removedBlockCount,
  })  : currentBlocks = List.unmodifiable(currentBlocks),
        proposedBlocks = List.unmodifiable(proposedBlocks) {
    if (position < 1 ||
        position > 8 ||
        title.isEmpty ||
        title != title.trim() ||
        title.runes.length > 160 ||
        remainingMinutes < 0 ||
        remainingMinutes > 30000 ||
        activeRevision < 1 ||
        activeRevision > baseRevision ||
        baseRevision < 1 ||
        baseRevision > 199 ||
        proposedRevision != baseRevision + 1 ||
        currentBlocks.length > 120 ||
        proposedBlocks.length > 120 ||
        !_contiguous(currentBlocks) ||
        !_contiguous(proposedBlocks) ||
        currentBlocks.map((block) => block.id).toSet().length !=
            currentBlocks.length ||
        proposedBlocks.map((block) => block.id).toSet().length !=
            proposedBlocks.length ||
        !_blocksAreOrdered(currentBlocks) ||
        !_blocksAreOrdered(proposedBlocks) ||
        proposedBlocks.any((block) => block.creditedMinutes != 0)) {
      throw const MultiExamPlanContractException(
        'Exam balance item is invalid.',
      );
    }
    _validateChangeSummary();
  }

  factory MultiExamPlanItem.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'position',
        'plan_id',
        'title',
        'deadline_at',
        'remaining_minutes',
        'active_revision',
        'base_revision',
        'proposed_revision',
        'current_blocks',
        'proposed_blocks',
        'retained_minutes',
        'added_minutes',
        'shifted_minutes',
        'removed_minutes',
        'retained_block_count',
        'added_block_count',
        'shifted_block_count',
        'removed_block_count',
      },
      'exam balance item',
    );
    return MultiExamPlanItem(
      position: _integer(json['position'], 'item.position'),
      planId: _uuid(json['plan_id'], 'item.plan_id'),
      title: _text(json['title'], 'item.title', maxLength: 160),
      deadlineAt: _instant(json['deadline_at'], 'item.deadline_at'),
      remainingMinutes: _integer(
        json['remaining_minutes'],
        'item.remaining_minutes',
      ),
      activeRevision: _integer(
        json['active_revision'],
        'item.active_revision',
      ),
      baseRevision: _integer(json['base_revision'], 'item.base_revision'),
      proposedRevision: _integer(
        json['proposed_revision'],
        'item.proposed_revision',
      ),
      currentBlocks: _blocks(json['current_blocks'], 'item.current_blocks'),
      proposedBlocks: _blocks(
        json['proposed_blocks'],
        'item.proposed_blocks',
      ),
      retainedMinutes: _integer(
        json['retained_minutes'],
        'item.retained_minutes',
      ),
      addedMinutes: _integer(
        json['added_minutes'],
        'item.added_minutes',
      ),
      shiftedMinutes: _integer(
        json['shifted_minutes'],
        'item.shifted_minutes',
      ),
      removedMinutes: _integer(
        json['removed_minutes'],
        'item.removed_minutes',
      ),
      retainedBlockCount: _integer(
        json['retained_block_count'],
        'item.retained_block_count',
      ),
      addedBlockCount: _integer(
        json['added_block_count'],
        'item.added_block_count',
      ),
      shiftedBlockCount: _integer(
        json['shifted_block_count'],
        'item.shifted_block_count',
      ),
      removedBlockCount: _integer(
        json['removed_block_count'],
        'item.removed_block_count',
      ),
    );
  }

  final int position;
  final String planId;
  final String title;
  final DateTime deadlineAt;
  final int remainingMinutes;
  final int activeRevision;
  final int baseRevision;
  final int proposedRevision;
  final List<MultiExamPlanBlock> currentBlocks;
  final List<MultiExamPlanBlock> proposedBlocks;
  final int retainedMinutes;
  final int addedMinutes;
  final int shiftedMinutes;
  final int removedMinutes;
  final int retainedBlockCount;
  final int addedBlockCount;
  final int shiftedBlockCount;
  final int removedBlockCount;

  void _validateChangeSummary() {
    final unmatchedProposed = [...proposedBlocks];
    var retainedMinutesExpected = 0;
    var retainedCountExpected = 0;
    var oldUnmatchedMinutes = 0;
    var oldUnmatchedCount = 0;
    for (final current in currentBlocks) {
      final index = current.creditedMinutes == 0
          ? unmatchedProposed.indexWhere(
              (candidate) =>
                  candidate.scheduleSignature == current.scheduleSignature,
            )
          : -1;
      if (index == -1) {
        oldUnmatchedMinutes += current.effectiveMinutes;
        oldUnmatchedCount += 1;
      } else {
        unmatchedProposed.removeAt(index);
        retainedMinutesExpected += current.effectiveMinutes;
        retainedCountExpected += 1;
      }
    }
    final newUnmatchedMinutes = unmatchedProposed.fold<int>(
      0,
      (total, block) => total + block.effectiveMinutes,
    );
    final newUnmatchedCount = unmatchedProposed.length;
    final shiftedMinutesExpected = oldUnmatchedMinutes < newUnmatchedMinutes
        ? oldUnmatchedMinutes
        : newUnmatchedMinutes;
    final shiftedCountExpected = oldUnmatchedCount < newUnmatchedCount
        ? oldUnmatchedCount
        : newUnmatchedCount;
    final actual = (
      retainedMinutes,
      addedMinutes,
      shiftedMinutes,
      removedMinutes,
      retainedBlockCount,
      addedBlockCount,
      shiftedBlockCount,
      removedBlockCount,
    );
    final expected = (
      retainedMinutesExpected,
      newUnmatchedMinutes - shiftedMinutesExpected,
      shiftedMinutesExpected,
      oldUnmatchedMinutes - shiftedMinutesExpected,
      retainedCountExpected,
      newUnmatchedCount - shiftedCountExpected,
      shiftedCountExpected,
      oldUnmatchedCount - shiftedCountExpected,
    );
    if (actual != expected ||
        currentBlocks == proposedBlocks ||
        addedMinutes +
                shiftedMinutes +
                removedMinutes +
                addedBlockCount +
                shiftedBlockCount +
                removedBlockCount ==
            0) {
      throw const MultiExamPlanContractException(
        'Exam balance change summary is inconsistent.',
      );
    }
  }
}

class MultiExamPlanChildLink {
  const MultiExamPlanChildLink({
    required this.planId,
    required this.proposedRevision,
    required this.balanceId,
    required this.balanceRevision,
    required this.status,
  });

  factory MultiExamPlanChildLink.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'plan_id',
        'proposed_revision',
        'balance_id',
        'balance_revision',
        'status',
      },
      'exam balance child link',
    );
    final status = MultiExamPlanStatus.fromCode(json['status']);
    if (status == null) {
      throw const MultiExamPlanContractException(
        'Exam balance child status is invalid.',
      );
    }
    return MultiExamPlanChildLink(
      planId: _uuid(json['plan_id'], 'link.plan_id'),
      proposedRevision: _integer(
        json['proposed_revision'],
        'link.proposed_revision',
      ),
      balanceId: _uuid(json['balance_id'], 'link.balance_id'),
      balanceRevision: _integer(
        json['balance_revision'],
        'link.balance_revision',
      ),
      status: status,
    );
  }

  final String planId;
  final int proposedRevision;
  final String balanceId;
  final int balanceRevision;
  final MultiExamPlanStatus status;

  String get childKey => '$planId:$proposedRevision';
}

class MultiExamPlanBatch {
  MultiExamPlanBatch({
    required this.id,
    required this.status,
    required this.revision,
    required this.targetPlanId,
    required this.contextFingerprint,
    required this.confirmationFingerprint,
    required this.timezone,
    required this.createdAt,
    required this.updatedAt,
    required this.confirmedAt,
    required this.cancelledAt,
    required this.retainedMinutes,
    required this.addedMinutes,
    required this.shiftedMinutes,
    required this.removedMinutes,
    required List<MultiExamPlanItem> items,
    required List<MultiExamPlanChildLink> childLinks,
  })  : items = List.unmodifiable(items),
        childLinks = List.unmodifiable(childLinks) {
    try {
      profileDateTimeAt(instant: createdAt, timezoneName: timezone);
    } on ProfileTimezoneException {
      throw const MultiExamPlanContractException(
        'Exam balance timezone is invalid.',
      );
    }
    final lifecycleValid = switch (status) {
      MultiExamPlanStatus.proposed =>
        confirmedAt == null && cancelledAt == null,
      MultiExamPlanStatus.confirmed =>
        confirmedAt != null && cancelledAt == null,
      MultiExamPlanStatus.cancelled =>
        confirmedAt == null && cancelledAt != null,
    };
    final expectedPriority = [...items]..sort((left, right) {
        final deadline = left.deadlineAt.compareTo(right.deadlineAt);
        if (deadline != 0) return deadline;
        final remaining = right.remainingMinutes.compareTo(
          left.remainingMinutes,
        );
        return remaining != 0 ? remaining : left.planId.compareTo(right.planId);
      });
    final linksByPlan = {for (final link in childLinks) link.planId: link};
    final terminalAt = confirmedAt ?? cancelledAt;
    if (!lifecycleValid ||
        revision < 1 ||
        revision > 200 ||
        updatedAt.isBefore(createdAt) ||
        terminalAt != null &&
            (terminalAt.isBefore(createdAt) || terminalAt.isAfter(updatedAt)) ||
        items.length < 2 ||
        items.length > 8 ||
        childLinks.length != items.length ||
        items.map((item) => item.planId).toSet().length != items.length ||
        !items.any((item) => item.planId == targetPlanId) ||
        linksByPlan.length != childLinks.length ||
        !_sameIdentityOrder(items, expectedPriority) ||
        !_positionsAreContiguous(items) ||
        items.any((item) {
          final link = linksByPlan[item.planId];
          return link == null ||
              link.proposedRevision != item.proposedRevision ||
              link.balanceId != id ||
              link.balanceRevision != revision ||
              link.status != status;
        }) ||
        retainedMinutes !=
            items.fold<int>(0, (sum, item) => sum + item.retainedMinutes) ||
        addedMinutes !=
            items.fold<int>(0, (sum, item) => sum + item.addedMinutes) ||
        shiftedMinutes !=
            items.fold<int>(0, (sum, item) => sum + item.shiftedMinutes) ||
        removedMinutes !=
            items.fold<int>(0, (sum, item) => sum + item.removedMinutes)) {
      throw const MultiExamPlanContractException(
        'Exam balance batch is inconsistent.',
      );
    }
  }

  factory MultiExamPlanBatch.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'id',
        'status',
        'revision',
        'target_plan_id',
        'context_fingerprint',
        'confirmation_fingerprint',
        'timezone',
        'created_at',
        'updated_at',
        'confirmed_at',
        'cancelled_at',
        'retained_minutes',
        'added_minutes',
        'shifted_minutes',
        'removed_minutes',
        'items',
        'child_links',
      },
      'exam balance batch',
    );
    final status = MultiExamPlanStatus.fromCode(json['status']);
    if (status == null) {
      throw const MultiExamPlanContractException(
        'Exam balance status is invalid.',
      );
    }
    return MultiExamPlanBatch(
      id: _uuid(json['id'], 'balance.id'),
      status: status,
      revision: _integer(json['revision'], 'balance.revision'),
      targetPlanId: _uuid(json['target_plan_id'], 'balance.target_plan_id'),
      contextFingerprint: _fingerprint(
        json['context_fingerprint'],
        'balance.context_fingerprint',
      ),
      confirmationFingerprint: _fingerprint(
        json['confirmation_fingerprint'],
        'balance.confirmation_fingerprint',
      ),
      timezone: _text(json['timezone'], 'balance.timezone', maxLength: 100),
      createdAt: _instant(json['created_at'], 'balance.created_at'),
      updatedAt: _instant(json['updated_at'], 'balance.updated_at'),
      confirmedAt: _nullableInstant(json, 'confirmed_at'),
      cancelledAt: _nullableInstant(json, 'cancelled_at'),
      retainedMinutes: _integer(
        json['retained_minutes'],
        'balance.retained_minutes',
      ),
      addedMinutes: _integer(
        json['added_minutes'],
        'balance.added_minutes',
      ),
      shiftedMinutes: _integer(
        json['shifted_minutes'],
        'balance.shifted_minutes',
      ),
      removedMinutes: _integer(
        json['removed_minutes'],
        'balance.removed_minutes',
      ),
      items: _list(json['items'], 'balance.items')
          .map(
            (value) => MultiExamPlanItem.fromJson(
              _map(value, 'balance item'),
            ),
          )
          .toList(growable: false),
      childLinks: _list(json['child_links'], 'balance.child_links')
          .map(
            (value) => MultiExamPlanChildLink.fromJson(
              _map(value, 'balance child link'),
            ),
          )
          .toList(growable: false),
    );
  }

  final String id;
  final MultiExamPlanStatus status;
  final int revision;
  final String targetPlanId;
  final String contextFingerprint;
  final String confirmationFingerprint;
  final String timezone;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;
  final int retainedMinutes;
  final int addedMinutes;
  final int shiftedMinutes;
  final int removedMinutes;
  final List<MultiExamPlanItem> items;
  final List<MultiExamPlanChildLink> childLinks;
}

class MultiExamPlanBatchSummary {
  const MultiExamPlanBatchSummary({
    required this.id,
    required this.status,
    required this.revision,
    required this.targetPlanId,
    required this.affectedPlanCount,
    required this.shiftedMinutes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MultiExamPlanBatchSummary.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'id',
        'status',
        'revision',
        'target_plan_id',
        'affected_plan_count',
        'shifted_minutes',
        'created_at',
        'updated_at',
      },
      'exam balance summary',
    );
    final status = MultiExamPlanStatus.fromCode(json['status']);
    final count = _integer(
      json['affected_plan_count'],
      'summary.affected_plan_count',
    );
    final shifted = _integer(
      json['shifted_minutes'],
      'summary.shifted_minutes',
    );
    final revision = _integer(json['revision'], 'summary.revision');
    final createdAt = _instant(json['created_at'], 'summary.created_at');
    final updatedAt = _instant(json['updated_at'], 'summary.updated_at');
    if (status == null ||
        revision < 1 ||
        revision > 200 ||
        count < 2 ||
        count > 8 ||
        shifted < 0 ||
        shifted > 240000 ||
        updatedAt.isBefore(createdAt)) {
      throw const MultiExamPlanContractException(
        'Exam balance summary is invalid.',
      );
    }
    return MultiExamPlanBatchSummary(
      id: _uuid(json['id'], 'summary.id'),
      status: status,
      revision: revision,
      targetPlanId: _uuid(json['target_plan_id'], 'summary.target_plan_id'),
      affectedPlanCount: count,
      shiftedMinutes: shifted,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory MultiExamPlanBatchSummary.fromBatch(MultiExamPlanBatch batch) =>
      MultiExamPlanBatchSummary(
        id: batch.id,
        status: batch.status,
        revision: batch.revision,
        targetPlanId: batch.targetPlanId,
        affectedPlanCount: batch.items.length,
        shiftedMinutes: batch.shiftedMinutes,
        createdAt: batch.createdAt,
        updatedAt: batch.updatedAt,
      );

  final String id;
  final MultiExamPlanStatus status;
  final int revision;
  final String targetPlanId;
  final int affectedPlanCount;
  final int shiftedMinutes;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool matchesBatch(MultiExamPlanBatch batch) =>
      id == batch.id &&
      status == batch.status &&
      revision == batch.revision &&
      targetPlanId == batch.targetPlanId &&
      affectedPlanCount == batch.items.length &&
      shiftedMinutes == batch.shiftedMinutes &&
      createdAt == batch.createdAt &&
      updatedAt == batch.updatedAt;
}

class MultiExamPlanFeed {
  MultiExamPlanFeed({required List<MultiExamPlanBatchSummary> balances})
      : balances = List.unmodifiable(balances) {
    final expected = [...balances]..sort((left, right) {
        final updated = right.updatedAt.compareTo(left.updatedAt);
        return updated != 0 ? updated : right.id.compareTo(left.id);
      });
    if (balances.length > 200 ||
        balances.map((balance) => balance.id).toSet().length !=
            balances.length ||
        !_sameSummaryOrder(balances, expected)) {
      throw const MultiExamPlanContractException(
        'Exam balance feed is invalid.',
      );
    }
  }

  factory MultiExamPlanFeed.fromJson(Map<String, dynamic> json) {
    _expectEnvelope(json);
    _expectExactKeys(
      json,
      const {'contract_version', 'origin', 'balances'},
      'exam balance feed',
    );
    return MultiExamPlanFeed(
      balances: _list(json['balances'], 'balances')
          .map(
            (value) => MultiExamPlanBatchSummary.fromJson(
              _map(value, 'balance summary'),
            ),
          )
          .toList(growable: false),
    );
  }

  final List<MultiExamPlanBatchSummary> balances;
}

class MultiExamPlanBatchResponse {
  const MultiExamPlanBatchResponse(this.balance);

  factory MultiExamPlanBatchResponse.fromJson(Map<String, dynamic> json) {
    _expectEnvelope(json);
    _expectExactKeys(
      json,
      const {'contract_version', 'origin', 'balance'},
      'exam balance response',
    );
    return MultiExamPlanBatchResponse(
      MultiExamPlanBatch.fromJson(_map(json['balance'], 'balance')),
    );
  }

  final MultiExamPlanBatch balance;
}

sealed class MultiExamPlanProposalResult {
  const MultiExamPlanProposalResult();

  factory MultiExamPlanProposalResult.fromJson(Map<String, dynamic> json) {
    _expectEnvelope(json);
    return switch (json['outcome']) {
      'no_change' => MultiExamPlanNoChange.fromJson(json),
      'single_plan' => MultiExamPlanSingle.fromJson(json),
      'multi_exam_batch' => MultiExamPlanBatchProposal.fromJson(json),
      _ => throw const MultiExamPlanContractException(
          'Exam balance proposal outcome is invalid.',
        ),
    };
  }
}

class MultiExamPlanNoChange extends MultiExamPlanProposalResult {
  const MultiExamPlanNoChange({required this.targetPlanId});

  factory MultiExamPlanNoChange.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'contract_version',
        'origin',
        'outcome',
        'target_plan_id',
        'reason',
      },
      'no-change exam balance',
    );
    if (json['outcome'] != 'no_change' ||
        json['reason'] != 'already_balanced') {
      throw const MultiExamPlanContractException(
        'No-change exam balance is invalid.',
      );
    }
    return MultiExamPlanNoChange(
      targetPlanId: _uuid(json['target_plan_id'], 'target_plan_id'),
    );
  }

  final String targetPlanId;
}

class MultiExamPlanSingle extends MultiExamPlanProposalResult {
  const MultiExamPlanSingle({required this.plan});

  factory MultiExamPlanSingle.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'contract_version', 'origin', 'outcome', 'plan'},
      'single-plan exam balance',
    );
    if (json['outcome'] != 'single_plan') {
      throw const MultiExamPlanContractException(
        'Single-plan exam balance is invalid.',
      );
    }
    final plan = DeadlinePlanResponse.fromJson(_map(json['plan'], 'plan')).plan;
    if (plan.kind != DeadlinePlanKind.exam || plan.pendingRevision == null) {
      throw const MultiExamPlanContractException(
        'Single-plan Exam balance must return one staged Exam.',
      );
    }
    return MultiExamPlanSingle(plan: plan);
  }

  final DeadlinePlan plan;
}

class MultiExamPlanBatchProposal extends MultiExamPlanProposalResult {
  const MultiExamPlanBatchProposal({required this.balance});

  factory MultiExamPlanBatchProposal.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'contract_version', 'origin', 'outcome', 'balance'},
      'batch exam balance proposal',
    );
    if (json['outcome'] != 'multi_exam_batch') {
      throw const MultiExamPlanContractException(
        'Batch exam balance proposal is invalid.',
      );
    }
    final balance = MultiExamPlanBatch.fromJson(
      _map(json['balance'], 'balance'),
    );
    if (balance.status != MultiExamPlanStatus.proposed) {
      throw const MultiExamPlanContractException(
        'Exam balance proposal must be staged.',
      );
    }
    return MultiExamPlanBatchProposal(balance: balance);
  }

  final MultiExamPlanBatch balance;
}

bool _contiguous(List<MultiExamPlanBlock> blocks) {
  for (var index = 0; index < blocks.length; index += 1) {
    if (blocks[index].sequence != index + 1) return false;
  }
  return true;
}

bool _blocksAreOrdered(List<MultiExamPlanBlock> blocks) {
  for (var index = 1; index < blocks.length; index += 1) {
    final previous = blocks[index - 1];
    final current = blocks[index];
    final byStart = previous.startsAt.compareTo(current.startsAt);
    if (byStart > 0 || byStart == 0 && previous.id.compareTo(current.id) > 0) {
      return false;
    }
  }
  return true;
}

bool _sameIdentityOrder(
  List<MultiExamPlanItem> left,
  List<MultiExamPlanItem> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index].planId != right[index].planId) return false;
  }
  return true;
}

bool _positionsAreContiguous(List<MultiExamPlanItem> items) {
  for (var index = 0; index < items.length; index += 1) {
    if (items[index].position != index + 1) return false;
  }
  return true;
}

bool _sameSummaryOrder(
  List<MultiExamPlanBatchSummary> left,
  List<MultiExamPlanBatchSummary> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index].id != right[index].id) return false;
  }
  return true;
}

List<MultiExamPlanBlock> _blocks(Object? value, String field) =>
    _list(value, field)
        .map(
          (item) => MultiExamPlanBlock.fromJson(_map(item, '$field item')),
        )
        .toList(growable: false);

void _expectEnvelope(Map<String, dynamic> json) {
  if (json['contract_version'] != multiExamPlanContractVersion ||
      json['origin'] != 'authenticated_backend') {
    throw const MultiExamPlanContractException(
      'Exam balance response provenance is invalid.',
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
    onFailure: () => throw MultiExamPlanContractException(
      '$model fields are invalid.',
    ),
  );
}

Map<String, dynamic> _map(Object? value, String field) => requireStrictMap(
      value,
      onFailure: () => throw MultiExamPlanContractException(
        '$field is invalid.',
      ),
    );

List<dynamic> _list(Object? value, String field) => requireStrictList(
      value,
      onFailure: () => throw MultiExamPlanContractException(
        '$field is invalid.',
      ),
    );

String _uuid(Object? value, String field) => requireStrictUuid(
      value,
      minVersion: 1,
      maxVersion: 5,
      onFailure: () => throw MultiExamPlanContractException(
        '$field is invalid.',
      ),
    );

String _text(Object? value, String field, {required int maxLength}) =>
    requireStrictString(
      value,
      maxLength: maxLength,
      length: StrictStringLength.runes,
      onFailure: () => throw MultiExamPlanContractException(
        '$field is invalid.',
      ),
    );

int _integer(Object? value, String field) => requireStrictInt(
      value,
      onFailure: () => throw MultiExamPlanContractException(
        '$field is invalid.',
      ),
    );

DateTime _instant(Object? value, String field) => requireStrictAwareDateTime(
      value,
      maxFractionDigits: 6,
      validateDateAndTimeComponents: false,
      onFailure: () => throw MultiExamPlanContractException(
        '$field is invalid.',
      ),
    );

DateTime? _nullableInstant(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value == null ? null : _instant(value, key);
}

String _date(Object? value, String field) {
  if (value is! String || !isStrictLocalDate(value)) {
    throw MultiExamPlanContractException('$field is invalid.');
  }
  return value;
}

String _fingerprint(Object? value, String field) {
  if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw MultiExamPlanContractException('$field is invalid.');
  }
  return value;
}
