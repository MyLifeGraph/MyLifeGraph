import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/deadline_plan.dart';

typedef PreparationWorkloadDetailLoader = Future<PreparationWorkloadDetail>
    Function(String localDate);
typedef PreparationPlanAction = void Function(String planId);

class PreparationWorkloadCard extends StatefulWidget {
  const PreparationWorkloadCard({
    super.key,
    required this.value,
    required this.onRetry,
    required this.onOpenSettings,
    this.onOpenPlans,
    this.onLoadDayDetail,
    this.onReviewPlan,
    this.onReplanPlan,
    this.compact = false,
  });

  final AsyncValue<PreparationWorkload> value;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenPlans;
  final PreparationWorkloadDetailLoader? onLoadDayDetail;
  final PreparationPlanAction? onReviewPlan;
  final PreparationPlanAction? onReplanPlan;
  final bool compact;

  @override
  State<PreparationWorkloadCard> createState() =>
      _PreparationWorkloadCardState();
}

class _PreparationWorkloadCardState extends State<PreparationWorkloadCard> {
  final Map<String, AsyncValue<PreparationWorkloadDetail>> _details = {};

  @override
  void didUpdateWidget(covariant PreparationWorkloadCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value.asData?.value.generatedAt !=
        widget.value.asData?.value.generatedAt) {
      _details.clear();
    }
  }

  Future<void> _loadDetail(String localDate) async {
    final loader = widget.onLoadDayDetail;
    if (loader == null) return;
    final workloadGeneratedAt = widget.value.asData?.value.generatedAt;
    setState(() => _details[localDate] = const AsyncLoading());
    try {
      final detail = await loader(localDate);
      if (!mounted ||
          workloadGeneratedAt != widget.value.asData?.value.generatedAt) {
        return;
      }
      setState(() => _details[localDate] = AsyncData(detail));
    } catch (error, stackTrace) {
      if (!mounted ||
          workloadGeneratedAt != widget.value.asData?.value.generatedAt) {
        return;
      }
      setState(
        () => _details[localDate] = AsyncError(error, stackTrace),
      );
    }
  }

  void _handleExpansion(PreparationWorkloadDay day, bool expanded) {
    if (!expanded ||
        day.activePlanCount == 0 ||
        widget.onLoadDayDetail == null) {
      return;
    }
    final current = _details[day.localDateKey];
    if (current == null || current.hasError) {
      _loadDetail(day.localDateKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.value.when(
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
            OutlinedButton(
              onPressed: widget.onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (workload) => widget.compact
          ? _CompactWorkload(
              workload: workload,
              onOpenSettings: widget.onOpenSettings,
              onOpenPlans: widget.onOpenPlans,
              details: _details,
              canLoadDetails: widget.onLoadDayDetail != null,
              onExpansionChanged: _handleExpansion,
              onRetryDetail: _loadDetail,
              onReloadSummary: widget.onRetry,
              onReviewPlan: widget.onReviewPlan,
              onReplanPlan: widget.onReplanPlan,
            )
          : _ExpandedWorkload(
              workload: workload,
              onOpenSettings: widget.onOpenSettings,
              details: _details,
              canLoadDetails: widget.onLoadDayDetail != null,
              onExpansionChanged: _handleExpansion,
              onRetryDetail: _loadDetail,
              onReloadSummary: widget.onRetry,
              onReviewPlan: widget.onReviewPlan,
              onReplanPlan: widget.onReplanPlan,
            ),
    );
  }
}

class _CompactWorkload extends StatelessWidget {
  const _CompactWorkload({
    required this.workload,
    required this.onOpenSettings,
    required this.onOpenPlans,
    required this.details,
    required this.canLoadDetails,
    required this.onExpansionChanged,
    required this.onRetryDetail,
    required this.onReloadSummary,
    required this.onReviewPlan,
    required this.onReplanPlan,
  });

  final PreparationWorkload workload;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenPlans;
  final Map<String, AsyncValue<PreparationWorkloadDetail>> details;
  final bool canLoadDetails;
  final void Function(PreparationWorkloadDay, bool) onExpansionChanged;
  final ValueChanged<String> onRetryDetail;
  final VoidCallback onReloadSummary;
  final PreparationPlanAction? onReviewPlan;
  final PreparationPlanAction? onReplanPlan;

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
              timezone: workload.timezone,
              detail: details[day.localDateKey],
              canLoadDetail: canLoadDetails,
              onExpansionChanged: (expanded) =>
                  onExpansionChanged(day, expanded),
              onRetryDetail: () => onRetryDetail(day.localDateKey),
              onReloadSummary: onReloadSummary,
              onReviewPlan: onReviewPlan,
              onReplanPlan: onReplanPlan,
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
    required this.details,
    required this.canLoadDetails,
    required this.onExpansionChanged,
    required this.onRetryDetail,
    required this.onReloadSummary,
    required this.onReviewPlan,
    required this.onReplanPlan,
  });

  final PreparationWorkload workload;
  final VoidCallback onOpenSettings;
  final Map<String, AsyncValue<PreparationWorkloadDetail>> details;
  final bool canLoadDetails;
  final void Function(PreparationWorkloadDay, bool) onExpansionChanged;
  final ValueChanged<String> onRetryDetail;
  final VoidCallback onReloadSummary;
  final PreparationPlanAction? onReviewPlan;
  final PreparationPlanAction? onReplanPlan;

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
              timezone: workload.timezone,
              detail: details[day.localDateKey],
              canLoadDetail: canLoadDetails,
              onExpansionChanged: (expanded) =>
                  onExpansionChanged(day, expanded),
              onRetryDetail: () => onRetryDetail(day.localDateKey),
              onReloadSummary: onReloadSummary,
              onReviewPlan: onReviewPlan,
              onReplanPlan: onReplanPlan,
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
  const _WorkloadDayRow({
    required this.day,
    required this.budget,
    required this.timezone,
    required this.detail,
    required this.canLoadDetail,
    required this.onExpansionChanged,
    required this.onRetryDetail,
    required this.onReloadSummary,
    required this.onReviewPlan,
    required this.onReplanPlan,
  });

  final PreparationWorkloadDay day;
  final int? budget;
  final String timezone;
  final AsyncValue<PreparationWorkloadDetail>? detail;
  final bool canLoadDetail;
  final ValueChanged<bool> onExpansionChanged;
  final VoidCallback onRetryDetail;
  final VoidCallback onReloadSummary;
  final PreparationPlanAction? onReviewPlan;
  final PreparationPlanAction? onReplanPlan;

  @override
  Widget build(BuildContext context) {
    final needsReview = day.overBudgetMinutes > 0;
    final date = DateFormat('EEE, MMM d').format(day.localDate);
    final status = budget == null
        ? 'No total budget'
        : needsReview
            ? 'Needs review · ${_duration(day.overBudgetMinutes)} over'
            : '${_duration(day.remainingBudgetMinutes ?? 0)} remaining';
    final summary = _DaySummary(day: day, status: status);
    if (!canLoadDetail || day.activePlanCount == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(
                date,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: summary),
          ],
        ),
      );
    }
    return ExpansionTile(
      key: ValueKey('preparation-workload-day-${day.localDateKey}'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(
        left: AppSpacing.sm,
        right: AppSpacing.sm,
        bottom: AppSpacing.sm,
      ),
      onExpansionChanged: onExpansionChanged,
      title: Text(date, style: Theme.of(context).textTheme.labelLarge),
      subtitle: summary,
      children: [
        _WorkloadDayDetail(
          summary: day,
          summaryBudget: budget,
          summaryTimezone: timezone,
          value: detail,
          onRetry: onRetryDetail,
          onReloadSummary: onReloadSummary,
          onReviewPlan: onReviewPlan,
          onReplanPlan: onReplanPlan,
        ),
      ],
    );
  }
}

class _DaySummary extends StatelessWidget {
  const _DaySummary({required this.day, required this.status});

  final PreparationWorkloadDay day;
  final String status;

  @override
  Widget build(BuildContext context) {
    final needsReview = day.overBudgetMinutes > 0;
    return Column(
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
    );
  }
}

class _WorkloadDayDetail extends StatelessWidget {
  const _WorkloadDayDetail({
    required this.summary,
    required this.summaryBudget,
    required this.summaryTimezone,
    required this.value,
    required this.onRetry,
    required this.onReloadSummary,
    required this.onReviewPlan,
    required this.onReplanPlan,
  });

  final PreparationWorkloadDay summary;
  final int? summaryBudget;
  final String summaryTimezone;
  final AsyncValue<PreparationWorkloadDetail>? value;
  final VoidCallback onRetry;
  final VoidCallback onReloadSummary;
  final PreparationPlanAction? onReviewPlan;
  final PreparationPlanAction? onReplanPlan;

  @override
  Widget build(BuildContext context) {
    final detail = value;
    if (detail == null || detail.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('Loading plan breakdown…')),
          ],
        ),
      );
    }
    if (detail.hasError) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Plan breakdown unavailable. The confirmed daily total above was not replaced.',
            ),
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }
    final data = detail.requireValue;
    final changed =
        data.reservedPreparationMinutes != summary.reservedPreparationMinutes ||
            data.contributions.length != summary.activePlanCount ||
            data.dailyPreparationBudgetMinutes != summaryBudget ||
            data.timezone != summaryTimezone;
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (changed) ...[
            const Text(
              'Reservations changed since this seven-day summary was loaded.',
            ),
            TextButton(
              onPressed: onReloadSummary,
              child: const Text('Reload 7-day load'),
            ),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: data.overBudgetMinutes > 0
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              data.overBudgetMinutes > 0
                  ? 'At least ${_duration(data.overBudgetMinutes)} must be redistributed on this date to fit your current daily preparation budget. Review a plan below; nothing changes automatically.'
                  : data.dailyPreparationBudgetMinutes == null
                      ? 'No account-wide daily budget is set. This breakdown is read-only.'
                      : 'This date currently fits your daily preparation budget. This breakdown is read-only.',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final contribution in data.contributions) ...[
            _WorkloadContribution(
              contribution: contribution,
              onReviewPlan: onReviewPlan,
              onReplanPlan: onReplanPlan,
            ),
            if (contribution != data.contributions.last)
              const Divider(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}

class _WorkloadContribution extends StatelessWidget {
  const _WorkloadContribution({
    required this.contribution,
    required this.onReviewPlan,
    required this.onReplanPlan,
  });

  final PreparationWorkloadContribution contribution;
  final PreparationPlanAction? onReviewPlan;
  final PreparationPlanAction? onReplanPlan;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          contribution.title,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text(
          '${_duration(contribution.reservedPreparationMinutes)} reserved · '
          '${contribution.blockCount} ${contribution.blockCount == 1 ? 'block' : 'blocks'}',
        ),
        if (onReviewPlan != null || onReplanPlan != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (onReviewPlan != null)
                OutlinedButton(
                  key: ValueKey('workload-review-${contribution.planId}'),
                  onPressed: () => onReviewPlan!(contribution.planId),
                  child: const Text('Review plan'),
                ),
              if (onReplanPlan != null)
                OutlinedButton.icon(
                  key: ValueKey('workload-replan-${contribution.planId}'),
                  onPressed: () => onReplanPlan!(contribution.planId),
                  icon: const Icon(Icons.autorenew),
                  label: const Text('Replan remaining time'),
                ),
            ],
          ),
        ],
      ],
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
