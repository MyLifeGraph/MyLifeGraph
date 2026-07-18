import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../actions/domain/executable_action_target.dart';
import '../../domain/daily_briefing.dart';
import '../../domain/decision_feedback.dart';

typedef GenerateBriefingCallback = Future<void> Function({
  required bool force,
});
typedef ExecuteBriefingActionCallback = Future<void> Function(
  ExecutableActionTarget target,
);
typedef SubmitFeedbackCallback = Future<void> Function(
  BriefingAction action,
  DecisionFeedbackType type,
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
    required this.isSubmittingFeedback,
    required this.feedbackError,
    required this.submittedFeedbackType,
    required this.onFeedback,
    required this.onShowFeedbackHistory,
  });

  final AsyncValue<BriefingFeed> value;
  final bool isGenerating;
  final String? generationError;
  final Set<String> executingActionIds;
  final VoidCallback onRetryRead;
  final GenerateBriefingCallback onGenerate;
  final ExecuteBriefingActionCallback onExecute;
  final bool isSubmittingFeedback;
  final String? feedbackError;
  final DecisionFeedbackType? submittedFeedbackType;
  final SubmitFeedbackCallback onFeedback;
  final VoidCallback onShowFeedbackHistory;

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
              'Today\'s plan unavailable',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Nothing was replaced. Check your connection and try loading your plan again.',
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetryRead,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry today\'s plan'),
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
                  'Today\'s plan',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: AppSpacing.sm),
                Text(
                  'A personal plan is unavailable in demo mode. The app will not pretend the example data is yours.',
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
          isSubmittingFeedback: isSubmittingFeedback,
          feedbackError: feedbackError,
          submittedFeedbackType: submittedFeedbackType,
          onFeedback: onFeedback,
          onShowFeedbackHistory: onShowFeedbackHistory,
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
                Icons.rule_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Plan today',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const _BriefingPill(label: 'Not ready'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Create a plan from your latest check-ins and the tasks or habits you can do today. This will not change them.',
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Rule-based · not AI-written',
            style: Theme.of(context).textTheme.labelMedium,
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
                : const Icon(Icons.playlist_add_check),
            label: Text(
              isGenerating ? 'Creating…' : 'Create today\'s plan',
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
    required this.isSubmittingFeedback,
    required this.feedbackError,
    required this.submittedFeedbackType,
    required this.onFeedback,
    required this.onShowFeedbackHistory,
  });

  final BriefingFeed feed;
  final bool isGenerating;
  final String? generationError;
  final Set<String> executingActionIds;
  final VoidCallback onGenerate;
  final ExecuteBriefingActionCallback onExecute;
  final bool isSubmittingFeedback;
  final String? feedbackError;
  final DecisionFeedbackType? submittedFeedbackType;
  final SubmitFeedbackCallback onFeedback;
  final VoidCallback onShowFeedbackHistory;

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
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Rule-based · not AI-written',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
              _BriefingPill(label: stale ? 'Needs update' : 'Up to date'),
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
                'Your check-ins, tasks, or habits changed after this plan was created. Update it before starting an action.',
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
          const SizedBox(height: AppSpacing.md),
          Text(
            'How did this suggestion fit?',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'This records feedback only; it does not complete or change the action.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: DecisionFeedbackType.values.map((type) {
              return ChoiceChip(
                label: Text(_feedbackLabel(type)),
                selected: submittedFeedbackType == type,
                onSelected: stale ||
                        isSubmittingFeedback ||
                        submittedFeedbackType == type
                    ? null
                    : (_) => onFeedback(briefing.primaryAction, type),
              );
            }).toList(growable: false),
          ),
          if (submittedFeedbackType != null) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Saved. Use Update today\'s plan if you want this feedback considered now.',
            ),
          ],
          if (feedbackError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              feedbackError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
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
                label: Text(
                  isGenerating ? 'Updating…' : 'Update today\'s plan',
                ),
              ),
              TextButton.icon(
                onPressed: onShowFeedbackHistory,
                icon: const Icon(Icons.history),
                label: const Text('Feedback history'),
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
      BriefingMode.push => 'Higher-capacity',
      BriefingMode.steady => 'Balanced',
      BriefingMode.recover => 'Recovery',
      BriefingMode.plan => 'Planning',
    };

String _qualityLabel(BriefingDataQuality quality) => switch (quality) {
      BriefingDataQuality.missing => 'No current',
      BriefingDataQuality.partial => 'Some missing',
      BriefingDataQuality.current => 'Up-to-date',
      BriefingDataQuality.stale => 'Older',
    };

String _feedbackLabel(DecisionFeedbackType type) => switch (type) {
      DecisionFeedbackType.done => 'Done',
      DecisionFeedbackType.later => 'Later',
      DecisionFeedbackType.notHelpful => 'Not helpful',
      DecisionFeedbackType.tooMuch => 'Too much',
      DecisionFeedbackType.doesNotFit => "Doesn't fit",
    };

String _commandLabel(ExecutableActionCommand command) => switch (command) {
      ExecutableActionCommand.openTask => 'Open task',
      ExecutableActionCommand.completeTask => 'Complete task',
      ExecutableActionCommand.logHabit => 'Mark habit done',
      ExecutableActionCommand.startFocus => 'Start focus',
      ExecutableActionCommand.reviewPlan => 'Review your week',
      ExecutableActionCommand.openCapture => 'Open check-in',
    };

IconData _commandIcon(ExecutableActionCommand command) => switch (command) {
      ExecutableActionCommand.openTask => Icons.open_in_new,
      ExecutableActionCommand.completeTask => Icons.check,
      ExecutableActionCommand.logHabit => Icons.check_circle_outline,
      ExecutableActionCommand.startFocus => Icons.timer_outlined,
      ExecutableActionCommand.reviewPlan => Icons.event_note_outlined,
      ExecutableActionCommand.openCapture => Icons.tune,
    };
