import '../../quick_action/data/habit_completion_supabase_data_source.dart';
import '../../quick_action/domain/habit_v1.dart';
import '../domain/weekly_review.dart';

abstract interface class WeeklyReviewHabitGateway {
  Future<HabitV1> fetchOwnedHabit(String habitId);

  Future<HabitV1> updateHabit({
    required HabitV1 habit,
    required String title,
    String? description,
    required HabitCadence cadence,
  });

  Future<HabitV1> setHabitLifecycle({
    required HabitV1 habit,
    required HabitLifecycle lifecycle,
  });
}

class WeeklyReviewHabitGatewayImpl implements WeeklyReviewHabitGateway {
  const WeeklyReviewHabitGatewayImpl(this._dataSource);

  final HabitCompletionSupabaseDataSource _dataSource;

  @override
  Future<HabitV1> fetchOwnedHabit(String habitId) =>
      _dataSource.fetchOwnedHabit(habitId);

  @override
  Future<HabitV1> updateHabit({
    required HabitV1 habit,
    required String title,
    String? description,
    required HabitCadence cadence,
  }) =>
      _dataSource.updateHabit(
        habit: habit,
        title: title,
        description: description,
        cadence: cadence,
      );

  @override
  Future<HabitV1> setHabitLifecycle({
    required HabitV1 habit,
    required HabitLifecycle lifecycle,
  }) =>
      _dataSource.setHabitLifecycle(habit: habit, lifecycle: lifecycle);
}

typedef WeeklyReviewSnapshotRefresh = Future<void> Function();
typedef WeeklyReviewLatestLoader = Future<WeeklyReviewFeed> Function();

enum WeeklyReviewApplyStatus {
  applied,
  kept,
  requiresSetup,
  stagedOnly,
}

class WeeklyReviewApplyResult {
  const WeeklyReviewApplyResult(
    this.status, {
    this.snapshotRefreshFailed = false,
  });

  final WeeklyReviewApplyStatus status;
  final bool snapshotRefreshFailed;
}

class WeeklyReviewProposalApplier {
  const WeeklyReviewProposalApplier({
    required WeeklyReviewHabitGateway habitGateway,
    required WeeklyReviewLatestLoader loadLatestReview,
    required WeeklyReviewSnapshotRefresh refreshDailySnapshot,
  })  : _habitGateway = habitGateway,
        _loadLatestReview = loadLatestReview,
        _refreshDailySnapshot = refreshDailySnapshot;

  final WeeklyReviewHabitGateway _habitGateway;
  final WeeklyReviewLatestLoader _loadLatestReview;
  final WeeklyReviewSnapshotRefresh _refreshDailySnapshot;

  Future<WeeklyReviewApplyResult> apply(
    WeeklyReviewProposal proposal, {
    required String expectedReviewId,
    required String expectedSourceFingerprint,
  }) async {
    switch (proposal.applicationMode) {
      case WeeklyReviewApplicationMode.none:
        return const WeeklyReviewApplyResult(WeeklyReviewApplyStatus.kept);
      case WeeklyReviewApplicationMode.settingsSetup:
        return const WeeklyReviewApplyResult(
          WeeklyReviewApplyStatus.requiresSetup,
        );
      case WeeklyReviewApplicationMode.stagedOnly:
        return WeeklyReviewApplyResult(
          proposal.ownership == WeeklyReviewOwnership.setup
              ? WeeklyReviewApplyStatus.requiresSetup
              : WeeklyReviewApplyStatus.stagedOnly,
        );
      case WeeklyReviewApplicationMode.directHabit:
        break;
    }

    if (proposal.ownership != WeeklyReviewOwnership.manual) {
      throw const WeeklyReviewProposalApplyException(
        'Only manual habits can be changed directly.',
      );
    }
    await _requireCurrentProposal(
      proposal,
      expectedReviewId: expectedReviewId,
      expectedSourceFingerprint: expectedSourceFingerprint,
    );
    final habit = await _habitGateway.fetchOwnedHabit(proposal.targetId);
    if (habit.id != proposal.targetId ||
        habit.title != proposal.targetTitle ||
        habit.isSetupManaged ||
        !habit.updatedAt.isAtSameMomentAs(proposal.expectedUpdatedAt) ||
        _stateFromHabit(habit) != proposal.change.before) {
      throw const WeeklyReviewProposalApplyException(
        'This habit changed after the review. Refresh before applying it.',
      );
    }
    final after = proposal.change.after;
    if (after == null) {
      throw const WeeklyReviewProposalApplyException(
        'The proposed habit state is missing.',
      );
    }

    switch (proposal.operation) {
      case WeeklyReviewOperation.shrink:
        await _habitGateway.updateHabit(
          habit: habit,
          title: habit.title,
          description: habit.description,
          cadence: _cadenceFromReview(after.cadence),
        );
      case WeeklyReviewOperation.pause:
        await _habitGateway.setHabitLifecycle(
          habit: habit,
          lifecycle: HabitLifecycle.paused,
        );
      case WeeklyReviewOperation.archive:
        await _habitGateway.setHabitLifecycle(
          habit: habit,
          lifecycle: HabitLifecycle.archived,
        );
      case WeeklyReviewOperation.keep:
      case WeeklyReviewOperation.replace:
      case WeeklyReviewOperation.defer:
        throw const WeeklyReviewProposalApplyException(
          'This proposal cannot be applied directly.',
        );
    }

    var snapshotRefreshFailed = false;
    try {
      await _refreshDailySnapshot();
    } catch (_) {
      snapshotRefreshFailed = true;
    }
    return WeeklyReviewApplyResult(
      WeeklyReviewApplyStatus.applied,
      snapshotRefreshFailed: snapshotRefreshFailed,
    );
  }

  Future<void> _requireCurrentProposal(
    WeeklyReviewProposal proposal, {
    required String expectedReviewId,
    required String expectedSourceFingerprint,
  }) async {
    late final WeeklyReviewFeed feed;
    try {
      feed = await _loadLatestReview();
    } catch (_) {
      throw const WeeklyReviewProposalApplyException(
        'Weekly review could not be revalidated. No habit change was made.',
      );
    }
    final review = feed.review;
    if (feed.origin != WeeklyReviewOrigin.authenticatedBackend ||
        feed.freshness != WeeklyReviewFreshness.current ||
        review == null ||
        review.id != expectedReviewId ||
        review.provenance.sourceFingerprint != expectedSourceFingerprint) {
      throw const WeeklyReviewProposalApplyException(
        'Weekly review changed before confirmation. Refresh before applying it.',
      );
    }
    final matches = review.proposals.where(
      (candidate) => candidate.id == proposal.id,
    );
    if (matches.length != 1 ||
        !_sameApplicableProposal(matches.single, proposal)) {
      throw const WeeklyReviewProposalApplyException(
        'Weekly review changed before confirmation. Refresh before applying it.',
      );
    }
  }
}

bool _sameApplicableProposal(
  WeeklyReviewProposal latest,
  WeeklyReviewProposal displayed,
) =>
    latest.targetId == displayed.targetId &&
    latest.targetTitle == displayed.targetTitle &&
    latest.operation == displayed.operation &&
    latest.ownership == displayed.ownership &&
    latest.applicationMode == displayed.applicationMode &&
    latest.expectedUpdatedAt.isAtSameMomentAs(displayed.expectedUpdatedAt) &&
    latest.change.before == displayed.change.before &&
    latest.change.after == displayed.change.after;

WeeklyReviewHabitState _stateFromHabit(HabitV1 habit) => WeeklyReviewHabitState(
      lifecycle: switch (habit.lifecycle) {
        HabitLifecycle.active => WeeklyReviewHabitLifecycle.active,
        HabitLifecycle.paused => WeeklyReviewHabitLifecycle.paused,
        HabitLifecycle.archived => WeeklyReviewHabitLifecycle.archived,
      },
      cadence: switch (habit.cadence.kind) {
        HabitCadenceKind.daily => WeeklyReviewHabitCadence(
            kind: WeeklyReviewCadenceKind.daily,
            weeklyTarget: null,
            scheduledWeekdays: const [],
          ),
        HabitCadenceKind.weekdays => WeeklyReviewHabitCadence(
            kind: WeeklyReviewCadenceKind.weekdays,
            weeklyTarget: null,
            scheduledWeekdays: habit.cadence.scheduledWeekdays.toList()..sort(),
          ),
        HabitCadenceKind.weeklyTarget => WeeklyReviewHabitCadence(
            kind: WeeklyReviewCadenceKind.weeklyTarget,
            weeklyTarget: habit.cadence.weeklyTarget,
            scheduledWeekdays: const [],
          ),
      },
    );

HabitCadence _cadenceFromReview(WeeklyReviewHabitCadence cadence) =>
    switch (cadence.kind) {
      WeeklyReviewCadenceKind.daily => HabitCadence.daily(),
      WeeklyReviewCadenceKind.weekdays =>
        HabitCadence.weekdays(cadence.scheduledWeekdays),
      WeeklyReviewCadenceKind.weeklyTarget =>
        HabitCadence.weeklyTarget(cadence.weeklyTarget!),
    };

class WeeklyReviewProposalApplyException implements Exception {
  const WeeklyReviewProposalApplyException(this.message);

  final String message;

  @override
  String toString() => message;
}
