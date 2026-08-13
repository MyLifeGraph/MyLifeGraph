import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/deadline_plans/domain/multi_exam_plan.dart';

import 'support/multi_exam_plan_fixtures.dart';

void main() {
  test('strict batch validates order, aggregates, revisions, and child links',
      () {
    final batch = MultiExamPlanBatchResponse.fromJson(
      multiExamBatchEnvelope(),
    ).balance;

    expect(batch.items, hasLength(2));
    expect(batch.items.first.planId, multiExamTargetId);
    expect(batch.shiftedMinutes, 60);
    expect(batch.childLinks.first.childKey, '$multiExamTargetId:2');
  });

  test('proposal union accepts exactly no-change, single, and batch', () {
    expect(
      MultiExamPlanProposalResult.fromJson(
        multiExamProposalEnvelope(outcome: 'no_change'),
      ),
      isA<MultiExamPlanNoChange>(),
    );
    expect(
      MultiExamPlanProposalResult.fromJson(
        multiExamProposalEnvelope(outcome: 'single_plan'),
      ),
      isA<MultiExamPlanSingle>(),
    );
    expect(
      MultiExamPlanProposalResult.fromJson(multiExamProposalEnvelope()),
      isA<MultiExamPlanBatchProposal>(),
    );

    final mixed = multiExamProposalEnvelope()..['reason'] = 'already_balanced';
    expect(
      () => MultiExamPlanProposalResult.fromJson(mixed),
      throwsA(isA<MultiExamPlanContractException>()),
    );
  });

  test('summary shifted-minute bound matches the backend aggregate ceiling',
      () {
    final atLimit = multiExamFeedEnvelope();
    ((atLimit['balances'] as List).single
        as Map<String, dynamic>)['shifted_minutes'] = 240000;
    expect(
      MultiExamPlanFeed.fromJson(atLimit).balances.single.shiftedMinutes,
      240000,
    );

    final aboveLimit = multiExamFeedEnvelope();
    ((aboveLimit['balances'] as List).single
        as Map<String, dynamic>)['shifted_minutes'] = 240001;
    expect(
      () => MultiExamPlanFeed.fromJson(aboveLimit),
      throwsA(isA<MultiExamPlanContractException>()),
    );
  });

  test('change axes are disjoint for old and new unmatched asymmetry', () {
    final oldLonger = multiExamItem(
      planId: multiExamTargetId,
      position: 1,
      title: 'Algorithms exam',
      currentStart: '2026-08-20T09:00:00Z',
      proposedStart: '2026-08-21T09:00:00Z',
    );
    (oldLonger['current_blocks'] as List).first['planned_minutes'] = 60;
    (oldLonger['current_blocks'] as List).first['ends_at'] =
        '2026-08-20T10:00:00.000Z';
    (oldLonger['current_blocks'] as List).first['reserved_ends_at'] =
        '2026-08-20T10:00:00.000Z';
    oldLonger
      ..['shifted_minutes'] = 30
      ..['removed_minutes'] = 30;
    final parsedOld = MultiExamPlanItem.fromJson(oldLonger);
    expect((parsedOld.shiftedMinutes, parsedOld.removedMinutes), (30, 30));

    final newLonger = multiExamItem(
      planId: multiExamTargetId,
      position: 1,
      title: 'Algorithms exam',
      currentStart: '2026-08-20T09:00:00Z',
      proposedStart: '2026-08-21T09:00:00Z',
    );
    (newLonger['proposed_blocks'] as List).first['planned_minutes'] = 60;
    (newLonger['proposed_blocks'] as List).first['ends_at'] =
        '2026-08-21T10:00:00.000Z';
    (newLonger['proposed_blocks'] as List).first['reserved_ends_at'] =
        '2026-08-21T10:00:00.000Z';
    newLonger
      ..['shifted_minutes'] = 30
      ..['added_minutes'] = 30;
    final parsedNew = MultiExamPlanItem.fromJson(newLonger);
    expect((parsedNew.shiftedMinutes, parsedNew.addedMinutes), (30, 30));
  });

  test('duplicate signatures and partial credit use multiset matching', () {
    final item = multiExamItem(
      planId: multiExamTargetId,
      position: 1,
      title: 'Algorithms exam',
      currentStart: '2026-08-20T09:00:00Z',
      proposedStart: '2026-08-20T09:00:00Z',
    );
    final current = item['current_blocks'] as List<dynamic>;
    final duplicate = Map<String, dynamic>.from(current.first as Map)
      ..['id'] = '13000000-0000-4000-8000-000000000003'
      ..['sequence'] = 2
      ..['credited_minutes'] = 10;
    current.add(duplicate);
    item
      ..['retained_minutes'] = 30
      ..['shifted_minutes'] = 0
      ..['removed_minutes'] = 20
      ..['retained_block_count'] = 1
      ..['shifted_block_count'] = 0
      ..['removed_block_count'] = 1;

    final parsed = MultiExamPlanItem.fromJson(item);
    expect(parsed.retainedMinutes, 30);
    expect(parsed.removedMinutes, 20);
  });

  test('cancel then new preview allows active below latest base', () {
    final item = multiExamItem(
      planId: multiExamTargetId,
      position: 1,
      title: 'Algorithms exam',
      currentStart: '2026-08-20T09:00:00Z',
      proposedStart: '2026-08-21T09:00:00Z',
      activeRevision: 2,
      baseRevision: 4,
    );
    final parsed = MultiExamPlanItem.fromJson(item);
    expect(
      (parsed.activeRevision, parsed.baseRevision, parsed.proposedRevision),
      (2, 4, 5),
    );
  });

  test('unknown keys, forged totals, order, and link mismatch fail closed', () {
    final unknown = multiExamBatchEnvelope()..['extra'] = true;
    expect(
      () => MultiExamPlanBatchResponse.fromJson(unknown),
      throwsA(isA<MultiExamPlanContractException>()),
    );

    final forged = multiExamBatchEnvelope();
    (forged['balance'] as Map<String, dynamic>)['shifted_minutes'] = 59;
    expect(
      () => MultiExamPlanBatchResponse.fromJson(forged),
      throwsA(isA<MultiExamPlanContractException>()),
    );

    final reordered = multiExamBatchEnvelope();
    final items =
        (reordered['balance'] as Map<String, dynamic>)['items'] as List;
    (reordered['balance'] as Map<String, dynamic>)['items'] =
        items.reversed.toList();
    expect(
      () => MultiExamPlanBatchResponse.fromJson(reordered),
      throwsA(isA<MultiExamPlanContractException>()),
    );

    final badLink = multiExamBatchEnvelope();
    final links =
        (badLink['balance'] as Map<String, dynamic>)['child_links'] as List;
    (links.first as Map<String, dynamic>)['proposed_revision'] = 3;
    expect(
      () => MultiExamPlanBatchResponse.fromJson(badLink),
      throwsA(isA<MultiExamPlanContractException>()),
    );

    final forgedTarget = multiExamBatchEnvelope();
    (forgedTarget['balance'] as Map<String, dynamic>)['target_plan_id'] =
        '90000000-0000-4000-8000-000000000009';
    expect(
      () => MultiExamPlanBatchResponse.fromJson(forgedTarget),
      throwsA(isA<MultiExamPlanContractException>()),
    );

    final invalidTimezone = multiExamBatchEnvelope();
    (invalidTimezone['balance'] as Map<String, dynamic>)['timezone'] =
        'Not/A_Timezone';
    expect(
      () => MultiExamPlanBatchResponse.fromJson(invalidTimezone),
      throwsA(isA<MultiExamPlanContractException>()),
    );

    final terminalProposal = multiExamProposalEnvelope();
    terminalProposal['balance'] = multiExamBatch(status: 'confirmed');
    expect(
      () => MultiExamPlanProposalResult.fromJson(terminalProposal),
      throwsA(isA<MultiExamPlanContractException>()),
    );

    final unorderedFeed = multiExamFeedEnvelope();
    final newest = Map<String, dynamic>.from(
      (unorderedFeed['balances'] as List).single as Map,
    )..['updated_at'] = '2026-08-14T09:00:00Z';
    final oldest = Map<String, dynamic>.from(newest)
      ..['id'] = '91000000-0000-4000-8000-000000000009'
      ..['updated_at'] = '2026-08-12T09:00:00Z';
    unorderedFeed['balances'] = [oldest, newest];
    expect(
      () => MultiExamPlanFeed.fromJson(unorderedFeed),
      throwsA(isA<MultiExamPlanContractException>()),
    );
  });
}
