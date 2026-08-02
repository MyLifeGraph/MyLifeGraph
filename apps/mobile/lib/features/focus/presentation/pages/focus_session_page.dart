import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:my_life_graph/core/constants/app_radii.dart';
import 'package:my_life_graph/core/theme/app_icons.dart';

import '../../../../composition/focus_session_providers.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../application/focus_session_controller.dart';
import '../../domain/focus_session.dart';
import '../../../focus_protection/domain/focus_protection.dart';
import '../widgets/focus_reflection_sheet.dart';

export '../../../../composition/focus_session_providers.dart'
    show
        focusSessionPageDataSourceProvider,
        focusStudySettingsDataSourceProvider;

enum _PreparationChoice { ready, notNeeded }

class FocusSessionPage extends ConsumerStatefulWidget {
  const FocusSessionPage({
    super.key,
    this.initialTargetKind,
    this.initialTargetId,
    this.initialPlannedMinutes,
    this.initialRecoveryMinutes,
    this.initialSourceKind,
    this.initialSourceBlockId,
    this.initialSessionId,
  });

  final FocusTargetKind? initialTargetKind;
  final String? initialTargetId;
  final int? initialPlannedMinutes;
  final int? initialRecoveryMinutes;
  final FocusScheduleSourceKind? initialSourceKind;
  final String? initialSourceBlockId;
  final String? initialSessionId;

  @override
  ConsumerState<FocusSessionPage> createState() => _FocusSessionPageState();
}

class _FocusSessionPageState extends ConsumerState<FocusSessionPage>
    with WidgetsBindingObserver {
  FocusSessionLaunch get _launch => FocusSessionLaunch(
        initialTargetKind: widget.initialTargetKind,
        initialTargetId: widget.initialTargetId,
        initialPlannedMinutes: widget.initialPlannedMinutes,
        initialRecoveryMinutes: widget.initialRecoveryMinutes,
        initialSourceKind: widget.initialSourceKind,
        initialSourceBlockId: widget.initialSourceBlockId,
        initialSessionId: widget.initialSessionId,
      );

  FocusSessionController get _controller =>
      ref.read(focusSessionControllerProvider(_launch).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_load);
  }

  @override
  void didUpdateWidget(covariant FocusSessionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTargetKind == widget.initialTargetKind &&
        oldWidget.initialTargetId == widget.initialTargetId &&
        oldWidget.initialPlannedMinutes == widget.initialPlannedMinutes &&
        oldWidget.initialRecoveryMinutes == widget.initialRecoveryMinutes &&
        oldWidget.initialSourceKind == widget.initialSourceKind &&
        oldWidget.initialSourceBlockId == widget.initialSourceBlockId &&
        oldWidget.initialSessionId == widget.initialSessionId) {
      return;
    }
    Future.microtask(_load);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !ref.read(focusSessionControllerProvider(_launch)).isSaving) {
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(focusSessionControllerProvider(_launch));
    return AppPage(
      title: 'Focus session',
      subtitle: 'A real timed execution block linked to an optional action',
      backFallback: AppRoutes.quickAction,
      actions: [
        IconButton(
          tooltip: 'Refresh focus sessions',
          onPressed: state.isLoading || state.isSaving ? null : _load,
          icon: const Icon(AppIcons.refresh),
        ),
      ],
      children: [
        if (state.isLoading)
          const AppCard(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: CircularProgressIndicator(),
              ),
            ),
          )
        else if (state.loadError != null)
          _FocusLoadErrorCard(
            message: state.loadError!,
            onRetry: _load,
          )
        else if (state.active != null) ...[
          _ActiveFocusCard(
            session: state.active!,
            target: state.targetFor(state.active!),
            now: state.clockNow,
            isSaving: state.isSaving,
            onFinish: _finish,
            onAbandon: _abandon,
          ),
          if (state.protectionStatus?.platformSupported == true)
            _ActiveFocusProtectionCard(
              status: state.protectionStatus!,
              sessionId: state.active!.id,
              isBusy: state.isChangingProtection,
              onEmergencyRelease: _emergencyRelease,
            ),
        ] else if (state.recoveryEndsAt?.isAfter(state.clockNow) == true)
          _RecoveryCard(
            endsAt: state.recoveryEndsAt!,
            now: state.clockNow,
            onSkip: _controller.skipRecovery,
          )
        else ...[
          if (state.scheduledContext == null &&
              state.studySetupStatus == StudySetupLoadStatus.unavailable &&
              !state.continueWithoutStudySetup)
            _StudySetupUnavailableCard(
              onRetry: _controller.retryStudySettings,
              onContinue: _controller.continueWithoutSavedStudySetup,
            ),
          _StartFocusCard(
            plannedMinutes: state.plannedMinutes,
            recoveryMinutes: state.recoveryMinutes,
            suggestion: FocusPreferenceSuggestion.fromSessions(state.recent),
            targets: state.targets,
            selectedTargetValue: state.selectedTargetValue,
            isSaving: state.isSaving,
            startEnabled: state.canStart,
            scheduledContext: state.scheduledContext,
            inlineError: state.startConflictMessage ??
                (state.scheduledContext?.canStart == false
                    ? _focusStartBlockingText(
                        state.scheduledContext!.blockingReason,
                      )
                    : null),
            onDurationChanged: _controller.setPlannedMinutes,
            onCustomDuration: _chooseCustomDuration,
            onTargetChanged: _controller.selectTarget,
            onStart: _start,
          ),
        ],
        if (!state.isLoading && state.loadError == null)
          _FocusHistoryCard(
            sessions: state.recent,
            reflections: state.reflections,
            reflectionDataAvailable: state.reflectionDataAvailable,
            onRate: _openReflection,
          ),
      ],
    );
  }

  Future<void> _load() async {
    final result = await _controller.load();
    final reflection = result.initialReflection;
    if (reflection == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openReflection(reflection));
    });
  }

  Future<void> _chooseCustomDuration() async {
    final state = ref.read(focusSessionControllerProvider(_launch));
    final maximum = state.scheduledContext?.remainingMinutes ?? 240;
    final textController = TextEditingController(
      text: '${state.plannedMinutes}',
    );
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom focus duration'),
        content: TextField(
          key: const ValueKey('custom-focus-duration'),
          controller: textController,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Minutes',
            helperText: 'Between 5 and $maximum minutes',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(textController.text.trim());
              if (value != null && value >= 5 && value <= maximum) {
                Navigator.of(context).pop(value);
              }
            },
            child: const Text('Use duration'),
          ),
        ],
      ),
    );
    textController.dispose();
    if (selected != null && mounted) {
      _controller.setPlannedMinutes(selected);
    }
  }

  Future<void> _start() async {
    final state = ref.read(focusSessionControllerProvider(_launch));
    if (state.isSaving || !state.canStart) return;
    final prepared = await _confirmPreparation();
    if (prepared != true || !mounted) return;
    final result = await _controller.start();
    if (!mounted) return;
    switch (result.outcome) {
      case FocusStartOutcome.started:
        _showMessage('Focus session started.');
        break;
      case FocusStartOutcome.failed:
        final conflictMessage = _focusStartErrorText(result.error!);
        final current = ref.read(focusSessionControllerProvider(_launch));
        if (current.scheduledContext != null && conflictMessage != null) {
          _controller.setStartConflictMessage(conflictMessage);
        } else {
          _showMessage(
            result.error is FocusCommandException
                ? (result.error! as FocusCommandException).message
                : 'Could not start focus session.',
          );
        }
        break;
      case FocusStartOutcome.ignored:
      case FocusStartOutcome.anotherSessionActive:
        break;
    }
  }

  Future<void> _finish() async {
    final result = await _controller.finish(
      onCommitted: (finished, protectionConfirmed) async {
        if (!mounted) return;
        final focusMessage = finished.recoveryMinutes > 0
            ? 'Focus session finished. Recovery started; linked actions were not completed automatically.'
            : 'Focus session finished. Linked tasks and habits were not completed automatically.';
        _showMessage(
          protectionConfirmed
              ? focusMessage
              : '$focusMessage Android cleanup could not be confirmed; local expiry and the next device reconciliation will retry it.',
        );
        await _maybePromptForReflection(finished);
      },
    );
    if (mounted && result.error != null) {
      _showMessage(
        result.error is FocusCommandException
            ? (result.error! as FocusCommandException).message
            : 'Could not finish focus session.',
      );
    }
  }

  Future<bool?> _confirmPreparation() {
    final items = ref
            .read(focusSessionControllerProvider(_launch))
            .studySettings
            ?.preparationItems
            .where((item) => item.active)
            .toList(growable: false) ??
        const <FocusPreparationItem>[];
    if (items.isEmpty) {
      return Future.value(true);
    }
    final choices = <String, _PreparationChoice?>{
      for (final item in items) item.key: null,
    };
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final complete = choices.values.every((choice) => choice != null);
          return AlertDialog(
            title: const Text('Prepare to focus'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'These choices are only for this start. They are not saved or evaluated.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppSpacing.md,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.label,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.xs,
                              children: [
                                ChoiceChip(
                                  label: const Text('Ready'),
                                  selected: choices[item.key] ==
                                      _PreparationChoice.ready,
                                  onSelected: (_) {
                                    setDialogState(() {
                                      choices[item.key] =
                                          _PreparationChoice.ready;
                                    });
                                  },
                                ),
                                ChoiceChip(
                                  label: const Text('Not needed today'),
                                  selected: choices[item.key] ==
                                      _PreparationChoice.notNeeded,
                                  onSelected: (_) {
                                    setDialogState(() {
                                      choices[item.key] =
                                          _PreparationChoice.notNeeded;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                key: const ValueKey('focus-skip-preparation'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Skip remaining and start'),
              ),
              FilledButton(
                key: const ValueKey('focus-preparation-start'),
                onPressed: complete
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: const Text('Start'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _abandon() async {
    final state = ref.read(focusSessionControllerProvider(_launch));
    if (state.active == null || state.isSaving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abandon focus session?'),
        content: const Text(
          'Elapsed time will be kept, but this block will be marked abandoned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep focusing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Abandon session'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await _controller.abandon(
      onCommitted: (abandoned, protectionConfirmed) async {
        if (!mounted) return;
        _showMessage(
          protectionConfirmed
              ? 'Focus session abandoned.'
              : 'Focus session abandoned. Android cleanup could not be confirmed; local expiry and the next device reconciliation will retry it.',
        );
        await _maybePromptForReflection(abandoned);
      },
    );
    if (mounted && result.error != null) {
      _showMessage(
        result.error is FocusCommandException
            ? (result.error! as FocusCommandException).message
            : 'Could not abandon focus session.',
      );
    }
  }

  Future<void> _emergencyRelease() async {
    final state = ref.read(focusSessionControllerProvider(_launch));
    if (state.active == null || state.isChangingProtection) return;
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _EmergencyReleaseDialog(),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    final result = await _controller.emergencyRelease();
    if (!mounted || !result.accepted) return;
    _showMessage(
      result.released
          ? 'Device protection released. This Focus session remains active and will not be protected again.'
          : 'Could not release Android protection. Try again.',
    );
  }

  Future<void> _maybePromptForReflection(FocusSession session) async {
    final state = ref.read(focusSessionControllerProvider(_launch));
    if (!state.reflectionPromptEnabled ||
        !state.reflectionDataAvailable ||
        !mounted) {
      return;
    }
    await _openReflection(session);
  }

  Future<void> _openReflection(FocusSession session) async {
    if (session.isActive || !mounted) return;
    final existing = ref
        .read(focusSessionControllerProvider(_launch))
        .reflections[session.id];
    final outcome = await showFocusReflectionSheet(
      context: context,
      session: session,
      existing: existing,
      onSave: (draft) async {
        return _controller.saveReflection(
          session: session,
          draft: draft,
          existing: existing,
        );
      },
      onDelete: (reflection) async {
        await _controller.deleteReflection(
          session: session,
          reflection: reflection,
        );
      },
    );
    if (!mounted) return;
    switch (outcome) {
      case FocusReflectionSheetOutcome.saved:
        _showMessage('Focus reflection saved.');
        break;
      case FocusReflectionSheetOutcome.deleted:
        _showMessage('Focus reflection deleted.');
        break;
      case FocusReflectionSheetOutcome.skipped:
      case null:
        break;
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _FocusLoadErrorCard extends StatelessWidget {
  const _FocusLoadErrorCard({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'No empty focus state was assumed. Check your connection and '
            'try again.',
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(AppIcons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _StartFocusCard extends StatelessWidget {
  const _StartFocusCard({
    required this.plannedMinutes,
    required this.recoveryMinutes,
    required this.suggestion,
    required this.targets,
    required this.selectedTargetValue,
    required this.isSaving,
    required this.startEnabled,
    required this.scheduledContext,
    required this.inlineError,
    required this.onDurationChanged,
    required this.onCustomDuration,
    required this.onTargetChanged,
    required this.onStart,
  });

  final int plannedMinutes;
  final int recoveryMinutes;
  final FocusPreferenceSuggestion? suggestion;
  final List<FocusTargetOption> targets;
  final String? selectedTargetValue;
  final bool isSaving;
  final bool startEnabled;
  final FocusStartContext? scheduledContext;
  final String? inlineError;
  final ValueChanged<int> onDurationChanged;
  final VoidCallback onCustomDuration;
  final ValueChanged<String?> onTargetChanged;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final maximum = scheduledContext?.remainingMinutes ?? 240;
    final durations = <int>{
      25,
      50,
      90,
      plannedMinutes,
      if (suggestion != null) suggestion!.durationMinutes,
    }.where((minutes) => minutes >= 5 && minutes <= maximum).toList()
      ..sort();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Start a focus block',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Finishing records focused time. It never completes a linked '
            'task or habit automatically.',
          ),
          if (scheduledContext != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Planned '
              '${DateFormat.MMMd().add_Hm().format(scheduledContext!.originalStartsAt.toLocal())}–'
              '${DateFormat.Hm().format(scheduledContext!.originalEndsAt.toLocal())} · '
              '${scheduledContext!.remainingMinutes} min remaining',
              key: const ValueKey('focus-scheduled-origin'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'This session starts now. Its actual timestamps are used for progress and reflection.',
            ),
          ],
          if (recoveryMinutes > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '$plannedMinutes min focus + $recoveryMinutes min recovery',
              key: const ValueKey('focus-rhythm-summary'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SegmentedButton<int>(
            direction: _focusChoiceDirection(context),
            segments: [
              for (final minutes in durations)
                ButtonSegment(
                  value: minutes,
                  label: Text('$minutes min'),
                ),
            ],
            selected: {plannedMinutes},
            onSelectionChanged:
                isSaving ? null : (values) => onDurationChanged(values.single),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: isSaving ? null : onCustomDuration,
              icon: const Icon(AppIcons.tune),
              label: const Text('Custom duration'),
            ),
          ),
          if (suggestion != null && scheduledContext == null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(AppIcons.insightsOutlined, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Your ${suggestion!.evidenceSessions} recent completed sessions cluster around '
                      '${suggestion!.durationMinutes} minutes. '
                      'This is a suggestion, not an automatic setting.',
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          DropdownButtonFormField<String?>(
            key: ValueKey('focus-target-selector-$selectedTargetValue'),
            initialValue: selectedTargetValue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: scheduledContext == null
                  ? 'Linked action optional'
                  : 'Linked planned task',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  'Independent focus block',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ...targets.map(
                (target) => DropdownMenuItem<String?>(
                  value: target.value,
                  child: Text(
                    '${target.kind == FocusTargetKind.task ? 'Task' : 'Habit'}: '
                    '${target.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged:
                isSaving || scheduledContext != null ? null : onTargetChanged,
          ),
          if (scheduledContext != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              recoveryMinutes == 0
                  ? 'No recovery is reserved for this block.'
                  : '$recoveryMinutes min recovery is fixed by the plan.',
              key: const ValueKey('focus-scheduled-recovery'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (inlineError != null) ...[
            const SizedBox(height: AppSpacing.md),
            Semantics(
              liveRegion: true,
              child: Container(
                key: const ValueKey('focus-start-inline-conflict'),
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Text(
                  inlineError!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: isSaving || !startEnabled ? null : onStart,
              icon: isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AppIcons.playArrow),
              label: const Text('Start focus session'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudySetupUnavailableCard extends StatelessWidget {
  const _StudySetupUnavailableCard({
    required this.onRetry,
    required this.onContinue,
  });

  final VoidCallback onRetry;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                AppIcons.warningAmberOutlined,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'Saved Study Setup could not be loaded. Starting a new session is blocked until you retry or explicitly continue without it.',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(AppIcons.refresh),
                label: const Text('Retry Study Setup'),
              ),
              TextButton(
                onPressed: onContinue,
                child: const Text('Continue without saved Study Setup'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveFocusCard extends StatelessWidget {
  const _ActiveFocusCard({
    required this.session,
    required this.target,
    required this.now,
    required this.isSaving,
    required this.onFinish,
    required this.onAbandon,
  });

  final FocusSession session;
  final FocusTargetOption? target;
  final DateTime now;
  final bool isSaving;
  final VoidCallback onFinish;
  final VoidCallback onAbandon;

  @override
  Widget build(BuildContext context) {
    final plannedEnd = session.startedAt.add(
      Duration(minutes: session.plannedMinutes),
    );
    final elapsed = now.isAfter(session.startedAt)
        ? now.difference(session.startedAt)
        : Duration.zero;
    final remaining =
        plannedEnd.isAfter(now) ? plannedEnd.difference(now) : Duration.zero;
    final plannedDuration = Duration(minutes: session.plannedMinutes);
    final progress = elapsed.inMilliseconds / plannedDuration.inMilliseconds;
    final reachedPlan = !plannedEnd.isAfter(now);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                AppIcons.timerOutlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Focus active',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(session.label ?? target?.title ?? 'Independent focus block'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Started ${DateFormat.Hm().format(session.startedAt.toLocal())} · '
            '${session.plannedMinutes} planned minutes'
            '${session.recoveryMinutes > 0 ? ' · ${session.recoveryMinutes} min recovery after completion' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            liveRegion: reachedPlan,
            label: reachedPlan
                ? 'Planned focus time reached'
                : '${_focusTimerText(remaining)} remaining',
            child: Text(
              reachedPlan
                  ? '+${_focusTimerText(now.difference(plannedEnd))}'
                  : _focusTimerText(remaining),
              key: const ValueKey('focus-countdown'),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            reachedPlan
                ? 'Planned time reached'
                : 'Ends at ${DateFormat.Hm().format(plannedEnd.toLocal())}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(value: progress.clamp(0, 1)),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            key: const ValueKey('active-focus-actions'),
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              TextButton(
                onPressed: isSaving ? null : onAbandon,
                child: const Text('Abandon'),
              ),
              FilledButton(
                onPressed: isSaving ? null : onFinish,
                child: const Text(
                  'Finish focus session',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveFocusProtectionCard extends StatelessWidget {
  const _ActiveFocusProtectionCard({
    required this.status,
    required this.sessionId,
    required this.isBusy,
    required this.onEmergencyRelease,
  });

  final FocusProtectionStatus status;
  final String sessionId;
  final bool isBusy;
  final VoidCallback onEmergencyRelease;

  @override
  Widget build(BuildContext context) {
    final lease = status.lease;
    final matchesSession = lease?.sessionId == sessionId;
    final leaseActive = matchesSession && lease?.isActive == true;
    final released = matchesSession &&
        lease?.state == FocusProtectionLeaseState.emergencyReleased;
    final mechanisms = <String>[
      if (matchesSession && status.activeMechanisms.contains('app_blocking'))
        'Selected apps',
      if (matchesSession &&
          status.activeMechanisms.contains('silence_notifications'))
        'Normal notifications',
    ];
    final hasActiveMechanism = mechanisms.isNotEmpty;
    final title = !status.configurationKnown
        ? 'Device protection status unavailable'
        : !status.configuration.enabled
            ? 'Device protection is off'
            : released
                ? 'Device protection released'
                : leaseActive && hasActiveMechanism
                    ? 'Device protection active'
                    : 'Focus continues with partial protection';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                hasActiveMechanism
                    ? AppIcons.lockOutline
                    : AppIcons.warningAmberOutlined,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      mechanisms.isEmpty
                          ? released
                              ? 'The synced Focus session is still active. Reloading will not restart protection for this session.'
                              : 'No Android protection mechanism is currently active.'
                          : 'Active: ${mechanisms.join(' and ')}.',
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (status.warnings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final warning in status.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text('• ${_focusProtectionWarningText(warning)}'),
              ),
          ],
          if (leaseActive) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              key: const ValueKey('focus-protection-emergency-release'),
              onPressed: isBusy ? null : onEmergencyRelease,
              icon: const Icon(AppIcons.lockResetOutlined),
              label: const Text('Emergency release'),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmergencyReleaseDialog extends StatefulWidget {
  const _EmergencyReleaseDialog();

  @override
  State<_EmergencyReleaseDialog> createState() =>
      _EmergencyReleaseDialogState();
}

class _EmergencyReleaseDialogState extends State<_EmergencyReleaseDialog> {
  static const _seconds = 5;
  int _remaining = _seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Release device protection?'),
      content: Text(
        _remaining > 0
            ? 'Wait $_remaining seconds, then confirm. The synced Focus session will keep running.'
            : 'Confirm to stop only this device’s protection. This session will not be protected again after reload.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep protection'),
        ),
        FilledButton(
          key: const ValueKey('confirm-focus-protection-emergency-release'),
          onPressed:
              _remaining <= 0 ? () => Navigator.of(context).pop(true) : null,
          child: Text(
            _remaining > 0 ? 'Confirm in $_remaining' : 'Confirm release',
          ),
        ),
      ],
    );
  }
}

String _focusProtectionWarningText(FocusProtectionWarning warning) {
  return switch (warning) {
    FocusProtectionWarning.accessibilityDisabled =>
      'Selected apps cannot be blocked without Accessibility access.',
    FocusProtectionWarning.notificationPolicyMissing =>
      'Notifications cannot be silenced without Do Not Disturb access.',
    FocusProtectionWarning.dndUnsupported =>
      'Notification silencing requires Android 10 or newer.',
    FocusProtectionWarning.noAppsSelected =>
      'No apps are selected for blocking.',
    FocusProtectionWarning.zenRuleMissingOrOverridden =>
      'Android could not confirm the Focus rule, or the rule was disabled, removed, or overridden.',
    FocusProtectionWarning.nativeFailure =>
      'Android protection status could not be confirmed; the Focus session continues.',
  };
}

String? _focusStartErrorText(Object error) {
  final failure = apiFailureFrom(error);
  if (failure?.isConflict != true) return null;
  final data = failure?.responseData;
  final detail = data is Map ? data['detail'] : null;
  return _focusStartBlockingText(detail is String ? detail : null);
}

String _focusStartBlockingText(String? reason) {
  return switch (reason) {
    'source_fully_credited' =>
      'This planned block has already received all of its focus credit.',
    'source_remaining_too_short' =>
      'Fewer than five planned minutes remain, so another session cannot be started.',
    'active_focus_session' =>
      'Another focus session is already active. Open its timer first.',
    'deadline_plan_block' =>
      'Another preparation block overlaps this focus and recovery time.',
    'planner_task_block' =>
      'Another planned task overlaps this focus and recovery time.',
    'fixed_commitment' =>
      'A fixed commitment overlaps this focus and recovery time.',
    'recurring_commitment' =>
      'A recurring commitment overlaps this focus and recovery time.',
    'calendar_availability_unavailable' =>
      'Calendar busy time is enabled, but its current projection is unavailable.',
    'calendar_busy' =>
      'Imported calendar busy time overlaps this focus and recovery time.',
    'availability_unavailable' =>
      'Saved availability could not be resolved safely for this time.',
    'Scheduled Focus duration exceeds remaining minutes.' =>
      'Choose a duration no longer than the remaining planned time.',
    'focus_request_conflict' =>
      'This start request was already used with different details. Try again.',
    _ => 'This planned session cannot start at the selected duration now.',
  };
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({
    required this.endsAt,
    required this.now,
    required this.onSkip,
  });

  final DateTime endsAt;
  final DateTime now;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final remaining =
        endsAt.isAfter(now) ? endsAt.difference(now) : Duration.zero;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                AppIcons.selfImprovementOutlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Recovery break',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'This local countdown is not a focus session and does not add progress or preparation time.',
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            liveRegion: true,
            label: '${_focusTimerText(remaining)} recovery remaining',
            child: Text(
              _focusTimerText(remaining),
              key: const ValueKey('recovery-countdown'),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Reserved recovery ends at ${DateFormat.Hm().format(endsAt)}',
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('skip-recovery'),
              onPressed: onSkip,
              child: const Text('Skip recovery'),
            ),
          ),
        ],
      ),
    );
  }
}

Axis _focusChoiceDirection(BuildContext context) {
  final scaledBody = MediaQuery.textScalerOf(context).scale(14);
  return MediaQuery.sizeOf(context).width < 420 || scaledBody > 20
      ? Axis.vertical
      : Axis.horizontal;
}

String _focusTimerText(Duration duration) {
  final safeSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = safeSeconds ~/ 3600;
  final minutes = safeSeconds.remainder(3600) ~/ 60;
  final seconds = safeSeconds.remainder(60);
  final minuteText = minutes.toString().padLeft(2, '0');
  final secondText = seconds.toString().padLeft(2, '0');
  return hours > 0
      ? '${hours.toString().padLeft(2, '0')}:$minuteText:$secondText'
      : '$minuteText:$secondText';
}

class _FocusHistoryCard extends StatelessWidget {
  const _FocusHistoryCard({
    required this.sessions,
    required this.reflections,
    required this.reflectionDataAvailable,
    required this.onRate,
  });

  final List<FocusSession> sessions;
  final Map<String, FocusReflection> reflections;
  final bool reflectionDataAvailable;
  final ValueChanged<FocusSession> onRate;

  @override
  Widget build(BuildContext context) {
    final terminal = sessions.where((session) => !session.isActive).take(5);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent focus', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (terminal.isEmpty)
            const Text('No finished sessions yet.')
          else
            ...terminal.map(
              (session) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  session.status == FocusSessionStatus.completed
                      ? AppIcons.checkCircleOutline
                      : AppIcons.cancelOutlined,
                ),
                title: Text(session.label ?? 'Focus session'),
                subtitle: Text(
                  '${session.actualMinutes ?? 0} min · ${session.status.code}',
                ),
                trailing: reflectionDataAvailable
                    ? TextButton(
                        key: ValueKey(
                          'focus-reflection-${session.id}',
                        ),
                        onPressed: () => onRate(session),
                        child: Text(
                          reflections.containsKey(session.id) ? 'Edit' : 'Rate',
                        ),
                      )
                    : const Tooltip(
                        message: 'Reflection history could not be loaded.',
                        child: Icon(AppIcons.syncProblemOutlined),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
