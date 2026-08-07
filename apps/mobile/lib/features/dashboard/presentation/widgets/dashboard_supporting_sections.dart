import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_category_visuals.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_visual_tokens.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_schedule_day_card.dart';
import '../../../briefings/domain/decision_feedback.dart';
import '../../../optimization/domain/entities/recommendation_feed.dart';
import '../../domain/entities/dashboard_full_week.dart';
import 'dashboard_section_widgets.dart';
import 'recommendation_card.dart';

class DashboardSupportingState {
  const DashboardSupportingState({
    required this.accountData,
    required this.canUseWeeklyReview,
    required this.recommendations,
    required this.feedback,
    required this.fullWeek,
    required this.isRefreshingRecommendations,
    required this.recommendationRefreshError,
  });

  final bool accountData;
  final bool canUseWeeklyReview;
  final AsyncValue<RecommendationFeed>? recommendations;
  final AsyncValue<List<DecisionFeedback>>? feedback;
  final AsyncValue<DashboardFullWeekProjection>? fullWeek;
  final bool isRefreshingRecommendations;
  final String? recommendationRefreshError;
}

class DashboardSupportingActions {
  const DashboardSupportingActions({
    required this.onToggleRecommendations,
    required this.onToggleFeedback,
    required this.onToggleFullWeek,
    required this.onOpenWeeklyReview,
    required this.onRetryRecommendations,
    required this.onRefreshRecommendations,
    required this.onRetryFeedback,
    required this.onDeleteFeedback,
    required this.onRetryFullWeek,
    required this.onOpenPreparationPlan,
  });

  final VoidCallback onToggleRecommendations;
  final VoidCallback onToggleFeedback;
  final VoidCallback onToggleFullWeek;
  final VoidCallback onOpenWeeklyReview;
  final VoidCallback onRetryRecommendations;
  final VoidCallback onRefreshRecommendations;
  final VoidCallback onRetryFeedback;
  final Future<void> Function(DecisionFeedback item) onDeleteFeedback;
  final VoidCallback onRetryFullWeek;
  final ValueChanged<String> onOpenPreparationPlan;
}

class DashboardSupportingSections extends StatelessWidget {
  const DashboardSupportingSections({
    super.key,
    required this.recommendationsExpanded,
    required this.feedbackExpanded,
    required this.fullWeekExpanded,
    required this.state,
    required this.actions,
  });

  final bool recommendationsExpanded;
  final bool feedbackExpanded;
  final bool fullWeekExpanded;
  final DashboardSupportingState state;
  final DashboardSupportingActions actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.canUseWeeklyReview) ...[
          _WeeklyReviewEntry(
            key: const ValueKey('dashboard-weekly-review'),
            onOpen: actions.onOpenWeeklyReview,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        DashboardInlineExpansionCard(
          key: const ValueKey('dashboard-recommendations'),
          title: 'Recommendations',
          subtitle: 'Rule-based suggestions from your available signals.',
          expanded: recommendationsExpanded,
          onToggle: actions.onToggleRecommendations,
          child: _RecommendationsContent(
            value: state.recommendations,
            accountData: state.accountData,
            isRefreshing: state.isRefreshingRecommendations,
            refreshError: state.recommendationRefreshError,
            onRetry: actions.onRetryRecommendations,
            onRefresh: actions.onRefreshRecommendations,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        DashboardInlineExpansionCard(
          key: const ValueKey('dashboard-feedback-history'),
          title: 'Decision feedback history',
          subtitle: 'Inspect or delete previously saved feedback.',
          expanded: feedbackExpanded,
          onToggle: actions.onToggleFeedback,
          child: _FeedbackHistoryContent(
            value: state.feedback,
            onRetry: actions.onRetryFeedback,
            onDelete: actions.onDeleteFeedback,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        DashboardInlineExpansionCard(
          key: const ValueKey('dashboard-full-week'),
          title: 'Full week',
          subtitle:
              'This profile-local Monday–Sunday with Setup and Preparation.',
          expanded: fullWeekExpanded,
          onToggle: actions.onToggleFullWeek,
          child: _FullWeekContent(
            value: state.fullWeek,
            onRetry: actions.onRetryFullWeek,
            onOpenPreparationPlan: actions.onOpenPreparationPlan,
          ),
        ),
      ],
    );
  }
}

class _WeeklyReviewEntry extends StatelessWidget {
  const _WeeklyReviewEntry({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          AppIcons.eventNoteOutlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: const Text('Review your week'),
        subtitle: const Text(
          'Completed, skipped, missed, carried, and recovery facts stay distinct.',
        ),
        trailing: const Icon(AppIcons.chevronRight),
        onTap: onOpen,
      ),
    );
  }
}

class _RecommendationsContent extends StatelessWidget {
  const _RecommendationsContent({
    required this.value,
    required this.accountData,
    required this.isRefreshing,
    required this.refreshError,
    required this.onRetry,
    required this.onRefresh,
  });

  final AsyncValue<RecommendationFeed>? value;
  final bool accountData;
  final bool isRefreshing;
  final String? refreshError;
  final VoidCallback onRetry;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final current = value;
    if (current == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (accountData)
          OutlinedButton.icon(
            onPressed: isRefreshing ? null : onRefresh,
            icon: isRefreshing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppIcons.refresh, size: 18),
            label: const Text('Refresh recommendations'),
          ),
        if (refreshError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          DashboardInlineMessage(
            icon: AppIcons.errorOutline,
            message: refreshError!,
            color: Theme.of(context).colorScheme.error,
          ),
        ],
        if (accountData) const SizedBox(height: AppSpacing.md),
        current.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (_, __) => DashboardSectionErrorCard(
            title: 'Recommendations unavailable',
            message: 'Your account data was not replaced with demo content.',
            onRetry: onRetry,
          ),
          data: (feed) => _RecommendationFeedView(feed: feed),
        ),
      ],
    );
  }
}

class _RecommendationFeedView extends StatelessWidget {
  const _RecommendationFeedView({required this.feed});

  final RecommendationFeed feed;

  @override
  Widget build(BuildContext context) {
    final isDemo = feed.provenance == RecommendationProvenance.demo;
    final freshness = switch (feed.freshness) {
      RecommendationFreshness.current => 'Up to date',
      RecommendationFreshness.missing => 'Not created yet',
      RecommendationFreshness.olderThanSevenDays => 'Older than 7 days',
      RecommendationFreshness.periodMismatch => 'From an earlier period',
      RecommendationFreshness.notApplicable => 'Demo',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            DashboardStatusPill(
              icon: isDemo ? AppIcons.scienceOutlined : AppIcons.ruleOutlined,
              label: isDemo ? 'Example suggestions' : 'Rule-based suggestions',
            ),
            DashboardStatusPill(
              icon: feed.freshness.needsRefresh
                  ? AppIcons.history
                  : AppIcons.checkCircleOutline,
              label: freshness,
            ),
            if (feed.generatedAt != null)
              DashboardStatusPill(
                icon: AppIcons.schedule,
                label: DateFormat.yMMMd().add_Hm().format(feed.generatedAt!),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (feed.items.isEmpty)
          const DashboardEmptySectionCard(
            icon: AppIcons.lightbulbOutline,
            message: 'No current recommendations yet.',
          )
        else
          for (final item in feed.items.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: RecommendationCard(recommendation: item),
            ),
      ],
    );
  }
}

class _FeedbackHistoryContent extends StatefulWidget {
  const _FeedbackHistoryContent({
    required this.value,
    required this.onRetry,
    required this.onDelete,
  });

  final AsyncValue<List<DecisionFeedback>>? value;
  final VoidCallback onRetry;
  final Future<void> Function(DecisionFeedback item) onDelete;

  @override
  State<_FeedbackHistoryContent> createState() =>
      _FeedbackHistoryContentState();
}

class _FeedbackHistoryContentState extends State<_FeedbackHistoryContent> {
  final _deleting = <String>{};

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    if (value == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent feedback can influence matching rankings for up to 28 days. Deleting feedback does not change original briefing evidence.',
        ),
        const SizedBox(height: AppSpacing.md),
        value.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => DashboardSectionErrorCard(
            title: 'Feedback history unavailable',
            message: 'Saved feedback could not be loaded.',
            onRetry: widget.onRetry,
          ),
          data: (items) {
            if (items.isEmpty) {
              return const DashboardEmptySectionCard(
                icon: AppIcons.historyOutlined,
                message: 'No recent feedback.',
              );
            }
            return Column(
              children: [
                for (final item in items)
                  ListTile(
                    key: ValueKey('feedback-history-${item.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(_feedbackTypeLabel(item.feedbackType)),
                    subtitle: Text(
                      '${item.actionKind} · ${DateFormat.yMMMd().add_Hm().format(item.createdAt.toLocal())}',
                    ),
                    trailing: _deleting.contains(item.id)
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            tooltip: 'Delete feedback',
                            onPressed: () => _delete(item),
                            icon: const Icon(AppIcons.deleteOutline),
                          ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _delete(DecisionFeedback item) async {
    if (_deleting.contains(item.id)) return;
    setState(() => _deleting.add(item.id));
    try {
      await widget.onDelete(item);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feedback could not be deleted.')),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting.remove(item.id));
    }
  }
}

class _FullWeekContent extends StatelessWidget {
  const _FullWeekContent({
    required this.value,
    required this.onRetry,
    required this.onOpenPreparationPlan,
  });

  final AsyncValue<DashboardFullWeekProjection>? value;
  final VoidCallback onRetry;
  final ValueChanged<String> onOpenPreparationPlan;

  @override
  Widget build(BuildContext context) {
    final current = value;
    if (current == null) return const SizedBox.shrink();
    return current.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (_, __) => DashboardSectionErrorCard(
        title: 'Full week unavailable',
        message: 'No partial week was invented.',
        onRetry: onRetry,
      ),
      data: (projection) {
        final notices = [
          projection.commitmentLoadError,
          projection.preparationLoadError,
        ].whereType<String>().toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final notice in notices) ...[
              DashboardInlineMessage(
                icon: AppIcons.warningAmberOutlined,
                message: notice,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (projection.ratingLoadError case final ratingError?) ...[
              DashboardInlineMessage(
                icon: AppIcons.infoOutline,
                message: ratingError,
                color: context.visualTokens.attention,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            for (final day in projection.days) ...[
              AppScheduleDayCard(
                localDate: day.localDate,
                items: day.items.map(_fullWeekItemView).toList(growable: false),
                emptyLabel: projection.hasPartialSourceFailure
                    ? 'No items from the available source.'
                    : 'No Setup or Preparation items.',
                onItemTap: (view) {
                  final item = view.payload! as DashboardFullWeekItem;
                  final planId = item.planId;
                  if (planId != null) onOpenPreparationPlan(planId);
                },
              ),
              if (day != projection.days.last)
                const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

AppScheduleDayItem _fullWeekItemView(DashboardFullWeekItem item) {
  final detail = [
    item.timeLabel,
    if (item.location != null) item.location!,
    if (item.preparationState != null)
      _preparationStateLabel(item.preparationState!),
  ].join(' · ');
  return AppScheduleDayItem(
    id: item.id,
    title: item.title,
    detail: detail,
    category: item.kind == DashboardFullWeekItemKind.preparation
        ? AppCategory.preparation
        : AppCategory.setup,
    actionable: item.planId != null,
    status: switch (item.status) {
      DashboardAppointmentStatus.notApplicable =>
        AppScheduleItemStatus.notApplicable,
      DashboardAppointmentStatus.open => AppScheduleItemStatus.open,
      DashboardAppointmentStatus.completed => AppScheduleItemStatus.completed,
      DashboardAppointmentStatus.fullyRated => AppScheduleItemStatus.fullyRated,
    },
    payload: item,
  );
}

String _feedbackTypeLabel(DecisionFeedbackType type) => switch (type) {
      DecisionFeedbackType.done => 'Done',
      DecisionFeedbackType.later => 'Later',
      DecisionFeedbackType.notHelpful => 'Not helpful',
      DecisionFeedbackType.tooMuch => 'Too much today',
      DecisionFeedbackType.doesNotFit => 'Does not fit',
    };

String _preparationStateLabel(String state) => switch (state) {
      'upcoming' => 'Upcoming',
      'partial' => 'Partly tracked',
      'completed' => 'Completed',
      'missed' => 'Missed',
      _ => 'Preparation',
    };
