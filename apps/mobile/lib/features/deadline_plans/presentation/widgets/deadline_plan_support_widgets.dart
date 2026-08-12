part of '../pages/deadline_plans_page.dart';

class _DurationFields extends StatelessWidget {
  const _DurationFields({
    required this.prefix,
    required this.hours,
    required this.minutes,
    required this.label,
  });

  final String prefix;
  final TextEditingController hours;
  final TextEditingController minutes;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: ValueKey('$prefix-hours'),
              controller: hours,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Hours'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              key: ValueKey('$prefix-minutes'),
              controller: minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Minutes'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressValue extends StatelessWidget {
  const _ProgressValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _OperationErrorCard extends StatelessWidget {
  const _OperationErrorCard({
    required this.state,
    required this.onRetry,
    required this.onReload,
    required this.onDismiss,
    required this.onReview,
  });

  final DeadlinePlanState state;
  final Future<bool> Function() onRetry;
  final Future<void> Function() onReload;
  final VoidCallback onDismiss;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final exact = state.requiresExactRetry;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exact
                ? 'Could not confirm the plan save'
                : 'Could not update the plan',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            exact
                ? 'Your submitted values are still here and locked for a safe retry. Retry unchanged or load the latest saved plan.'
                : deadlinePlanConflictGuidance(state.operationError!) ??
                    _errorMessage(state.operationError!),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (exact)
                FilledButton(
                  onPressed: state.isBusy ? null : onRetry,
                  child: const Text('Retry unchanged'),
                ),
              OutlinedButton(
                onPressed: state.isBusy ? null : onReload,
                child: const Text('Load latest plan'),
              ),
              if (onReview != null)
                OutlinedButton(
                  onPressed: state.isBusy ? null : onReview,
                  child: const Text('Review entered values'),
                ),
              if (!exact && !state.reloadSuggested)
                TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineOperationError extends StatelessWidget {
  const _InlineOperationError({
    required this.error,
    required this.exactRetryLocked,
    required this.isBusy,
    required this.onRetry,
    required this.onReload,
    required this.onDismiss,
  });

  final Object error;
  final bool exactRetryLocked;
  final bool isBusy;
  final Future<bool> Function() onRetry;
  final Future<void> Function() onReload;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('deadline-plan-inline-error'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Could not update this plan',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            exactRetryLocked
                ? 'The plan remains unchanged and visible. Retry the exact request or load the latest saved state.'
                : deadlinePlanConflictGuidance(error) ?? _errorMessage(error),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (exactRetryLocked)
                FilledButton(
                  onPressed: isBusy ? null : onRetry,
                  child: const Text('Retry unchanged'),
                ),
              OutlinedButton(
                onPressed: isBusy ? null : onReload,
                child: const Text('Load latest plan'),
              ),
              if (!exactRetryLocked)
                TextButton(
                  onPressed: isBusy ? null : onDismiss,
                  child: const Text('Dismiss'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(message),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _CalendarPrefillCard extends StatelessWidget {
  const _CalendarPrefillCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(message),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton(
                onPressed: onPrimary,
                child: Text(primaryLabel),
              ),
              if (secondaryLabel != null && onSecondary != null)
                TextButton(
                  onPressed: onSecondary,
                  child: Text(secondaryLabel!),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    this.tone = AppStatusTone.neutral,
  });
  final String label;
  final AppStatusTone tone;

  @override
  Widget build(BuildContext context) => AppStatusPill(
        label: label,
        tone: tone,
      );
}

int? _durationInput(String hoursText, String minutesText) {
  final cleanHours = hoursText.trim();
  final cleanMinutes = minutesText.trim();
  if (cleanHours.isEmpty && cleanMinutes.isEmpty) return null;
  final hours = cleanHours.isEmpty ? 0 : int.tryParse(cleanHours);
  final minutes = cleanMinutes.isEmpty ? 0 : int.tryParse(cleanMinutes);
  if (hours == null ||
      minutes == null ||
      hours < 0 ||
      minutes < 0 ||
      minutes > 59) {
    return null;
  }
  return hours * 60 + minutes;
}

String _duration(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest min';
  if (rest == 0) return '$hours h';
  return '$hours h $rest min';
}

Axis _choiceDirection(BuildContext context) {
  final scaledBody = MediaQuery.textScalerOf(context).scale(14);
  return MediaQuery.sizeOf(context).width < 420 || scaledBody > 20
      ? Axis.vertical
      : Axis.horizontal;
}

String _statusLabel(DeadlinePlanStatus status) => switch (status) {
      DeadlinePlanStatus.draft => 'Draft',
      DeadlinePlanStatus.active => 'Active',
      DeadlinePlanStatus.completed => 'Completed',
      DeadlinePlanStatus.cancelled => 'Cancelled',
    };

AppStatusTone _statusTone(DeadlinePlanStatus status) => switch (status) {
      DeadlinePlanStatus.active ||
      DeadlinePlanStatus.completed =>
        AppStatusTone.success,
      DeadlinePlanStatus.cancelled => AppStatusTone.danger,
      DeadlinePlanStatus.draft => AppStatusTone.neutral,
    };

String _compactPlanSummary({
  required DeadlinePlan plan,
  required bool pending,
  required int remaining,
  required int tracked,
  required bool sourceNeedsReview,
}) {
  if (sourceNeedsReview) {
    return 'Source changed · review before confirming another preview';
  }
  if (pending) {
    return plan.isActive
        ? 'Preview ready · active reservations stay unchanged until confirmation'
        : 'Preview ready · nothing is reserved until confirmation';
  }
  if (plan.isTerminal) {
    return '${_duration(tracked)} tracked Focus · saved preparation history';
  }
  final attention =
      plan.record.attentionReasons.isNotEmpty ? ' · needs attention' : '';
  return '${_duration(remaining)} remaining · ${_duration(tracked)} tracked$attention';
}

String _blockLabel(DeadlinePlanBlockState state) => switch (state) {
      DeadlinePlanBlockState.proposed => 'proposed',
      DeadlinePlanBlockState.upcoming => 'upcoming',
      DeadlinePlanBlockState.partial => 'partly credited',
      DeadlinePlanBlockState.completed => 'fully credited',
      DeadlinePlanBlockState.missed => 'missed',
    };

String _deadlineAllocationDescription(DeadlinePlanKind kind) => switch (kind) {
      DeadlinePlanKind.exam =>
        'A new or replanned Exam preview spreads its first sessions across suitable days.',
      DeadlinePlanKind.assignment =>
        'A new or replanned Assignment preview fills the earliest suitable day before moving on.',
    };

String _planningWindowDescription(String energyWindow) =>
    switch (energyWindow) {
      'early_morning' =>
        'Rule-based windows: prefers 06:00–11:00, then tries 13:00–17:00 and 18:00–21:00 if needed.',
      'morning' =>
        'Rule-based windows: prefers 08:00–13:00, then tries 14:00–18:00 and 18:00–21:00 if needed.',
      'afternoon' =>
        'Rule-based windows: prefers 13:00–18:00, then tries 09:00–12:00 and 18:00–21:00 if needed.',
      'evening' =>
        'Rule-based windows: prefers 18:00–23:00, then tries 14:00–17:00 and 09:00–12:00 if needed.',
      _ =>
        'Rule-based windows: tries 09:00–12:00, 14:00–18:00, then 18:00–21:00.',
    };

String _errorMessage(Object error) => switch (error) {
      DeadlinePlanAccessException() =>
        'Your preparation-plan session is no longer available. Load the latest plan and try again.',
      DeadlinePlanContractException() =>
        'The preparation plan could not be read safely. Load the latest plan before trying again.',
      _ => 'The preparation plan operation could not be completed.',
    };
