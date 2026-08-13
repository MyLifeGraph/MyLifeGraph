import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_category_visuals.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_schedule_day_card.dart';
import '../../../deadline_plans/domain/exam_week_outlook.dart';
import '../../domain/planner.dart';

class PlannerLockedCard extends StatelessWidget {
  const PlannerLockedCard({super.key});

  @override
  Widget build(BuildContext context) => const AppCard(
        key: ValueKey('planner-locked'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(AppIcons.lockOutline),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Synced Planner unavailable'),
                  SizedBox(height: AppSpacing.xs),
                  Text(
                    'Guest and demo sessions stay local. They do not create or invent synced plans.',
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class PlannerAddNewSection extends StatelessWidget {
  const PlannerAddNewSection({
    super.key,
    required this.busy,
    required this.calendarPreference,
    required this.availabilityIncomplete,
    required this.onTask,
    required this.onHabit,
    required this.onExam,
    required this.onAssignment,
    required this.onCommitment,
    required this.onReviewSetup,
    required this.onCalendarPreference,
  });

  final bool busy;
  final PlannerPreferences? calendarPreference;
  final bool availabilityIncomplete;
  final VoidCallback onTask;
  final VoidCallback onHabit;
  final VoidCallback onExam;
  final VoidCallback onAssignment;
  final VoidCallback onCommitment;
  final VoidCallback onReviewSetup;
  final ValueChanged<bool>? onCalendarPreference;

  @override
  Widget build(BuildContext context) => AppCard(
        key: const ValueKey('planner-add-new'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add new', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Only explicit values are planned. Nothing is scheduled in the background.',
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _CreateButton(
                  key: const ValueKey('planner-add-task'),
                  category: AppCategory.task,
                  icon: AppIcons.taskAltOutlined,
                  label: 'Task',
                  onPressed: busy ? null : onTask,
                ),
                _CreateButton(
                  key: const ValueKey('planner-add-habit'),
                  category: AppCategory.habit,
                  icon: AppIcons.repeatOutlined,
                  label: 'Habit',
                  onPressed: busy ? null : onHabit,
                ),
                _CreateButton(
                  key: const ValueKey('planner-add-exam'),
                  category: AppCategory.preparation,
                  icon: AppIcons.schoolOutlined,
                  label: 'Exam',
                  onPressed: busy ? null : onExam,
                ),
                _CreateButton(
                  key: const ValueKey('planner-add-assignment'),
                  category: AppCategory.preparation,
                  icon: AppIcons.assignmentOutlined,
                  label: 'Assignment',
                  onPressed: busy ? null : onAssignment,
                ),
                _CreateButton(
                  key: const ValueKey('planner-add-commitment'),
                  category: AppCategory.fixedCommitment,
                  icon: AppIcons.eventBusyOutlined,
                  label: 'Fixed commitment',
                  onPressed: busy ? null : onCommitment,
                ),
              ],
            ),
            if (availabilityIncomplete) ...[
              const Divider(height: AppSpacing.xl),
              Container(
                key: const ValueKey('planner-availability-warning'),
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(AppIcons.eventNoteOutlined),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Availability may be incomplete',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              const Text(
                                'Add recurring classes or work times before the first automatic plan. Calendar import stays optional.',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton.tonalIcon(
                      key: const ValueKey('planner-review-setup-schedule'),
                      onPressed: busy ? null : onReviewSetup,
                      icon: const Icon(AppIcons.calendarViewWeekOutlined),
                      label: const Text('Add weekly schedule'),
                    ),
                  ],
                ),
              ),
            ],
            if (calendarPreference != null) ...[
              const Divider(height: AppSpacing.xl),
              SwitchListTile(
                key: const ValueKey('planner-calendar-consent'),
                contentPadding: EdgeInsets.zero,
                value: calendarPreference!.useCalendarBusyTime,
                onChanged: busy ? null : onCalendarPreference,
                secondary: const Icon(AppIcons.calendarMonthOutlined),
                title: const Text('Use current calendar import as busy time'),
                subtitle: Text(
                  calendarPreference!.calendarAvailable
                      ? 'Read-only. A changed import makes open previews stale.'
                      : 'No current .ics import is available. Import one in Settings first.',
                ),
              ),
            ],
          ],
        ),
      );
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({
    required this.category,
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final AppCategory category;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final visual = category.visual(context);
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: visual.foreground,
        backgroundColor: visual.background,
        side: BorderSide(color: visual.foreground.withValues(alpha: 0.45)),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class PlannerExamWeekOutlookSection extends StatelessWidget {
  const PlannerExamWeekOutlookSection({
    super.key,
    required this.value,
    required this.onRetry,
    required this.onEveningCheckIn,
    required this.onReviewPlan,
    required this.onReplan,
    this.enabled = true,
  });

  final AsyncValue<ExamWeekOutlook?> value;
  final VoidCallback onRetry;
  final VoidCallback onEveningCheckIn;
  final ValueChanged<String> onReviewPlan;
  final ValueChanged<String> onReplan;
  final bool enabled;

  @override
  Widget build(BuildContext context) => value.when(
        loading: () => const AppCard(
          key: ValueKey('planner-exam-week-outlook-loading'),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(child: Text('Checking the next exam window…')),
            ],
          ),
        ),
        error: (_, __) => AppCard(
          key: const ValueKey('planner-exam-week-outlook-error'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Exam outlook unavailable',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Capacity and sleep context could not be read. Try loading the outlook again.',
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(AppIcons.refresh),
                label: const Text('Retry outlook'),
              ),
            ],
          ),
        ),
        data: (outlook) {
          if (outlook == null || outlook.mode == 'inactive') {
            return const SizedBox.shrink();
          }
          return _ExamWeekOutlookCard(
            outlook: outlook,
            onEveningCheckIn: onEveningCheckIn,
            onReviewPlan: onReviewPlan,
            onReplan: onReplan,
            enabled: enabled,
          );
        },
      );
}

class _ExamWeekOutlookCard extends StatelessWidget {
  const _ExamWeekOutlookCard({
    required this.outlook,
    required this.onEveningCheckIn,
    required this.onReviewPlan,
    required this.onReplan,
    required this.enabled,
  });

  final ExamWeekOutlook outlook;
  final VoidCallback onEveningCheckIn;
  final ValueChanged<String> onReviewPlan;
  final ValueChanged<String> onReplan;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final urgent = outlook.mode == 'overdue' ||
        {'high', 'critical'}.contains(outlook.riskLevel);
    final accent = urgent ? colors.error : colors.tertiary;
    final shortNights = outlook.recentSleepNights
        .where((night) => night.atLeastOneHourShort)
        .length;
    return AppCard(
      key: ValueKey('planner-exam-week-outlook-${outlook.mode}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                outlook.mode == 'overdue'
                    ? AppIcons.reportGmailerrorredOutlined
                    : outlook.mode == 'exam_week'
                        ? AppIcons.schoolOutlined
                        : AppIcons.visibilityOutlined,
                color: accent,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _outlookTitle(outlook.mode),
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: accent),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(_outlookSummary(outlook)),
                  ],
                ),
              ),
              _OutlookRiskChip(
                label: _riskLabel(outlook.riskLevel),
                color: accent,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _capacityLabel(outlook.capacityStatus),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${_minutes(outlook.minutes.remainingMinutes)} remaining · '
                  '${_minutes(outlook.minutes.futureScheduledMinutes)} already scheduled before the warning buffer',
                ),
                if (outlook.minutes.missedPreparationMinutes > 0)
                  Text(
                    '${_minutes(outlook.minutes.missedPreparationMinutes)} in missed, uncredited blocks',
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (outlook.currentSleepPlan == null) ...[
            const Text(
              'No personal sleep plan is saved yet. The protected-capacity comparison remains unknown.',
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: const ValueKey('exam-outlook-evening-check-in'),
              onPressed: onEveningCheckIn,
              icon: const Icon(AppIcons.bedtimeOutlined),
              label: const Text('Set it in Evening check-in'),
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(AppIcons.bedtimeOutlined),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Sleep plan ${outlook.currentSleepPlan!.plannedSleepTime} · '
                    '${_minutes(outlook.currentSleepPlan!.sleepTargetMinutes)} target. '
                    'This outlook protects it hypothetically; it does not lock time.',
                  ),
                ),
              ],
            ),
            if (shortNights >= 2) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '$shortNights of the last ${outlook.recentSleepNights.length} valid nights were at least one hour below their saved target.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: accent,
                    ),
              ),
            ],
          ],
          if (outlook.warningCodes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: outlook.warningCodes
                  .map(
                    (code) => Chip(
                      avatar: Icon(
                        AppIcons.warningAmberOutlined,
                        size: 18,
                        color: accent,
                      ),
                      label: Text(_warningLabel(code)),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          for (final exam in outlook.exams) ...[
            _OutlookExamRow(
              exam: exam,
              onReview: enabled ? () => onReviewPlan(exam.planId) : null,
              onReplan: enabled ? () => onReplan(exam.planId) : null,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (outlook.assignments.isNotEmpty) ...[
            const Divider(),
            Text(
              'Assignments counted in capacity',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final assignment in outlook.assignments)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  '${assignment.title} · ${_minutes(assignment.remainingMinutes)} remaining · due ${_outlookDueLabel(assignment)}',
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Read-only outlook. Opening this card neither creates a preview nor changes your current saved plan.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _OutlookRiskChip extends StatelessWidget {
  const _OutlookRiskChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
        ),
      );
}

class _OutlookExamRow extends StatelessWidget {
  const _OutlookExamRow({
    required this.exam,
    required this.onReview,
    required this.onReplan,
  });

  final ExamWeekPlanOutlook exam;
  final VoidCallback? onReview;
  final VoidCallback? onReplan;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(exam.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${_outlookDueLabel(exam)} · ${_minutes(exam.remainingMinutes)} remaining',
            ),
            if (exam.missedPreparationMinutes > 0)
              Text(
                '${_minutes(exam.missedPreparationMinutes)} missed and still uncredited',
              ),
            if (exam.pendingPreviewSleepOverlap)
              const Text(
                'The staged preview overlaps the saved sleep window. It remains unconfirmed.',
              ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton(
                  onPressed: onReview,
                  child: const Text('Review plan'),
                ),
                FilledButton.tonal(
                  onPressed: onReplan,
                  child: const Text('Replan remaining time'),
                ),
              ],
            ),
          ],
        ),
      );
}

String _outlookTitle(String mode) => switch (mode) {
      'watch' => 'Exam watch · next 14 days',
      'exam_week' => 'Exam week',
      'overdue' => 'Exam plan overdue',
      _ => 'Exam outlook',
    };

String _outlookSummary(ExamWeekOutlook outlook) => switch (outlook.mode) {
      'watch' =>
        '${outlook.exams.length} upcoming exam${outlook.exams.length == 1 ? '' : 's'} now affects the 14-day capacity check.',
      'exam_week' =>
        '${outlook.exams.length} exam${outlook.exams.length == 1 ? '' : 's'} falls within seven profile-local days.',
      'overdue' =>
        'At least one exam deadline has passed with preparation still remaining.',
      _ => '',
    };

String _riskLabel(String risk) => switch (risk) {
      'on_track' => 'On track',
      'attention' => 'Attention',
      'high' => 'High risk',
      'critical' => 'Critical',
      _ => 'Unknown',
    };

String _capacityLabel(String capacity) => switch (capacity) {
      'fits_with_sleep_protected' => 'Remaining work fits with sleep protected',
      'fits_only_using_sleep_window' =>
        'Remaining work fits only by using the sleep window',
      'does_not_fit_before_buffer' =>
        'Remaining work does not fit before the warning buffer',
      _ => 'Capacity is incomplete',
    };

String _warningLabel(String code) => switch (code) {
      'exam_overdue' => 'Exam overdue',
      'missing_recommended_buffer' => 'Missing exam buffer',
      'missed_preparation_blocks' => 'Missed preparation',
      'remaining_work_does_not_fit' => 'Remaining work does not fit',
      'sleep_capacity_tradeoff' => 'Sleep-capacity tradeoff',
      'repeated_sleep_shortfall' => 'Repeated sleep shortfall',
      'sleep_plan_missing' => 'Sleep plan missing',
      'capacity_incomplete' => 'Capacity incomplete',
      'pending_preview_sleep_overlap' => 'Preview overlaps sleep',
      _ => code,
    };

String _outlookDueLabel(ExamWeekPlanOutlook plan) {
  if (plan.daysRemaining < 0) {
    return '${-plan.daysRemaining} day${plan.daysRemaining == -1 ? '' : 's'} overdue';
  }
  if (plan.daysRemaining == 0) return 'due today';
  return 'due in ${plan.daysRemaining} day${plan.daysRemaining == 1 ? '' : 's'}';
}

class PlannerNeedsAttentionSection extends StatelessWidget {
  const PlannerNeedsAttentionSection({
    super.key,
    required this.items,
    required this.onOpen,
    this.enabled = true,
  });

  final List<PlannerAttention> items;
  final ValueChanged<PlannerAttention> onOpen;
  final bool enabled;

  @override
  Widget build(BuildContext context) => AppCard(
        key: const ValueKey('planner-needs-attention'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Needs attention',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (items.isEmpty)
              const Row(
                children: [
                  Icon(AppIcons.checkCircleOutline),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('Nothing currently needs review.')),
                ],
              )
            else
              for (final item in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item.kind == 'stale_preview'
                        ? AppIcons.updateOutlined
                        : item.kind == 'unscheduled'
                            ? AppIcons.timerOffOutlined
                            : AppIcons.warningAmberOutlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(item.title),
                  subtitle: Text(item.detail),
                  trailing: item.planId == null
                      ? (item.target == 'study_setup'
                          ? const Icon(AppIcons.chevronRight)
                          : item.unplacedMinutes > 0
                              ? Text('${item.unplacedMinutes} min')
                              : null)
                      : const Icon(AppIcons.chevronRight),
                  onTap: !enabled ||
                          item.planId == null && item.target != 'study_setup'
                      ? null
                      : () => onOpen(item),
                ),
          ],
        ),
      );
}

class PlannerSevenDaySection extends StatelessWidget {
  const PlannerSevenDaySection({
    super.key,
    required this.days,
    required this.onItemTap,
    this.enabled = true,
  });

  final List<PlannerDay> days;
  final ValueChanged<PlannerDayItem> onItemTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey('planner-seven-days'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Next seven days',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final day in days) ...[
            AppScheduleDayCard(
              localDate: day.localDate,
              items: day.items
                  .map((item) => _plannerDayItemView(item, enabled: enabled))
                  .toList(growable: false),
              emptyLabel: 'No planned or fixed items.',
              onItemTap: (view) => onItemTap(view.payload! as PlannerDayItem),
            ),
            if (day != days.last) const SizedBox(height: AppSpacing.sm),
          ],
        ],
      );
}

AppScheduleDayItem _plannerDayItemView(
  PlannerDayItem item, {
  required bool enabled,
}) {
  final visual = _visual(item.kind);
  final time = item.allDay
      ? 'All day'
      : item.recoveryMinutes > 0
          ? '${DateFormat.Hm().format(item.startsAt!.toLocal())}–'
              '${DateFormat.Hm().format(item.endsAt!.toLocal())} focus + '
              '${item.recoveryMinutes} min recovery · reserved until '
              '${DateFormat.Hm().format(item.reservedEndsAt!.toLocal())}'
          : '${DateFormat.Hm().format(item.startsAt!.toLocal())}–'
              '${DateFormat.Hm().format(item.endsAt!.toLocal())}';
  return AppScheduleDayItem(
    id: item.id,
    title: item.title,
    detail: time,
    category: visual.category,
    icon: visual.icon,
    actionable: enabled &&
        const {
          'manual_commitment',
          'task_block',
          'habit_slot',
          'preparation',
        }.contains(item.kind),
    payload: item,
  );
}

class PlannerPreparationSection extends StatelessWidget {
  const PlannerPreparationSection({
    super.key,
    required this.plans,
    required this.onOpen,
    this.enabled = true,
  });

  final List<PlannerPreparation> plans;
  final ValueChanged<PlannerPreparation> onOpen;
  final bool enabled;

  @override
  Widget build(BuildContext context) => AppCard(
        key: const ValueKey('planner-ongoing-preparation'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ongoing preparation',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (plans.isEmpty)
              const Text('No active exam or assignment preparation.')
            else
              for (final plan in plans)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(AppIcons.schoolOutlined),
                  title: Text(plan.title),
                  subtitle: Text(
                    '${_minutes(plan.remainingMinutes)} remaining · '
                    '${plan.nextBlockStartsAt == null ? 'no next block' : 'next ${DateFormat.MMMd().add_Hm().format(plan.nextBlockStartsAt!.toLocal())}'}',
                  ),
                  trailing: plan.hasPendingPreview
                      ? const Chip(label: Text('Preview'))
                      : const Icon(AppIcons.chevronRight),
                  onTap: enabled ? () => onOpen(plan) : null,
                ),
          ],
        ),
      );
}

class PlannerPendingPreviewsSection extends StatelessWidget {
  const PlannerPendingPreviewsSection({
    super.key,
    required this.plans,
    required this.onOpen,
    this.enabled = true,
  });

  final List<PlannerActionPlan> plans;
  final ValueChanged<PlannerActionPlan> onOpen;
  final bool enabled;

  @override
  Widget build(BuildContext context) => AppCard(
        key: const ValueKey('planner-pending-previews'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pending previews',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Review every staged Task or Habit change before confirmation.',
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final plan in plans)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  plan.targetKind == 'task'
                      ? AppIcons.taskOutlined
                      : AppIcons.repeatOutlined,
                ),
                title: Text(plan.pendingRevision!.targetTitle),
                subtitle: Text(
                  '${plan.targetKind == 'task' ? 'Task' : 'Habit'} preview · '
                  '${plan.pendingRevision!.plannedMinutes} min placed',
                ),
                trailing: const Icon(AppIcons.chevronRight),
                onTap: enabled ? () => onOpen(plan) : null,
              ),
          ],
        ),
      );
}

class PlannerHabitsSection extends StatelessWidget {
  const PlannerHabitsSection({
    super.key,
    required this.items,
    required this.onOpen,
    this.enabled = true,
  });

  final List<PlannerHabitSummary> items;
  final ValueChanged<PlannerHabitSummary> onOpen;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final unplanned =
        items.where((item) => item.planningStatus == 'unplanned').length;
    return AppCard(
      key: const ValueKey('planner-habits'),
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: false,
        title: const Text('Habits'),
        subtitle: Text('${items.length} active · $unplanned unplanned'),
        children: [
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('No active Habits.'),
              ),
            )
          else
            for (final item in items)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                ),
                leading: const Icon(AppIcons.repeatOutlined),
                title: Text(item.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_habitCadence(item)} · '
                      '${item.durationMinutes == null ? 'duration not set' : '${item.durationMinutes} min'} · '
                      '${item.planningStatus == 'scheduled' ? 'Scheduled' : 'Unplanned'}',
                    ),
                    if (item.ownership == 'setup' || item.hasPendingPreview)
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          if (item.ownership == 'setup')
                            const Text('Managed in Setup'),
                          if (item.hasPendingPreview)
                            const Text('Preview ready'),
                        ],
                      ),
                  ],
                ),
                trailing: const Icon(AppIcons.chevronRight),
                onTap: enabled ? () => onOpen(item) : null,
              ),
        ],
      ),
    );
  }
}

class PlannerUnscheduledTasksSection extends StatelessWidget {
  const PlannerUnscheduledTasksSection({
    super.key,
    required this.items,
    required this.onOpen,
    this.enabled = true,
  });

  final List<PlannerUnscheduledTask> items;
  final ValueChanged<PlannerUnscheduledTask> onOpen;
  final bool enabled;

  @override
  Widget build(BuildContext context) => AppCard(
        key: const ValueKey('planner-unscheduled-tasks'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Unscheduled Tasks',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (items.isEmpty)
              const Text('No open Tasks are waiting for a plan.')
            else
              for (final item in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(AppIcons.taskOutlined),
                  title: Text(item.title),
                  subtitle: Text(_reason(item.reason)),
                  trailing: const Icon(AppIcons.chevronRight),
                  onTap: enabled ? () => onOpen(item) : null,
                ),
          ],
        ),
      );
}

class PlannerHistorySection extends StatelessWidget {
  const PlannerHistorySection({super.key, required this.items});

  final List<PlannerHistoryItem> items;

  @override
  Widget build(BuildContext context) => AppCard(
        key: const ValueKey('planner-history'),
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          title: const Text('Completed and archived'),
          subtitle: Text('${items.length} historical items'),
          children: [
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No history yet.'),
                ),
              )
            else
              for (final item in items)
                ListTile(
                  leading: const Icon(AppIcons.history),
                  title: Text(item.title),
                  subtitle: Text(item.kind == 'task' ? 'Task' : 'Habit'),
                ),
          ],
        ),
      );
}

class PlannerMutationError extends StatelessWidget {
  const PlannerMutationError({
    super.key,
    required this.exactRetryRequired,
    required this.conflict,
    required this.onRetryExact,
    required this.onReload,
  });

  final bool exactRetryRequired;
  final bool conflict;
  final VoidCallback? onRetryExact;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              exactRetryRequired
                  ? 'Result not confirmed'
                  : conflict
                      ? 'Planner changed'
                      : 'Could not save change',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              exactRetryRequired
                  ? 'Retry the exact submitted values, or reload before starting another change.'
                  : conflict
                      ? 'Reload current data and create a new preview. Active reservations were not changed.'
                      : 'Your entered values are retained on this page.',
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (onRetryExact != null)
                  FilledButton(
                    onPressed: onRetryExact,
                    child: const Text('Retry same change'),
                  ),
                OutlinedButton(
                  onPressed: onReload,
                  child: const Text('Reload Planner'),
                ),
              ],
            ),
          ],
        ),
      );
}

class PlannerLoadError extends StatelessWidget {
  const PlannerLoadError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          children: [
            const Text(
              'Planner could not be loaded. Check your connection and try again.',
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(AppIcons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
}

class _BlockVisual {
  const _BlockVisual(this.icon, this.category);

  final IconData icon;
  final AppCategory category;
}

_BlockVisual _visual(String kind) => switch (kind) {
      'setup_commitment' => const _BlockVisual(
          AppIcons.settingsSuggestOutlined,
          AppCategory.setup,
        ),
      'manual_commitment' => const _BlockVisual(
          AppIcons.eventBusyOutlined,
          AppCategory.fixedCommitment,
        ),
      'task_block' =>
        const _BlockVisual(AppIcons.taskOutlined, AppCategory.task),
      'habit_slot' =>
        const _BlockVisual(AppIcons.repeatOutlined, AppCategory.habit),
      'preparation' =>
        const _BlockVisual(AppIcons.schoolOutlined, AppCategory.preparation),
      _ => const _BlockVisual(
          AppIcons.calendarMonthOutlined,
          AppCategory.calendar,
        ),
    };

String _reason(String value) => switch (value) {
      'released' => 'Future reservations were released. Create a new preview.',
      'missing_scheduling_inputs' =>
        'Duration, exact deadline, or session length is missing.',
      'no_time_available' =>
        'No time was available within the current planning limits.',
      _ => 'No confirmed reservation.',
    };

String _habitCadence(PlannerHabitSummary item) => switch (item.cadenceKind) {
      'daily' => 'Daily',
      'weekdays' => item.scheduledWeekdays.map(_weekdayShort).join(', '),
      _ => '${item.weeklyTarget} times per week',
    };

String _weekdayShort(int value) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][value - 1];

String _minutes(int value) {
  final hours = value ~/ 60;
  final minutes = value % 60;
  if (hours == 0) return '$minutes min';
  if (minutes == 0) return '$hours h';
  return '$hours h $minutes min';
}
