import 'package:flutter/material.dart';

import 'package:my_life_graph/core/constants/app_radii.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../composition/projection_refresh_providers.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import '../../domain/quick_check_in.dart';
import 'package:my_life_graph/composition/quick_check_in_providers.dart';
import '../widgets/daily_capture_controls.dart';

class MorningCalibrationPage extends ConsumerStatefulWidget {
  const MorningCalibrationPage({super.key});

  @override
  ConsumerState<MorningCalibrationPage> createState() =>
      _MorningCalibrationPageState();
}

class _MorningCalibrationPageState
    extends ConsumerState<MorningCalibrationPage> {
  late MorningCalibrationDraft _draft;
  var _stepIndex = 0;
  var _isLoading = true;
  var _loadedSavedCapture = false;
  var _safeCaptureLoaded = false;
  var _eveningPlanUnavailable = false;
  var _continueWithoutEveningPlan = false;
  var _isSaving = false;
  String? _loadError;
  String? _saveError;

  static const _steps = <_MorningStep>[
    _MorningStep(
      eyebrow: 'MORNING · SLEEP',
      title: 'How did you sleep?',
      subtitle: 'Estimate when sleep started and when you woke.',
      kind: _MorningStepKind.sleep,
    ),
    _MorningStep(
      eyebrow: 'MORNING · CHECK-IN',
      title: 'How are you starting today?',
      subtitle:
          'Add sleep quality and current energy. Evening context stays untouched.',
      kind: _MorningStepKind.checkIn,
    ),
  ];

  @override
  void initState() {
    super.initState();
    final capturedAt = ref.read(currentInstantProvider)();
    _draft = MorningCalibrationDraft.empty(
      capturedAt,
      entryDate: ref.read(profileLocalDateSourceProvider).dateKeyAt(capturedAt),
    );
    Future<void>.microtask(_loadToday);
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
      canContinue: _canUseCurrentStep,
      isLastStep: _stepIndex == _steps.length - 1,
      isLoading: _isLoading,
      isSaving: _isSaving,
      saveLabel: 'Save morning check-in',
      statusMessage: _loadedSavedCapture
          ? 'Today\'s morning check-in is loaded. Saving updates only these morning answers.'
          : null,
      errorMessage: _saveError,
      loadErrorMessage: _loadError ??
          (_eveningPlanUnavailable && !_continueWithoutEveningPlan
              ? 'The previous Evening sleep plan could not be loaded. Retry, or explicitly continue without that plan.'
              : null),
      onRetryLoad: _loadToday,
      secondaryLoadActionLabel:
          _eveningPlanUnavailable && !_continueWithoutEveningPlan
              ? 'Continue without previous Evening plan'
              : null,
      onSecondaryLoadAction: _eveningPlanUnavailable
          ? () => setState(() => _continueWithoutEveningPlan = true)
          : null,
      onClose: () =>
          context.canPop() ? context.pop() : context.go(AppRoutes.quickAction),
      onBack: _previousStep,
      onNext: _nextStep,
      child: _buildStep(step.kind),
    );
  }

  Widget _buildStep(_MorningStepKind kind) {
    return switch (kind) {
      _MorningStepKind.sleep => _buildSleepStep(),
      _MorningStepKind.checkIn => _buildCheckInStep(),
    };
  }

  Widget _buildSleepStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CaptureInfoDisclosure(
          heading: 'Estimated sleep duration',
          description:
              'These are your own estimates, not objectively measured sleep.',
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            SizedBox(
              width: 260,
              child: CaptureClockControl(
                label: 'Estimated sleep start',
                semanticLabel: 'estimated sleep start',
                value: _draft.estimatedSleepStartedAt == null
                    ? null
                    : dailyCaptureClock(
                        _draft.estimatedSleepStartedAt!,
                      ),
                quickValues: const ['22:00', '23:00', '00:00'],
                onChanged: _setEstimatedSleepStart,
              ),
            ),
            SizedBox(
              width: 260,
              child: CaptureClockControl(
                label: 'Wake time',
                semanticLabel: 'estimated wake time',
                value: _draft.wokeAt == null
                    ? null
                    : dailyCaptureClock(_draft.wokeAt!),
                fallback: TimeOfDay.fromDateTime(DateTime.now()),
                quickValues: const ['05:30', '07:00', '08:00'],
                onChanged: _setWakeTime,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadii.xl),
          ),
          child: Text(
            _draft.estimatedSleepMinutes == null
                ? '—'
                : formatCaptureMinutes(_draft.estimatedSleepMinutes!),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        CaptureInfoDisclosure(
          heading: 'Sleep target used for this night',
          description: _draft.sourceEveningCaptureId == null
              ? 'No saved Evening sleep plan was available. Confirm the target you used.'
              : 'Loaded from the latest saved Evening plan. You can correct it for this night.',
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

  Widget _buildCheckInStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CaptureInfoDisclosure(
          heading: 'Estimated sleep quality',
          description:
              'How restorative did your sleep feel, independently of how long you slept?',
        ),
        const SizedBox(height: AppSpacing.md),
        CaptureRatingControl(
          value: _draft.sleepQuality,
          semanticPrefix: 'morning sleep quality',
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(sleepQuality: value),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Current energy',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        CaptureRatingControl(
          value: _draft.energy,
          semanticPrefix: 'morning energy',
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(energy: value),
          ),
        ),
        Text(
          'This check-in records how today starts. It does not create or change a plan.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  bool get _canUseCurrentStep =>
      !_isLoading &&
      _safeCaptureLoaded &&
      (!_eveningPlanUnavailable || _continueWithoutEveningPlan) &&
      _canContinue;

  bool get _canContinue => switch (_steps[_stepIndex].kind) {
        _MorningStepKind.sleep => _hasValidSleepDetails,
        _MorningStepKind.checkIn => _draft.isComplete,
      };

  bool get _hasValidSleepDetails {
    final start = _draft.estimatedSleepStartedAt;
    final wake = _draft.wokeAt;
    final minutes = _draft.estimatedSleepMinutes;
    final target = _draft.sleepTargetMinutes;
    if (start == null || wake == null || minutes == null || target == null) {
      return false;
    }
    final duration = wake.difference(start);
    return duration.inSeconds == minutes * 60 &&
        minutes > 0 &&
        minutes <= 16 * 60 &&
        target >= 300 &&
        target <= 720 &&
        target % 15 == 0;
  }

  void _previousStep() {
    if (_stepIndex > 0) {
      setState(() => _stepIndex--);
    }
  }

  Future<void> _nextStep() async {
    if (!_canUseCurrentStep) {
      return;
    }
    if (_stepIndex < _steps.length - 1) {
      setState(() => _stepIndex++);
      return;
    }
    await _save();
  }

  void _setEstimatedSleepStart(String value) {
    _applySleepClocks(
      start: value,
      wake: _draft.wokeAt == null
          ? dailyCaptureClock(DateTime.now())
          : dailyCaptureClock(_draft.wokeAt!),
    );
  }

  void _setWakeTime(String value) {
    final start = _draft.estimatedSleepStartedAt;
    if (start == null) {
      setState(() {
        _draft = _draft.copyWith(
          wokeAt: _clockOnEntryDate(value),
          estimatedSleepMinutes: null,
          sleepHours: null,
        );
      });
      return;
    }
    _applySleepClocks(start: dailyCaptureClock(start), wake: value);
  }

  void _applySleepClocks({
    required String start,
    required String wake,
  }) {
    final interval = estimatedSleepIntervalForLocalClocks(
      entryDate: _draft.entryDate,
      estimatedSleepStartedAt: start,
      wokeAt: wake,
    );
    setState(() {
      _draft = _draft.withSleepInterval(
        estimatedSleepStartedAt: interval.estimatedSleepStartedAt,
        wokeAt: interval.wokeAt,
      );
    });
  }

  DateTime _clockOnEntryDate(String value) {
    final interval = estimatedSleepIntervalForLocalClocks(
      entryDate: _draft.entryDate,
      estimatedSleepStartedAt: '00:00',
      wokeAt: value,
    );
    return interval.wokeAt;
  }

  Future<void> _save() async {
    if (_isSaving ||
        _stepIndex != _steps.length - 1 ||
        !_safeCaptureLoaded ||
        _eveningPlanUnavailable && !_continueWithoutEveningPlan ||
        !_draft.isComplete) {
      return;
    }
    final draft = _draft.normalized();
    setState(() {
      _draft = draft;
      _isSaving = true;
      _saveError = null;
    });
    try {
      final store = ref.read(quickCheckInStoreProvider);
      await store.saveMorning(draft);
      await ref.read(projectionRefreshCoordinatorProvider).dailyCaptureChanged(
            targetDate: draft.entryDate,
            refreshDailySnapshot:
                store.target == QuickCheckInSaveTarget.supabase,
          );
      if (!mounted) {
        return;
      }
      _showMessage(
        store.target == QuickCheckInSaveTarget.guest
            ? 'Morning check-in saved on this device.'
            : 'Morning check-in saved.',
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
    if (_isLoading && _safeCaptureLoaded) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
      _eveningPlanUnavailable = false;
      _continueWithoutEveningPlan = false;
    });
    try {
      final store = ref.read(quickCheckInStoreProvider);
      final entry = await store.loadToday(
        ref.read(profileLocalDateSourceProvider).today(),
      );
      _safeCaptureLoaded = true;
      EveningShutdownDraft? sleepPlan;
      try {
        sleepPlan = await store.loadLatestEvening();
      } catch (_) {
        _eveningPlanUnavailable = true;
      }
      final saved = entry?.morning;
      if (mounted) {
        var next = (saved ?? _draft).forEditing(sleepPlan: sleepPlan).copyWith(
              capturedAt: saved == null ? null : _draft.capturedAt,
            );
        if (next.wokeAt == null) {
          next = next.copyWith(
            wokeAt: _clockOnEntryDate(dailyCaptureClock(DateTime.now())),
          );
        }
        if (next.estimatedSleepStartedAt == null &&
            sleepPlan?.plannedSleepTime != null) {
          final interval = estimatedSleepIntervalForLocalClocks(
            entryDate: next.entryDate,
            estimatedSleepStartedAt: sleepPlan!.plannedSleepTime!,
            wokeAt: dailyCaptureClock(next.wokeAt!),
          );
          next = next.withSleepInterval(
            estimatedSleepStartedAt: interval.estimatedSleepStartedAt,
            wokeAt: interval.wokeAt,
          );
        }
        setState(() {
          _draft = next;
          _loadedSavedCapture = saved != null;
          _safeCaptureLoaded = true;
          _loadError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _safeCaptureLoaded = false;
          _loadError =
              'Today\'s saved capture could not be loaded. Saving is blocked because its current branch version is unknown. Your draft is still here.';
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

enum _MorningStepKind {
  sleep,
  checkIn,
}

class _MorningStep {
  const _MorningStep({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.kind,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final _MorningStepKind kind;
}
