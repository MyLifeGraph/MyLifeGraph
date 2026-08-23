import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_category_visuals.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_motion_tokens.dart';
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
