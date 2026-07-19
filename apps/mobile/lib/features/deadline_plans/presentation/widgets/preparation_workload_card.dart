import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/deadline_plan.dart';

class PreparationWorkloadCard extends StatelessWidget {
  const PreparationWorkloadCard({
    super.key,
    required this.value,
    required this.onRetry,
    required this.onOpenSettings,
    this.onOpenPlans,
    this.compact = false,
  });

  final AsyncValue<PreparationWorkload> value;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenPlans;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const AppCard(
        child: Row(
          children: [
            SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(child: Text('Loading 7-day preparation load…')),
          ],
        ),
      ),
      error: (_, __) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Preparation load unavailable',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Confirmed reservations could not be read. No empty or estimated workload was substituted.',
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
      data: (workload) => compact
          ? _CompactWorkload(
              workload: workload,
              onOpenSettings: onOpenSettings,
              onOpenPlans: onOpenPlans,
            )
          : _ExpandedWorkload(
              workload: workload,
              onOpenSettings: onOpenSettings,
            ),
    );
  }
}

class _CompactWorkload extends StatelessWidget {
  const _CompactWorkload({
    required this.workload,
    required this.onOpenSettings,
    required this.onOpenPlans,
  });

  final PreparationWorkload workload;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenPlans;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        key: const ValueKey('today-preparation-workload'),
        leading: const Icon(Icons.stacked_bar_chart_outlined),
        title: const Text('7-day preparation load'),
        subtitle: Text(_summary(workload)),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        children: [
          _BudgetExplanation(
            workload: workload,
            onOpenSettings: onOpenSettings,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final day in workload.days) ...[
            _WorkloadDayRow(
              day: day,
              budget: workload.dailyPreparationBudgetMinutes,
            ),
            if (day != workload.days.last) const Divider(height: 1),
          ],
          if (onOpenPlans != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onOpenPlans,
                icon: const Icon(Icons.calendar_view_week_outlined),
                label: const Text('Open preparation plans'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpandedWorkload extends StatelessWidget {
  const _ExpandedWorkload({
    required this.workload,
    required this.onOpenSettings,
  });

  final PreparationWorkload workload;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.stacked_bar_chart_outlined),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your next 7 days',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(_summary(workload)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _BudgetExplanation(
            workload: workload,
            onOpenSettings: onOpenSettings,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final day in workload.days) ...[
            _WorkloadDayRow(
              day: day,
              budget: workload.dailyPreparationBudgetMinutes,
            ),
            if (day != workload.days.last) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _BudgetExplanation extends StatelessWidget {
  const _BudgetExplanation({
    required this.workload,
    required this.onOpenSettings,
  });

  final PreparationWorkload workload;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final budget = workload.dailyPreparationBudgetMinutes;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          Text(
            budget == null
                ? 'No account-wide daily budget set. Existing per-plan limits still apply.'
                : '${_duration(budget)} total preparation per day across confirmed plans.',
          ),
          TextButton(
            onPressed: onOpenSettings,
            child: Text(budget == null ? 'Set budget' : 'Change budget'),
          ),
        ],
      ),
    );
  }
}

class _WorkloadDayRow extends StatelessWidget {
  const _WorkloadDayRow({required this.day, required this.budget});

  final PreparationWorkloadDay day;
  final int? budget;

  @override
  Widget build(BuildContext context) {
    final needsReview = day.overBudgetMinutes > 0;
    final date = DateFormat('EEE, MMM d').format(day.localDate);
    final status = budget == null
        ? 'No total budget'
        : needsReview
            ? 'Needs review · ${_duration(day.overBudgetMinutes)} over'
            : '${_duration(day.remainingBudgetMinutes ?? 0)} remaining';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(date, style: Theme.of(context).textTheme.labelLarge),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_duration(day.reservedPreparationMinutes)} reserved · '
                  '${day.activePlanCount} ${day.activePlanCount == 1 ? 'plan' : 'plans'}',
                ),
                Text(
                  '${_duration(day.fixedCommitmentMinutes)} weekly setup commitments',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  status,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: needsReview
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _summary(PreparationWorkload workload) {
  final review = workload.daysNeedingReview;
  return '${_duration(workload.totalReservedMinutes)} confirmed'
      '${review == 0 ? '' : ' · $review ${review == 1 ? 'day' : 'days'} need review'}';
}

String _duration(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '$minutes min';
  if (remainder == 0) return '${hours}h';
  return '${hours}h ${remainder}m';
}
