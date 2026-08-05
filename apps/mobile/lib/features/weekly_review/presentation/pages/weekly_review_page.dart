import 'package:flutter/material.dart';

import 'package:my_life_graph/core/constants/app_radii.dart';

import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../domain/weekly_review.dart';
import 'package:my_life_graph/composition/weekly_review_providers.dart';

class WeeklyReviewPage extends ConsumerStatefulWidget {
  const WeeklyReviewPage({super.key});

  @override
  ConsumerState<WeeklyReviewPage> createState() => _WeeklyReviewPageState();
}

class _WeeklyReviewPageState extends ConsumerState<WeeklyReviewPage> {
  bool _isGenerating = false;
  String? _generationError;

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(latestWeeklyReviewProvider);
    return AppPage(
      title: 'Weekly review',
      subtitle: 'What happened last week, based on saved activity',
      backFallback: AppRoutes.dashboard,
      actions: [
        IconButton(
          tooltip: 'Retry weekly review',
          onPressed: _isGenerating
              ? null
              : () => ref.invalidate(latestWeeklyReviewProvider),
          icon: const Icon(AppIcons.refresh),
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
              'Weekly reviews require a synced account. Demo data is not presented as your personal review.',
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
          onRefresh: () => _generate(feed, force: true),
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
            'Nothing was replaced. Check your connection and try loading the review again.',
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(AppIcons.refresh),
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
            'There is not enough saved activity yet. Keep completing tasks, habits, Focus sessions, and recovery check-ins. Nothing will change automatically.',
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
            'Create a rule-based review from your saved activity. This does not change any task, habit, or calendar item.',
          ),
          if (generationError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              generationError!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
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
                : const Icon(AppIcons.factCheckOutlined),
            label: Text(
              isGenerating ? 'Creating…' : 'Create weekly review',
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
    required this.onRefresh,
  });

  final WeeklyReviewFeed feed;
  final bool isGenerating;
  final String? generationError;
  final VoidCallback onRefresh;

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
                  _ReviewPill(label: stale ? 'Needs update' : 'Up to date'),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(review.narrative),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${_qualityLabel(review.dataQuality)} data · rule-based · not AI-written',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              if (stale) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Text(
                    'Your saved activity changed after this review. Update it to see the current weekly facts.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _WeeklyFactsCard(
          facts: review.facts,
          isGenerating: isGenerating,
          generationError: generationError,
          onRefresh: onRefresh,
        ),
      ],
    );
  }
}

class _WeeklyFactsCard extends StatelessWidget {
  const _WeeklyFactsCard({
    required this.facts,
    required this.isGenerating,
    required this.generationError,
    required this.onRefresh,
  });

  final WeeklyReviewFacts facts;
  final bool isGenerating;
  final String? generationError;
  final VoidCallback onRefresh;

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
          if (generationError != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              generationError!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: isGenerating ? null : onRefresh,
            icon: isGenerating
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppIcons.refresh),
            label: Text(
              isGenerating ? 'Updating…' : 'Update weekly review',
            ),
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
        borderRadius: BorderRadius.circular(AppRadii.md),
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
        borderRadius: BorderRadius.circular(AppRadii.pill),
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
