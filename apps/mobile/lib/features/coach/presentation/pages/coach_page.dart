import 'package:flutter/material.dart';

import 'package:my_life_graph/core/constants/app_radii.dart';

import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_motion_tokens.dart';
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
  final _latestResponseKey = GlobalKey();

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
      title: 'Coach preview',
      subtitle: 'Development-only explanations and suggestions',
      actions: [
        IconButton(
          tooltip: 'Refresh Coach',
          onPressed: state.isLoading || state.isSending
              ? null
              : () => ref.read(coachControllerProvider.notifier).load(),
          icon: const Icon(AppIcons.refreshOutlined),
        ),
      ],
      children: [
        _CapabilityCard(state: state),
        _CoachContextCard(
          state: state,
          onScopeSelected:
              ref.read(coachControllerProvider.notifier).selectScope,
          onPatternHorizonSelected:
              ref.read(coachControllerProvider.notifier).selectPatternHorizon,
          onFocusSessionSelected:
              ref.read(coachControllerProvider.notifier).selectFocusSession,
          onPromptSelected: _usePromptStarter,
        ),
        _ComposerCard(
          state: state,
          controller: _messageController,
          onChanged: ref.read(coachControllerProvider.notifier).updateDraft,
          onSend: _send,
        ),
        if (state.latestResponse != null && state.latestMessage != null)
          Semantics(
            key: _latestResponseKey,
            container: true,
            liveRegion: true,
            child: _ConversationTurnCard(
              title: 'Latest response',
              message: state.latestMessage!,
              response: state.latestResponse!,
            ),
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
    if (!sent || !mounted) return;
    _messageController.clear();
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

  void _usePromptStarter(String prompt) {
    final state = ref.read(coachControllerProvider);
    if (state.isSending || !state.contextIsValid) return;
    _messageController.value = TextEditingValue(
      text: prompt,
      selection: TextSelection.collapsed(offset: prompt.length),
    );
    ref.read(coachControllerProvider.notifier).updateDraft(prompt);
  }

  Future<void> _confirmDeleteHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'This removes the saved Coach conversation. It does not delete '
          'your tasks, check-ins, or memories.',
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
    final title = state.isRateLimited
        ? 'Rate limited'
        : switch (capability.state) {
            CoachCapabilityState.ready => 'Development Coach ready',
            CoachCapabilityState.disabled => 'Coach unavailable',
            CoachCapabilityState.unavailable => 'Coach temporarily unavailable',
          };
    final icon = ready && capability.limits.remainingRequests > 0
        ? AppIcons.checkCircleOutline
        : AppIcons.infoOutline;
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
          Text(_availabilitySummary(capability)),
          if (ready) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${capability.limits.remainingRequests} of '
              '${capability.limits.requestsPerLocalDay} development requests remain today',
            ),
          ],
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
            title: const Text('Technical availability'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Status: ${capability.state.code}\n'
                  'Reason: ${_humanize(capability.reasonCode)}\n'
                  'Requested model: ${capability.modelRequested ?? 'CLI default'}',
                ),
              ),
            ],
          ),
          if (state.capabilityError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'The latest availability refresh failed; the last validated '
              'state remains visible.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

String _availabilitySummary(CoachCapabilities capability) {
  if (capability.reasonCode == 'local_demo') {
    return 'Coach replies are unavailable in guest or local demo mode. '
        'Use a locally synced account with a Coach-enabled local stack.';
  }
  if (capability.provider == CoachProviderName.disabled) {
    return 'Local replies are off for this run. Restart with '
        'npm run start:local:coach for the signed-in local Codex '
        'connection, or npm run start:local:coach:fake for fixed test '
        'replies.';
  }
  if (capability.provider == CoachProviderName.fake) {
    return capability.state == CoachCapabilityState.ready
        ? 'Uses fixed test responses. This is not a live assistant.'
        : 'The fixed local test provider is currently unavailable.';
  }
  if (capability.provider == CoachProviderName.localCodexOauth) {
    return capability.state == CoachCapabilityState.ready
        ? 'Uses this developer\'s explicitly enabled local Codex login. '
            'This is not a production service and may not work on another '
            'device or account.'
        : 'The explicitly enabled local Codex connection is currently '
            'unavailable. Check the reason below, then refresh Coach.';
  }
  return 'No Coach response provider is available.';
}

class _CoachContextCard extends StatelessWidget {
  const _CoachContextCard({
    required this.state,
    required this.onScopeSelected,
    required this.onPatternHorizonSelected,
    required this.onFocusSessionSelected,
    required this.onPromptSelected,
  });

  final CoachState state;
  final ValueChanged<CoachContextScope> onScopeSelected;
  final ValueChanged<CoachPatternHorizon> onPatternHorizonSelected;
  final ValueChanged<String> onFocusSessionSelected;
  final ValueChanged<String> onPromptSelected;

  @override
  Widget build(BuildContext context) {
    final scope = state.selectedScope;
    final promptsEnabled = state.capabilities?.canRespond == true &&
        state.contextIsValid &&
        !state.isSending;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose Coach context',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Coach uses only the bounded, read-only data for the selected '
            'view. Changing this selection does not change your data.',
          ),
          if (state.contextOptionsError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ErrorText(coachErrorMessage(state.contextOptionsError)),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final value in CoachContextScope.values)
                ChoiceChip(
                  key: ValueKey('coach-context-${value.code}'),
                  label: Text(_contextScopeLabel(value)),
                  selected: scope == value,
                  onSelected: state.isSending
                      ? null
                      : (selected) {
                          if (selected) onScopeSelected(value);
                        },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          switch (scope) {
            CoachContextScope.today => const Text(
                'Uses today’s bounded state, current actions, recent Focus, '
                'selected memories, and limited Coach history.',
              ),
            CoachContextScope.patterns => _PatternContextControls(
                state: state,
                onSelected: onPatternHorizonSelected,
              ),
            CoachContextScope.focus => _FocusContextControls(
                state: state,
                onSelected: onFocusSessionSelected,
              ),
            CoachContextScope.review => const Text(
                'Compares the last two complete ISO weeks using bounded, '
                'rule-based evidence.',
              ),
          },
          const SizedBox(height: AppSpacing.md),
          Text(
            'Prompt starters',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final starter in _promptStarters(scope))
                ActionChip(
                  key: ValueKey(
                    'coach-prompt-${scope.code}-${starter.key}',
                  ),
                  label: Text(starter.label),
                  onPressed: promptsEnabled
                      ? () => onPromptSelected(starter.prompt)
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PatternContextControls extends StatelessWidget {
  const _PatternContextControls({
    required this.state,
    required this.onSelected,
  });

  final CoachState state;
  final ValueChanged<CoachPatternHorizon> onSelected;

  @override
  Widget build(BuildContext context) {
    final enabled = state.contextOptions.personalPatternAnalysisEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Uses deterministic historical summaries, coverage, changes, '
          'counterexamples, and limitations—not a raw history dump.',
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<CoachPatternHorizon>(
            key: const ValueKey('coach-pattern-horizon'),
            segments: const [
              ButtonSegment(
                value: CoachPatternHorizon.days90,
                label: Text('90 days'),
              ),
              ButtonSegment(
                value: CoachPatternHorizon.year1,
                label: Text('1 year'),
              ),
              ButtonSegment(
                value: CoachPatternHorizon.allAvailable,
                label: Text('All available'),
              ),
            ],
            selected: {state.patternHorizon},
            onSelectionChanged: state.isSending
                ? null
                : (selection) => onSelected(selection.single),
          ),
        ),
        if (!enabled && state.contextOptionsError == null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Pattern analysis is off in Personal learning settings. Turn it '
            'on before asking Coach to use historical study evidence.',
            key: const ValueKey('coach-pattern-analysis-disabled'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ],
      ],
    );
  }
}

class _FocusContextControls extends StatelessWidget {
  const _FocusContextControls({
    required this.state,
    required this.onSelected,
  });

  final CoachState state;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = state.contextOptions.focusOptions;
    final selected = options.where(
      (option) => option.focusSessionId == state.selectedFocusSessionId,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Uses one finished Focus session and its saved reflection when one '
          'exists. It does not change the session.',
        ),
        const SizedBox(height: AppSpacing.sm),
        if (options.isEmpty)
          const Text(
            'No finished Focus sessions are available for Coach yet.',
            key: ValueKey('coach-focus-options-empty'),
          )
        else
          _FocusOptionPicker(
            selected: selected.isEmpty ? null : selected.single,
            options: options,
            enabled: !state.isSending,
            onSelected: onSelected,
          ),
        if (state.contextOptions.moreFocusOptionsAvailable) ...[
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Showing the 10 most recent finished Focus sessions.',
          ),
        ],
      ],
    );
  }
}

class _FocusOptionPicker extends StatelessWidget {
  const _FocusOptionPicker({
    required this.selected,
    required this.options,
    required this.enabled,
    required this.onSelected,
  });

  final CoachFocusOption? selected;
  final List<CoachFocusOption> options;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final option = selected;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        key: const ValueKey('coach-focus-session-picker'),
        onPressed: enabled ? () => _showPicker(context) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              const Icon(AppIcons.centerFocusStrong),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option == null
                          ? 'Choose a Focus session'
                          : _focusOptionTitle(option),
                    ),
                    if (option != null)
                      Text(
                        _focusOptionSubtitle(option),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Icon(AppIcons.chevronRight),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text(
                  'Choose a Focus session',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final option in options)
                      ListTile(
                        key: ValueKey(
                          'coach-focus-option-${option.focusSessionId}',
                        ),
                        title: Text(_focusOptionTitle(option)),
                        subtitle: Text(_focusOptionSubtitle(option)),
                        trailing:
                            option.focusSessionId == selected?.focusSessionId
                                ? const Icon(AppIcons.check)
                                : null,
                        onTap: () => Navigator.of(context).pop(
                          option.focusSessionId,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selectedId != null) onSelected(selectedId);
  }
}

String _focusOptionTitle(CoachFocusOption option) =>
    DateFormat('MMM d, y, HH:mm').format(option.localStartedAt);

String _focusOptionSubtitle(CoachFocusOption option) {
  final status =
      option.status == CoachFocusStatus.completed ? 'Completed' : 'Abandoned';
  final reflection = option.hasReflection ? ' · Rated' : '';
  return '${option.actualMinutes} min actual · '
      '${option.plannedMinutes} min planned · $status$reflection';
}

String _contextScopeLabel(CoachContextScope scope) => switch (scope) {
      CoachContextScope.today => 'Today',
      CoachContextScope.patterns => 'Patterns',
      CoachContextScope.focus => 'Focus',
      CoachContextScope.review => 'Review',
    };

class _PromptStarter {
  const _PromptStarter({
    required this.key,
    required this.label,
    required this.prompt,
  });

  final String key;
  final String label;
  final String prompt;
}

List<_PromptStarter> _promptStarters(CoachContextScope scope) =>
    switch (scope) {
      CoachContextScope.today => const [
          _PromptStarter(
            key: 'priorities',
            label: 'Today’s priorities',
            prompt: 'What are the two most sensible priorities for me today, '
                'and what are you uncertain about?',
          ),
          _PromptStarter(
            key: 'protect-time',
            label: 'Protect my time',
            prompt: 'What should I protect time for today, and why?',
          ),
        ],
      CoachContextScope.patterns => const [
          _PromptStarter(
            key: 'changes',
            label: 'What changed?',
            prompt: 'What changed in my study patterns over this period, and '
                'what remains uncertain?',
          ),
          _PromptStarter(
            key: 'obstacles',
            label: 'Recurring obstacles',
            prompt: 'Which recurring obstacle is most worth testing next?',
          ),
          _PromptStarter(
            key: 'counterevidence',
            label: 'Counterevidence',
            prompt: 'What evidence contradicts the strongest pattern?',
          ),
        ],
      CoachContextScope.focus => const [
          _PromptStarter(
            key: 'reflection',
            label: 'Reflect on this session',
            prompt: 'What does this Focus session suggest, and what should I '
                'reflect on next?',
          ),
          _PromptStarter(
            key: 'uncertainty',
            label: 'What is uncertain?',
            prompt: 'What are you uncertain about in this Focus session?',
          ),
        ],
      CoachContextScope.review => const [
          _PromptStarter(
            key: 'compare',
            label: 'Compare both weeks',
            prompt: 'What changed between the last two full weeks, and what '
                'remains uncertain?',
          ),
          _PromptStarter(
            key: 'experiment',
            label: 'A small experiment',
            prompt: 'What is one small experiment worth trying next week?',
          ),
        ],
    };

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
            'Coach can explain and suggest. Every change remains a preview. It cannot apply changes to your '
            'tasks, habits, or schedule.',
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
                  ? 'Keep the message within 2,000 characters.'
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
                  'Your message is still here. Retry it unchanged to check the same request safely.',
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
                  : const Icon(AppIcons.sendOutlined),
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
            'Only selected saved notes may be used in an answer. Selecting one does not change it.',
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
        memory.selected ? AppIcons.bookmark : AppIcons.bookmarkBorder,
      ),
      title: Text(memory.title),
      subtitle: Text(
        '${setupOwned ? 'From Setup' : 'Added manually'} · '
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
              child: Text('Only part of this saved note can be shown here.'),
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
                          ? AppIcons.removeCircleOutline
                          : AppIcons.addCircleOutline,
                    ),
              label: Text(
                memory.selected ? 'Remove from Coach' : 'Use in Coach',
              ),
            ),
            if (setupOwned)
              TextButton.icon(
                onPressed: () => context.go('${AppRoutes.onboarding}?edit=1'),
                icon: const Icon(AppIcons.tuneOutlined),
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
                    : const Icon(AppIcons.deleteOutline),
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
          borderRadius: BorderRadius.circular(AppRadii.md),
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
                  title: Text(_coachSourceLabel(item.source)),
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
                'Answered at: '
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
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
      );
}

String _humanize(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String _coachSourceLabel(CoachContextSource source) => switch (source) {
      CoachContextSource.profile => 'Profile',
      CoachContextSource.dailySnapshot => 'Today\'s check-in state',
      CoachContextSource.dailyBriefing => 'Today\'s plan',
      CoachContextSource.goals => 'Goals',
      CoachContextSource.tasks => 'Tasks',
      CoachContextSource.habits => 'Habits',
      CoachContextSource.focusSessions => 'Focus sessions',
      CoachContextSource.weeklyReview => 'Weekly review',
      CoachContextSource.memories => 'Selected saved notes',
      CoachContextSource.coachHistory => 'Earlier Coach messages',
      CoachContextSource.dailyCapture => 'Daily Capture',
      CoachContextSource.focusReflections => 'Focus sessions and reflections',
      CoachContextSource.habitOutcomes => 'Habit outcomes',
      CoachContextSource.decisionFeedback => 'Decision feedback',
      CoachContextSource.weeklyReviews => 'Weekly reviews',
      CoachContextSource.taskLifecycle => 'Task lifecycle',
    };
