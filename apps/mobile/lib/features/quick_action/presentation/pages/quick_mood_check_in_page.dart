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
      eyebrow: 'EVENING · CHECK-IN',
      title: 'Close today in under a minute',
      subtitle: 'Three quick ratings are enough for today\'s state.',
      kind: _EveningStepKind.checkIn,
    ),
    _EveningStep(
      eyebrow: 'EVENING · CONTEXT',
      title: 'What should tomorrow know?',
      subtitle:
          'Choose the main friction. Everything else appears only when useful.',
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

  Widget _buildContextStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Main friction',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        CaptureChoiceControl<MainFriction>(
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
        if (_draft.requiresStressContext) ...[
          const SizedBox(height: AppSpacing.lg),
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
        const SizedBox(height: AppSpacing.md),
        Semantics(
          button: true,
          selected: _draft.makeTomorrowGentler,
          label: 'make tomorrow gentler',
          onTap: () => setState(
            () => _draft = _draft.copyWith(
              makeTomorrowGentler: !_draft.makeTomorrowGentler,
            ),
          ),
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
    );
  }

  bool get _canContinue {
    if (_isLoading) {
      return false;
    }
    return switch (_steps[_stepIndex].kind) {
      _EveningStepKind.checkIn =>
        _draft.mood != null && _draft.energy != null && _draft.stress != null,
      _EveningStepKind.context =>
        _draft.mainFriction != null && _draft.hasConsistentStressContext,
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
      StressControllability.hardlyControllable => 'Little influence',
      StressControllability.partlyControllable => 'Some influence',
      StressControllability.mostlyControllable => 'Mostly within my influence',
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
  checkIn,
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
