import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../application/coach_controller.dart';
import '../../domain/coach.dart';
import '../providers/coach_providers.dart';

class CoachPage extends ConsumerStatefulWidget {
  const CoachPage({super.key});

  @override
  ConsumerState<CoachPage> createState() => _CoachPageState();
}

class _CoachPageState extends ConsumerState<CoachPage> {
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(coachControllerProvider);
    final history = state.latestResponse == null
        ? state.history.turns
        : state.history.turns
            .where((turn) => turn.requestId != state.latestResponse!.requestId)
            .toList(growable: false);

    return AppPage(
      title: 'Coach',
      subtitle: 'Bounded planning and reflection with visible data use',
      actions: [
        IconButton(
          tooltip: 'Refresh Coach',
          onPressed: state.isLoading || state.isSending
              ? null
              : () => ref.read(coachControllerProvider.notifier).load(),
          icon: const Icon(Icons.refresh_outlined),
        ),
      ],
      children: [
        _CapabilityCard(state: state),
        _ComposerCard(
          state: state,
          controller: _messageController,
          onChanged: ref.read(coachControllerProvider.notifier).updateDraft,
          onSend: _send,
        ),
        if (state.latestResponse != null && state.latestMessage != null)
          _ConversationTurnCard(
            title: 'Latest response',
            message: state.latestMessage!,
            response: state.latestResponse!,
          ),
        _MemoriesCard(state: state),
        _HistoryCard(
          state: state,
          turns: history,
          onDelete: _confirmDeleteHistory,
        ),
        const SizedBox(height: 72),
      ],
    );
  }

  Future<void> _send() async {
    final sent = await ref.read(coachControllerProvider.notifier).send();
    if (sent && mounted) _messageController.clear();
  }

  Future<void> _confirmDeleteHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'This removes the persisted Coach conversation. It does not delete '
          'your goals, tasks, check-ins, or memories.',
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
            Expanded(child: Text('Loading Coach availability…')),
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
            Text(coachErrorMessage(state.capabilityError)),
          ],
        ),
      );
    }

    final ready = capability.state == CoachCapabilityState.ready;
    final localProvider =
        capability.provider == CoachProviderName.localCodexOauth;
    final title = state.isRateLimited
        ? 'Rate limited'
        : switch (capability.state) {
            CoachCapabilityState.ready => 'Coach ready',
            CoachCapabilityState.disabled => 'Coach unavailable',
            CoachCapabilityState.unavailable => 'Coach temporarily unavailable',
          };
    final icon = ready && capability.limits.remainingRequests > 0
        ? Icons.check_circle_outline
        : Icons.info_outline;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            localProvider
                ? 'Responses use your explicitly enabled local development '
                    'Codex connection.'
                : capability.provider == CoachProviderName.fake
                    ? 'Responses use the deterministic test provider.'
                    : 'This local surface does not contact a Coach provider.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Availability: ${capability.state.code} · '
            'Reason: ${_humanize(capability.reasonCode)}',
          ),
          if (ready) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${capability.limits.remainingRequests} of '
              '${capability.limits.requestsPerLocalDay} local requests remain',
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            capability.modelRequested == null
                ? 'Requested model: CLI default'
                : 'Requested model: ${capability.modelRequested}',
          ),
          if (state.capabilityError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'The latest availability refresh failed; the last validated '
              'state remains visible.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _ComposerCard extends StatelessWidget {
  const _ComposerCard({
    required this.state,
    required this.controller,
    required this.onChanged,
    required this.onSend,
  });

  final CoachState state;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final capabilityReady =
        state.capabilities?.state == CoachCapabilityState.ready &&
            state.capabilities!.limits.remainingRequests > 0 &&
            !state.isRateLimited;
    final countColor = state.draftCodepoints > coachMessageCodepoints
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ask Coach', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Coach can explain and suggest. It cannot apply changes to your '
            'tasks, habits, goals, or schedule.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('coach-message-field'),
            controller: controller,
            enabled: capabilityReady && !state.isSending,
            minLines: 3,
            maxLines: 7,
            textInputAction: TextInputAction.newline,
            onChanged: onChanged,
            decoration: InputDecoration(
              labelText: 'Ask Coach',
              hintText: 'What should I pay attention to today?',
              border: const OutlineInputBorder(),
              errorText: state.draftCodepoints > coachMessageCodepoints
                  ? 'Keep the message within 2,000 Unicode code points.'
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
          if (!capabilityReady) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              state.isRateLimited
                  ? 'Rate limited. Existing history and memories remain '
                      'available.'
                  : 'Sending is unavailable. Existing history and memories '
                      'remain available.',
            ),
          ],
          if (state.sendError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ErrorText(coachErrorMessage(state.sendError)),
            if (state.exactRetryMessage != null)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'The exact message and request identity will be reused.',
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('coach-send-button'),
              onPressed: state.canSend ? onSend : null,
              icon: state.isSending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: const Text('Send'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoriesCard extends ConsumerWidget {
  const _MemoriesCard({required this.state});

  final CoachState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = state.memories;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selected memories',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${selection.selectedCount} selected of '
            '${selection.maxSelected} · ${selection.availableCount} available',
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Only selected memories may enter Coach context. Selection does '
            'not change the underlying memory.',
          ),
          if (state.memoryError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ErrorText(coachErrorMessage(state.memoryError)),
          ],
          if (state.memoryActionError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ErrorText(coachErrorMessage(state.memoryActionError)),
          ],
          if (selection.memories.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const Text('No eligible memories are available.'),
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            ...selection.memories.map(
              (memory) => _MemoryTile(
                memory: memory,
                isUpdating: state.updatingMemoryId == memory.id,
                selectionLimitReached:
                    selection.selectedCount >= selection.maxSelected,
                onSelected: (selected) => ref
                    .read(coachControllerProvider.notifier)
                    .setMemorySelected(memory, selected),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({
    required this.memory,
    required this.isUpdating,
    required this.selectionLimitReached,
    required this.onSelected,
  });

  final CoachMemory memory;
  final bool isUpdating;
  final bool selectionLimitReached;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final setupOwned = memory.ownership == CoachMemoryOwnership.setup;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
      leading: Icon(
        memory.selected ? Icons.bookmark : Icons.bookmark_border,
      ),
      title: Text(memory.title),
      subtitle: Text(
        '${setupOwned ? 'Setup-owned' : 'Manual'} · '
        '${memory.selected ? 'selected' : 'not selected'}',
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(memory.content),
        ),
        if (memory.contentTruncated)
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(top: AppSpacing.xs),
              child: Text('Preview truncated by the backend.'),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: isUpdating || !memory.selected && selectionLimitReached
                  ? null
                  : () => onSelected(!memory.selected),
              icon: isUpdating
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      memory.selected
                          ? Icons.remove_circle_outline
                          : Icons.add_circle_outline,
                    ),
              label: Text(
                memory.selected ? 'Remove from Coach' : 'Use in Coach',
              ),
            ),
            if (setupOwned)
              TextButton.icon(
                onPressed: () => context.go('${AppRoutes.onboarding}?edit=1'),
                icon: const Icon(Icons.tune_outlined),
                label: const Text('Edit in Setup'),
              ),
          ],
        ),
      ],
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
                onPressed: hasConversation && !state.isDeletingHistory
                    ? onDelete
                    : null,
                icon: state.isDeletingHistory
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
                label: const Text('Delete conversation'),
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
                  ? 'No persisted Coach conversation yet.'
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
  });

  final String title;
  final String message;
  final CoachResponse response;
  final bool nested;

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
        _ResponseDetails(response: response),
      ],
    );
    if (nested) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: content,
        ),
      );
    }
    return AppCard(child: content);
  }
}

class _ResponseDetails extends StatelessWidget {
  const _ResponseDetails({required this.response});

  final CoachResponse response;

  @override
  Widget build(BuildContext context) {
    final suggestion = response.stagedSuggestion;
    final provenance = response.provenance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Uncertainty', style: Theme.of(context).textTheme.labelLarge),
        Text(
          '${_humanize(response.uncertainty.level.code)} · '
          '${response.uncertainty.reason}',
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('Safety', style: Theme.of(context).textTheme.labelLarge),
        Text(_humanize(response.safety.classification.code)),
        if (suggestion != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Review-only suggestion',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Text(suggestion.title),
          Text(suggestion.rationale),
          const Text('This suggestion cannot apply changes.'),
        ],
        const SizedBox(height: AppSpacing.sm),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
          title: const Text('Data used'),
          children: [
            if (response.usedContext.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('No product context was used.'),
              )
            else
              ...response.usedContext.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(_humanize(item.source.code)),
                  subtitle: Text(
                    '${item.includedCount} of ${item.availableCount} included · '
                    '${item.omittedCount} omitted · '
                    '${_humanize(item.freshness.code)}',
                  ),
                ),
              ),
          ],
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
          title: const Text('Provider and model'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Source: ${_humanize(provenance.source.code)}\n'
                'Provider: ${_humanize(provenance.provider.code)}\n'
                'Mode: ${_humanize(provenance.providerMode.code)}\n'
                'Model requested: '
                '${provenance.modelRequested ?? 'CLI default'}\n'
                'Model reported: '
                '${provenance.modelReported ?? 'Not reported'}\n'
                'Prompt version: ${provenance.promptVersion}\n'
                'Context version: ${provenance.contextVersion}\n'
                'Provider called: ${provenance.providerCalled ? 'yes' : 'no'}\n'
                'Generated: '
                '${DateFormat('MMM d, HH:mm').format(provenance.generatedAt.toLocal())}',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
}

String _humanize(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
