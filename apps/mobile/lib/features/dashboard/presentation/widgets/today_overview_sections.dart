import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_category_visuals.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/theme/app_visual_tokens.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_info_disclosure.dart';
import '../../domain/entities/dashboard_snapshot.dart';
import 'dashboard_section_widgets.dart';

class TodayOverviewActions {
  const TodayOverviewActions({
    required this.onAddEvening,
    required this.onAddMorning,
    required this.onOpenPreparationPlan,
    required this.onStartPreparationFocus,
  });

  final VoidCallback onAddEvening;
  final VoidCallback onAddMorning;
  final ValueChanged<String> onOpenPreparationPlan;
  final ValueChanged<String> onStartPreparationFocus;
}

/// Capture actions and the agenda precede supporting progress information.
class TodayOverviewSections extends StatelessWidget {
  const TodayOverviewSections({
    super.key,
    required this.snapshot,
    required this.canExecute,
    required this.actions,
    this.latestCheckIn,
  });

  final DashboardSnapshot snapshot;
  final bool canExecute;
  final TodayOverviewActions actions;
  final AsyncValue<DashboardCheckIn?>? latestCheckIn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CheckInStreakCard(
          snapshot: snapshot,
          latestCheckIn: latestCheckIn,
          onAddMorning: actions.onAddMorning,
          onAddEvening: actions.onAddEvening,
        ),
        const SizedBox(height: AppSpacing.md),
        _TodayAgenda(
          snapshot: snapshot,
          canExecute: canExecute,
          onOpenPreparationPlan: actions.onOpenPreparationPlan,
          onStartPreparationFocus: actions.onStartPreparationFocus,
        ),
        const SizedBox(height: AppSpacing.md),
        _TodayProgressCard(snapshot: snapshot),
      ],
    );
  }
}

class _CheckInStreakCard extends StatelessWidget {
  const _CheckInStreakCard({
    required this.snapshot,
    required this.latestCheckIn,
    required this.onAddMorning,
    required this.onAddEvening,
  });

  final DashboardSnapshot snapshot;
  final AsyncValue<DashboardCheckIn?>? latestCheckIn;
  final VoidCallback onAddMorning;
  final VoidCallback onAddEvening;

  @override
  Widget build(BuildContext context) {
    final checkIns = snapshot.checkIns;
    final unavailable =
        snapshot.sourceStates?.checkIns.status == TodaySourceStatus.unavailable;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TodayInfoDisclosure(
            topic: 'Check-in streak',
            description:
                'Both check-ins count as one day. Catch up within 48 hours after the day ends to keep your streak.',
            headerBuilder: (context, infoButton) => Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  AppIcons.localFireDepartmentOutlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppInfoHeading(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final theme = Theme.of(context).textTheme;
                        final days = checkIns?.completedDaysStreak ?? 0;
                        final label = Text(
                          constraints.maxWidth < 340
                              ? 'Streak'
                              : 'Check-in streak',
                          style: theme.titleMedium,
                        );
                        final count = unavailable
                            ? Text('Unavailable', style: theme.bodySmall)
                            : Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '$days',
                                      style: theme.headlineSmall,
                                    ),
                                    TextSpan(
                                      text: days == 1 ? ' day' : ' days',
                                      style: theme.bodyMedium,
                                    ),
                                  ],
                                ),
                              );
                        // Normal phone sizes stay on one line. Enlarged type
                        // wraps rather than shrinking or clipping information.
                        if (MediaQuery.textScalerOf(context).scale(16) > 20 ||
                            constraints.maxWidth < 180) {
                          return Wrap(
                            spacing: AppSpacing.md,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [label, count],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: label),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  right: AppSpacing.sm,
                                ),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: count,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                infoButton,
              ],
            ),
          ),
          if (unavailable) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              snapshot.sourceStates?.checkIns.message ??
                  'Check-ins could not be loaded.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _LatestCheckInInset(
            value: latestCheckIn ?? AsyncData(snapshot.latestCheckIn),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              final morning = _CheckInButton(
                label: 'Morning check-in',
                compactLabel: 'Morning Check-in',
                saved: checkIns?.morningSaved == true,
                icon: AppIcons.wbSunnyOutlined,
                compact: compact,
                onPressed: onAddMorning,
              );
              final evening = _CheckInButton(
                label: 'Evening check-in',
                compactLabel: 'Evening Check-in',
                saved: checkIns?.eveningSaved == true,
                icon: AppIcons.nightsStayOutlined,
                compact: compact,
                onPressed: onAddEvening,
              );
              if (!compact) {
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [morning, evening],
                );
              }
              return Row(
                children: [
                  Expanded(child: morning),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: evening),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LatestCheckInInset extends StatelessWidget {
  const _LatestCheckInInset({required this.value});

  final AsyncValue<DashboardCheckIn?> value;

  @override
  Widget build(BuildContext context) {
    final checkIn = value.valueOrNull;
    final content = value.when(
      loading: () => const Text('Loading latest check-in…'),
      error: (_, __) => const Text('Latest check-in unavailable.'),
      data: (checkIn) => checkIn == null
          ? const Text('No saved check-in yet.')
          : _latestValues(context, checkIn),
    );
    if (value.isLoading || value.hasError || checkIn == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [const Text('Last check-in'), content],
      );
    }
    return Column(
      key: const ValueKey('beat-yesterday'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Last check-in'),
            Text(
              '(${DateFormat.yMMMd().format(checkIn.entryDate)})',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        content,
      ],
    );
  }

  Widget _latestValues(BuildContext context, DashboardCheckIn checkIn) {
    final metrics = _beatYesterdayMetrics(checkIn);
    if (metrics.isEmpty) return const Text('No core values saved.');
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final tileWidth = (constraints.maxWidth - AppSpacing.xs) / 2;
        return Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final metric in metrics)
              if (compact)
                SizedBox(
                  width: tileWidth,
                  child: _BeatYesterdayMetric(metric: metric, expanded: true),
                )
              else
                _BeatYesterdayMetric(metric: metric),
          ],
        );
      },
    );
  }
}

class _BeatYesterdayMetric extends StatelessWidget {
  const _BeatYesterdayMetric({required this.metric, this.expanded = false});

  final ({String label, String value}) metric;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final tokens = context.visualTokens;
    final (icon, color, surface) = switch (metric.label) {
      'Mood' => (AppIcons.moodOutlined, tokens.brand, tokens.successSurface),
      'Energy' => (AppIcons.boltOutlined, tokens.info, tokens.infoSurface),
      'Sleep duration' => (
        AppIcons.bedtimeOutlined,
        tokens.dataViolet,
        tokens.surfaceSubtle,
      ),
      'Sleep quality' => (
        AppIcons.nightsStayOutlined,
        tokens.success,
        tokens.successSurface,
      ),
      'Stress' => (
        AppIcons.warningAmberOutlined,
        tokens.attention,
        tokens.attentionSurface,
      ),
      _ => (AppIcons.infoOutline, tokens.textSecondary, tokens.surfaceSubtle),
    };
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: '${metric.label}: ${metric.value}',
      child: ExcludeSemantics(
        child: Container(
          width: expanded ? double.infinity : null,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Row(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: AppSpacing.xs),
              if (expanded)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        metric.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelMedium,
                      ),
                      Text(
                        metric.value,
                        maxLines: 1,
                        style: textTheme.titleSmall,
                      ),
                    ],
                  ),
                )
              else
                Text('${metric.label}  ${metric.value}'),
            ],
          ),
        ),
      ),
    );
  }
}

List<({String label, String value})> _beatYesterdayMetrics(
  DashboardCheckIn checkIn,
) {
  return [
    if (checkIn.mood != null) (label: 'Mood', value: '${checkIn.mood}/10'),
    if (checkIn.energy != null)
      (label: 'Energy', value: '${checkIn.energy}/10'),
    if (checkIn.sleepHours != null)
      (
        label: 'Sleep duration',
        value: '${_compactDecimal(checkIn.sleepHours!)} h',
      ),
    if (checkIn.sleepQuality != null)
      (label: 'Sleep quality', value: '${checkIn.sleepQuality}/10'),
    if (checkIn.stress != null)
      (label: 'Stress', value: '${checkIn.stress}/10'),
  ];
}

String _compactDecimal(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

class _CheckInButton extends StatelessWidget {
  const _CheckInButton({
    required this.label,
    required this.saved,
    required this.icon,
    required this.onPressed,
    this.compact = false,
    this.compactLabel,
  });

  final String label;
  final String? compactLabel;
  final bool saved;
  final bool compact;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = '${saved ? 'Edit' : 'Add'} $label';
    final tokens = context.visualTokens;
    final statusColor = saved ? tokens.success : tokens.attention;
    final style = ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(statusColor),
      side: WidgetStatePropertyAll(
        BorderSide(color: statusColor.withValues(alpha: 0.5)),
      ),
      backgroundColor: WidgetStatePropertyAll(
        saved ? tokens.successSurface : tokens.attentionSurface,
      ),
    );
    return Semantics(
      button: true,
      label: '$text. ${saved ? 'Saved' : 'Not saved'} today.',
      child: compact
          ? _compactButton(context, style)
          : OutlinedButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(saved ? AppIcons.checkCircleOutline : icon),
              label: Text(text),
            ),
    );
  }

  Widget _compactButton(BuildContext context, ButtonStyle style) {
    final textTheme = Theme.of(context).textTheme;
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(saved ? AppIcons.checkCircleOutline : icon, size: 18),
          const SizedBox(height: 2),
          Text(
            compactLabel ?? label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: textTheme.labelLarge,
          ),
          Text(
            saved ? 'Done' : 'To do',
            style: textTheme.labelSmall?.copyWith(
              color: saved
                  ? context.visualTokens.success
                  : context.visualTokens.attention,
            ),
          ),
        ],
      ),
    );
    return OutlinedButton(
      onPressed: onPressed,
      style: style.copyWith(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: child,
    );
  }
}

class _TodayProgressCard extends StatelessWidget {
  const _TodayProgressCard({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final progress = snapshot.progress;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TodayInfoDisclosure(
            topic: 'Today\'s progress',
            description:
                'Includes both check-ins, today\'s tasks and habits, and confirmed preparation blocks. Skipped habits do not count as completed.',
            headerBuilder: (context, infoButton) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: AppInfoHeading(
                      child: Text(
                        'Today\'s progress',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                ),
                infoButton,
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (progress == null) ...[
            Text(
              'Progress unavailable',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'At least one counted source could not be verified, so no partial total is shown.',
            ),
          ] else ...[
            Semantics(
              label:
                  '${progress.completed} of ${progress.total} counted items completed today',
              child: ExcludeSemantics(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress.ratio),
                  duration: context.motionTokens.emphasisFor(context),
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 12,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    color: context.visualTokens.success,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${progress.completed}/${progress.total} completed',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _TodayAgenda extends StatefulWidget {
  const _TodayAgenda({
    required this.snapshot,
    required this.canExecute,
    required this.onOpenPreparationPlan,
    required this.onStartPreparationFocus,
  });

  final DashboardSnapshot snapshot;
  final bool canExecute;
  final ValueChanged<String> onOpenPreparationPlan;
  final ValueChanged<String> onStartPreparationFocus;

  @override
  State<_TodayAgenda> createState() => _TodayAgendaState();
}

class _TodayAgendaState extends State<_TodayAgenda> {
  bool _showAll = false;
  bool _showCompleted = false;

  Widget _item(TodayTimelineItem item) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: _AgendaItem(
      item: item,
      canExecute: widget.canExecute,
      onOpenPreparationPlan: widget.onOpenPreparationPlan,
      onStartPreparationFocus: widget.onStartPreparationFocus,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    // Elapsed calendar entries and abandoned Focus are not completions.
    final completed = snapshot.timeline
        .where((item) => const {'completed', 'done'}.contains(item.state))
        .toList(growable: false);
    final active = snapshot.timeline
        .where((item) => !const {'completed', 'done'}.contains(item.state))
        .toList(growable: false);
    final sourceErrors =
        snapshot.sourceStates?.timelineStates
            .where((state) => state.status == TodaySourceStatus.unavailable)
            .map((state) => state.message)
            .whereType<String>()
            .toList(growable: false) ??
        const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashboardSectionTitle(
          title: 'Today\'s schedule',
          subtitle: 'Today\'s scheduled time blocks, in order.',
          icon: AppIcons.schedule,
        ),
        if (sourceErrors.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          DashboardInlineMessage(
            icon: AppIcons.warningAmberOutlined,
            message: sourceErrors.join(' '),
            color: Theme.of(context).colorScheme.error,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (snapshot.timeline.isEmpty)
          const DashboardEmptySectionCard(
            icon: AppIcons.calendarTodayOutlined,
            message: 'Nothing timed on the calendar today.',
          )
        else ...[
          ...(_showAll ? active : active.take(3)).map(_item),
          if (active.length > 3)
            TextButton.icon(
              onPressed: () => setState(() => _showAll = !_showAll),
              icon: Icon(_showAll ? AppIcons.expandLess : AppIcons.expandMore),
              label: Text(
                _showAll ? 'Show less' : 'Show all (${active.length})',
              ),
            ),
          if (completed.isNotEmpty)
            DashboardInlineExpansionCard(
              title: 'Completed (${completed.length})',
              expanded: _showCompleted,
              onToggle: () => setState(() => _showCompleted = !_showCompleted),
              child: Column(children: completed.map(_item).toList()),
            ),
        ],
      ],
    );
  }
}

class _AgendaItem extends StatelessWidget {
  const _AgendaItem({
    required this.item,
    required this.canExecute,
    required this.onOpenPreparationPlan,
    required this.onStartPreparationFocus,
  });

  final TodayTimelineItem item;
  final bool canExecute;
  final ValueChanged<String> onOpenPreparationPlan;
  final ValueChanged<String> onStartPreparationFocus;

  @override
  Widget build(BuildContext context) {
    final appearance = _agendaAppearance(context, item.kind);
    final detail = _agendaDetail(item);
    final rowAction = _rowAction(context);
    final isPast = const {'completed', 'ended', 'done'}.contains(item.state);
    return Semantics(
      container: true,
      button: rowAction != null,
      enabled: rowAction != null,
      label: '${appearance.label}. ${item.title}. ${_agendaTime(item)}.',
      child: Opacity(
        opacity: isPast ? 0.62 : 1,
        child: Material(
          color: appearance.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            side: BorderSide(
              color: appearance.foreground.withValues(alpha: .3),
            ),
          ),
          child: InkWell(
            onTap: rowAction,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 64,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _agendaTime(item),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: appearance.foreground),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Icon(
                          appearance.icon,
                          color: appearance.foreground,
                          size: 21,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appearance.label,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: appearance.foreground,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          item.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: appearance.foreground),
                        ),
                        if (detail != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            detail,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: appearance.foreground),
                          ),
                        ],
                        if (item.location != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            item.location!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: appearance.foreground),
                          ),
                        ],
                        if (canExecute &&
                            item.kind == TodayTimelineKind.habitSlot &&
                            item.habitId != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          FilledButton.tonalIcon(
                            onPressed: () =>
                                context.push(AppRoutes.habitCompletion),
                            icon: const Icon(AppIcons.checkCircleOutline),
                            label: const Text('Log habit'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (item.kind == TodayTimelineKind.focusSession)
                    IconButton(
                      tooltip: item.state == 'active'
                          ? 'Open Focus timer'
                          : 'Review Focus session',
                      onPressed: _rowAction(context),
                      icon: const Icon(AppIcons.timerOutlined, size: 20),
                    ),
                  if ((item.kind == TodayTimelineKind.preparation &&
                          item.planId != null) ||
                      (canExecute && item.kind == TodayTimelineKind.taskBlock))
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.kind == TodayTimelineKind.preparation &&
                            item.planId != null)
                          IconButton(
                            tooltip: 'Open plan',
                            onPressed: () =>
                                onOpenPreparationPlan(item.planId!),
                            icon: const Icon(
                              AppIcons.calendarMonthOutlined,
                              size: 20,
                            ),
                          ),
                        if (canExecute &&
                            item.kind == TodayTimelineKind.preparation &&
                            item.blockId != null &&
                            const {
                              'upcoming',
                              'partial',
                              'missed',
                            }.contains(item.state))
                          IconButton(
                            tooltip: 'Start focus',
                            onPressed: () =>
                                onStartPreparationFocus(item.blockId!),
                            icon: const Icon(AppIcons.timerOutlined, size: 20),
                          ),
                        if (canExecute &&
                            item.kind == TodayTimelineKind.taskBlock)
                          IconButton(
                            tooltip: 'Start focus',
                            onPressed: () => context.push(
                              _scheduledFocusRoute(
                                sourceKind: 'planner_task_block',
                                blockId: item.id,
                              ),
                            ),
                            icon: const Icon(AppIcons.timerOutlined, size: 20),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  VoidCallback? _rowAction(BuildContext context) {
    switch (item.kind) {
      case TodayTimelineKind.focusSession:
        return () => context.push(
          Uri(
            path: AppRoutes.deepWork,
            queryParameters: {'session_id': item.id},
          ).toString(),
        );
      case TodayTimelineKind.preparation:
        final planId = item.planId;
        if (!canExecute || item.state == 'completed') {
          return planId == null ? null : () => onOpenPreparationPlan(planId);
        }
        final blockId = item.blockId;
        if (blockId == null ||
            !const {'upcoming', 'partial', 'missed'}.contains(item.state)) {
          return planId == null ? null : () => onOpenPreparationPlan(planId);
        }
        return () => onStartPreparationFocus(blockId);
      case TodayTimelineKind.taskBlock:
        return canExecute
            ? () => context.push(
                _scheduledFocusRoute(
                  sourceKind: 'planner_task_block',
                  blockId: item.id,
                ),
              )
            : null;
      case TodayTimelineKind.habitSlot:
        return canExecute
            ? () => context.push(AppRoutes.habitCompletion)
            : null;
      case TodayTimelineKind.setupCommitment:
      case TodayTimelineKind.calendarEvent:
      case TodayTimelineKind.manualCommitment:
        return null;
    }
  }
}

String _scheduledFocusRoute({
  required String sourceKind,
  required String blockId,
}) => Uri(
  path: AppRoutes.deepWork,
  queryParameters: {'source_kind': sourceKind, 'source_block_id': blockId},
).toString();

String _agendaTime(TodayTimelineItem item) {
  if (item.allDay) return 'All day';
  final startsAt = item.startsAt;
  final endsAt = item.endsAt;
  if (startsAt == null || endsAt == null) return 'Time unavailable';
  return '${DateFormat.Hm().format(startsAt)}–${DateFormat.Hm().format(endsAt)}';
}

String? _agendaDetail(TodayTimelineItem item) => switch (item.kind) {
  TodayTimelineKind.setupCommitment => null,
  TodayTimelineKind.preparation => [
    _preparationStateLabel(item.state ?? ''),
    if (item.creditedTrackedMinutes != null && item.plannedMinutes != null)
      '${item.creditedTrackedMinutes}/${item.plannedMinutes} min tracked',
  ].join(' · '),
  TodayTimelineKind.calendarEvent =>
    item.sourceLabel == null
        ? 'Imported calendar event'
        : 'Imported from ${item.sourceLabel}',
  TodayTimelineKind.focusSession => [
    switch (item.state) {
      'active' => 'Active',
      'completed' => 'Completed',
      'abandoned' => 'Abandoned',
      _ => 'Focus',
    },
    if (item.actualMinutes != null) '${item.actualMinutes} min',
  ].join(' · '),
  TodayTimelineKind.taskBlock => '${item.plannedMinutes} min reserved',
  TodayTimelineKind.habitSlot => '${item.plannedMinutes} min reserved',
  TodayTimelineKind.manualCommitment => 'Fixed commitment',
};

AppCategoryVisual _agendaAppearance(
  BuildContext context,
  TodayTimelineKind kind,
) {
  final category = switch (kind) {
    TodayTimelineKind.setupCommitment => AppCategory.setup,
    TodayTimelineKind.preparation => AppCategory.preparation,
    TodayTimelineKind.calendarEvent => AppCategory.calendar,
    TodayTimelineKind.focusSession => AppCategory.focus,
    TodayTimelineKind.taskBlock => AppCategory.task,
    TodayTimelineKind.habitSlot => AppCategory.habit,
    TodayTimelineKind.manualCommitment => AppCategory.fixedCommitment,
  };
  return category.visual(context);
}

String _preparationStateLabel(String state) => switch (state) {
  'upcoming' => 'Upcoming',
  'partial' => 'Partly tracked',
  'completed' => 'Completed',
  'missed' => 'Missed',
  _ => 'Preparation',
};
