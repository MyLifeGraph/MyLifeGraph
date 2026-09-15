import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../composition/projection_refresh_providers.dart';
import '../../../../composition/capture_draft_providers.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/time/profile_timezone.dart';
import '../../../../core/navigation/app_routes.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import '../../domain/quick_check_in.dart';
import '../../domain/capture_draft_proposal.dart';
import 'package:my_life_graph/composition/quick_check_in_providers.dart';
import '../widgets/daily_capture_controls.dart';
import '../../../../composition/skillset_providers.dart';
import '../../domain/skillset_signals.dart';
import '../widgets/optional_skillset_controls.dart';

class MorningCalibrationPage extends ConsumerStatefulWidget {
  const MorningCalibrationPage({super.key, this.proposal});

  final CaptureDraftProposal? proposal;

  @override
  ConsumerState<MorningCalibrationPage> createState() =>
      _MorningCalibrationPageState();
}

class _MorningCalibrationPageState
    extends ConsumerState<MorningCalibrationPage> {
  late MorningCalibrationDraft _draft;
  var _stepIndex = 0;
  var _isLoading = true;
  var _safeCaptureLoaded = false;
  var _eveningPlanUnavailable = false;
  var _continueWithoutEveningPlan = false;
  var _isSaving = false;
  var _proposalApplied = false;
  (String, DateTime)? _voiceBaseline;
  var _revisingSavedCapture = false;
  String? _loadError;
  String? _saveError;

  static const _steps = <_MorningStep>[
    _MorningStep(
      eyebrow: 'MORNING · SLEEP',
      title: 'How did you sleep?',
      kind: _MorningStepKind.sleep,
    ),
    _MorningStep(
      eyebrow: 'MORNING · CHECK-IN',
      title: 'How are you starting today?',
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
    final proposalOwnerMatches =
        widget.proposal == null ||
        ref.watch(captureDraftOwnerProvider) == widget.proposal!.ownerId;
    final step = _steps[_stepIndex];
    return CaptureFlowScaffold(
      eyebrow: step.eyebrow,
      title: step.title,
      subtitle: widget.proposal == null
          ? null
          : _revisingSavedCapture
          ? 'Review suggestions. Saving updates today\'s Morning check-in.'
          : 'Review suggestions and fill any gaps before saving.',
      progress: (_stepIndex + 1) / _steps.length,
      canGoBack: _stepIndex > 0,
      canContinue: _canUseCurrentStep,
      isLastStep: _stepIndex == _steps.length - 1,
      isLoading: _isLoading,
      isSaving: _isSaving,
      saveLabel: 'Save',
      errorMessage: _saveError,
      loadErrorMessage:
          (!_proposalMatchesContext
              ? 'This voice draft belongs to a different account, day or timezone. Start a new check-in.'
              : _loadError) ??
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
      child: proposalOwnerMatches
          ? _buildStep(step.kind)
          : const SizedBox.shrink(),
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
        const SizedBox(height: AppSpacing.sm),
        CaptureClockControl(
          label: 'Sleep start',
          quickAdjust: true,
          semanticLabel: 'estimated sleep start',
          value: _draft.estimatedSleepStartedAt == null
              ? null
              : _clock(_draft.estimatedSleepStartedAt!),
          onChanged: _setEstimatedSleepStart,
        ),
        const SizedBox(height: AppSpacing.sm),
        CaptureClockControl(
          label: 'Wake time',
          quickAdjust: true,
          semanticLabel: 'estimated wake time',
          value: _draft.wokeAt == null ? null : _clock(_draft.wokeAt!),
          fallback: TimeOfDay.fromDateTime(DateTime.now()),
          onChanged: _setWakeTime,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                'Duration',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              _draft.estimatedSleepMinutes == null
                  ? '—'
                  : formatCaptureMinutes(_draft.estimatedSleepMinutes!),
              key: const ValueKey('morning-sleep-duration'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
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
    final allowExtras =
        ref.watch(optionalSkillsetCaptureProvider) ||
        widget.proposal?.fields.containsKey('motivation') == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CaptureInfoDisclosure(
          heading: 'Sleep quality',
          description:
              'How restorative did your sleep feel, independently of how long you slept?',
        ),
        const SizedBox(height: AppSpacing.sm),
        CaptureRatingControl(
          value: _draft.sleepQuality,
          semanticPrefix: 'morning sleep quality',
          onChanged: (value) =>
              setState(() => _draft = _draft.copyWith(sleepQuality: value)),
        ),
        const SizedBox(height: AppSpacing.lg),
        CaptureRatingControl(
          label: 'Current energy',
          value: _draft.energy,
          semanticPrefix: 'morning energy',
          onChanged: (value) =>
              setState(() => _draft = _draft.copyWith(energy: value)),
        ),
        if (allowExtras)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: OptionalSkillsetChoice(
              label: 'Study motivation (optional)',
              choices: const ['Low', 'Medium', 'High'],
              value: _draft.skillset?.values['motivation'],
              onChanged: (value) => setState(
                () => _draft = _draft.copyWith(
                  skillset: (_draft.skillset ?? const SkillsetSignals({}))
                      .withValue('motivation', value),
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool get _canUseCurrentStep =>
      !_isLoading &&
      _proposalMatchesContext &&
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
          ? _clock(DateTime.now())
          : _clock(_draft.wokeAt!),
    );
  }

  void _setWakeTime(String value) {
    final start = _draft.estimatedSleepStartedAt;
    if (start == null) {
      try {
        setState(() {
          _draft = _draft.copyWith(
            wokeAt: _clockOnEntryDate(value),
            estimatedSleepMinutes: null,
            sleepHours: null,
          );
        });
      } on ProfileTimezoneException {
        setState(
          () => _saveError =
              'That time is ambiguous or unavailable in your timezone. Choose another time.',
        );
      }
      return;
    }
    _applySleepClocks(start: _clock(start), wake: value);
  }

  void _applySleepClocks({required String start, required String wake}) {
    try {
      final interval =
          widget.proposal?.sleepInterval(start: start, wake: wake) ??
          estimatedSleepIntervalForLocalClocks(
            entryDate: _draft.entryDate,
            estimatedSleepStartedAt: start,
            wokeAt: wake,
          );
      setState(() {
        _saveError = null;
        _draft = _draft.withSleepInterval(
          estimatedSleepStartedAt: interval.estimatedSleepStartedAt,
          wokeAt: interval.wokeAt,
        );
      });
    } on ProfileTimezoneException {
      setState(
        () => _saveError =
            'That time is ambiguous or unavailable in your timezone. Choose another time.',
      );
    }
  }

  DateTime _clockOnEntryDate(String value) {
    if (widget.proposal != null) {
      return widget.proposal!.clockOnEntryDate(value);
    }
    final interval = estimatedSleepIntervalForLocalClocks(
      entryDate: _draft.entryDate,
      estimatedSleepStartedAt: '00:00',
      wokeAt: value,
    );
    return interval.wokeAt;
  }

  String _clock(DateTime instant) =>
      widget.proposal?.clockForInstant(instant) ?? dailyCaptureClock(instant);

  Future<void> _save() async {
    if (_isSaving ||
        _stepIndex != _steps.length - 1 ||
        !_safeCaptureLoaded ||
        !_proposalMatchesContext ||
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
      await ref
          .read(projectionRefreshCoordinatorProvider)
          .dailyCaptureChanged(
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
          ? 'Synced check-in saving is unavailable. Your answers are still here; try again when your account connection is available.'
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
    if (!_proposalMatchesContext) {
      setState(() {
        _safeCaptureLoaded = false;
        _isLoading = false;
        _loadError =
            'This voice draft belongs to a different account, day or timezone. Start a new check-in.';
      });
      return;
    }
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
      if (mounted && _proposalMatchesContext) {
        final baseline = saved == null
            ? null
            : (saved.captureId, saved.capturedAt);
        if (_proposalApplied && baseline != _voiceBaseline) {
          setState(() {
            _safeCaptureLoaded = false;
            _loadError =
                'Today\'s check-in changed. Start a new voice check-in to review the latest values.';
          });
          return;
        }
        var next = (_proposalApplied ? _draft : saved ?? _draft)
            .forEditing(sleepPlan: sleepPlan)
            .copyWith(capturedAt: saved == null ? null : _draft.capturedAt);
        if (widget.proposal == null && next.wokeAt == null) {
          next = next.copyWith(
            wokeAt: _clockOnEntryDate(_clock(DateTime.now())),
          );
        }
        if (widget.proposal == null &&
            next.estimatedSleepStartedAt == null &&
            sleepPlan?.plannedSleepTime != null) {
          final interval = estimatedSleepIntervalForLocalClocks(
            entryDate: next.entryDate,
            estimatedSleepStartedAt: sleepPlan!.plannedSleepTime!,
            wokeAt: _clock(next.wokeAt!),
          );
          next = next.withSleepInterval(
            estimatedSleepStartedAt: interval.estimatedSleepStartedAt,
            wokeAt: interval.wokeAt,
          );
        }
        if (!_proposalApplied && widget.proposal != null) {
          next = widget.proposal!.applyToMorning(next, allowSkillset: true);
          _voiceBaseline = baseline;
          _proposalApplied = true;
        }
        setState(() {
          _draft = next;
          _revisingSavedCapture = saved != null;
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

  bool get _proposalMatchesContext {
    final proposal = widget.proposal;
    if (proposal == null) return true;
    final dates = ref.read(profileLocalDateSourceProvider);
    return proposal.matches(
          ownerId: ref.read(captureDraftOwnerProvider),
          entryDate: dates.todayKey(),
          timezone: dates.timezoneName,
          branch: 'morning',
        ) &&
        proposal.entryDate == _draft.entryDate;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

enum _MorningStepKind { sleep, checkIn }

class _MorningStep {
  const _MorningStep({
    required this.eyebrow,
    required this.title,
    required this.kind,
  });

  final String eyebrow;
  final String title;
  final _MorningStepKind kind;
}
