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

/// Owns the stable Today summary sequence: capture streak, progress, and
/// agenda. Task and Habit commands deliberately belong to separate sections.
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
        _TodayProgressCard(snapshot: snapshot),
        const SizedBox(height: AppSpacing.lg),
        _TodayAgenda(
          snapshot: snapshot,
          canExecute: canExecute,
          onOpenPreparationPlan: actions.onOpenPreparationPlan,
          onStartPreparationFocus: actions.onStartPreparationFocus,
        ),
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
                'A day counts when both check-ins are saved. You can enter both at any time today; an unfinished current day does not end the prior streak.',
            headerBuilder: (context, infoButton) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Icon(
                    AppIcons.localFireDepartmentOutlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 30,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.sm,
                              ),
                              child: Text(
                                'Check-in streak',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          ),
                          infoButton,
                        ],
                      ),
                      Text(
                        unavailable
                            ? 'Streak unavailable'
                            : '${checkIns?.completedDaysStreak ?? 0} consecutive ${checkIns?.completedDaysStreak == 1 ? 'day' : 'days'}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
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
          _BeatYesterdayInset(
            value: latestCheckIn ?? AsyncData(snapshot.latestCheckIn),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _CheckInButton(
                label: 'Morning check-in',
                saved: checkIns?.morningSaved == true,
                icon: AppIcons.wbSunnyOutlined,
                onPressed: onAddMorning,
              ),
              _CheckInButton(
                label: 'Evening check-in',
                saved: checkIns?.eveningSaved == true,
                icon: AppIcons.nightsStayOutlined,
                onPressed: onAddEvening,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BeatYesterdayInset extends StatelessWidget {
  const _BeatYesterdayInset({required this.value});

  final AsyncValue<DashboardCheckIn?> value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('beat-yesterday'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Beat yesterday',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          value.when(
            loading: () => const Row(
              children: [
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(child: Text('Loading your latest saved check-in…')),
              ],
            ),
            error: (_, __) => const Text(
              'Latest saved check-in details are unavailable. Your streak and check-in actions still work.',
            ),
            data: (checkIn) {
              if (checkIn == null) {
                return const Text('No saved check-in values yet.');
              }
              final metrics = _beatYesterdayMetrics(checkIn);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Latest saved · ${DateFormat.yMMMd().format(checkIn.entryDate)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (metrics.isEmpty)
                    const Text('No core values were saved in this check-in.')
                  else
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final metric in metrics)
                          _BeatYesterdayMetric(metric: metric),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BeatYesterdayMetric extends StatelessWidget {
  const _BeatYesterdayMetric({required this.metric});

  final ({String label, String value}) metric;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${metric.label}: ${metric.value}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Text('${metric.label}  ${metric.value}'),
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
  });

  final String label;
  final bool saved;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = '${saved ? 'Edit' : 'Add'} $label';
    return Semantics(
      button: true,
      label: '$text. ${saved ? 'Saved' : 'Not saved'} today.',
      child: saved
          ? OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(AppIcons.checkCircleOutline),
              label: Text(text),
            )
          : FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(text),
            ),
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
                    child: Text(
                      'Today\'s progress',
                      style: Theme.of(context).textTheme.titleLarge,
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
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
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

class _TodayAgenda extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final sourceErrors = snapshot.sourceStates?.timelineStates
            .where((state) => state.status == TodaySourceStatus.unavailable)
            .map((state) => state.message)
            .whereType<String>()
            .toList(growable: false) ??
        const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DashboardSectionTitle(
          title: 'Today at a glance',
          subtitle: 'Your timed day in one compact agenda.',
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
            message: 'No timed blocks or all-day events are available today.',
          )
        else
          ...snapshot.timeline.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _AgendaItem(
                item: item,
                canExecute: canExecute,
                onOpenPreparationPlan: onOpenPreparationPlan,
                onStartPreparationFocus: onStartPreparationFocus,
              ),
            ),
          ),
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
    return Semantics(
      container: true,
      button: rowAction != null,
      enabled: rowAction != null,
      label: '${appearance.label}. ${item.title}. ${_agendaTime(item)}.',
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
                  width: 76,
                  child: Text(
                    _agendaTime(item),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: appearance.foreground,
                        ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(appearance.icon, color: appearance.foreground, size: 21),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appearance.label,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: appearance.foreground,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        item.title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: appearance.foreground,
                                ),
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          detail,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: appearance.foreground,
                                  ),
                        ),
                      ],
                      if (item.location != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          item.location!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: appearance.foreground,
                                  ),
                        ),
                      ],
                      if (item.kind == TodayTimelineKind.preparation &&
                          item.planId != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            OutlinedButton(
                              onPressed: () =>
                                  onOpenPreparationPlan(item.planId!),
                              child: const Text('Open plan'),
                            ),
                            if (canExecute &&
                                item.blockId != null &&
                                const {
                                  'upcoming',
                                  'partial',
                                  'missed',
                                }.contains(item.state))
                              FilledButton.tonalIcon(
                                onPressed: () => onStartPreparationFocus(
                                  item.blockId!,
                                ),
                                icon: const Icon(AppIcons.timerOutlined),
                                label: const Text('Start focus'),
                              ),
                          ],
                        ),
                      ],
                      if (canExecute &&
                          item.kind == TodayTimelineKind.taskBlock) ...[
                        const SizedBox(height: AppSpacing.sm),
                        FilledButton.tonalIcon(
                          onPressed: () => context.push(
                            _scheduledFocusRoute(
                              sourceKind: 'planner_task_block',
                              blockId: item.id,
                            ),
                          ),
                          icon: const Icon(AppIcons.timerOutlined),
                          label: const Text('Start focus'),
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
              ],
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
}) =>
    Uri(
      path: AppRoutes.deepWork,
      queryParameters: {
        'source_kind': sourceKind,
        'source_block_id': blockId,
      },
    ).toString();

String _agendaTime(TodayTimelineItem item) {
  if (item.allDay) return 'All day';
  final startsAt = item.startsAt;
  final endsAt = item.endsAt;
  if (startsAt == null || endsAt == null) return 'Time unavailable';
  return '${DateFormat.Hm().format(startsAt)}–${DateFormat.Hm().format(endsAt)}';
}

String? _agendaDetail(TodayTimelineItem item) => switch (item.kind) {
      TodayTimelineKind.setupCommitment => 'Recurring Setup commitment',
      TodayTimelineKind.preparation => [
          _preparationStateLabel(item.state ?? ''),
          if (item.creditedTrackedMinutes != null &&
              item.plannedMinutes != null)
            '${item.creditedTrackedMinutes}/${item.plannedMinutes} min tracked',
        ].join(' · '),
      TodayTimelineKind.calendarEvent => item.sourceLabel == null
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
