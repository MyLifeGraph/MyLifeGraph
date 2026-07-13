import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../briefings/presentation/providers/briefing_providers.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../application/weekly_review_proposal_applier.dart';
import '../../domain/weekly_review.dart';
import '../providers/weekly_review_providers.dart';

class WeeklyReviewPage extends ConsumerStatefulWidget {
  const WeeklyReviewPage({super.key});

  @override
  ConsumerState<WeeklyReviewPage> createState() => _WeeklyReviewPageState();
}

class _WeeklyReviewPageState extends ConsumerState<WeeklyReviewPage> {
  bool _isGenerating = false;
  String? _generationError;
  final Set<String> _applyingProposalIds = {};
  final Set<String> _appliedProposalIds = {};
  final Set<String> _noChangeProposalIds = {};
  String? _proposalError;

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(latestWeeklyReviewProvider);
    return AppPage(
      title: 'Weekly review',
      subtitle: 'A bounded look at the last completed week',
      actions: [
        IconButton(
          tooltip: 'Retry weekly review',
          onPressed: _isGenerating
              ? null
              : () => ref.invalidate(latestWeeklyReviewProvider),
          icon: const Icon(Icons.refresh),
        ),
      ],
      children: [
        value.when(
          loading: () => const AppCard(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (_, __) => _ReviewReadError(
            onRetry: () => ref.invalidate(latestWeeklyReviewProvider),
          ),
          data: _buildFeed,
        ),
      ],
    );
  }

  Widget _buildFeed(WeeklyReviewFeed feed) {
    if (feed.origin == WeeklyReviewOrigin.localDemo) {
      return const AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weekly review unavailable',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: AppSpacing.sm),
            Text(
              'Weekly reviews require a synced account. No personalized review was fabricated for local demo mode.',
            ),
          ],
        ),
      );
    }
    return switch (feed.freshness) {
      WeeklyReviewFreshness.notReady => _NotReadyReviewCard(feed: feed),
      WeeklyReviewFreshness.missing => _MissingReviewCard(
          feed: feed,
          isGenerating: _isGenerating,
          generationError: _generationError,
          onGenerate: () => _generate(feed, force: false),
        ),
      WeeklyReviewFreshness.current ||
      WeeklyReviewFreshness.stale =>
        _CurrentReview(
          feed: feed,
          isGenerating: _isGenerating,
          generationError: _generationError,
          applyingProposalIds: _applyingProposalIds,
          appliedProposalIds: _appliedProposalIds,
          noChangeProposalIds: _noChangeProposalIds,
          proposalError: _proposalError,
          onRefresh: () => _generate(feed, force: true),
          onProposal: (proposal) => _handleProposal(feed, proposal),
        ),
    };
  }

  Future<void> _generate(
    WeeklyReviewFeed feed, {
    required bool force,
  }) async {
    if (_isGenerating) return;
    setState(() {
      _isGenerating = true;
      _generationError = null;
    });
    try {
      await ref.read(weeklyReviewRepositoryProvider).generate(
            periodKey: feed.periodKey,
            force: force,
          );
      ref.invalidate(latestWeeklyReviewProvider);
      if (mounted) {
        setState(() {
          _appliedProposalIds.clear();
          _noChangeProposalIds.clear();
          _proposalError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _generationError =
              'Weekly review could not be refreshed. Existing content was kept.';
        });
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _handleProposal(
    WeeklyReviewFeed feed,
    WeeklyReviewProposal proposal,
  ) async {
    if (feed.freshness == WeeklyReviewFreshness.stale ||
        _applyingProposalIds.contains(proposal.id)) {
      return;
    }
    if (proposal.applicationMode == WeeklyReviewApplicationMode.directHabit) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _ApplyProposalDialog(proposal: proposal),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() {
      _applyingProposalIds.add(proposal.id);
      _proposalError = null;
    });
    try {
      final review = feed.review!;
      final result = await ref.read(weeklyReviewProposalApplierProvider).apply(
            proposal,
            expectedReviewId: review.id,
            expectedSourceFingerprint: review.provenance.sourceFingerprint,
          );
      if (!mounted) return;
      switch (result.status) {
        case WeeklyReviewApplyStatus.applied:
          setState(() => _appliedProposalIds.add(proposal.id));
          ref.invalidate(latestWeeklyReviewProvider);
          ref.invalidate(dashboardSnapshotProvider);
          ref.invalidate(todayBriefingProvider);
          _showMessage(
            result.snapshotRefreshFailed
                ? 'Habit saved; daily snapshot refresh failed.'
                : 'Habit change saved.',
          );
        case WeeklyReviewApplyStatus.kept:
          setState(() => _noChangeProposalIds.add(proposal.id));
          _showMessage('Current habit kept. No change was made.');
        case WeeklyReviewApplyStatus.requiresSetup:
          context.go('${AppRoutes.onboarding}?edit=1');
        case WeeklyReviewApplyStatus.stagedOnly:
          if (proposal.operation == WeeklyReviewOperation.replace) {
            context.go(AppRoutes.habitManagement);
          } else {
            setState(() => _noChangeProposalIds.add(proposal.id));
            _showMessage('Change deferred. No habit was changed.');
          }
      }
    } catch (error) {
      if (mounted) {
        if (error is WeeklyReviewProposalApplyException) {
          ref.invalidate(latestWeeklyReviewProvider);
        }
        setState(() {
          _proposalError = error is WeeklyReviewProposalApplyException
              ? error.message
              : 'Habit change could not be confirmed. Refresh and retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _applyingProposalIds.remove(proposal.id));
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _ReviewReadError extends StatelessWidget {
  const _ReviewReadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weekly review unavailable',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Your account data was not replaced with a generated or demo review.',
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry weekly review'),
          ),
        ],
      ),
    );
  }
}

class _NotReadyReviewCard extends StatelessWidget {
  const _NotReadyReviewCard({required this.feed});

  final WeeklyReviewFeed feed;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weekly review not ready',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(_periodLabel(feed)),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'There is not enough trustworthy weekly evidence yet. Keep using explicit task, habit, focus, and recovery outcomes; no plan change was inferred.',
          ),
        ],
      ),
    );
  }
}

class _MissingReviewCard extends StatelessWidget {
  const _MissingReviewCard({
    required this.feed,
    required this.isGenerating,
    required this.generationError,
    required this.onGenerate,
  });

  final WeeklyReviewFeed feed;
  final bool isGenerating;
  final String? generationError;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No weekly review yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(_periodLabel(feed)),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Generate a deterministic review deliberately. This does not change any task, habit, goal, or schedule item.',
          ),
          if (generationError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              generationError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: isGenerating ? null : onGenerate,
            icon: isGenerating
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined),
            label: Text(
              isGenerating ? 'Generating…' : 'Generate weekly review',
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentReview extends StatelessWidget {
  const _CurrentReview({
    required this.feed,
    required this.isGenerating,
    required this.generationError,
    required this.applyingProposalIds,
    required this.appliedProposalIds,
    required this.noChangeProposalIds,
    required this.proposalError,
    required this.onRefresh,
    required this.onProposal,
  });

  final WeeklyReviewFeed feed;
  final bool isGenerating;
  final String? generationError;
  final Set<String> applyingProposalIds;
  final Set<String> appliedProposalIds;
  final Set<String> noChangeProposalIds;
  final String? proposalError;
  final VoidCallback onRefresh;
  final ValueChanged<WeeklyReviewProposal> onProposal;

  @override
  Widget build(BuildContext context) {
    final review = feed.review!;
    final stale = feed.freshness == WeeklyReviewFreshness.stale;
    return Column(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Last week in context',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(_periodLabel(feed)),
                      ],
                    ),
                  ),
                  _ReviewPill(label: stale ? 'Stale' : 'Current'),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(review.narrative),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${_qualityLabel(review.dataQuality)} data · deterministic · no LLM',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              if (stale) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Source facts changed after this review. Refresh before applying a proposal.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _WeeklyFactsCard(facts: review.facts),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Proposed adjustments',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'At most two bounded changes. Nothing is applied without your explicit choice.',
              ),
              const SizedBox(height: AppSpacing.md),
              if (review.proposals.isEmpty)
                const Text('No change is suggested for this week.')
              else
                ...review.proposals.map(
                  (proposal) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _ProposalCard(
                      proposal: proposal,
                      stale: stale,
                      isApplying: applyingProposalIds.contains(proposal.id),
                      isApplied: appliedProposalIds.contains(proposal.id),
                      isNoChange: noChangeProposalIds.contains(proposal.id),
                      onPressed: () => onProposal(proposal),
                    ),
                  ),
                ),
              if (proposalError != null) ...[
                Text(
                  proposalError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (generationError != null) ...[
                Text(
                  generationError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              OutlinedButton.icon(
                onPressed: isGenerating ? null : onRefresh,
                icon: isGenerating
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(
                  isGenerating ? 'Refreshing…' : 'Refresh weekly review',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeeklyFactsCard extends StatelessWidget {
  const _WeeklyFactsCard({required this.facts});

  final WeeklyReviewFacts facts;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Explicit weekly facts',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _FactTile(
                label: 'Completed',
                value:
                    '${facts.tasks.completed} tasks · ${facts.habits.completed} habit outcomes',
              ),
              _FactTile(label: 'Skipped', value: '${facts.habits.skipped}'),
              _FactTile(label: 'Missed', value: '${facts.habits.missed}'),
              _FactTile(
                label: 'Carried',
                value:
                    '${facts.tasks.carried} · ${facts.tasks.overdueCarried} overdue',
              ),
              _FactTile(
                label: 'Recovery days',
                value:
                    '${facts.recovery.recoveryDays}/${facts.recovery.observedDays} observed',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${facts.habits.scheduledOpportunities} scheduled habit opportunities · '
            '${facts.habits.recoveryOpen} recovery-open · '
            '${facts.habits.unknown} unknown',
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${facts.habits.stableDefinitions} stable habit definitions · '
            '${facts.habits.changedDefinitions} changed definitions',
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${facts.focus.completedSessions} completed focus sessions · '
            '${facts.focus.actualMinutes} actual minutes · '
            '${facts.feedback.total} recommendation feedback events',
          ),
        ],
      ),
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 128),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.stale,
    required this.isApplying,
    required this.isApplied,
    required this.isNoChange,
    required this.onPressed,
  });

  final WeeklyReviewProposal proposal;
  final bool stale;
  final bool isApplying;
  final bool isApplied;
  final bool isNoChange;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            proposal.targetTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_operationLabel(proposal.operation)} · '
            '${_ownershipLabel(proposal.ownership)}',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(proposal.reason),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${_stateLabel(proposal.change.before)} → '
            '${proposal.change.after == null ? 'Staged for manual review' : _stateLabel(proposal.change.after!)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: stale || isApplying || isApplied || isNoChange
                ? null
                : onPressed,
            icon: isApplying
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_proposalIcon(proposal.applicationMode)),
            label: Text(
              isApplied
                  ? 'Change applied'
                  : isNoChange
                      ? 'No change made'
                      : _proposalButtonLabel(proposal),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplyProposalDialog extends StatelessWidget {
  const _ApplyProposalDialog({required this.proposal});

  final WeeklyReviewProposal proposal;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Apply this habit change?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(proposal.targetTitle),
          const SizedBox(height: AppSpacing.sm),
          Text(_stateLabel(proposal.change.before)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Icon(Icons.arrow_downward, size: 18),
          ),
          Text(_stateLabel(proposal.change.after!)),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Only this manual habit will change. Its outcome history is preserved.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep current'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Apply change'),
        ),
      ],
    );
  }
}

class _ReviewPill extends StatelessWidget {
  const _ReviewPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

String _periodLabel(WeeklyReviewFeed feed) =>
    '${DateFormat.MMMd().format(feed.startsOn)}–'
    '${DateFormat.yMMMd().format(feed.endsOn)} · ${feed.timezone}';

String _qualityLabel(WeeklyReviewDataQuality quality) => switch (quality) {
      WeeklyReviewDataQuality.insufficient => 'Insufficient',
      WeeklyReviewDataQuality.partial => 'Partial',
      WeeklyReviewDataQuality.sufficient => 'Sufficient',
    };

String _operationLabel(WeeklyReviewOperation operation) => switch (operation) {
      WeeklyReviewOperation.keep => 'Keep',
      WeeklyReviewOperation.shrink => 'Shrink',
      WeeklyReviewOperation.pause => 'Pause',
      WeeklyReviewOperation.replace => 'Replace',
      WeeklyReviewOperation.archive => 'Archive',
      WeeklyReviewOperation.defer => 'Defer',
    };

String _ownershipLabel(WeeklyReviewOwnership ownership) => switch (ownership) {
      WeeklyReviewOwnership.manual => 'Manual habit',
      WeeklyReviewOwnership.setup => 'Setup-managed habit',
    };

String _proposalButtonLabel(WeeklyReviewProposal proposal) =>
    switch (proposal.applicationMode) {
      WeeklyReviewApplicationMode.directHabit => 'Apply change',
      WeeklyReviewApplicationMode.settingsSetup => 'Review in Setup',
      WeeklyReviewApplicationMode.stagedOnly =>
        proposal.operation == WeeklyReviewOperation.replace
            ? 'Manage habits'
            : 'Keep current',
      WeeklyReviewApplicationMode.none => 'Keep current',
    };

IconData _proposalIcon(WeeklyReviewApplicationMode mode) => switch (mode) {
      WeeklyReviewApplicationMode.directHabit => Icons.check,
      WeeklyReviewApplicationMode.settingsSetup => Icons.tune_outlined,
      WeeklyReviewApplicationMode.stagedOnly => Icons.open_in_new,
      WeeklyReviewApplicationMode.none => Icons.remove_circle_outline,
    };

String _stateLabel(WeeklyReviewHabitState state) =>
    '${_lifecycleLabel(state.lifecycle)} · ${_cadenceLabel(state.cadence)}';

String _lifecycleLabel(WeeklyReviewHabitLifecycle lifecycle) =>
    switch (lifecycle) {
      WeeklyReviewHabitLifecycle.active => 'Active',
      WeeklyReviewHabitLifecycle.paused => 'Paused',
      WeeklyReviewHabitLifecycle.archived => 'Archived',
    };

String _cadenceLabel(WeeklyReviewHabitCadence cadence) =>
    switch (cadence.kind) {
      WeeklyReviewCadenceKind.daily => 'Daily',
      WeeklyReviewCadenceKind.weekdays =>
        'Weekdays ${cadence.scheduledWeekdays.join(', ')}',
      WeeklyReviewCadenceKind.weeklyTarget =>
        '${cadence.weeklyTarget} times per week',
    };
