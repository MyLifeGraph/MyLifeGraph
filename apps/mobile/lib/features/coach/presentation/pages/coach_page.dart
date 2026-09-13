import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../composition/widgets/coach_provider_settings_card.dart';
import '../../application/coach_controller.dart';
import '../../application/coach_turn_notice.dart';
import '../../domain/coach.dart';
import 'package:my_life_graph/composition/widgets/app_header_actions.dart';
import '../providers/coach_providers.dart';
import '../widgets/coach_dictation_button.dart';

class CoachPage extends ConsumerStatefulWidget {
  const CoachPage({super.key});

  @override
  ConsumerState<CoachPage> createState() => _CoachPageState();
}

class _CoachPageState extends ConsumerState<CoachPage> {
  final _messageController = TextEditingController();
  final _chatScrollController = ScrollController();
  final _latestResponseKey = GlobalKey();
  final _pendingMessageKey = GlobalKey();
  final _latestReadMarkerKey = GlobalKey();
  final _failureReadMarkerKey = GlobalKey();
  final _composerViewportKey = GlobalKey();
  bool _readCheckScheduled = false;
  bool _historyPositioned = false;

  @override
  void dispose() {
    _messageController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(coachControllerProvider);
    ref.listen(coachTurnNoticeProvider, (_, __) => _scheduleReadCheck());
    _syncDraft(state.isSending ? '' : state.draft);
    final history = [
      ...state.history.turns.where(
        (turn) => turn.requestId != state.latestResponse?.requestId,
      ),
      if (state.latestResponse != null && state.latestMessage != null)
        CoachHistoryTurn(
          requestId: state.latestResponse!.requestId,
          message: state.latestMessage!,
          response: state.latestResponse!,
          createdAt: state.latestResponse!.provenance.generatedAt,
        ),
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final page = AppPage(
      title: 'Coach',
      compactHeader: true,
      actions: [
        if (state.capabilities?.canRespond == true)
          Tooltip(
            message: '${state.capabilities!.limits.remainingRequests} of '
                '${state.capabilities!.limits.requestsPerLocalDay} questions left '
                '${state.capabilities!.limits.requestPeriod == 'utc_day' ? 'today (UTC)' : 'today'}',
            child: Text(
              '${state.capabilities!.limits.remainingRequests}/'
              '${state.capabilities!.limits.requestsPerLocalDay} left',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        AppHeaderActions(
          pageActions: [
            IconButton(
              tooltip: 'Refresh Coach',
              onPressed: state.isLoading ||
                      state.isSending ||
                      state.isDeletingHistory ||
                      state.busyRetrySeconds > 0
                  ? null
                  : () => ref.read(coachControllerProvider.notifier).load(),
              icon: const Icon(AppIcons.refreshOutlined),
            ),
          ],
        ),
      ],
      viewportBody: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        if (state.capabilities?.canRespond != true ||
            state.isRateLimited || state.capabilityError != null ||
            state.capabilities?.provider == CoachProviderName.fake ||
            state.capabilities?.provider == CoachProviderName.localCodexOauth) ...[
        _CapabilityCard(
          state: state,
        ),
        const SizedBox(height: AppSpacing.md),
        ],
        Expanded(child: DecoratedBox(
          key: const Key('app-page-body-outline'),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: LayoutBuilder(builder: (context, constraints) {
            final timeline = SizeChangedLayoutNotifier(child: _ChatTimeline(
              state: state,
              turns: history,
              onDelete: _confirmDeleteHistory,
              latestResponseKey: _latestResponseKey,
              readMarkerKey: _latestReadMarkerKey,
              pendingMessageKey: _pendingMessageKey,
            ));
            final composer = SizeChangedLayoutNotifier(
                key: _composerViewportKey,
                child: _ComposerCard(
                  state: state,
                  allowLocalDictation: ref.watch(coachLocalDictationProvider),
                  controller: _messageController,
                  failureReadMarkerKey: _failureReadMarkerKey,
                  onChanged: ref.read(coachControllerProvider.notifier).updateDraft,
                  onSend: _send,
                  onCancel: ref.read(coachControllerProvider.notifier).cancelAnalysis,
                  onProviderChanged: () => ref.read(coachControllerProvider.notifier).load(),
                ),
            );
            final compactHeight = constraints.maxHeight <
                MediaQuery.textScalerOf(context).scale(240);
            final scroll = SingleChildScrollView(
              key: const Key('coach-chat-scroll'),
              controller: _chatScrollController,
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.sm),
              child: compactHeight
                  ? Column(children: [timeline, const SizedBox(height: AppSpacing.sm), composer])
                  : timeline,
            );
            // At very small heights keep all controls reachable in this same
            // chat viewport rather than adding another page/composer scroller.
            if (compactHeight) return scroll;
            return Column(children: [
              Expanded(child: scroll),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.sm),
                child: composer,
              ),
            ]);
          })),
        )),
      ],
      ),
      children: const [],
    );
    if (state.isLoading) _historyPositioned = false;
    if (!_historyPositioned && !state.isLoading && state.historyError == null) {
      _historyPositioned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && history.isNotEmpty && _chatScrollController.hasClients) {
          _chatScrollController.jumpTo(_chatScrollController.position.maxScrollExtent);
          _scheduleReadCheck();
        }
      });
    }
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
    final sending = ref.read(coachControllerProvider.notifier).send();
    _revealMessage(_pendingMessageKey);
    final sent = await sending;
    if (sent && mounted) _revealMessage(_latestResponseKey);
  }

  void _revealMessage(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = key.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
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
    final viewport = notice.status == CoachTurnNoticeStatus.failed && scrollable == null
        ? _composerViewportKey.currentContext?.findRenderObject()
        : scrollable?.context.findRenderObject();
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
        child: Row(children: [
          SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('Loading Coach …')),
        ]),
      );
    }
    if (capability == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Coach availability error',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            _ErrorText(coachErrorMessage(state.capabilityError)),
          ],
        ),
      );
    }
    final ready = capability.canRespond;
    final demo = capability.reasonCode == 'local_demo';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!ready || state.isRateLimited) ...[
            Row(
              children: [
                const Icon(AppIcons.cloudOffOutlined),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    state.isRateLimited
                        ? 'Daily question limit reached'
                        : 'Coach unavailable',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (demo || capability.provider == CoachProviderName.fake ||
              capability.provider == CoachProviderName.localCodexOauth)
            Text(_availabilitySummary(capability)),
          if (state.capabilityError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ErrorText(
              'Coach availability may be out of date. '
              '${coachErrorMessage(state.capabilityError)}',
            ),
          ],
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

class _ComposerCard extends StatefulWidget {
  const _ComposerCard({
    required this.state,
    this.allowLocalDictation = false,
    required this.controller,
    required this.failureReadMarkerKey,
    required this.onChanged,
    required this.onSend,
    required this.onCancel,
    required this.onProviderChanged,
  });

  final CoachState state;
  final bool allowLocalDictation;
  final TextEditingController controller;
  final GlobalKey failureReadMarkerKey;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final VoidCallback onProviderChanged;

  @override
  State<_ComposerCard> createState() => _ComposerCardState();
}

class _ComposerCardState extends State<_ComposerCard> {
  bool _dictating = false;
  CoachState get state => widget.state;
  TextEditingController get controller => widget.controller;
  GlobalKey get failureReadMarkerKey => widget.failureReadMarkerKey;
  ValueChanged<String> get onChanged => widget.onChanged;
  VoidCallback get onSend => widget.onSend;
  VoidCallback get onCancel => widget.onCancel;

  void _submitDraft() {
    if (state.canSend && !_dictating) onSend();
  }

  KeyEventResult _onComposerKey(FocusNode node, KeyEvent event) {
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter ||
        (controller.value.composing.isValid &&
            !controller.value.composing.isCollapsed)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        if (state.isLoading || state.isSending || state.isDeletingHistory) {
          return KeyEventResult.handled;
        }
        final selection = controller.selection;
        final start = selection.isValid ? selection.start : controller.text.length;
        final end = selection.isValid ? selection.end : start;
        final text = controller.text.replaceRange(start, end, '\n');
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: start + 1),
        );
        onChanged(text);
      } else {
        _submitDraft();
      }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final available = state.capabilities?.canRespond == true ||
        state.exactRetryMessage != null;
    final countColor = state.draftCodepoints > coachMessageCodepoints
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoachDictationButton(
              enabled: (available || widget.allowLocalDictation) &&
                  !state.isLoading && !state.isSending && !state.isDeletingHistory,
              canSendDirect: state.capabilities?.canRespond == true &&
                  !state.isRateLimited && !state.isLoading && !state.isSending &&
                  !state.isDeletingHistory && state.busyRetrySeconds == 0,
              onBusyChanged: (value) {
                if (mounted) setState(() => _dictating = value);
              },
              onText: (text, sendNow) {
                final previous = controller.text.trimRight();
                final combined = previous.isEmpty ? text : '$previous $text';
                if (combined.runes.length > coachMessageCodepoints) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('The question is too long. Shorten it and dictate again.'),
                  ));
                  return;
                }
                controller.text = combined;
                controller.selection = TextSelection.collapsed(offset: combined.length);
                onChanged(combined);
                if (sendNow) onSend();
              },
              idleBuilder: (microphone) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Focus(
                  onKeyEvent: _onComposerKey,
                  child: TextField(
            key: const Key('coach-message-field'),
            controller: controller,
            enabled: (available || widget.allowLocalDictation) &&
                !state.isLoading &&
                !state.isSending &&
                !state.isDeletingHistory,
            minLines: 1,
            maxLines: 5,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _submitDraft(),
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: 'Message Coach',
              filled: false,
              isDense: true,
              contentPadding: const EdgeInsets.all(AppSpacing.sm),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorText: state.draftCodepoints > coachMessageCodepoints
                  ? 'Keep the question within 2,000 characters.'
                  : null,
            ),
          )),
                Row(children: [
                Expanded(child: Tooltip(
                  message: 'Choose Coach',
                  child: TextButton.icon(
                  key: const Key('coach-model-button'),
                  onPressed: state.isLoading || state.isSending ||
                      state.isDeletingHistory || state.busyRetrySeconds > 0
                      ? null : () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          showDragHandle: true,
                          builder: (_) => _CoachOptionsSheet(
                            onChanged: widget.onProviderChanged,
                          ),
                        ),
                  icon: const Icon(AppIcons.tuneOutlined),
                  label: Text(switch (state.capabilities?.provider) {
                    CoachProviderName.operatorCodexPilot => 'Standard',
                    CoachProviderName.openai => 'OpenAI',
                    CoachProviderName.gemini => 'Gemini',
                    CoachProviderName.localCodexOauth => 'Local Coach',
                    CoachProviderName.fake => 'Test Coach',
                    _ => 'Choose Coach',
                  }),
                  style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                ))),
                microphone,
                if (state.isSending)
                  IconButton.outlined(
                    key: const Key('coach-cancel-button'),
                    tooltip: state.isCancelling ? 'Cancelling …' : 'Cancel analysis',
                    onPressed: state.isCancelling ? null : onCancel,
                    icon: const Icon(AppIcons.close),
                  )
                else
                  IconButton.filled(
                    key: const Key('coach-send-button'),
                    tooltip: state.canRetryExact ? 'Retry unchanged' : 'Send',
                    onPressed: state.canSend && !_dictating ? onSend : null,
                    icon: Icon(state.canRetryExact
                        ? AppIcons.refreshOutlined : AppIcons.sendOutlined),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (!_dictating && state.draftCodepoints > 0)
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${state.draftCodepoints}/$coachMessageCodepoints',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: countColor),
            ),
          ),
          if (state.sendError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ErrorText(coachErrorMessage(state.sendError)),
            if (state.busyRetrySeconds > 0)
              Padding(
                key: const ValueKey('coach-busy-countdown'),
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Manual retry available in ${state.busyRetrySeconds} s.',
                ),
              ),
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

        ],
      ),
    );
  }
}

class _CoachOptionsSheet extends ConsumerWidget {
  const _CoachOptionsSheet({required this.onChanged});

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(coachControllerProvider);
    final capability = state.capabilities;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(top: false, child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Choose Coach', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          CoachProviderSettingsCard(
            compact: true,
            directSelection: true,
            onSelected: (provider) {
              if (provider == CoachProviderName.operatorCodexPilot) {
                Navigator.of(context).pop();
              }
            },
            enabled: !state.isLoading && !state.isSending &&
                !state.isDeletingHistory && state.busyRetrySeconds == 0,
            onChanged: onChanged,
            availabilityDetails: capability == null
                ? coachErrorMessage(state.capabilityError)
                : 'Status: ${_humanize(capability.state.code)}\n'
                  'Reason: ${_humanize(capability.reasonCode)}\n'
                  'Model: ${capability.modelRequested ?? 'Not applicable'}\n'
                  'Service tier: ${_humanize(capability.serviceTier)}',
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(alignment: Alignment.centerRight, child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          )),
        ],
      ),
      )),
    );
  }
}

class _ChatTimeline extends StatelessWidget {
  const _ChatTimeline({
    required this.state,
    required this.turns,
    required this.onDelete,
    required this.latestResponseKey,
    required this.readMarkerKey,
    required this.pendingMessageKey,
  });

  final CoachState state;
  final List<CoachHistoryTurn> turns;
  final VoidCallback onDelete;
  final GlobalKey latestResponseKey;
  final GlobalKey readMarkerKey;
  final GlobalKey pendingMessageKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('coach-chat-timeline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (turns.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('coach-delete-conversation'),
              onPressed: state.isLoading || state.isDeletingHistory ||
                      state.isSending ? null : onDelete,
              icon: state.isDeletingHistory
                  ? const SizedBox.square(dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(AppIcons.deleteOutline),
              label: const Text('Delete conversation'),
            ),
          ),
        if (state.historyError != null)
          _ErrorText(coachErrorMessage(state.historyError)),
        if (state.historyActionError != null)
          _ErrorText(coachErrorMessage(state.historyActionError)),
        if (turns.isEmpty && !state.isSending && !state.isLoading &&
            state.historyError == null) ...[
          Container(
            key: const Key('coach-empty-chat'),
            constraints: const BoxConstraints(minHeight: 180),
            padding: const EdgeInsets.all(AppSpacing.xl),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ask your coach anything',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'For example: What patterns do you notice in my week?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
        for (final turn in turns)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Semantics(
              key: turn.requestId == state.latestResponse?.requestId
                  ? latestResponseKey : ValueKey('coach-turn-${turn.requestId}'),
              container: true,
              liveRegion: turn.requestId == state.latestResponse?.requestId,
              child: _ConversationTurnCard(
                title: DateFormat('MMM d, HH:mm').format(turn.createdAt.toLocal()),
                message: turn.message,
                response: turn.response,
                readMarkerKey: turn.requestId == state.latestResponse?.requestId
                    ? readMarkerKey : null,
              ),
            ),
          ),
        if (state.isSending) ...[
          _UserMessage(message: state.draft.trim()),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            liveRegion: true,
            child: AppCard(
              key: pendingMessageKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Coach', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    key: const Key('coach-activity'),
                    children: [
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(
                        state.activityMessage ?? 'Working with personal data …',
                      )),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _UserMessage extends StatelessWidget {
  const _UserMessage({required this.message, this.timestamp});
  final String message;
  final String? timestamp;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: FractionallySizedBox(
      widthFactor: 0.9,
      child: AppSurface(
        variant: AppSurfaceVariant.raised,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(message),
            if (timestamp != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(timestamp!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ConversationTurnCard extends StatelessWidget {
  const _ConversationTurnCard({
    required this.title,
    required this.message,
    required this.response,
    this.readMarkerKey,
  });

  final String title;
  final String message;
  final CoachResponse response;
  final GlobalKey? readMarkerKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _UserMessage(message: message, timestamp: title),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Coach', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(response.reply),
              const SizedBox(height: AppSpacing.md),
              Text('Uncertainty', style: Theme.of(context).textTheme.labelLarge),
              Text('${_humanize(response.uncertainty.level)} · '
                  '${response.uncertainty.reason}'),
              if (readMarkerKey != null)
                ExcludeSemantics(
                  child: SizedBox(key: readMarkerKey, height: 1,
                      width: double.infinity),
                ),
              const SizedBox(height: AppSpacing.sm),
              _AnalysisDetails(response: response),
            ],
          ),
        ),
      ],
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
            (value) =>
                Align(alignment: Alignment.centerLeft, child: Text('• $value')),
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
            'Answered: ${DateFormat('MMM d, HH:mm').format(provenance.generatedAt.toLocal())}',
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

String _coverageText(CoachEvidence evidence, {required bool legacy}) {
  if (legacy) {
    final available = evidence.availableRecordCount ?? evidence.recordCount;
    return '${evidence.recordCount} of $available ${_recordLabel(available)} '
        'selected for this older response';
  }
  return '${evidence.recordCount} ${_recordLabel(evidence.recordCount)} '
      'in snapshot${_period(evidence)}';
}

String _snapshotText(CoachProvenance provenance, {required bool legacy}) {
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
