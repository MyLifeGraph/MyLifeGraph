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
      eyebrow: 'MORNING CALIBRATION',
      title: 'Calibrate this morning',
      subtitle:
          'Sleep, current energy, and today\'s shape only. Evening context stays untouched.',
      progress: 1,
      canGoBack: false,
      canContinue: _draft.isComplete,
      isLastStep: true,
      isLoading: _isLoading,
      isSaving: _isSaving,
      saveLabel: 'Save morning calibration',
      statusMessage: _loadedSavedCapture
          ? 'Today\'s Morning Calibration is loaded. Saving replaces only its morning state.'
          : _loadError,
      errorMessage: _saveError,
      onClose: () => context.go(AppRoutes.quickAction),
      onBack: () {},
      onNext: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sleep hours',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Rough half-hour steps are enough.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          CaptureSleepHoursControl(
            value: _draft.sleepHours,
            onChanged: (value) => setState(
              () => _draft = _draft.copyWith(sleepHours: value),
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
            'This calibration records current state only. It does not generate recommendations or create or change a plan.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_isSaving || !_draft.isComplete) {
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
            ? 'Morning Calibration saved locally.'
            : 'Morning Calibration saved.',
      );
      context.go(AppRoutes.dashboard);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error is QuickCheckInUnavailableException
          ? error.message
          : 'Could not save. Your exact Morning Calibration is still here. Try again.';
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
      final saved = entry?.morning;
      if (saved != null && mounted) {
        setState(() {
          _draft = saved.copyWith(capturedAt: _draft.capturedAt);
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
