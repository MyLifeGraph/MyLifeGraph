import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_category_visuals.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_schedule_day_card.dart';
import '../../../../core/widgets/app_surface.dart';
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
    required this.onFullWeekAction,
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
  final ValueChanged<DashboardFullWeekAction> onFullWeekAction;
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

  Widget get compact => _DashboardSupportingCompactSections(
        recommendationsExpanded: recommendationsExpanded,
        feedbackExpanded: feedbackExpanded,
        state: state,
        actions: actions,
      );

  Widget get fullWeek => DashboardFullWeekSection(
        expanded: fullWeekExpanded,
        value: state.fullWeek,
        actions: actions,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        compact,
        const SizedBox(height: AppSpacing.sm),
        fullWeek,
      ],
    );
  }
}

class _DashboardSupportingCompactSections extends StatelessWidget {
  const _DashboardSupportingCompactSections({
    required this.recommendationsExpanded,
    required this.feedbackExpanded,
    required this.state,
    required this.actions,
  });

  final bool recommendationsExpanded;
  final bool feedbackExpanded;
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
      ],
    );
  }
}

class DashboardFullWeekSection extends StatelessWidget {
  const DashboardFullWeekSection({
    super.key,
    required this.expanded,
    required this.value,
    required this.actions,
  });

  final bool expanded;
  final AsyncValue<DashboardFullWeekProjection>? value;
  final DashboardSupportingActions actions;

  @override
  Widget build(BuildContext context) {
    return DashboardInlineExpansionCard(
      key: const ValueKey('dashboard-full-week'),
      title: 'Full week',
      subtitle:
          'Your profile-local Monday–Sunday agenda across Setup, Preparation, Calendar, Focus, Planner Tasks, Habits, and Fixed commitments.',
      expanded: expanded,
      onToggle: actions.onToggleFullWeek,
      child: _FullWeekContent(
        value: value,
        onRetry: actions.onRetryFullWeek,
        onAction: actions.onFullWeekAction,
      ),
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
            message: 'Your recommendations could not be loaded right now.',
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
              tone: AppStatusTone.info,
            ),
            DashboardStatusPill(
              icon: feed.freshness.needsRefresh
                  ? AppIcons.history
                  : AppIcons.checkCircleOutline,
              label: freshness,
              tone: feed.freshness.needsRefresh
                  ? AppStatusTone.attention
                  : AppStatusTone.success,
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

const dashboardFullWeekMinimumWebCardWidth = 208.0;
const dashboardFullWeekDayGap = AppSpacing.sm;
const dashboardFullWeekNarrowBreakpoint = 400.0;
const dashboardFullWeekLargeTextThreshold = 24.0;
const dashboardFullWeekMaximumWidth = 1680.0;

class _FullWeekContent extends StatelessWidget {
  const _FullWeekContent({
    required this.value,
    required this.onRetry,
    required this.onAction,
  });

  final AsyncValue<DashboardFullWeekProjection>? value;
  final VoidCallback onRetry;
  final ValueChanged<DashboardFullWeekAction> onAction;

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
      error: (_, __) => Semantics(
        liveRegion: true,
        child: DashboardSectionErrorCard(
          title: 'Full week unavailable',
          message: 'The complete week could not be loaded. Try again.',
          onRetry: onRetry,
        ),
      ),
      data: (projection) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final source in projection.unavailableSources) ...[
              Semantics(
                liveRegion: true,
                child: DashboardInlineMessage(
                  icon: AppIcons.warningAmberOutlined,
                  message: '${source.label}: ${source.message}',
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            DashboardFullWeekAgenda(
              projection: projection,
              onAction: onAction,
            ),
          ],
        );
      },
    );
  }
}

class DashboardFullWeekAgenda extends StatefulWidget {
  const DashboardFullWeekAgenda({
    super.key,
    required this.projection,
    required this.onAction,
  });

  final DashboardFullWeekProjection projection;
  final ValueChanged<DashboardFullWeekAction> onAction;

  @override
  State<DashboardFullWeekAgenda> createState() =>
      _DashboardFullWeekAgendaState();
}

class _DashboardFullWeekAgendaState extends State<DashboardFullWeekAgenda> {
  final ScrollController _controller = ScrollController();
  late int _snappedDay;
  double? _lastExtent;
  bool _syncScheduled = false;
  bool _snapScheduled = false;

  @override
  void initState() {
    super.initState();
    _snappedDay = _initialDay(widget.projection);
  }

  @override
  void didUpdateWidget(DashboardFullWeekAgenda oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameDate(
          oldWidget.projection.weekStartsOn,
          widget.projection.weekStartsOn,
        ) ||
        oldWidget.projection.timezone != widget.projection.timezone) {
      _snappedDay = _initialDay(widget.projection);
      _lastExtent = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final webGridMinimum = dashboardFullWeekMinimumWebCardWidth * 7 +
            dashboardFullWeekDayGap * 6;
        if (constraints.maxWidth >= webGridMinimum) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0;
                  index < widget.projection.days.length;
                  index++) ...[
                Expanded(child: _dayCard(widget.projection.days[index])),
                if (index < widget.projection.days.length - 1)
                  const SizedBox(width: dashboardFullWeekDayGap),
              ],
            ],
          );
        }

        final scaledBody = MediaQuery.textScalerOf(context).scale(16);
        final visibleSlots =
            constraints.maxWidth < dashboardFullWeekNarrowBreakpoint ||
                    scaledBody >= dashboardFullWeekLargeTextThreshold
                ? 2.0
                : 2.5;
        final extent = constraints.maxWidth / visibleSlots;
        _scheduleSync(extent);
        return NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            _scheduleSnap(extent);
            return false;
          },
          child: SingleChildScrollView(
            key: const ValueKey('dashboard-full-week-day-strip'),
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final day in widget.projection.days)
                  SizedBox(
                    width: extent,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: dashboardFullWeekDayGap,
                      ),
                      child: _dayCard(day),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dayCard(DashboardFullWeekDay day) => AppScheduleDayCard(
        key: ValueKey('dashboard-full-week-day-${_dateKey(day.localDate)}'),
        localDate: day.localDate,
        items: day.items.map(_fullWeekItemView).toList(growable: false),
        emptyLabel: widget.projection.unavailableSources.isEmpty
            ? 'Nothing scheduled.'
            : 'No items from available sources.',
        onItemTap: (view) {
          final item = view.payload! as DashboardFullWeekItem;
          final action = item.action;
          if (action != null) widget.onAction(action);
        },
      );

  void _scheduleSync(double extent) {
    if (_lastExtent == extent && _controller.hasClients) return;
    _lastExtent = extent;
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpTo(
        (_snappedDay * extent).clamp(
          0.0,
          _controller.position.maxScrollExtent,
        ),
      );
    });
  }

  void _snapToNearestDay(double extent) {
    if (!_controller.hasClients || extent <= 0) return;
    final requested = (_controller.offset / extent).round().clamp(0, 5).toInt();
    _snappedDay = requested;
    final offset = (requested * extent).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    if ((_controller.offset - offset).abs() < 0.5) return;
    _controller.animateTo(
      offset,
      duration: context.motionTokens.stateFor(context),
      curve: context.motionTokens.curve,
    );
  }

  void _scheduleSnap(double extent) {
    if (_snapScheduled) return;
    _snapScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snapScheduled = false;
      if (mounted) _snapToNearestDay(extent);
    });
  }
}

int _initialDay(DashboardFullWeekProjection projection) => projection.localToday
    .difference(projection.weekStartsOn)
    .inDays
    .clamp(0, 5)
    .toInt();

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

AppScheduleDayItem _fullWeekItemView(DashboardFullWeekItem item) {
  final detail = [
    item.timeLabel,
    if (item.detail != null) item.detail!,
    _fullWeekStatusLabel(item.status),
  ].join(' · ');
  return AppScheduleDayItem(
    id: item.id,
    title: item.title,
    detail: detail,
    category: switch (item.category) {
      DashboardFullWeekCategory.setup => AppCategory.setup,
      DashboardFullWeekCategory.preparation => AppCategory.preparation,
      DashboardFullWeekCategory.calendar => AppCategory.calendar,
      DashboardFullWeekCategory.focus => AppCategory.focus,
      DashboardFullWeekCategory.task => AppCategory.task,
      DashboardFullWeekCategory.habit => AppCategory.habit,
      DashboardFullWeekCategory.fixedCommitment => AppCategory.fixedCommitment,
    },
    actionable: item.action != null,
    status: item.category == DashboardFullWeekCategory.setup ||
            item.category == DashboardFullWeekCategory.calendar ||
            item.category == DashboardFullWeekCategory.fixedCommitment
        ? AppScheduleItemStatus.notApplicable
        : const {
            DashboardFullWeekItemStatus.completed,
            DashboardFullWeekItemStatus.done,
          }.contains(item.status)
            ? AppScheduleItemStatus.completed
            : AppScheduleItemStatus.open,
    payload: item,
  );
}

String _fullWeekStatusLabel(DashboardFullWeekItemStatus status) =>
    switch (status) {
      DashboardFullWeekItemStatus.active ||
      DashboardFullWeekItemStatus.inProgress =>
        'In progress',
      DashboardFullWeekItemStatus.completed ||
      DashboardFullWeekItemStatus.done =>
        'Completed',
      DashboardFullWeekItemStatus.abandoned => 'Ended',
      DashboardFullWeekItemStatus.missed => 'Missed',
      DashboardFullWeekItemStatus.skipped => 'Skipped',
      DashboardFullWeekItemStatus.open => 'Open',
      DashboardFullWeekItemStatus.todo => 'To do',
      DashboardFullWeekItemStatus.cancelled => 'Cancelled',
      DashboardFullWeekItemStatus.scheduled => 'Scheduled',
      DashboardFullWeekItemStatus.upcoming => 'Upcoming',
      DashboardFullWeekItemStatus.partial => 'Partially completed',
      DashboardFullWeekItemStatus.confirmed => 'Confirmed',
      DashboardFullWeekItemStatus.tentative => 'Tentative',
    };

String _feedbackTypeLabel(DecisionFeedbackType type) => switch (type) {
      DecisionFeedbackType.done => 'Done',
      DecisionFeedbackType.later => 'Later',
      DecisionFeedbackType.notHelpful => 'Not helpful',
      DecisionFeedbackType.tooMuch => 'Too much today',
      DecisionFeedbackType.doesNotFit => 'Does not fit',
    };
