import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_category_visuals.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_visual_tokens.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_schedule_day_card.dart';
import '../../domain/entities/dashboard_full_week.dart';
import 'dashboard_section_widgets.dart';

class DashboardSupportingState {
  const DashboardSupportingState({
    required this.canUseWeeklyReview,
    required this.fullWeek,
  });

  final bool canUseWeeklyReview;
  final AsyncValue<DashboardFullWeekProjection>? fullWeek;
}

class DashboardSupportingActions {
  const DashboardSupportingActions({
    required this.onToggleFullWeek,
    required this.onOpenWeeklyReview,
    required this.onRetryFullWeek,
    required this.onFullWeekAction,
  });

  final VoidCallback onToggleFullWeek;
  final VoidCallback onOpenWeeklyReview;
  final VoidCallback onRetryFullWeek;
  final ValueChanged<DashboardFullWeekAction> onFullWeekAction;
}

class DashboardSupportingSections extends StatelessWidget {
  const DashboardSupportingSections({
    super.key,
    required this.fullWeekExpanded,
    required this.state,
    required this.actions,
  });

  final bool fullWeekExpanded;
  final DashboardSupportingState state;
  final DashboardSupportingActions actions;

  bool get hasCompactContent => state.canUseWeeklyReview;

  Widget get compact => state.canUseWeeklyReview
      ? _WeeklyReviewEntry(
          key: const ValueKey('dashboard-weekly-review'),
          onOpen: actions.onOpenWeeklyReview,
        )
      : const SizedBox.shrink();

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
        if (hasCompactContent) ...[
          compact,
          const SizedBox(height: AppSpacing.sm),
        ],
        fullWeek,
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
        title: const Text('Weekly review'),
        subtitle: const Text(
          'Look back at last week. This is not a today to-do.',
        ),
        trailing: const Icon(AppIcons.chevronRight),
        onTap: onOpen,
      ),
    );
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
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = _initialDay(widget.projection);
  }

  @override
  void didUpdateWidget(DashboardFullWeekAgenda oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameDate(
          oldWidget.projection.weekStartsOn,
          widget.projection.weekStartsOn,
        ) ||
        oldWidget.projection.timezone != widget.projection.timezone) {
      _page = _initialDay(widget.projection);
    }
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
        return _mobileDayPager(context);
      },
    );
  }

  Widget _mobileDayPager(BuildContext context) {
    final days = widget.projection.days;
    final day = days[_page];
    final tokens = context.visualTokens;
    return Column(
      key: const ValueKey('dashboard-full-week-day-pager'),
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('dashboard-full-week-prev'),
              tooltip: 'Previous day',
              onPressed: _page > 0 ? () => _goTo(_page - 1) : null,
              icon: const RotatedBox(
                quarterTurns: 2,
                child: Icon(AppIcons.chevronRight),
              ),
            ),
            Expanded(
              child: Text(
                DateFormat('EEEE, MMM d').format(day.localDate),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              key: const ValueKey('dashboard-full-week-next'),
              tooltip: 'Next day',
              onPressed:
                  _page < days.length - 1 ? () => _goTo(_page + 1) : null,
              icon: const Icon(AppIcons.chevronRight),
            ),
          ],
        ),
        Row(
          children: [
            for (var index = 0; index < days.length; index++)
              Expanded(
                child: InkWell(
                  onTap: () => _goTo(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      DateFormat('E').format(days[index].localDate),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: index == _page
                                ? tokens.brand
                                : tokens.textSecondary,
                            fontWeight: index == _page
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        GestureDetector(
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -180) _goTo(_page + 1);
            if (velocity > 180) _goTo(_page - 1);
          },
          child: _dayCard(day, showDate: false),
        ),
      ],
    );
  }

  Widget _dayCard(DashboardFullWeekDay day, {bool showDate = true}) =>
      AppScheduleDayCard(
        key: ValueKey('dashboard-full-week-day-${_dateKey(day.localDate)}'),
        localDate: day.localDate,
        showDate: showDate,
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

  void _goTo(int page) {
    final last = widget.projection.days.length - 1;
    final next = page.clamp(0, last);
    if (next == _page) return;
    setState(() => _page = next);
  }
}

int _initialDay(DashboardFullWeekProjection projection) => projection.localToday
    .difference(projection.weekStartsOn)
    .inDays
    .clamp(0, projection.days.length - 1)
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
