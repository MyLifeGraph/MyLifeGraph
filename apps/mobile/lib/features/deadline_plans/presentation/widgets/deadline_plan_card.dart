part of '../pages/deadline_plans_page.dart';

class _DeadlinePlanCard extends StatefulWidget {
  const _DeadlinePlanCard({
    super.key,
    required this.plan,
    required this.expanded,
    required this.isBusy,
    required this.exactRetryLocked,
    required this.confirmLabel,
    required this.operationError,
    required this.onToggle,
    required this.onAdjust,
    required this.onReplanMissed,
    required this.onConfirm,
    required this.onComplete,
    required this.onCancel,
    required this.onStartBlock,
    required this.onRetry,
    required this.onReload,
    required this.onDismissError,
  });

  final DeadlinePlan plan;
  final bool expanded;
  final bool isBusy;
  final bool exactRetryLocked;
  final String confirmLabel;
  final Object? operationError;
  final VoidCallback onToggle;
  final VoidCallback onAdjust;
  final VoidCallback onReplanMissed;
  final VoidCallback onConfirm;
  final VoidCallback onComplete;
  final VoidCallback onCancel;
  final ValueChanged<DeadlinePlanBlock> onStartBlock;
  final Future<bool> Function() onRetry;
  final Future<void> Function() onReload;
  final VoidCallback onDismissError;

  @override
  State<_DeadlinePlanCard> createState() => _DeadlinePlanCardState();
}

class _DeadlinePlanCardState extends State<_DeadlinePlanCard> {
  static const _collapsedBlockLimit = 6;

  bool _showAllDisplayedBlocks = false;
  bool _showAllActiveBlocks = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final isBusy = widget.isBusy;
    final exactRetryLocked = widget.exactRetryLocked;
    final onAdjust = widget.onAdjust;
    final onReplanMissed = widget.onReplanMissed;
    final onConfirm = widget.onConfirm;
    final onComplete = widget.onComplete;
    final onCancel = widget.onCancel;
    final onStartBlock = widget.onStartBlock;
    final revision = plan.displayedRevision;
    if (revision == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusPill(
              label: _statusLabel(plan.status),
              tone: _statusTone(plan.status),
            ),
            const SizedBox(height: AppSpacing.sm),
            InkWell(
              onTap: widget.onToggle,
              child: Row(
                children: [
                  Icon(
                    widget.expanded ? AppIcons.expandLess : AppIcons.expandMore,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      plan.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.expanded) ...[
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'This unconfirmed preview was discarded. It created no task or reserved preparation blocks.',
              ),
            ],
          ],
        ),
      );
    }
    final pending = plan.pendingRevision != null;
    final active = plan.activeRevision;
    final sourceNeedsReview =
        revision.sourceStatus == DeadlinePlanSourceStatus.stale ||
            revision.sourceStatus == DeadlinePlanSourceStatus.unavailable;
    final canMutate = !isBusy && !exactRetryLocked && !plan.isTerminal;
    final missedSourceRevision = pending && active != null ? active : revision;
    final missedBlocks = plan.isActive
        ? missedSourceRevision.blocks
            .where((block) => block.state == DeadlinePlanBlockState.missed)
            .toList(growable: false)
        : const <DeadlinePlanBlock>[];
    final missedMinutes = missedBlocks.fold<int>(
      0,
      (sum, block) =>
          sum + (block.plannedMinutes - block.creditedTrackedMinutes),
    );
    final estimate = revision.estimatedTotalMinutes;
    final prior = revision.creditedPriorMinutes;
    final tracked = pending
        ? revision.trackedFocusMinutesAtProposal
        : plan.progress.trackedFocusMinutes;
    final accounted = (prior + tracked).clamp(0, estimate).toInt();
    final remaining = pending
        ? revision.remainingMinutesAtProposal
        : plan.progress.remainingMinutes;
    if (!widget.expanded) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                _StatusPill(
                  label: pending ? 'Preview' : _statusLabel(plan.status),
                  tone: pending
                      ? AppStatusTone.attention
                      : _statusTone(plan.status),
                ),
                _StatusPill(
                  label: revision.kind == DeadlinePlanKind.exam
                      ? 'Exam'
                      : 'Assignment',
                  tone: AppStatusTone.info,
                ),
                if (sourceNeedsReview)
                  const _StatusPill(
                    label: 'Source changed',
                    tone: AppStatusTone.attention,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            InkWell(
              key: ValueKey('deadline-toggle-plan-${plan.id}'),
              onTap: widget.onToggle,
              child: Row(
                children: [
                  const Icon(AppIcons.expandMore),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      revision.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _compactPlanSummary(
                plan: plan,
                pending: pending,
                remaining: remaining,
                tracked: tracked,
                sourceNeedsReview: sourceNeedsReview,
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusPill(
                label: pending ? 'Preview' : _statusLabel(plan.status),
                tone: pending
                    ? AppStatusTone.attention
                    : _statusTone(plan.status),
              ),
              _StatusPill(
                label: revision.kind == DeadlinePlanKind.exam
                    ? 'Exam'
                    : 'Assignment',
                tone: AppStatusTone.info,
              ),
              if (sourceNeedsReview)
                const _StatusPill(
                  label: 'Source changed',
                  tone: AppStatusTone.attention,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          InkWell(
            key: ValueKey('deadline-toggle-plan-${plan.id}'),
            onTap: widget.onToggle,
            child: Row(
              children: [
                const Icon(AppIcons.expandLess),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    revision.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Finish by ${DateFormat.yMMMd().add_Hm().format(revision.deadlineAt.toLocal())} · device time',
          ),
          AppInfoSectionDisclosure(
            heading: 'How new previews place time',
            description:
                '${_deadlineAllocationDescription(revision.kind)} ${_planningWindowDescription(revision.bestEnergyWindow)} Preparation blocks use your profile timezone: ${revision.timezone}.',
            headingStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
            descriptionStyle: Theme.of(context).textTheme.bodySmall,
            keyPrefix: 'deadline-plan-info',
          ),
          if (pending && revision.timingPreference.usedLearnedPattern)
            Text(
              revision.timingPreference.fellBackToSetup
                  ? 'Learned timing considered · Setup fallback · '
                      '${revision.timingPreference.evidenceCount} rated sessions'
                  : 'Learned timing applied · '
                      '${revision.timingPreference.evidenceCount} rated sessions',
              key: const Key('deadline-learned-timing-applied'),
              style: Theme.of(context).textTheme.bodySmall,
            )
          else if (pending && revision.timingPreference.warning != null)
            Text(
              'Personal pattern unavailable · Setup timing used',
              key: const Key('deadline-learned-timing-fallback'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _ProgressValue(
                label: pending ? 'Proposed estimate' : 'Estimate',
                value: _duration(estimate),
              ),
              _ProgressValue(
                label: 'Tracked focus',
                value: _duration(tracked),
              ),
              _ProgressValue(
                label: 'Remaining',
                value: _duration(remaining),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: (accounted / estimate).clamp(0, 1).toDouble(),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${_duration(revision.plannedMinutes)} scheduled · ${_duration(revision.unscheduledMinutes)} unscheduled',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (revision.recoveryMinutes > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${_duration(revision.preferredSessionMinutes)} focus + '
              '${_duration(revision.recoveryMinutes)} recovery per full block. '
              'Recovery is reserved but is not learning time, progress, or preparation budget.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (revision.unscheduledMinutes > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Not all remaining preparation fits before the buffer. Increase the daily cap, start earlier, shorten the buffer, or revise your estimate.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ],
          if (sourceNeedsReview) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'The imported calendar event may be out of date or unavailable. Check the deadline before confirming another version of this plan.',
            ),
          ],
          if (plan.record.attentionReasons.contains('timezone_changed')) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: const Text(
                'The account timezone changed. Existing reservations were not moved. Create a new preview before confirming different times.',
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            pending
                ? plan.isActive
                    ? 'Proposed reservations only. Your currently active plan remains in place until you confirm.'
                    : 'Proposed reservations only. Nothing is reserved until you confirm.'
                : 'Reserved in MyLifeGraph only',
          ),
          if (plan.isActive) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Linked Focus completed after this plan was first activated counts toward the plan as a whole and fills reserved blocks in chronological order. Starting from a row only prefills its remaining duration.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (missedMinutes >= 5) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
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
                    'Plan needs attention',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${missedBlocks.length} reserved ${missedBlocks.length == 1 ? 'block has' : 'blocks have'} passed with ${_duration(missedMinutes)} still uncredited. Start a missed block now if the actual time is free, or replan the remainder.',
                  ),
                  if (pending) ...[
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'The active reservations still need attention while the replacement remains an unconfirmed preview.',
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton.icon(
                    key: ValueKey('deadline-replan-missed-${plan.id}'),
                    onPressed: canMutate ? onReplanMissed : null,
                    icon: const Icon(AppIcons.autorenew),
                    label: const Text('Replan remaining time'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          for (final block in _visibleBlocks(
            revision.blocks,
            showAll: _showAllDisplayedBlocks,
          ))
            _DeadlineBlockTile(
              block: block,
              canStart: plan.isActive &&
                  !pending &&
                  block.plannedMinutes - block.creditedTrackedMinutes >= 5 &&
                  (block.state == DeadlinePlanBlockState.upcoming ||
                      block.state == DeadlinePlanBlockState.partial ||
                      block.state == DeadlinePlanBlockState.missed),
              onStart: () => onStartBlock(block),
            ),
          if (revision.blocks.length > _collapsedBlockLimit)
            TextButton.icon(
              key: ValueKey('deadline-toggle-blocks-${plan.id}'),
              onPressed: () => setState(
                () => _showAllDisplayedBlocks = !_showAllDisplayedBlocks,
              ),
              icon: Icon(
                _showAllDisplayedBlocks
                    ? AppIcons.expandLess
                    : AppIcons.expandMore,
              ),
              label: Text(
                _showAllDisplayedBlocks
                    ? 'Show fewer blocks'
                    : 'Show all ${revision.blocks.length} blocks',
              ),
            ),
          if (pending && active != null) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Currently reserved until you confirm',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(active.title),
            Text(
              '${_duration(active.plannedMinutes)} remains on the weekly plan while this replacement is only a preview.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final block in _visibleBlocks(
              active.blocks,
              showAll: _showAllActiveBlocks,
            ))
              _DeadlineBlockTile(
                block: block,
                canStart:
                    block.plannedMinutes - block.creditedTrackedMinutes >= 5 &&
                        (block.state == DeadlinePlanBlockState.upcoming ||
                            block.state == DeadlinePlanBlockState.partial ||
                            block.state == DeadlinePlanBlockState.missed),
                onStart: () => onStartBlock(block),
              ),
            if (active.blocks.length > _collapsedBlockLimit)
              TextButton.icon(
                key: ValueKey('deadline-toggle-active-blocks-${plan.id}'),
                onPressed: () => setState(
                  () => _showAllActiveBlocks = !_showAllActiveBlocks,
                ),
                icon: Icon(
                  _showAllActiveBlocks
                      ? AppIcons.expandLess
                      : AppIcons.expandMore,
                ),
                label: Text(
                  _showAllActiveBlocks
                      ? 'Show fewer active blocks'
                      : 'Show all ${active.blocks.length} active blocks',
                ),
              ),
          ],
          if (widget.operationError != null) ...[
            const SizedBox(height: AppSpacing.md),
            _InlineOperationError(
              error: widget.operationError!,
              exactRetryLocked: widget.exactRetryLocked,
              isBusy: widget.isBusy,
              onRetry: widget.onRetry,
              onReload: widget.onReload,
              onDismiss: widget.onDismissError,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (pending)
                FilledButton.icon(
                  onPressed: canMutate && !sourceNeedsReview ? onConfirm : null,
                  icon: const Icon(AppIcons.eventAvailableOutlined),
                  label: Text(widget.confirmLabel),
                ),
              if (!plan.isTerminal)
                OutlinedButton.icon(
                  onPressed: canMutate ? onAdjust : null,
                  icon: const Icon(AppIcons.tune),
                  label: const Text('Adjust estimate or plan'),
                ),
              if (plan.isActive)
                OutlinedButton.icon(
                  onPressed: canMutate ? onComplete : null,
                  icon: const Icon(AppIcons.checkCircleOutline),
                  label: const Text('Mark preparation complete'),
                ),
              if (plan.isActive || plan.isDraft)
                TextButton(
                  onPressed: canMutate ? onCancel : null,
                  child: Text(plan.isDraft ? 'Discard preview' : 'Cancel plan'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Iterable<DeadlinePlanBlock> _visibleBlocks(
    List<DeadlinePlanBlock> blocks, {
    required bool showAll,
  }) =>
      showAll ? blocks : blocks.take(_collapsedBlockLimit);
}

class _DeadlineBlockTile extends StatelessWidget {
  const _DeadlineBlockTile({
    required this.block,
    required this.canStart,
    required this.onStart,
  });

  final DeadlinePlanBlock block;
  final bool canStart;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('deadline-block-${block.id}'),
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Text('${block.sequence}')),
      title: Text(
        '${block.localDate} · ${block.localStartTime.substring(0, 5)}–${block.localEndTime.substring(0, 5)}',
      ),
      subtitle: Text(
        '${_duration(block.plannedMinutes)} focus'
        '${block.recoveryMinutes > 0 ? ' + ${_duration(block.recoveryMinutes)} recovery · reserved until ${DateFormat.Hm().format(block.reservedEndsAt.toLocal())}' : ''}'
        ' · ${_blockLabel(block.state)}'
        '${block.creditedTrackedMinutes > 0 ? ' · ${_duration(block.creditedTrackedMinutes)} tracked' : ''}',
      ),
      trailing: canStart
          ? IconButton(
              tooltip: 'Start plan focus with this remaining duration',
              onPressed: onStart,
              icon: const Icon(AppIcons.playArrow),
            )
          : null,
    );
  }
}
