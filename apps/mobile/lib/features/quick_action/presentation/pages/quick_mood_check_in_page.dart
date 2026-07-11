import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
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

  static const _steps = <_EveningStep>[
    _EveningStep(
      eyebrow: 'EVENING · MOOD',
      title: 'How did today feel?',
      subtitle: 'Choose the mood value that best matches the day.',
      kind: _EveningStepKind.mood,
    ),
    _EveningStep(
      eyebrow: 'EVENING · ENERGY',
      title: 'How much energy was left?',
      subtitle: 'Use your end-of-day energy, not tomorrow\'s estimate.',
      kind: _EveningStepKind.energy,
    ),
    _EveningStep(
      eyebrow: 'EVENING · STRESS',
      title: 'How intense was the stress?',
      subtitle: 'The number stays separate from its source and control.',
      kind: _EveningStepKind.stress,
    ),
    _EveningStep(
      eyebrow: 'STRESS SOURCE',
      title: 'What drove the pressure?',
      subtitle: 'Choose the main source. Different causes need different care.',
      kind: _EveningStepKind.stressSource,
    ),
    _EveningStep(
      eyebrow: 'CONTROLLABILITY',
      title: 'How much could you influence it?',
      subtitle: 'Low control is context, not a personal failure.',
      kind: _EveningStepKind.stressControllability,
    ),
    _EveningStep(
      eyebrow: 'FOCUS BAND',
      title: 'How much focused time happened?',
      subtitle:
          'A rough band is enough. It is not converted into fake minutes.',
      kind: _EveningStepKind.focusBand,
    ),
    _EveningStep(
      eyebrow: 'MAIN FRICTION',
      title: 'What got in the way most?',
      subtitle: 'Choose one structured friction signal for today.',
      kind: _EveningStepKind.mainFriction,
    ),
    _EveningStep(
      eyebrow: 'TOMORROW',
      title: 'What is one likely priority?',
      subtitle: 'Name one realistic priority. This does not create a task.',
      kind: _EveningStepKind.tomorrowPriority,
    ),
    _EveningStep(
      eyebrow: 'OPTIONAL DETAIL',
      title: 'Anything worth carrying forward?',
      subtitle: 'Leave every field blank if there is nothing more to add.',
      kind: _EveningStepKind.optionalDetail,
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
      saveLabel: 'Save evening shutdown',
      statusMessage: _loadedSavedCapture
          ? 'Today\'s Evening Shutdown is loaded. Saving replaces only its evening state.'
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
      _EveningStepKind.mood => CaptureRatingControl(
          value: _draft.mood,
          semanticPrefix: 'evening mood',
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(mood: value),
          ),
        ),
      _EveningStepKind.energy => CaptureRatingControl(
          value: _draft.energy,
          semanticPrefix: 'evening energy',
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(energy: value),
          ),
        ),
      _EveningStepKind.stress => CaptureRatingControl(
          value: _draft.stress,
          semanticPrefix: 'evening stress',
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(stress: value),
          ),
        ),
      _EveningStepKind.stressSource => CaptureChoiceControl<StressSource>(
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
      _EveningStepKind.stressControllability =>
        CaptureChoiceControl<StressControllability>(
          value: _draft.stressControllability,
          choices: StressControllability.values
              .map(
                (value) => CaptureChoice(
                  value: value,
                  label: _stressControllabilityLabel(value),
                  semanticLabel: 'stress controllability ${value.code}',
                ),
              )
              .toList(),
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(stressControllability: value),
          ),
        ),
      _EveningStepKind.focusBand => CaptureChoiceControl<FocusBand>(
          value: _draft.focusBand,
          choices: FocusBand.values
              .map(
                (value) => CaptureChoice(
                  value: value,
                  label: _focusBandLabel(value),
                  semanticLabel: 'focus band ${value.code}',
                ),
              )
              .toList(),
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(focusBand: value),
          ),
        ),
      _EveningStepKind.mainFriction => CaptureChoiceControl<MainFriction>(
          value: _draft.mainFriction,
          choices: MainFriction.values
              .map(
                (value) => CaptureChoice(
                  value: value,
                  label: _mainFrictionLabel(value),
                  semanticLabel: 'main friction ${value.code}',
                ),
              )
              .toList(),
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(mainFriction: value),
          ),
        ),
      _EveningStepKind.tomorrowPriority => TextField(
          controller: _tomorrowPriorityController,
          maxLength: 160,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Tomorrow priority',
            hintText: 'For example: Finish the first project draft',
            helperText: 'Saved as capture context only; no task is created.',
          ),
        ),
      _EveningStepKind.optionalDetail => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            const SizedBox(height: AppSpacing.md),
            Semantics(
              button: true,
              selected: _draft.makeTomorrowGentler,
              label: 'make tomorrow gentler',
              child: ExcludeSemantics(
                child: FilterChip(
                  selected: _draft.makeTomorrowGentler,
                  onSelected: (selected) => setState(
                    () => _draft = _draft.copyWith(
                      makeTomorrowGentler: selected,
                    ),
                  ),
                  avatar: const Icon(Icons.spa_outlined),
                  label: const Text('Make tomorrow gentler'),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Optional blanks stay absent. They do not become tasks, memories, or recommendations.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
    };
  }

  bool get _canContinue {
    if (_isLoading) {
      return false;
    }
    return switch (_steps[_stepIndex].kind) {
      _EveningStepKind.mood => _draft.mood != null,
      _EveningStepKind.energy => _draft.energy != null,
      _EveningStepKind.stress => _draft.stress != null,
      _EveningStepKind.stressSource => _draft.stressSource != null,
      _EveningStepKind.stressControllability =>
        _draft.stressControllability != null,
      _EveningStepKind.focusBand => _draft.focusBand != null,
      _EveningStepKind.mainFriction => _draft.mainFriction != null,
      _EveningStepKind.tomorrowPriority =>
        _tomorrowPriorityController.text.trim().isNotEmpty,
      _EveningStepKind.optionalDetail => true,
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
            ? 'Evening Shutdown saved locally.'
            : 'Evening Shutdown saved.',
      );
      context.go(AppRoutes.dashboard);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error is QuickCheckInUnavailableException
          ? error.message
          : 'Could not save. Your exact Evening Shutdown is still here. Try again.';
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
      final entry =
          await ref.read(quickCheckInStoreProvider).loadToday(DateTime.now());
      final saved = entry?.evening;
      if (saved != null && mounted) {
        setState(() {
          _draft = saved.copyWith(capturedAt: _draft.capturedAt);
          _tomorrowPriorityController.text = saved.tomorrowPriority;
          _reflectionController.text = saved.reflectionNote;
          _blockerController.text = saved.specificBlocker;
          _loadedSavedCapture = true;
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
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
      StressControllability.hardlyControllable => 'Hardly controllable',
      StressControllability.partlyControllable => 'Partly controllable',
      StressControllability.mostlyControllable => 'Mostly controllable',
    };

String _focusBandLabel(FocusBand value) => switch (value) {
      FocusBand.none => 'None',
      FocusBand.underThirtyMinutes => 'Under 30 minutes',
      FocusBand.thirtyToSixtyMinutes => '30 to 60 minutes',
      FocusBand.oneToTwoHours => '1 to 2 hours',
      FocusBand.overTwoHours => 'Over 2 hours',
    };

String _mainFrictionLabel(MainFriction value) => switch (value) {
      MainFriction.unclearPriorities => 'Unclear priorities',
      MainFriction.tooMuchToDo => 'Too much to do',
      MainFriction.interruptions => 'Interruptions',
      MainFriction.hardToStart => 'Hard to start',
      MainFriction.lowEnergy => 'Low energy',
      MainFriction.emotionalLoad => 'Emotional load',
      MainFriction.physicalRecovery => 'Physical recovery',
      MainFriction.externalConstraints => 'External constraints',
    };

enum _EveningStepKind {
  mood,
  energy,
  stress,
  stressSource,
  stressControllability,
  focusBand,
  mainFriction,
  tomorrowPriority,
  optionalDetail,
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
