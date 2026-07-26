import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../focus/domain/focus_session.dart';
import '../../../focus/presentation/widgets/focus_reflection_sheet.dart';
import '../../../snapshots/presentation/providers/snapshot_providers.dart';
import '../../domain/quick_check_in.dart';
import '../providers/quick_check_in_providers.dart';
import '../widgets/daily_capture_controls.dart';

class QuickMoodCheckInPage extends ConsumerStatefulWidget {
  const QuickMoodCheckInPage({super.key});

  @override
  ConsumerState<QuickMoodCheckInPage> createState() =>
      _QuickMoodCheckInPageState();
}

class _QuickMoodCheckInPageState extends ConsumerState<QuickMoodCheckInPage> {
  final _tomorrowPriorityController = TextEditingController();
  final _reflectionController = TextEditingController();
  final _blockerController = TextEditingController();

  late EveningShutdownDraft _draft;
  var _stepIndex = 0;
  var _isLoading = true;
  var _loadedSavedCapture = false;
  var _isSaving = false;
  String? _loadError;
  String? _saveError;
  List<FocusSession> _todayFocusSessions = const [];
  Map<String, FocusReflection> _todayFocusReflections = const {};

  static const _steps = <_EveningStep>[
    _EveningStep(
      eyebrow: 'EVENING · CHECK-IN',
      title: 'Close today in under a minute',
      subtitle: 'Three quick ratings are enough for today\'s state.',
      kind: _EveningStepKind.checkIn,
    ),
    _EveningStep(
      eyebrow: 'EVENING · SLEEP PLAN',
      title: 'When do you plan to sleep?',
      subtitle:
          'Set tonight\'s intended start and your personal duration target.',
      kind: _EveningStepKind.sleepPlan,
    ),
    _EveningStep(
      eyebrow: 'EVENING · CONTEXT',
      title: 'What should tomorrow know?',
      subtitle: 'Add pressure context or optional notes only when useful.',
      kind: _EveningStepKind.context,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _draft = EveningShutdownDraft.empty(DateTime.now());
    Future<void>.microtask(_loadToday);
  }

  @override
  void dispose() {
    _tomorrowPriorityController.dispose();
    _reflectionController.dispose();
    _blockerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_stepIndex];
    return CaptureFlowScaffold(
      eyebrow: step.eyebrow,
      title: step.title,
      subtitle: step.subtitle,
      progress: (_stepIndex + 1) / _steps.length,
      canGoBack: _stepIndex > 0,
      canContinue: _canContinue,
      isLastStep: _stepIndex == _steps.length - 1,
      isLoading: _isLoading,
      isSaving: _isSaving,
      saveLabel: 'Save evening check-in',
      statusMessage: _loadedSavedCapture
          ? 'Today\'s evening check-in is loaded. Saving updates only these evening answers.'
          : _loadError,
      errorMessage: _saveError,
      onClose: () => context.go(AppRoutes.quickAction),
      onBack: _previousStep,
      onNext: _nextStep,
      child: _buildStep(step.kind),
    );
  }

  Widget _buildStep(_EveningStepKind kind) {
    return switch (kind) {
      _EveningStepKind.checkIn => _buildCheckInStep(),
      _EveningStepKind.sleepPlan => _buildSleepPlanStep(),
      _EveningStepKind.context => _buildContextStep(),
    };
  }

  Widget _buildCheckInStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Mood', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        CaptureRatingControl(
          value: _draft.mood,
          semanticPrefix: 'evening mood',
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(mood: value),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Energy left', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        CaptureRatingControl(
          value: _draft.energy,
          semanticPrefix: 'evening energy',
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(energy: value),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Stress', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        CaptureRatingControl(
          value: _draft.stress,
          semanticPrefix: 'evening stress',
          onChanged: (value) => setState(() {
            _draft = _draft.copyWith(
              stress: value,
              stressSource: value < 5 ? null : _draft.stressSource,
              stressControllability:
                  value < 5 ? null : _draft.stressControllability,
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSleepPlanStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Planned sleep time',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'This is your intention for tonight, not an automatic restriction.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        CaptureClockControl(
          label: 'Planned sleep start',
          semanticLabel: 'planned sleep time',
          value: _draft.plannedSleepTime,
          quickValues: const ['22:00', '23:00', '00:00'],
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(plannedSleepTime: value),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Sleep duration target',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Eight hours is shown first. It becomes your current sleep plan only when you save.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        CaptureSleepTargetControl(
          value: _draft.sleepTargetMinutes,
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(sleepTargetMinutes: value),
          ),
        ),
      ],
    );
  }

  Widget _buildContextStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_draft.requiresStressContext) ...[
          Text(
            'What drove the pressure?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          CaptureChoiceControl<StressSource>(
            value: _draft.stressSource,
            choices: StressSource.values
                .map(
                  (value) => CaptureChoice(
                    value: value,
                    label: _stressSourceLabel(value),
                    semanticLabel: 'stress source ${value.code}',
                    description: _stressSourceDescription(value),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(
              () => _draft = _draft.copyWith(stressSource: value),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'How much could you influence it?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          CaptureChoiceControl<StressControllability>(
            value: _draft.stressControllability,
            choices: StressControllability.values
                .map(
                  (value) => CaptureChoice(
                    value: value,
                    label: _stressControllabilityLabel(value),
                    semanticLabel: 'stress influence ${value.code}',
                  ),
                )
                .toList(),
            onChanged: (value) => setState(
              () => _draft = _draft.copyWith(stressControllability: value),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _tomorrowPriorityController,
          maxLength: 160,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Possible priority tomorrow (optional)',
            hintText: 'For example: Finish the first project draft',
            helperText: 'Context only; this does not create a task.',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _reflectionController,
          maxLength: 500,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Reflection (optional)',
            hintText: 'A short observation, if useful',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _blockerController,
          maxLength: 240,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Specific blocker (optional)',
            hintText: 'Leave blank if there was no specific blocker',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Optional blanks stay absent. They do not become tasks, memories, or recommendations.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_todayFocusSessions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              key: const ValueKey('evening-focus-reflections'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Today\'s Focus sessions'),
              subtitle: Text(
                '${_todayFocusReflections.length} rated · '
                '${_todayFocusSessions.length - _todayFocusReflections.length} open',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openTodayFocusReflections,
            ),
          ),
        ],
      ],
    );
  }

  bool get _canContinue {
    if (_isLoading) {
      return false;
    }
    return switch (_steps[_stepIndex].kind) {
      _EveningStepKind.checkIn =>
        _draft.mood != null && _draft.energy != null && _draft.stress != null,
      _EveningStepKind.sleepPlan =>
        _draft.plannedSleepTime != null && _draft.sleepTargetMinutes != null,
      _EveningStepKind.context => _draft.hasConsistentStressContext,
    };
  }

  void _previousStep() {
    if (_stepIndex > 0) {
      setState(() => _stepIndex--);
    }
  }

  Future<void> _nextStep() async {
    if (!_canContinue) {
      return;
    }
    if (_stepIndex < _steps.length - 1) {
      setState(() => _stepIndex++);
      return;
    }
    await _save();
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }
    final draft = _draft.copyWith(
      tomorrowPriority: _tomorrowPriorityController.text,
      reflectionNote: _reflectionController.text,
      specificBlocker: _blockerController.text,
    );
    setState(() {
      _draft = draft;
      _isSaving = true;
      _saveError = null;
    });
    try {
      final store = ref.read(quickCheckInStoreProvider);
      await store.saveEvening(draft);
      if (store.target == QuickCheckInSaveTarget.supabase) {
        await ref
            .read(snapshotRefreshServiceProvider)
            .refreshDailyAfterUserSignal(targetDate: draft.entryDate);
      }
      ref.invalidate(latestQuickCheckInProvider);
      ref.invalidate(dashboardSnapshotProvider);
      if (!mounted) {
        return;
      }
      _showMessage(
        store.target == QuickCheckInSaveTarget.guest
            ? 'Evening check-in saved on this device.'
            : 'Evening check-in saved.',
      );
      context.go(AppRoutes.dashboard);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error is QuickCheckInUnavailableException
          ? error.message
          : 'Could not save. Your answers are still here. Try again.';
      setState(() => _saveError = message);
      _showMessage(message);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _loadToday() async {
    try {
      final store = ref.read(quickCheckInStoreProvider);
      final results = await Future.wait<Object?>([
        store.loadToday(DateTime.now()),
        store.loadLatestEvening(),
        _loadTodayFocusReflections(),
      ]);
      final entry = results.first as DailyCaptureEntry?;
      final sleepPlan = results[1] as EveningShutdownDraft?;
      final focusData = results[2] as _TodayFocusReflectionData?;
      final saved = entry?.evening;
      if (mounted) {
        final source = saved?.forEditing() ?? _draft;
        final next = source.copyWith(
          capturedAt: saved == null ? null : _draft.capturedAt,
          plannedSleepTime:
              source.plannedSleepTime ?? sleepPlan?.plannedSleepTime,
          sleepTargetMinutes: source.sleepTargetMinutes ??
              sleepPlan?.sleepTargetMinutes ??
              EveningShutdownDraft.defaultSleepTargetMinutes,
        );
        setState(() {
          _draft = next;
          if (saved != null) {
            _tomorrowPriorityController.text = saved.tomorrowPriority;
            _reflectionController.text = saved.reflectionNote;
            _blockerController.text = saved.specificBlocker;
            _loadedSavedCapture = true;
          }
          _todayFocusSessions = focusData?.sessions ?? const [];
          _todayFocusReflections = focusData?.reflections ?? const {};
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadError =
              'Today\'s saved capture could not be loaded. Saving will retry the server read before it changes anything.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<_TodayFocusReflectionData?> _loadTodayFocusReflections() async {
    try {
      final source = ref.read(eveningFocusReflectionSourceProvider);
      if (source == null) return null;
      final recent = await source.fetchRecentSessions(limit: 50);
      final today = dailyCaptureEntryDate(DateTime.now());
      final sessions = recent
          .where(
            (session) =>
                !session.isActive && session.snapshotEntryDate == today,
          )
          .toList(growable: false);
      final reflections = await source.fetchReflectionsForSessions(sessions);
      return _TodayFocusReflectionData(
        sessions: sessions,
        reflections: reflections,
      );
    } catch (_) {
      // The optional Focus row must not block Daily Capture.
      return null;
    }
  }

  Future<void> _openTodayFocusReflections() async {
    if (_todayFocusSessions.isEmpty) return;
    final selected = _todayFocusSessions.length == 1
        ? _todayFocusSessions.single
        : await showModalBottomSheet<FocusSession>(
            context: context,
            showDragHandle: true,
            builder: (sheetContext) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text(
                    'Today\'s Focus sessions',
                    style: Theme.of(sheetContext).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final session in _todayFocusSessions)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        session.status == FocusSessionStatus.completed
                            ? Icons.check_circle_outline
                            : Icons.cancel_outlined,
                      ),
                      title: Text(session.label ?? 'Focus session'),
                      subtitle: Text(
                        '${session.actualMinutes ?? 0} min · '
                        '${_todayFocusReflections.containsKey(session.id) ? 'rated' : 'open'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(sheetContext).pop(session),
                    ),
                ],
              ),
            ),
          );
    if (selected == null || !mounted) return;
    await _openFocusReflection(selected);
  }

  Future<void> _openFocusReflection(FocusSession session) async {
    final source = ref.read(eveningFocusReflectionSourceProvider);
    if (source == null || !mounted) return;
    final existing = _todayFocusReflections[session.id];
    final outcome = await showFocusReflectionSheet(
      context: context,
      session: session,
      existing: existing,
      onSave: (draft) async {
        final saved = await source.saveReflection(
          session: session,
          draft: draft,
          existing: existing,
        );
        if (mounted) {
          setState(() {
            _todayFocusReflections = {
              ..._todayFocusReflections,
              session.id: saved,
            };
          });
        }
        return saved;
      },
      onDelete: (reflection) async {
        await source.deleteReflection(reflection);
        if (mounted) {
          setState(() {
            _todayFocusReflections = {..._todayFocusReflections}
              ..remove(session.id);
          });
        }
      },
    );
    if (!mounted) return;
    if (outcome == FocusReflectionSheetOutcome.saved) {
      _showMessage('Focus reflection saved.');
    } else if (outcome == FocusReflectionSheetOutcome.deleted) {
      _showMessage('Focus reflection deleted.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _TodayFocusReflectionData {
  const _TodayFocusReflectionData({
    required this.sessions,
    required this.reflections,
  });

  final List<FocusSession> sessions;
  final Map<String, FocusReflection> reflections;
}

String _stressSourceLabel(StressSource value) => switch (value) {
      StressSource.workload => 'Workload',
      StressSource.avoidablePressure => 'Avoidable pressure',
      StressSource.privateEmotional => 'Private or emotional',
      StressSource.physicalRecovery => 'Physical recovery',
      StressSource.externalEnvironment => 'External environment',
    };

String _stressSourceDescription(StressSource value) => switch (value) {
      StressSource.workload => 'Deadlines, volume, meetings, or responsibility',
      StressSource.avoidablePressure =>
        'Late starts, unclear next actions, or planning debt',
      StressSource.privateEmotional =>
        'Personal events, conflict, grief, family, or worry',
      StressSource.physicalRecovery =>
        'Illness, pain, poor sleep, exhaustion, or recovery',
      StressSource.externalEnvironment =>
        'Travel, noise, interruptions, or external constraints',
    };

String _stressControllabilityLabel(StressControllability value) =>
    switch (value) {
      StressControllability.hardlyControllable => 'Little influence',
      StressControllability.partlyControllable => 'Some influence',
      StressControllability.mostlyControllable => 'Mostly within my influence',
    };

enum _EveningStepKind {
  checkIn,
  sleepPlan,
  context,
}

class _EveningStep {
  const _EveningStep({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.kind,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final _EveningStepKind kind;
}
