import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/quick_action/domain/habit_v1.dart';
import 'package:my_life_graph/features/weekly_review/application/weekly_review_proposal_applier.dart';
import 'package:my_life_graph/features/weekly_review/domain/weekly_review.dart';

import 'support/weekly_review_fixtures.dart';

void main() {
  test('shrink refetches exact manual habit and performs one typed update',
      () async {
    final gateway = _FakeHabitGateway(_habit());
    var refreshes = 0;
    final proposal = _proposal();
    final applier = WeeklyReviewProposalApplier(
      habitGateway: gateway,
      loadLatestReview: () async => _feedForProposal(proposal),
      refreshDailySnapshot: () async => refreshes++,
    );

    final result = await _apply(applier, proposal);

    expect(result.status, WeeklyReviewApplyStatus.applied);
    expect(result.snapshotRefreshFailed, isFalse);
    expect(gateway.fetches, 1);
    expect(gateway.updates, 1);
    expect(gateway.lifecycleUpdates, 0);
    expect(gateway.updatedCadence?.kind, HabitCadenceKind.weeklyTarget);
    expect(gateway.updatedCadence?.weeklyTarget, 2);
    expect(refreshes, 1);
  });

  test('pause and archive each perform exactly one lifecycle update', () async {
    for (final values in [
      (
        operation: 'pause',
        beforeLifecycle: 'active',
        afterLifecycle: 'paused',
        habitLifecycle: HabitLifecycle.active,
        expectedLifecycle: HabitLifecycle.paused,
      ),
      (
        operation: 'archive',
        beforeLifecycle: 'paused',
        afterLifecycle: 'archived',
        habitLifecycle: HabitLifecycle.paused,
        expectedLifecycle: HabitLifecycle.archived,
      ),
    ]) {
      final gateway = _FakeHabitGateway(
        _habit(lifecycle: values.habitLifecycle),
      );
      final proposal = _proposal(
        operation: values.operation,
        before: weeklyHabitState(lifecycle: values.beforeLifecycle),
        after: weeklyHabitState(lifecycle: values.afterLifecycle),
      );
      final applier = WeeklyReviewProposalApplier(
        habitGateway: gateway,
        loadLatestReview: () async => _feedForProposal(proposal),
        refreshDailySnapshot: () async {},
      );

      await _apply(applier, proposal);

      expect(gateway.updates, 0);
      expect(gateway.lifecycleUpdates, 1);
      expect(gateway.updatedLifecycle, values.expectedLifecycle);
    }
  });

  test('changed timestamp, ownership, or before state causes zero writes',
      () async {
    final cases = [
      _habit(updatedAt: DateTime.utc(2026, 7, 12, 17, 31)),
      _habit(isSetupManaged: true),
      _habit(cadence: HabitCadence.weeklyTarget(4)),
    ];
    final proposal = _proposal();

    for (final habit in cases) {
      final gateway = _FakeHabitGateway(habit);
      final applier = WeeklyReviewProposalApplier(
        habitGateway: gateway,
        loadLatestReview: () async => _feedForProposal(proposal),
        refreshDailySnapshot: () async {},
      );

      await expectLater(
        _apply(applier, proposal),
        throwsA(isA<WeeklyReviewProposalApplyException>()),
      );
      expect(gateway.updates, 0);
      expect(gateway.lifecycleUpdates, 0);
    }
  });

  test('changed review fingerprint is rejected before a habit read or write',
      () async {
    final proposal = _proposal();
    final gateway = _FakeHabitGateway(_habit());
    final applier = WeeklyReviewProposalApplier(
      habitGateway: gateway,
      loadLatestReview: () async => _feedForProposal(
        proposal,
        fingerprint: _changedFingerprint,
      ),
      refreshDailySnapshot: () async {},
    );

    await expectLater(
      _apply(applier, proposal),
      throwsA(
        isA<WeeklyReviewProposalApplyException>().having(
          (error) => error.message,
          'message',
          'Weekly review changed before confirmation. Refresh before applying it.',
        ),
      ),
    );
    expect(gateway.fetches, 0);
    expect(gateway.updates, 0);
    expect(gateway.lifecycleUpdates, 0);
  });

  test('keep, Setup, and staged proposals perform no habit read or write',
      () async {
    final gateway = _FakeHabitGateway(_habit());
    final defaultProposal = _proposal();
    final applier = WeeklyReviewProposalApplier(
      habitGateway: gateway,
      loadLatestReview: () async => _feedForProposal(defaultProposal),
      refreshDailySnapshot: () async {},
    );

    final keptProposal = _proposal(
      operation: 'keep',
      applicationMode: 'none',
      after: weeklyHabitState(weeklyTarget: 3),
    );
    final kept = await _apply(applier, keptProposal);
    final setupProposal = _proposal(
      operation: 'pause',
      ownership: 'setup',
      applicationMode: 'settings_setup',
      after: weeklyHabitState(lifecycle: 'paused'),
    );
    final setup = await _apply(applier, setupProposal);
    final stagedProposal = _proposal(
      operation: 'replace',
      applicationMode: 'staged_only',
      after: null,
    );
    final staged = await _apply(applier, stagedProposal);
    final stagedSetupProposal = _proposal(
      operation: 'replace',
      ownership: 'setup',
      applicationMode: 'staged_only',
      after: null,
    );
    final stagedSetup = await _apply(applier, stagedSetupProposal);

    expect(kept.status, WeeklyReviewApplyStatus.kept);
    expect(setup.status, WeeklyReviewApplyStatus.requiresSetup);
    expect(staged.status, WeeklyReviewApplyStatus.stagedOnly);
    expect(stagedSetup.status, WeeklyReviewApplyStatus.requiresSetup);
    expect(gateway.fetches, 0);
    expect(gateway.updates, 0);
    expect(gateway.lifecycleUpdates, 0);
  });

  test('durable mutation succeeds honestly when snapshot refresh fails',
      () async {
    final gateway = _FakeHabitGateway(_habit());
    final proposal = _proposal();
    final applier = WeeklyReviewProposalApplier(
      habitGateway: gateway,
      loadLatestReview: () async => _feedForProposal(proposal),
      refreshDailySnapshot: () async => throw StateError('snapshot failed'),
    );

    final result = await _apply(applier, proposal);

    expect(result.status, WeeklyReviewApplyStatus.applied);
    expect(result.snapshotRefreshFailed, isTrue);
    expect(gateway.updates, 1);
  });
}

Future<WeeklyReviewApplyResult> _apply(
  WeeklyReviewProposalApplier applier,
  WeeklyReviewProposal proposal,
) =>
    applier.apply(
      proposal,
      expectedReviewId: _reviewId,
      expectedSourceFingerprint: _fingerprint,
    );

WeeklyReviewFeed _feedForProposal(
  WeeklyReviewProposal proposal, {
  String fingerprint = _fingerprint,
}) {
  final base = WeeklyReviewFeed.fromJson(weeklyReviewResponseJson());
  final review = base.review!;
  return WeeklyReviewFeed(
    origin: base.origin,
    periodKey: base.periodKey,
    startsOn: base.startsOn,
    endsOn: base.endsOn,
    timezone: base.timezone,
    freshness: WeeklyReviewFreshness.current,
    needsGeneration: false,
    staleReasons: const [],
    review: WeeklyReview(
      id: review.id,
      dataQuality: review.dataQuality,
      narrative: review.narrative,
      facts: review.facts,
      proposals: [proposal],
      evidenceRefs: review.evidenceRefs,
      provenance: WeeklyReviewProvenance(
        sourceSnapshotId: review.provenance.sourceSnapshotId,
        sourceSnapshotGeneratedAt: review.provenance.sourceSnapshotGeneratedAt,
        evidenceWindow: review.provenance.evidenceWindow,
        sourceFingerprint: fingerprint,
        limitations: review.provenance.limitations,
      ),
      generatedAt: review.generatedAt,
      updatedAt: review.updatedAt,
    ),
  );
}

WeeklyReviewProposal _proposal({
  String operation = 'shrink',
  String ownership = 'manual',
  String applicationMode = 'direct_habit',
  Map<String, dynamic>? before,
  Object? after = _defaultAfter,
}) {
  final feed = WeeklyReviewFeed.fromJson(
    weeklyReviewResponseJson(
      operation: operation,
      ownership: ownership,
      applicationMode: applicationMode,
      before: before,
      after: identical(after, _defaultAfter)
          ? weeklyHabitState(weeklyTarget: 2)
          : after,
    ),
  );
  return feed.review!.proposals.single;
}

HabitV1 _habit({
  HabitLifecycle lifecycle = HabitLifecycle.active,
  HabitCadence? cadence,
  bool isSetupManaged = false,
  DateTime? updatedAt,
}) =>
    HabitV1(
      id: '22222222-2222-4222-8222-222222222222',
      title: 'Walk after lunch',
      description: 'A short walk.',
      cadence: cadence ?? HabitCadence.weeklyTarget(3),
      lifecycle: lifecycle,
      createdAt: DateTime.utc(2026, 7, 1),
      updatedAt: updatedAt ?? DateTime.utc(2026, 7, 12, 17, 30),
      isSetupManaged: isSetupManaged,
      metadata: {
        'source': isSetupManaged ? 'intake-v1' : 'flutter-habit-management-v1',
        if (isSetupManaged) 'managed_by': 'setup',
      },
    );

class _FakeHabitGateway implements WeeklyReviewHabitGateway {
  _FakeHabitGateway(this.habit);

  final HabitV1 habit;
  int fetches = 0;
  int updates = 0;
  int lifecycleUpdates = 0;
  HabitCadence? updatedCadence;
  HabitLifecycle? updatedLifecycle;

  @override
  Future<HabitV1> fetchOwnedHabit(String habitId) async {
    fetches++;
    return habit;
  }

  @override
  Future<HabitV1> updateHabit({
    required HabitV1 habit,
    required String title,
    String? description,
    required HabitCadence cadence,
  }) async {
    updates++;
    updatedCadence = cadence;
    return habit;
  }

  @override
  Future<HabitV1> setHabitLifecycle({
    required HabitV1 habit,
    required HabitLifecycle lifecycle,
  }) async {
    lifecycleUpdates++;
    updatedLifecycle = lifecycle;
    return habit;
  }
}

const Object _defaultAfter = Object();
const String _reviewId = '11111111-1111-4111-8111-111111111111';
const String _fingerprint =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _changedFingerprint =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
