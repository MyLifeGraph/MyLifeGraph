import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../application/coach_controller.dart';
import '../../application/coach_turn_notice.dart';
import '../../domain/coach.dart';
import 'package:my_life_graph/composition/widgets/app_header_actions.dart';
import '../providers/coach_providers.dart';

class CoachPage extends ConsumerStatefulWidget {
  const CoachPage({super.key});

  @override
  ConsumerState<CoachPage> createState() => _CoachPageState();
}

class _CoachPageState extends ConsumerState<CoachPage> {
  final _messageController = TextEditingController();
  final _latestResponseKey = GlobalKey();
  final _latestReadMarkerKey = GlobalKey();
  final _failureReadMarkerKey = GlobalKey();
  bool _readCheckScheduled = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(coachControllerProvider);
    ref.listen(coachTurnNoticeProvider, (_, __) => _scheduleReadCheck());
    _syncDraft(state.draft);
    final history = state.latestResponse == null
        ? state.history.turns
        : state.history.turns
            .where((turn) => turn.requestId != state.latestResponse!.requestId)
            .toList(growable: false);
    final page = AppPage(
      title: 'Coach',
      subtitle: 'Ask freely. Personal data stays read-only.',
      actions: [
        AppHeaderActions(
          pageActions: [
            IconButton(
              tooltip: 'Refresh Coach',
              onPressed:
                  state.isLoading || state.isSending || state.isDeletingHistory
                      ? null
                      : () => ref.read(coachControllerProvider.notifier).load(),
              icon: const Icon(AppIcons.refreshOutlined),
            ),
          ],
        ),
      ],
      children: [
        _CapabilityCard(state: state),
        SizeChangedLayoutNotifier(
          child: _ComposerCard(
            state: state,
            controller: _messageController,
            failureReadMarkerKey: _failureReadMarkerKey,
            onChanged: ref.read(coachControllerProvider.notifier).updateDraft,
            onSend: _send,
            onCancel: ref.read(coachControllerProvider.notifier).cancelAnalysis,
          ),
        ),
        if (state.latestResponse != null && state.latestMessage != null)
          SizeChangedLayoutNotifier(
            child: Semantics(
              key: _latestResponseKey,
              container: true,
              liveRegion: true,
              child: _ConversationTurnCard(
                title: 'Latest response',
                message: state.latestMessage!,
                response: state.latestResponse!,
                readMarkerKey: _latestReadMarkerKey,
              ),
            ),
          ),
        _HistoryCard(
          state: state,
          turns: history,
          onDelete: _confirmDeleteHistory,
        ),
        const SizedBox(height: 72),
      ],
    );
    _scheduleReadCheck();
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _scheduleReadCheck();
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _scheduleReadCheck();
          return false;
        },
        child: page,
      ),
    );
  }

  Future<void> _send() async {
    final sent = await ref.read(coachControllerProvider.notifier).send();
    if (!sent || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final responseContext = _latestResponseKey.currentContext;
      if (responseContext == null) return;
      Scrollable.ensureVisible(
        responseContext,
        alignment: 0.08,
        duration: context.motionTokens.emphasisFor(context),
        curve: context.motionTokens.curve,
      );
    });
  }

  void _syncDraft(String draft) {
    if (_messageController.text == draft) return;
    _messageController.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }

  void _scheduleReadCheck() {
    if (_readCheckScheduled) return;
    _readCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readCheckScheduled = false;
      if (!mounted) return;
      _markVisibleNoticeRead();
    });
  }

  void _markVisibleNoticeRead() {
    final notice = ref.read(coachTurnNoticeProvider);
    final profileId = ref.read(coachActiveProfileIdProvider);
    if (notice == null || profileId == null || notice.profileId != profileId) {
      return;
    }
    final markerKey = switch (notice.status) {
      CoachTurnNoticeStatus.completed => _latestReadMarkerKey,
      CoachTurnNoticeStatus.failed => _failureReadMarkerKey,
    };
    final markerContext = markerKey.currentContext;
    final marker = markerContext?.findRenderObject();
    final scrollable =
        markerContext == null ? null : Scrollable.maybeOf(markerContext);
    final viewport = scrollable?.context.findRenderObject();
    if (marker is! RenderBox ||
        viewport is! RenderBox ||
        !marker.attached ||
        !viewport.attached ||
        !marker.hasSize ||
        !viewport.hasSize) {
      return;
    }
    final markerTop = marker.localToGlobal(Offset.zero).dy;
    final markerBottom = marker.localToGlobal(Offset(0, marker.size.height)).dy;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final viewportBottom =
        viewport.localToGlobal(Offset(0, viewport.size.height)).dy;
    const tolerance = 0.5;
    if (markerTop + tolerance < viewportTop ||
        markerBottom - tolerance > viewportBottom) {
      return;
    }
    ref.read(coachTurnNoticeProvider.notifier).markRead(
          profileId: profileId,
          requestId: notice.requestId,
          status: notice.status,
        );
  }

  Future<void> _confirmDeleteHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'This removes saved Coach messages and their recorded analysis '
          'details. It does not delete your personal product data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete conversation'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await ref.read(coachControllerProvider.notifier).deleteHistory();
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({required this.state});

  final CoachState state;

  @override
  Widget build(BuildContext context) {
    final capability = state.capabilities;
    if (state.isLoading && capability == null) {
      return const AppCard(
        child: Row(
          children: [
            SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(child: Text('Loading Coach availability …')),
          ],
        ),
      );
    }
    if (capability == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Coach availability error',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            _ErrorText(coachErrorMessage(state.capabilityError)),
          ],
        ),
      );
    }
    final ready = capability.canRespond;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ready ? AppIcons.checkCircleOutline : AppIcons.cloudOffOutlined,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  state.isRateLimited
                      ? 'Daily question limit reached'
                      : ready
                          ? 'Read-only Coach ready'
                          : 'Coach unavailable',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(_availabilitySummary(capability)),
          if (capability.state == CoachCapabilityState.ready) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${capability.limits.remainingRequests} of '
              '${capability.limits.requestsPerLocalDay} questions remain today',
            ),
          ],
          if (state.capabilityError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ErrorText(
              'Coach availability may be out of date. '
              '${coachErrorMessage(state.capabilityError)}',
            ),
          ],
          ExpansionTile(
            key: const Key('coach-capability-details'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
            title: const Text('Technical availability'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Status: ${_humanize(capability.state.code)}\n'
                  'Reason: ${_humanize(capability.reasonCode)}\n'
                  'Model: ${capability.modelRequested ?? 'Not applicable'}\n'
                  'Service tier: ${_humanize(capability.serviceTier)}\n'
                  'Tool limit: ${capability.limits.maxToolCalls}\n'
                  'Turn limit: ${capability.limits.turnTimeoutSeconds} seconds\n'
                  'Snapshot limit: ${capability.limits.snapshotMaxRows} rows · '
                  '${_formatBytes(capability.limits.snapshotMaxBytes)}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _availabilitySummary(CoachCapabilities capability) {
  if (capability.reasonCode == 'local_demo') {
    return 'Coach requires an authenticated synced account.';
  }
  if (capability.provider == CoachProviderName.fake) {
    return 'Uses deterministic test output. No live model is contacted.';
  }
  if (capability.provider == CoachProviderName.localCodexOauth) {
    return capability.state == CoachCapabilityState.ready
        ? 'Local development-only agent · gpt-5.5 · Fast configured. '
            'This is not a production service.'
        : 'The required local gpt-5.5 Fast connection is unavailable.';
  }
  return 'No Coach response provider is enabled for this run.';
}

class _ComposerCard extends StatelessWidget {
  const _ComposerCard({
    required this.state,
    required this.controller,
    required this.failureReadMarkerKey,
    required this.onChanged,
    required this.onSend,
    required this.onCancel,
  });

  final CoachState state;
  final TextEditingController controller;
  final GlobalKey failureReadMarkerKey;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final available = state.capabilities?.canRespond == true;
    final countColor = state.draftCodepoints > coachMessageCodepoints
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ask anything',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Coach may answer directly or inspect your read-only personal '
            'data with SQL and isolated Python. It cannot change the app.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('coach-message-field'),
            controller: controller,
            enabled: available &&
                !state.isLoading &&
                !state.isSending &&
                !state.isDeletingHistory,
            minLines: 3,
            maxLines: 8,
            textInputAction: TextInputAction.newline,
            onChanged: onChanged,
            decoration: InputDecoration(
              labelText: 'Your question',
              hintText: 'What do my data suggest about …?',
              border: const OutlineInputBorder(),
              errorText: state.draftCodepoints > coachMessageCodepoints
                  ? 'Keep the question within 2,000 characters.'
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${state.draftCodepoints}/$coachMessageCodepoints',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: countColor),
            ),
          ),
          if (state.isSending) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Row(
                key: const Key('coach-activity'),
                children: [
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      state.activityMessage ?? 'Working with personal data …',
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (state.sendError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ErrorText(coachErrorMessage(state.sendError)),
            if (state.exactRetryMessage != null)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Retry the unchanged question to check the same request safely.',
                ),
              ),
            ExcludeSemantics(
              child: SizedBox(
                key: failureReadMarkerKey,
                height: 1,
                width: double.infinity,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: state.isSending
                ? OutlinedButton.icon(
                    key: const Key('coach-cancel-button'),
                    onPressed: state.isCancelling ? null : onCancel,
                    icon: const Icon(AppIcons.close),
                    label: Text(
                      state.isCancelling ? 'Cancelling …' : 'Cancel analysis',
                    ),
                  )
                : FilledButton.icon(
                    key: const Key('coach-send-button'),
                    onPressed: state.canSend ? onSend : null,
                    icon: const Icon(AppIcons.sendOutlined),
                    label: const Text('Ask Coach'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.state,
    required this.turns,
    required this.onDelete,
  });

  final CoachState state;
  final List<CoachHistoryTurn> turns;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final hasConversation = turns.isNotEmpty || state.latestResponse != null;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Conversation history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: hasConversation &&
                        !state.isLoading &&
                        !state.isDeletingHistory &&
                        !state.isSending
                    ? onDelete
                    : null,
                icon: state.isDeletingHistory
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppIcons.deleteOutline),
                label: const Text('Delete'),
              ),
            ],
          ),
          if (state.historyError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ErrorText(coachErrorMessage(state.historyError)),
          ],
          if (state.historyActionError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ErrorText(coachErrorMessage(state.historyActionError)),
          ],
          if (turns.isEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              state.latestResponse == null
                  ? 'No saved Coach conversation yet.'
                  : 'The latest response is shown above.',
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.md),
            ...turns.reversed.map(
              (turn) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _ConversationTurnCard(
                  title: DateFormat('MMM d, HH:mm').format(
                    turn.createdAt.toLocal(),
                  ),
                  message: turn.message,
                  response: turn.response,
                  nested: true,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConversationTurnCard extends StatelessWidget {
  const _ConversationTurnCard({
    required this.title,
    required this.message,
    required this.response,
    this.nested = false,
    this.readMarkerKey,
  });

  final String title;
  final String message;
  final CoachResponse response;
  final bool nested;
  final GlobalKey? readMarkerKey;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Text('You', style: Theme.of(context).textTheme.labelLarge),
        Text(message),
        const SizedBox(height: AppSpacing.md),
        Text('Coach', style: Theme.of(context).textTheme.labelLarge),
        Text(response.reply),
        const SizedBox(height: AppSpacing.md),
        Text('Uncertainty', style: Theme.of(context).textTheme.labelLarge),
        Text('${_humanize(response.uncertainty.level)} · '
            '${response.uncertainty.reason}'),
        if (readMarkerKey != null)
          ExcludeSemantics(
            child: SizedBox(
              key: readMarkerKey,
              height: 1,
              width: double.infinity,
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        _AnalysisDetails(response: response),
      ],
    );
    if (!nested) return AppCard(child: content);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: content,
      ),
    );
  }
}

class _AnalysisDetails extends StatelessWidget {
  const _AnalysisDetails({required this.response});

  final CoachResponse response;

  @override
  Widget build(BuildContext context) {
    final provenance = response.provenance;
    final legacy = response.usesLegacySelectedContext;
    return ExpansionTile(
      key: ValueKey('coach-analysis-${response.requestId}'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
      title: const Text('Data and analysis details'),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            legacy
                ? 'Selected context in older response'
                : 'Snapshot source coverage',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        if (response.evidence.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              legacy
                  ? 'No selected context was recorded for this older response.'
                  : 'No snapshot source coverage was recorded.',
            ),
          ),
        ...response.evidence.map(
          (item) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(_humanize(item.source)),
            subtitle: Text(_coverageText(item, legacy: legacy)),
          ),
        ),
        if (response.evidence.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              legacy
                  ? 'Counts describe context selected for this older response, '
                      'not snapshot coverage or current tool evidence.'
                  : 'Counts and dates describe source coverage, not rows '
                      'returned by one query.',
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Analysis steps · ${response.agentTrace.toolCallCount}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        if (response.agentTrace.steps.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              legacy
                  ? 'No per-turn tool trace was recorded for this older '
                      'response.'
                  : 'No SQL or Python step was used.',
            ),
          )
        else
          ...response.agentTrace.steps.map(
            (step) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${step.sequence}. ${_toolLabel(step.tool)} · '
                '${_humanize(step.status)}',
              ),
              subtitle: Text(
                '${step.summary}\n'
                '${step.rowCount == null ? '' : '${step.rowCount} rows · '}'
                '${step.durationMs} ms',
              ),
            ),
          ),
        if (response.agentTrace.limitations.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Limitations',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          ...response.agentTrace.limitations.map(
            (value) => Align(
              alignment: Alignment.centerLeft,
              child: Text('• $value'),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Technical provenance',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${_provenanceLabel(provenance)}\n'
            'Provider called: ${provenance.providerCalled ? 'yes' : 'no'}\n'
            '${_snapshotText(provenance, legacy: legacy)}\n'
            'Prompt: ${provenance.promptVersion}\n'
            'Context: ${provenance.contextVersion}\n'
            'Answered: ${DateFormat('MMM d, HH:mm').format(
              provenance.generatedAt.toLocal(),
            )}',
          ),
        ),
      ],
    );
  }
}

String _provenanceLabel(CoachProvenance provenance) {
  if (provenance.provider == CoachProviderName.localCodexOauth) {
    if (provenance.fastMode &&
        provenance.serviceTier == 'fast' &&
        provenance.serviceTierStatus == 'configured') {
      return 'gpt-5.5 · Fast configured';
    }
    return 'Local Codex OAuth · Fast status not recorded';
  }
  return '${_humanize(provenance.provider.code)} · '
      '${_humanize(provenance.providerMode)}';
}

String _recordLabel(int value) => value == 1 ? 'record' : 'records';

String _coverageText(
  CoachEvidence evidence, {
  required bool legacy,
}) {
  if (legacy) {
    final available = evidence.availableRecordCount ?? evidence.recordCount;
    return '${evidence.recordCount} of $available ${_recordLabel(available)} '
        'selected for this older response';
  }
  return '${evidence.recordCount} ${_recordLabel(evidence.recordCount)} '
      'in snapshot${_period(evidence)}';
}

String _snapshotText(
  CoachProvenance provenance, {
  required bool legacy,
}) {
  if (legacy) return 'Snapshot: not recorded for this older response';
  return 'Snapshot: ${provenance.snapshotRowCount} rows · '
      '${_formatBytes(provenance.snapshotBytes)}';
}

String _period(CoachEvidence evidence) {
  if (evidence.periodStart == null && evidence.periodEnd == null) return '';
  return ' · ${evidence.periodStart ?? 'unknown'} to '
      '${evidence.periodEnd ?? 'unknown'}';
}

String _toolLabel(String value) => switch (value) {
      'inspect_data' => 'Catalog',
      'query_data' => 'Read-only SQL',
      'run_python' => 'Isolated Python',
      _ => _humanize(value),
    };

String _formatBytes(int value) {
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KiB';
  return '$value B';
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        liveRegion: true,
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
        ),
      );
}

String _humanize(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
