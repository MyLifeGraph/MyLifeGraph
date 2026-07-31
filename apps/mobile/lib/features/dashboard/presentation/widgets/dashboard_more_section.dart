import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../briefings/domain/decision_feedback.dart';
import 'package:my_life_graph/composition/briefing_providers.dart';
import '../../../deadline_plans/domain/deadline_plan.dart';
import 'package:my_life_graph/composition/widgets/preparation_workload_card.dart';
import '../../../optimization/domain/entities/recommendation_feed.dart';
import '../../domain/entities/dashboard_snapshot.dart';
import 'dashboard_section_widgets.dart';
import 'recommendation_card.dart';

class DashboardMoreState {
  const DashboardMoreState({
    required this.accountData,
    required this.supporting,
    required this.recommendations,
    required this.workload,
    required this.canUseWeeklyReview,
    required this.isRefreshingRecommendations,
    required this.recommendationRefreshError,
  });

  final bool accountData;
  final AsyncValue<DashboardSnapshot>? supporting;
  final AsyncValue<RecommendationFeed>? recommendations;
  final AsyncValue<PreparationWorkload>? workload;
  final bool canUseWeeklyReview;
  final bool isRefreshingRecommendations;
  final String? recommendationRefreshError;
}

class DashboardMoreActions {
  const DashboardMoreActions({
    required this.onRetryWorkload,
    required this.onLoadWorkloadDetail,
    required this.onOpenWeeklyReview,
    required this.onRetryRecommendations,
    required this.onRefreshRecommendations,
    required this.onShowFeedbackHistory,
    required this.onAddMorning,
    required this.onAddEvening,
    required this.onOpenPreparationPlan,
  });

  final VoidCallback onRetryWorkload;
  final PreparationWorkloadDetailLoader onLoadWorkloadDetail;
  final VoidCallback onOpenWeeklyReview;
  final VoidCallback onRetryRecommendations;
  final VoidCallback onRefreshRecommendations;
  final VoidCallback onShowFeedbackHistory;
  final VoidCallback onAddMorning;
  final VoidCallback onAddEvening;
  final ValueChanged<String> onOpenPreparationPlan;
}

/// Owns the lazy secondary Dashboard surface so changes to recommendations,
/// weekly review, saved signals, workload, or the full week stay out of the
/// primary Today layout.
class DashboardMoreSection extends StatelessWidget {
  const DashboardMoreSection({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.state,
    required this.actions,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final DashboardMoreState state;
  final DashboardMoreActions actions;

  @override
  Widget build(BuildContext context) {
    return DashboardInlineExpansionCard(
      key: const ValueKey('dashboard-more'),
      title: 'More',
      subtitle:
          'Workload, weekly review, saved signals, recommendations, and full week',
      expanded: expanded,
      onToggle: onToggle,
      child: _MoreDashboardContent(
        accountData: state.accountData,
        supporting: state.supporting,
        recommendations: state.recommendations,
        workload: state.workload,
        canUseWeeklyReview: state.canUseWeeklyReview,
        isRefreshingRecommendations: state.isRefreshingRecommendations,
        recommendationRefreshError: state.recommendationRefreshError,
        onRetryWorkload: actions.onRetryWorkload,
        onLoadWorkloadDetail: actions.onLoadWorkloadDetail,
        onOpenWeeklyReview: actions.onOpenWeeklyReview,
        onRetryRecommendations: actions.onRetryRecommendations,
        onRefreshRecommendations: actions.onRefreshRecommendations,
        onShowFeedbackHistory: actions.onShowFeedbackHistory,
        onAddMorning: actions.onAddMorning,
        onAddEvening: actions.onAddEvening,
        onOpenPreparationPlan: actions.onOpenPreparationPlan,
      ),
    );
  }
}

class DashboardFeedbackHistorySheet extends ConsumerWidget {
  const DashboardFeedbackHistorySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(decisionFeedbackProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Feedback history',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(AppIcons.close),
                ),
              ],
            ),
            const Text(
              'Recent feedback can influence matching rankings for up to 28 days. Delete an entry to correct it; original briefing evidence stays unchanged.',
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: value.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    const Text('Feedback history is unavailable.'),
                data: (items) {
                  if (items.isEmpty) return const Text('No recent feedback.');
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_feedbackTypeLabel(item.feedbackType)),
                        subtitle: Text(
                          '${item.actionKind} · ${DateFormat.yMMMd().add_Hm().format(item.createdAt.toLocal())}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Delete feedback',
                          onPressed: () async {
                            try {
                              await ref
                                  .read(feedbackRepositoryProvider)
                                  .delete(item.id);
                              ref.invalidate(decisionFeedbackProvider);
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Feedback could not be deleted.'),
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(AppIcons.deleteOutline),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _feedbackTypeLabel(DecisionFeedbackType type) => switch (type) {
      DecisionFeedbackType.done => 'Done',
      DecisionFeedbackType.later => 'Later',
      DecisionFeedbackType.notHelpful => 'Not helpful',
      DecisionFeedbackType.tooMuch => 'Too much today',
      DecisionFeedbackType.doesNotFit => 'Does not fit',
    };

class _WeeklyReviewEntryCard extends StatelessWidget {
  const _WeeklyReviewEntryCard({required this.onOpen});

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

class _MoreDashboardContent extends ConsumerWidget {
  const _MoreDashboardContent({
    required this.accountData,
    required this.supporting,
    required this.recommendations,
    required this.workload,
    required this.canUseWeeklyReview,
    required this.isRefreshingRecommendations,
    required this.recommendationRefreshError,
    required this.onRetryWorkload,
    required this.onLoadWorkloadDetail,
    required this.onOpenWeeklyReview,
    required this.onRetryRecommendations,
    required this.onRefreshRecommendations,
    required this.onShowFeedbackHistory,
    required this.onAddMorning,
    required this.onAddEvening,
    required this.onOpenPreparationPlan,
  });

  final bool accountData;
  final AsyncValue<DashboardSnapshot>? supporting;
  final AsyncValue<RecommendationFeed>? recommendations;
  final AsyncValue<PreparationWorkload>? workload;
  final bool canUseWeeklyReview;
  final bool isRefreshingRecommendations;
  final String? recommendationRefreshError;
  final VoidCallback onRetryWorkload;
  final PreparationWorkloadDetailLoader onLoadWorkloadDetail;
  final VoidCallback onOpenWeeklyReview;
  final VoidCallback onRetryRecommendations;
  final VoidCallback onRefreshRecommendations;
  final VoidCallback onShowFeedbackHistory;
  final VoidCallback onAddMorning;
  final VoidCallback onAddEvening;
  final ValueChanged<String> onOpenPreparationPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = supporting;
    final hasFeedbackHistory = accountData &&
        (ref.watch(decisionFeedbackProvider).valueOrNull?.isNotEmpty ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (workload != null) ...[
          PreparationWorkloadCard(
            value: workload!,
            compact: true,
            onRetry: onRetryWorkload,
            onLoadDayDetail: onLoadWorkloadDetail,
            onOpenSettings: () => context.push(AppRoutes.settings),
            onOpenPlans: () => context.push(AppRoutes.preparationPlans),
            onReviewPlan: onOpenPreparationPlan,
            onReplanPlan: (planId) => context.push(
              Uri(
                path: AppRoutes.plannerReplan,
                queryParameters: {'plan_id': planId},
              ).toString(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (canUseWeeklyReview) ...[
          _WeeklyReviewEntryCard(onOpen: onOpenWeeklyReview),
          const SizedBox(height: AppSpacing.md),
        ],
        if (details == null)
          const SizedBox.shrink()
        else
          details.when(
            loading: () => const AppCard(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const DashboardSectionErrorCard(
              title: 'Saved details unavailable',
              message:
                  'Saved check-in values and the full week could not be loaded.',
            ),
            data: (detail) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LatestCheckInCard(
                  snapshot: detail,
                  onAddEvening: onAddEvening,
                  onAddMorning: onAddMorning,
                ),
              ],
            ),
          ),
        if (recommendations != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _RecommendationsSection(
            value: recommendations!,
            accountData: accountData,
            isRefreshing: isRefreshingRecommendations,
            refreshError: recommendationRefreshError,
            onRetry: onRetryRecommendations,
            onRefresh: onRefreshRecommendations,
          ),
        ],
        if (hasFeedbackHistory) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(AppIcons.historyOutlined),
              title: const Text('Decision feedback history'),
              subtitle:
                  const Text('Inspect or delete previously saved feedback.'),
              trailing: const Icon(AppIcons.chevronRight),
              onTap: onShowFeedbackHistory,
            ),
          ),
        ],
        if (details != null)
          details.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (detail) => Padding(
              padding: const EdgeInsets.only(top: AppSpacing.lg),
              child: _ScheduleSection(
                days: detail.scheduleDays,
                preparationScheduleError: detail.preparationScheduleError,
                onOpenPreparationPlan: onOpenPreparationPlan,
              ),
            ),
          ),
      ],
    );
  }
}

class _LatestCheckInCard extends StatelessWidget {
  const _LatestCheckInCard({
    required this.snapshot,
    required this.onAddEvening,
    required this.onAddMorning,
  });

  final DashboardSnapshot snapshot;
  final VoidCallback onAddEvening;
  final VoidCallback onAddMorning;

  @override
  Widget build(BuildContext context) {
    final checkIn = snapshot.latestCheckIn;
    final metrics =
        checkIn == null ? const <_SignalMetric>[] : _metricsForCheckIn(checkIn);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
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
                      'Latest check-in',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      checkIn == null
                          ? 'No daily signals have been saved yet.'
                          : _checkInDateLabel(checkIn.entryDate),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (metrics.isEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: onAddMorning,
                  icon: const Icon(AppIcons.wbSunnyOutlined),
                  label: const Text('Morning check-in'),
                ),
                OutlinedButton.icon(
                  onPressed: onAddEvening,
                  icon: const Icon(AppIcons.nightsStayOutlined),
                  label: const Text('Evening check-in'),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children:
                  metrics.map((metric) => _SignalTile(metric: metric)).toList(),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                TextButton.icon(
                  onPressed: onAddMorning,
                  icon: const Icon(AppIcons.wbSunnyOutlined),
                  label: Text(
                    checkIn?.hasMorningCapture == true
                        ? 'Edit morning check-in'
                        : 'Add morning check-in',
                  ),
                ),
                TextButton.icon(
                  onPressed: onAddEvening,
                  icon: const Icon(AppIcons.nightsStayOutlined),
                  label: Text(
                    checkIn?.hasEveningCapture == true
                        ? 'Edit evening check-in'
                        : 'Add evening check-in',
                  ),
                ),
              ],
            ),
            if (checkIn?.stressSource != null &&
                checkIn?.stressControllability != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Stress source: ${_readableCaptureCode(checkIn!.stressSource!)} · '
                'influence: ${_stressInfluenceLabel(checkIn.stressControllability!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ],
      ),
    );
  }

  List<_SignalMetric> _metricsForCheckIn(DashboardCheckIn checkIn) {
    return [
      if (checkIn.mood != null)
        _SignalMetric('Mood', '${checkIn.mood}/10', AppIcons.moodOutlined),
      if (checkIn.energy != null)
        _SignalMetric(
          checkIn.hasMorningCapture ? 'Morning energy' : 'Evening energy',
          '${checkIn.energy}/10',
          AppIcons.boltOutlined,
        ),
      if (checkIn.sleepHours != null)
        _SignalMetric(
          'Previous-night sleep',
          '${_formatDecimal(checkIn.sleepHours!)} h',
          AppIcons.bedtimeOutlined,
        ),
      if (checkIn.sleepQuality != null)
        _SignalMetric(
          'Previous-night sleep quality',
          '${checkIn.sleepQuality}/10',
          AppIcons.nightsStayOutlined,
        ),
      if (checkIn.stress != null)
        _SignalMetric(
          'Stress',
          '${checkIn.stress}/10',
          AppIcons.speedOutlined,
        ),
      if (checkIn.focusMinutes != null)
        _SignalMetric(
          'Focus',
          '${checkIn.focusMinutes} min',
          AppIcons.timerOutlined,
        ),
      if (checkIn.focusBand != null)
        _SignalMetric(
          'Focus band',
          _readableCaptureCode(checkIn.focusBand!),
          AppIcons.timerOutlined,
        ),
      if (checkIn.dayShape != null)
        _SignalMetric(
          'Day shape',
          _readableCaptureCode(checkIn.dayShape!),
          AppIcons.calendarTodayOutlined,
        ),
      if (checkIn.steps != null)
        _SignalMetric(
          'Steps',
          NumberFormat.decimalPattern().format(checkIn.steps),
          AppIcons.directionsWalkOutlined,
        ),
      if (checkIn.activityLevel != null)
        _SignalMetric(
          'Activity',
          '${checkIn.activityLevel}/10',
          AppIcons.fitnessCenterOutlined,
        ),
      if (checkIn.screenTimeHours != null)
        _SignalMetric(
          'Screen time',
          '${_formatDecimal(checkIn.screenTimeHours!)} h',
          AppIcons.devicesOutlined,
        ),
    ];
  }

  String _checkInDateLabel(DateTime value) {
    final now = DateTime.now();
    final date = DateTime(value.year, value.month, value.day);
    final today = DateTime(now.year, now.month, now.day);
    if (date == today) {
      return 'Today · values shown exactly as saved';
    }
    if (date == today.subtract(const Duration(days: 1))) {
      return 'Yesterday · values shown exactly as saved';
    }
    return '${DateFormat.yMMMd().format(value)} · values shown exactly as saved';
  }

  String _formatDecimal(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }
}

class _SignalTile extends StatelessWidget {
  const _SignalTile({required this.metric});

  final _SignalMetric metric;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 142,
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(metric.icon, size: 20, color: colors.primary),
          const SizedBox(height: AppSpacing.sm),
          Text(metric.value, style: Theme.of(context).textTheme.titleMedium),
          Text(metric.label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

String _readableCaptureCode(String value) => value
    .replaceAll('_', ' ')
    .replaceFirstMapped(RegExp(r'^[a-z]'), (match) => match[0]!.toUpperCase());

String _stressInfluenceLabel(String value) => switch (value) {
      'hardly_controllable' => 'Little',
      'partly_controllable' => 'Some',
      'mostly_controllable' => 'Mostly within your influence',
      _ => _readableCaptureCode(value),
    };

class _RecommendationsSection extends StatelessWidget {
  const _RecommendationsSection({
    required this.value,
    required this.accountData,
    required this.isRefreshing,
    required this.refreshError,
    required this.onRetry,
    required this.onRefresh,
  });

  final AsyncValue<RecommendationFeed> value;
  final bool accountData;
  final bool isRefreshing;
  final String? refreshError;
  final VoidCallback onRetry;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashboardSectionTitle(
          title: 'Recommendations',
          subtitle: 'Rule-based suggestions from your available signals.',
          trailing: accountData
              ? OutlinedButton.icon(
                  onPressed: isRefreshing ? null : onRefresh,
                  icon: isRefreshing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(AppIcons.refresh, size: 18),
                  label: const Text('Refresh recommendations'),
                )
              : null,
        ),
        if (refreshError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          DashboardInlineMessage(
            icon: AppIcons.errorOutline,
            message: refreshError!,
            color: Theme.of(context).colorScheme.error,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        value.when(
          loading: () => const AppCard(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: CircularProgressIndicator(),
              ),
            ),
          ),
          error: (error, stackTrace) => DashboardSectionErrorCard(
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
          ...feed.items.take(3).map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: RecommendationCard(recommendation: item),
                ),
              ),
      ],
    );
  }
}

class _ScheduleSection extends StatelessWidget {
  const _ScheduleSection({
    required this.days,
    required this.preparationScheduleError,
    required this.onOpenPreparationPlan,
  });

  final List<ScheduleDay> days;
  final String? preparationScheduleError;
  final ValueChanged<String> onOpenPreparationPlan;

  @override
  Widget build(BuildContext context) {
    final daysWithEvents = days.where((day) => day.events.isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DashboardSectionTitle(
          title: 'Full week',
          subtitle: 'Recurring commitments and confirmed preparation blocks.',
        ),
        if (preparationScheduleError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            preparationScheduleError!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (daysWithEvents.isEmpty)
          const DashboardEmptySectionCard(
            icon: AppIcons.calendarTodayOutlined,
            message: 'No schedule entries this week.',
          )
        else
          ...daysWithEvents.map(
            (day) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 70,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            day.label,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            day.dateLabel,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: day.events
                            .map(
                              (event) => Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.sm,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      event.isDeadlinePreparation
                                          ? AppIcons.schoolOutlined
                                          : AppIcons.event,
                                      size: 18,
                                      color: event.isDeadlinePreparation
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : null,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(event.title),
                                          Text(
                                            event.time,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium,
                                          ),
                                          if (event.provenanceLabel != null)
                                            Text(
                                              [
                                                event.provenanceLabel!,
                                                if (event.state != null)
                                                  _preparationStateLabel(
                                                    event.state!,
                                                  ),
                                              ].join(' · '),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (event.deadlinePlanId != null)
                                      IconButton(
                                        tooltip: 'Open preparation plan',
                                        onPressed: () => onOpenPreparationPlan(
                                          event.deadlinePlanId!,
                                        ),
                                        icon: const Icon(
                                          AppIcons.arrowForward,
                                          size: 18,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _preparationStateLabel(String state) => switch (state) {
      'upcoming' => 'Upcoming',
      'partial' => 'Partly tracked',
      'completed' => 'Completed',
      'missed' => 'Missed',
      _ => 'Preparation',
    };

class _SignalMetric {
  const _SignalMetric(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}
