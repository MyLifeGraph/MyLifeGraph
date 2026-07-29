import 'package:flutter/material.dart';

import 'package:my_life_graph/core/constants/app_radii.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../snapshots/presentation/providers/snapshot_providers.dart';
import '../../domain/quick_check_in.dart';
import '../providers/quick_check_in_providers.dart';
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
  var _isLoading = true;
  var _loadedSavedCapture = false;
  var _safeCaptureLoaded = false;
  var _eveningPlanUnavailable = false;
  var _continueWithoutEveningPlan = false;
  var _isSaving = false;
  String? _loadError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _draft = MorningCalibrationDraft.empty(DateTime.now());
    Future<void>.microtask(_loadToday);
  }

  @override
  Widget build(BuildContext context) {
    return CaptureFlowScaffold(
      eyebrow: 'MORNING · CHECK-IN',
      title: 'How are you starting today?',
      subtitle:
          'Estimate when sleep started and when you woke. Evening context stays untouched.',
      progress: 1,
      canGoBack: false,
      canContinue: _safeCaptureLoaded &&
          (!_eveningPlanUnavailable || _continueWithoutEveningPlan) &&
          _draft.isComplete,
      isLastStep: true,
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
      onClose: () => context.go(AppRoutes.quickAction),
      onBack: () {},
      onNext: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Estimated sleep duration',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'These are your own estimates, not objectively measured sleep.',
            style: Theme.of(context).textTheme.bodyMedium,
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
                  ? 'Choose an ordered interval of no more than 16 hours.'
                  : formatCaptureMinutes(_draft.estimatedSleepMinutes!),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Sleep target used for this night',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _draft.sourceEveningCaptureId == null
                ? 'No saved Evening sleep plan was available. Confirm the target you used.'
                : 'Loaded from the latest saved Evening plan. You can correct it for this night.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          CaptureSleepTargetControl(
            value: _draft.sleepTargetMinutes,
            onChanged: (value) => setState(
              () => _draft = _draft.copyWith(sleepTargetMinutes: value),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Estimated sleep quality',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'How restorative did your sleep feel, independently of how long you slept?',
            style: Theme.of(context).textTheme.bodyMedium,
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
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Day shape',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Choose how constrained or flexible today already looks.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          CaptureChoiceControl<DayShape>(
            value: _draft.dayShape,
            choices: DayShape.values
                .map(
                  (value) => CaptureChoice(
                    value: value,
                    label: _dayShapeLabel(value),
                    semanticLabel: 'day shape ${value.code}',
                    description: _dayShapeDescription(value),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(
              () => _draft = _draft.copyWith(dayShape: value),
            ),
          ),
          Text(
            'This check-in records how today starts. It does not create or change a plan.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
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
      final entry = await store.loadToday(DateTime.now());
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

String _dayShapeLabel(DayShape value) => switch (value) {
      DayShape.normal => 'Normal',
      DayShape.constrained => 'Constrained',
      DayShape.flexible => 'Flexible',
    };

String _dayShapeDescription(DayShape value) => switch (value) {
      DayShape.normal => 'A typical amount of structure and room',
      DayShape.constrained => 'Fixed commitments or limited capacity',
      DayShape.flexible => 'More control over timing than usual',
    };
