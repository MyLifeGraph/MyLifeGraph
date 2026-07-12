import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../actions/domain/executable_action_target.dart';
import '../../domain/daily_briefing.dart';

typedef GenerateBriefingCallback = Future<void> Function({
  required bool force,
});
typedef ExecuteBriefingActionCallback = Future<void> Function(
  ExecutableActionTarget target,
);

class TodayBriefingSection extends StatelessWidget {
  const TodayBriefingSection({
    super.key,
    required this.value,
    required this.isGenerating,
    required this.generationError,
    required this.executingActionIds,
    required this.onRetryRead,
    required this.onGenerate,
    required this.onExecute,
  });

  final AsyncValue<BriefingFeed> value;
  final bool isGenerating;
  final String? generationError;
  final Set<String> executingActionIds;
  final VoidCallback onRetryRead;
  final GenerateBriefingCallback onGenerate;
  final ExecuteBriefingActionCallback onExecute;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const AppCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, stackTrace) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today briefing unavailable',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Your account data was not replaced with a generated or demo plan.',
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetryRead,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry briefing'),
            ),
          ],
        ),
      ),
      data: (feed) {
        if (feed.origin == BriefingOrigin.localDemo) {
          return const AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily briefing',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: AppSpacing.sm),
                Text(
                  'Personalized briefing generation is unavailable in local demo mode. No account plan was fabricated.',
                ),
              ],
            ),
          );
        }
        if (feed.freshness == BriefingFreshness.missing) {
          return _MissingBriefingCard(
            isGenerating: isGenerating,
            generationError: generationError,
            onGenerate: () => onGenerate(force: false),
          );
        }
        return _BriefingCard(
          feed: feed,
          isGenerating: isGenerating,
          generationError: generationError,
          executingActionIds: executingActionIds,
          onGenerate: () => onGenerate(force: true),
          onExecute: onExecute,
        );
      },
    );
  }
}

class _MissingBriefingCard extends StatelessWidget {
  const _MissingBriefingCard({
    required this.isGenerating,
    required this.generationError,
    required this.onGenerate,
  });

  final bool isGenerating;
  final String? generationError;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.assistant_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Plan today',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const _BriefingPill(label: 'Missing'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'No persisted briefing exists for today. Generate one deliberately from your current state and executable actions.',
          ),
          if (generationError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              generationError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: isGenerating ? null : onGenerate,
            icon: isGenerating
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined),
            label: Text(
              isGenerating ? 'Generating…' : 'Generate today briefing',
            ),
          ),
        ],
      ),
    );
  }
}

class _BriefingCard extends StatelessWidget {
  const _BriefingCard({
    required this.feed,
    required this.isGenerating,
    required this.generationError,
    required this.executingActionIds,
    required this.onGenerate,
    required this.onExecute,
  });

  final BriefingFeed feed;
  final bool isGenerating;
  final String? generationError;
  final Set<String> executingActionIds;
  final VoidCallback onGenerate;
  final ExecuteBriefingActionCallback onExecute;

  @override
  Widget build(BuildContext context) {
    final briefing = feed.briefing!;
    final stale = feed.freshness == BriefingFreshness.stale;
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
                      "Today's decision",
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${_modeLabel(briefing.mode)} mode · ${_qualityLabel(briefing.dataQuality)} data',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
              ),
              _BriefingPill(label: stale ? 'Stale' : 'Current'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(briefing.summary),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.speed_outlined, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(briefing.capacityNote)),
            ],
          ),
          if (stale) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Your source state changed after this briefing. Adjust today before starting its actions.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text('Primary action', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          _BriefingActionTile(
            action: briefing.primaryAction,
            primary: true,
            enabled: !stale,
            isExecuting: executingActionIds.contains(
              briefing.primaryAction.target.id,
            ),
            onExecute: onExecute,
          ),
          if (briefing.supportActions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Support actions',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            ...briefing.supportActions.map(
              (action) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _BriefingActionTile(
                  action: action,
                  primary: false,
                  enabled: !stale,
                  isExecuting: executingActionIds.contains(action.target.id),
                  onExecute: onExecute,
                ),
              ),
            ),
          ],
          if (generationError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              generationError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: isGenerating ? null : onGenerate,
                icon: isGenerating
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(isGenerating ? 'Adjusting…' : 'Adjust today'),
              ),
              Text(
                'Updated ${DateFormat.Hm().format(briefing.updatedAt.toLocal())}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BriefingActionTile extends StatelessWidget {
  const _BriefingActionTile({
    required this.action,
    required this.primary,
    required this.enabled,
    required this.isExecuting,
    required this.onExecute,
  });

  final BriefingAction action;
  final bool primary;
  final bool enabled;
  final bool isExecuting;
  final ExecuteBriefingActionCallback onExecute;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          action.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(action.reason),
        const SizedBox(height: AppSpacing.md),
        if (primary)
          FilledButton.icon(
            onPressed:
                enabled && !isExecuting ? () => onExecute(action.target) : null,
            icon: isExecuting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_commandIcon(action.target.command)),
            label: Text(_commandLabel(action.target.command)),
          )
        else
          OutlinedButton.icon(
            onPressed:
                enabled && !isExecuting ? () => onExecute(action.target) : null,
            icon: isExecuting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_commandIcon(action.target.command)),
            label: Text(_commandLabel(action.target.command)),
          ),
      ],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: primary
            ? Theme.of(context).colorScheme.primaryContainer.withAlpha(110)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: content,
    );
  }
}

class _BriefingPill extends StatelessWidget {
  const _BriefingPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

String _modeLabel(BriefingMode mode) => switch (mode) {
      BriefingMode.push => 'Push',
      BriefingMode.steady => 'Steady',
      BriefingMode.recover => 'Recover',
      BriefingMode.plan => 'Plan',
    };

String _qualityLabel(BriefingDataQuality quality) => switch (quality) {
      BriefingDataQuality.missing => 'Missing',
      BriefingDataQuality.partial => 'Partial',
      BriefingDataQuality.current => 'Current',
      BriefingDataQuality.stale => 'Stale',
    };

String _commandLabel(ExecutableActionCommand command) => switch (command) {
      ExecutableActionCommand.openTask => 'Open task',
      ExecutableActionCommand.completeTask => 'Complete task',
      ExecutableActionCommand.logHabit => 'Mark habit done',
      ExecutableActionCommand.startFocus => 'Start focus',
      ExecutableActionCommand.reviewPlan => 'Plan review unavailable',
      ExecutableActionCommand.openCapture => 'Open calibration',
    };

IconData _commandIcon(ExecutableActionCommand command) => switch (command) {
      ExecutableActionCommand.openTask => Icons.open_in_new,
      ExecutableActionCommand.completeTask => Icons.check,
      ExecutableActionCommand.logHabit => Icons.check_circle_outline,
      ExecutableActionCommand.startFocus => Icons.timer_outlined,
      ExecutableActionCommand.reviewPlan => Icons.event_note_outlined,
      ExecutableActionCommand.openCapture => Icons.tune,
    };
