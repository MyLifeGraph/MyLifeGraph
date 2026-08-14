import 'package:flutter/material.dart';

import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_info_disclosure.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_surface.dart';
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
              'Weekly reviews are available after you sign in with a synced account.',
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
            'The review could not be loaded. Check your connection and try again.',
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final summary = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last week in context',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(_periodLabel(feed)),
                    ],
                  );
                  final status = AppStatusPill(
                    label: stale ? 'Needs update' : 'Up to date',
                    tone:
                        stale ? AppStatusTone.attention : AppStatusTone.success,
                  );
                  if (constraints.maxWidth < 480 ||
                      MediaQuery.textScalerOf(context).scale(16) >= 28) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        summary,
                        const SizedBox(height: AppSpacing.sm),
                        status,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: summary),
                      const SizedBox(width: AppSpacing.sm),
                      status,
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              Text(review.narrative),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${_qualityLabel(review.dataQuality)} data quality',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              const AppInfoSectionDisclosure(
                heading: 'How this review is created',
                description:
                    'The review summarizes saved activity with fixed rules. It never changes tasks, habits, or calendar items.',
                compactHeading: true,
                keyPrefix: 'weekly-review-info',
              ),
              if (stale) ...[
                const SizedBox(height: AppSpacing.md),
                const AppStatePanel(
                  title: 'Review needs an update',
                  message:
                      'Your saved activity changed after this review. Update it to see the current weekly facts.',
                  tone: AppStatusTone.attention,
                  icon: AppIcons.updateOutlined,
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
            'Weekly facts',
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
            '${facts.focus.actualMinutes} actual minutes',
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 128),
      child: AppSurface(
        variant: AppSurfaceVariant.subtle,
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(value, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
      ),
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
