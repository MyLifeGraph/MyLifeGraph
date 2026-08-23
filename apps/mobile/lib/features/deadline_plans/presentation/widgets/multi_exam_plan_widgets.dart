part of '../pages/deadline_plans_page.dart';

class _MultiExamPlanSection extends StatelessWidget {
  const _MultiExamPlanSection({
    required this.state,
    required this.plans,
    required this.health,
    required this.profileTimezone,
    required this.selectedTargetPlanId,
    required this.mutationsBlocked,
    required this.onSelectTarget,
    required this.onPropose,
    required this.onOpenBalance,
    required this.onLoadBalance,
    required this.onConfirm,
    required this.onCancel,
    required this.onRetryExact,
    required this.onReload,
    required this.onRefreshSaved,
    required this.onDismissError,
  });

  final MultiExamPlanState state;
  final List<DeadlinePlan> plans;
  final ExamPlanHealth? health;
  final String? profileTimezone;
  final String? selectedTargetPlanId;
  final bool mutationsBlocked;
  final ValueChanged<String?> onSelectTarget;
  final VoidCallback onPropose;
  final ValueChanged<String> onOpenBalance;
  final ValueChanged<String> onLoadBalance;
  final ValueChanged<MultiExamPlanBatch> onConfirm;
  final ValueChanged<MultiExamPlanBatch> onCancel;
  final VoidCallback onRetryExact;
  final VoidCallback onReload;
  final VoidCallback onRefreshSaved;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    final currentProfileTimezone = _validProfileTimezone(profileTimezone);
    final candidates = plans
        .where(
          (plan) =>
              plan.isActive &&
              plan.kind == DeadlinePlanKind.exam &&
              plan.activeRevision != null,
        )
        .toList(growable: false)
      ..sort((left, right) {
        final leftRevision = left.activeRevision!;
        final rightRevision = right.activeRevision!;
        final deadline = leftRevision.deadlineAt.compareTo(
          rightRevision.deadlineAt,
        );
        if (deadline != 0) return deadline;
        final remaining = right.progress.remainingMinutes.compareTo(
          left.progress.remainingMinutes,
        );
        return remaining != 0 ? remaining : left.id.compareTo(right.id);
      });
    final selected = candidates.any(
      (candidate) => candidate.id == selectedTargetPlanId,
    )
        ? selectedTargetPlanId
        : null;
    final hasSinglePreview = plans.any((plan) => plan.pendingRevision != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          key: const ValueKey('multi-exam-balance-cta'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(AppIcons.tuneOutlined),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Balance exam plans',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Choose one saved Exam explicitly. MyLifeGraph will calculate a preview across affected Exams. Nothing moves until you review and confirm the whole preview; no external calendar or notification is changed.',
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                key: const ValueKey('multi-exam-target-picker'),
                initialValue: selected,
                isExpanded: true,
                itemHeight: null,
                decoration: const InputDecoration(
                  labelText: 'Exam to rebalance',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final plan in candidates)
                    DropdownMenuItem(
                      value: plan.id,
                      child: Text(
                        _multiExamCandidateLabel(plan, health),
                        softWrap: true,
                      ),
                    ),
                ],
                onChanged: mutationsBlocked || candidates.isEmpty
                    ? null
                    : onSelectTarget,
              ),
              if (candidates.isEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Confirm an Exam preparation plan before balancing Exam reservations.',
                ),
              ],
              if (hasSinglePreview) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Confirm or discard the existing single-plan preview first.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                key: const ValueKey('multi-exam-preview-button'),
                onPressed: selected == null ||
                        hasSinglePreview ||
                        mutationsBlocked ||
                        state.requiresExactRetry ||
                        state.metadataStatus !=
                            MultiExamPlanMetadataStatus.current
                    ? null
                    : onPropose,
                icon: const Icon(AppIcons.visibilityOutlined),
                label: const Text('Preview exam balance'),
              ),
              if (state.operation == MultiExamPlanOperation.proposing) ...[
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  liveRegion: true,
                  label: 'Calculating exam balance preview',
                  child: LinearProgressIndicator(),
                ),
              ],
              if (state.lastOutcome != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  liveRegion: true,
                  child: Text(_multiExamOutcomeCopy(state.lastOutcome!)),
                ),
              ],
            ],
          ),
        ),
        if (state.savedButRefreshFailed)
          _MessageCard(
            icon: AppIcons.syncProblemOutlined,
            title: 'Exam balance saved; screen refresh incomplete',
            message:
                'The server already saved this result. Do not repeat the mutation. Refresh the projections to show the latest plans.',
            actionLabel: 'Refresh saved result',
            onAction: onRefreshSaved,
            liveRegion: true,
          ),
        if (state.operationError != null)
          _MultiExamPlanErrorCard(
            error: state.operationError!,
            exactRetry: state.requiresExactRetry,
            onRetryExact: onRetryExact,
            onReload: onReload,
            onDismiss: onDismissError,
          ),
        if (state.loadError != null)
          _MessageCard(
            icon: AppIcons.cloudOffOutlined,
            title: 'Exam balance previews unavailable',
            message:
                'Saved preparation plans remain usable, but Exam balance history could not be loaded. Pending child previews stay protected from single confirmation.',
            actionLabel: 'Retry Exam balances',
            onAction: onReload,
            liveRegion: true,
          )
        else if (state.isLoading)
          const AppCard(
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: AppSpacing.md),
                Expanded(child: Text('Loading Exam balance previews…')),
              ],
            ),
          )
        else if (state.balances.isNotEmpty) ...[
          Text(
            'Exam balance previews',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final summary in state.balances)
            AppCard(
              key: ValueKey('multi-exam-summary-${summary.id}'),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_multiExamStatusIcon(summary.status)),
                title: Text(
                  '${summary.affectedPlanCount} Exams · ${_multiExamStatusLabel(summary.status)}',
                ),
                subtitle: Text(
                  '${_duration(summary.shiftedMinutes)} shifted · ${_multiExamSummaryUpdated(summary, currentProfileTimezone)}',
                ),
                trailing: const Icon(AppIcons.arrowForward),
                minVerticalPadding: AppSpacing.sm,
                onTap: mutationsBlocked || state.requiresExactRetry
                    ? null
                    : () => onOpenBalance(summary.id),
              ),
            ),
        ],
        if (state.listDetailError != null)
          _MessageCard(
            icon: AppIcons.cloudOffOutlined,
            title: 'Exam balance details unavailable',
            message:
                'Exam balance history loaded, but one or more pending preview details could not be verified. Pending child previews stay protected from single confirmation.',
            actionLabel: 'Retry Exam balances',
            onAction: onReload,
            liveRegion: true,
          ),
        if (state.selectedDetailError != null)
          _MessageCard(
            icon: AppIcons.searchOffOutlined,
            title: 'Requested Exam balance unavailable',
            message:
                'This preview could not be loaded for the signed-in account. Pending child previews remain fail-closed.',
            actionLabel: state.selectedDetailErrorBalanceId == null
                ? null
                : 'Retry preview',
            onAction: state.selectedDetailErrorBalanceId == null
                ? null
                : () => onLoadBalance(state.selectedDetailErrorBalanceId!),
            liveRegion: true,
          ),
        if (state.selectedBalance != null)
          _MultiExamPlanReviewCard(
            balance: state.selectedBalance!,
            profileTimezone: currentProfileTimezone,
            canConfirm: !mutationsBlocked &&
                currentProfileTimezone != null &&
                state.canConfirm(state.selectedBalance!),
            canCancel:
                !mutationsBlocked && state.canCancel(state.selectedBalance!),
            onConfirm: () => onConfirm(state.selectedBalance!),
            onCancel: () => onCancel(state.selectedBalance!),
          ),
      ],
    );
  }
}

String? _validProfileTimezone(String? timezoneName) {
  final normalized = timezoneName?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  try {
    profileDateTimeAt(
      instant: DateTime.utc(2000),
      timezoneName: normalized,
    );
    return normalized;
  } on ProfileTimezoneException {
    return null;
  }
}

class _MultiExamPlanReviewCard extends StatelessWidget {
  const _MultiExamPlanReviewCard({
    required this.balance,
    required this.profileTimezone,
    required this.canConfirm,
    required this.canCancel,
    required this.onConfirm,
    required this.onCancel,
  });

  final MultiExamPlanBatch balance;
  final String? profileTimezone;
  final bool canConfirm;
  final bool canCancel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final proposed = balance.status == MultiExamPlanStatus.proposed;
    return AppCard(
      key: ValueKey('multi-exam-detail-${balance.id}'),
      child: Semantics(
        container: true,
        label:
            'Exam balance review, ${_multiExamStatusLabel(balance.status)}, ${balance.items.length} affected Exams',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Review Exam balance',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                AppStatusPill(
                  label: _multiExamStatusLabel(balance.status),
                  icon: _multiExamStatusIcon(balance.status),
                  tone: _multiExamStatusTone(balance.status),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${_duration(balance.retainedMinutes)} retained · ${_duration(balance.shiftedMinutes)} shifted · ${_duration(balance.addedMinutes)} added · ${_duration(balance.removedMinutes)} removed',
            ),
            Text(
              profileTimezone == null
                  ? 'Current profile timezone unavailable. Local times stay hidden and confirmation is disabled until the account projection reloads.'
                  : 'Current profile timezone: $profileTimezone. Only the listed changed plans are part of this all-or-none preview.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final item in balance.items)
              ExpansionTile(
                key: ValueKey('multi-exam-item-${item.planId}'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
                title: Text('${item.position}. ${item.title}'),
                subtitle: Text(
                  '${_duration(item.remainingMinutes)} remaining · confirmed version ${item.activeRevision} · planning base ${item.baseRevision} · preview version ${item.proposedRevision}',
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_duration(item.retainedMinutes)} retained · ${_duration(item.shiftedMinutes)} shifted · ${_duration(item.addedMinutes)} added · ${_duration(item.removedMinutes)} removed',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _MultiExamBlocks(
                    heading: 'Currently reserved',
                    blocks: item.currentBlocks,
                    timezone: profileTimezone,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _MultiExamBlocks(
                    heading: 'Proposed after confirmation',
                    blocks: item.proposedBlocks,
                    timezone: profileTimezone,
                  ),
                ],
              ),
            if (proposed) ...[
              const Divider(),
              const Text(
                'Confirming applies every listed Exam revision atomically. Discarding removes only this batch preview and never cancels an active preparation plan.',
              ),
              const SizedBox(height: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('multi-exam-confirm-all'),
                    onPressed: canConfirm ? onConfirm : null,
                    icon: const Icon(AppIcons.eventAvailableOutlined),
                    label: const Text('Confirm all'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    key: const ValueKey('multi-exam-discard'),
                    onPressed: canCancel ? onCancel : null,
                    icon: const Icon(AppIcons.cancelOutlined),
                    label: const Text('Discard'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MultiExamBlocks extends StatelessWidget {
  const _MultiExamBlocks({
    required this.heading,
    required this.blocks,
    required this.timezone,
  });

  final String heading;
  final List<MultiExamPlanBlock> blocks;
  final String? timezone;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(heading, style: Theme.of(context).textTheme.titleSmall),
            if (blocks.isEmpty)
              const Text('No future reservation.')
            else
              for (final block in blocks)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(_multiExamBlockCopy(block, timezone)),
                ),
          ],
        ),
      );
}

class _MultiExamPlanErrorCard extends StatelessWidget {
  const _MultiExamPlanErrorCard({
    required this.error,
    required this.exactRetry,
    required this.onRetryExact,
    required this.onReload,
    required this.onDismiss,
  });

  final Object error;
  final bool exactRetry;
  final VoidCallback onRetryExact;
  final VoidCallback onReload;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final stale = apiFailureFrom(error)?.statusCode == 409;
    return Semantics(
      liveRegion: true,
      container: true,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(stale ? AppIcons.syncProblemOutlined : AppIcons.errorOutline),
            const SizedBox(height: AppSpacing.sm),
            Text(
              exactRetry
                  ? 'Exam balance result is uncertain'
                  : stale
                      ? 'Exam balance preview is stale'
                      : 'Exam balance could not be completed',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              exactRetry
                  ? 'The response was lost or the server failed after the request began. Retry the exact saved request; do not create a new request id.'
                  : stale
                      ? 'Focus, timezone, Study Setup, budget, Calendar, plan revisions or reservations changed. The readable review was kept. Reload and create a fresh preview; stale mutations are never retried automatically.'
                      : 'No automatic plan movement occurred. Review current plans before trying again.',
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton(
                  onPressed: exactRetry ? onRetryExact : onReload,
                  child: Text(
                    exactRetry
                        ? 'Retry unchanged request'
                        : 'Reload Exam balances',
                  ),
                ),
                if (!exactRetry && !stale)
                  TextButton(
                    onPressed: onDismiss,
                    child: const Text('Dismiss'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _multiExamCandidateLabel(DeadlinePlan plan, ExamPlanHealth? health) {
  final revision = plan.activeRevision!;
  ExamPlanHealthItem? healthItem;
  for (final candidate in health?.exams ?? const <ExamPlanHealthItem>[]) {
    if (candidate.planId == plan.id) {
      healthItem = candidate;
      break;
    }
  }
  final status = healthItem == null
      ? 'health unavailable'
      : _examHealthStatusLabel(healthItem.status).toLowerCase();
  return '${revision.title} · $status · ${_duration(plan.progress.remainingMinutes)} remaining';
}

String _multiExamOutcomeCopy(String outcome) => switch (outcome) {
      'no_change' =>
        'No change is needed. The selected Exam already has the minimal safe arrangement.',
      'single_plan' =>
        'One existing Deadline V1 preview was saved. Review that Exam card and confirm it there.',
      'multi_exam_batch' =>
        'A shared Exam balance preview was saved. Review every listed change before confirming all.',
      'confirmed' => 'Every listed Exam change was confirmed atomically.',
      'cancelled' =>
        'The shared preview was discarded. Active Exam plans were not cancelled.',
      _ => outcome,
    };

String _multiExamStatusLabel(MultiExamPlanStatus status) => switch (status) {
      MultiExamPlanStatus.proposed => 'Preview',
      MultiExamPlanStatus.confirmed => 'Confirmed',
      MultiExamPlanStatus.cancelled => 'Discarded',
    };

IconData _multiExamStatusIcon(MultiExamPlanStatus status) => switch (status) {
      MultiExamPlanStatus.proposed => AppIcons.visibilityOutlined,
      MultiExamPlanStatus.confirmed => AppIcons.checkCircleOutline,
      MultiExamPlanStatus.cancelled => AppIcons.cancelOutlined,
    };

AppStatusTone _multiExamStatusTone(MultiExamPlanStatus status) =>
    switch (status) {
      MultiExamPlanStatus.proposed => AppStatusTone.attention,
      MultiExamPlanStatus.confirmed => AppStatusTone.success,
      MultiExamPlanStatus.cancelled => AppStatusTone.neutral,
    };

String _multiExamBlockCopy(MultiExamPlanBlock block, String? timezone) {
  if (timezone == null) {
    return '${_duration(block.plannedMinutes)} Focus · current profile timezone unavailable';
  }
  try {
    final start = profileDateTimeAt(
      instant: block.startsAt,
      timezoneName: timezone,
    );
    final end = profileDateTimeAt(
      instant: block.endsAt,
      timezoneName: timezone,
    );
    return '${DateFormat.yMMMd().add_Hm().format(start)}–${DateFormat.Hm().format(end)} · ${_duration(block.plannedMinutes)} Focus${block.recoveryMinutes > 0 ? ' + ${_duration(block.recoveryMinutes)} recovery' : ''}${block.creditedMinutes > 0 ? ' · ${_duration(block.creditedMinutes)} credited' : ''}';
  } on ProfileTimezoneException {
    return '${_duration(block.plannedMinutes)} Focus · current profile timezone invalid';
  }
}

String _multiExamSummaryUpdated(
  MultiExamPlanBatchSummary summary,
  String? timezone,
) {
  if (timezone == null) return 'time unavailable until detail loads';
  try {
    final local = profileDateTimeAt(
      instant: summary.updatedAt,
      timezoneName: timezone,
    );
    return 'updated ${DateFormat.yMMMd().add_Hm().format(local)} $timezone';
  } on ProfileTimezoneException {
    return 'profile timezone unavailable';
  }
}
