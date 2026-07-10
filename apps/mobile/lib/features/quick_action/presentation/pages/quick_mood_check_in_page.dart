import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../snapshots/presentation/providers/snapshot_providers.dart';
import '../../domain/quick_check_in.dart';
import '../providers/quick_check_in_providers.dart';

class QuickMoodCheckInPage extends ConsumerStatefulWidget {
  const QuickMoodCheckInPage({super.key});

  @override
  ConsumerState<QuickMoodCheckInPage> createState() =>
      _QuickMoodCheckInPageState();
}

class _QuickMoodCheckInPageState extends ConsumerState<QuickMoodCheckInPage> {
  final TextEditingController _notesController = TextEditingController();
  late QuickCheckInDraft _draft;
  int _stepIndex = 0;
  bool _isLoadingDraft = true;
  bool _loadedSavedDraft = false;
  bool _isSaving = false;
  String? _loadError;
  String? _saveError;

  static const _steps = [
    _QuickStepSpec(
      label: 'MOOD',
      title: 'How are you feeling?',
      subtitle: 'Rate your current mood from heavy to great.',
      unit: '',
      kind: _QuickStepKind.rating,
    ),
    _QuickStepSpec(
      label: 'ENERGY',
      title: 'How much energy do you have?',
      subtitle: 'This helps today\'s plan reflect your available capacity.',
      unit: '',
      kind: _QuickStepKind.rating,
    ),
    _QuickStepSpec(
      label: 'SLEEP',
      title: 'Last night\'s sleep',
      subtitle: 'Rough hours are enough for now.',
      unit: 'h',
      kind: _QuickStepKind.sleep,
    ),
    _QuickStepSpec(
      label: 'STRESS',
      title: 'How stressed are you?',
      subtitle: 'Use this as a quick pressure check.',
      unit: '',
      kind: _QuickStepKind.rating,
    ),
    _QuickStepSpec(
      label: 'OPTIONAL CONTEXT',
      title: 'Anything else?',
      subtitle: 'Add optional context for today. It stays with this check-in.',
      unit: '',
      kind: _QuickStepKind.notes,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _draft = QuickCheckInDraft.empty(DateTime.now());
    Future<void>.microtask(_loadToday);
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_stepIndex];
    final progress = (_stepIndex + 1) / _steps.length;

    return Scaffold(
      backgroundColor: const Color(0xFF030809),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 900;
            final ultraCompact = constraints.maxHeight < 760;
            final outerPadding = compact ? AppSpacing.sm : AppSpacing.md;

            return SingleChildScrollView(
              padding: EdgeInsets.all(outerPadding),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - outerPadding * 2,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _QuickCheckInShell(
                      progress: progress,
                      step: step,
                      canGoBack: _stepIndex > 0,
                      canContinue: _canContinue,
                      isLastStep: _stepIndex == _steps.length - 1,
                      isLoadingDraft: _isLoadingDraft,
                      isSaving: _isSaving,
                      statusMessage: _loadedSavedDraft
                          ? 'Today\'s saved check-in is loaded. Saving updates it.'
                          : _loadError,
                      errorMessage: _saveError,
                      compact: compact,
                      ultraCompact: ultraCompact,
                      onClose: () => context.go(AppRoutes.quickAction),
                      onBack: _previousStep,
                      onNext: _nextStep,
                      child: _isLoadingDraft
                          ? const Padding(
                              padding: EdgeInsets.all(AppSpacing.xl),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : _buildStepContent(
                              step,
                              compact: compact,
                              ultraCompact: ultraCompact,
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStepContent(
    _QuickStepSpec step, {
    required bool compact,
    required bool ultraCompact,
  }) {
    return switch (step.kind) {
      _QuickStepKind.rating => _RatingStep(
          value: _currentRating,
          unit: step.unit,
          helperText: _helperTextForStep(step),
          semanticLabel: step.label.toLowerCase(),
          compact: compact,
          ultraCompact: ultraCompact,
          onChanged: _setCurrentRating,
        ),
      _QuickStepKind.sleep => _SleepStep(
          value: _draft.sleepHours,
          compact: compact,
          ultraCompact: ultraCompact,
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(sleepHours: value),
          ),
        ),
      _QuickStepKind.notes => _NotesStep(
          controller: _notesController,
          compact: compact,
          ultraCompact: ultraCompact,
        ),
    };
  }

  int? get _currentRating {
    return switch (_stepIndex) {
      0 => _draft.mood,
      1 => _draft.energy,
      3 => _draft.stress,
      _ => null,
    };
  }

  void _setCurrentRating(int value) {
    setState(() {
      switch (_stepIndex) {
        case 0:
          _draft = _draft.copyWith(mood: value);
        case 1:
          _draft = _draft.copyWith(energy: value);
        case 3:
          _draft = _draft.copyWith(stress: value);
      }
    });
  }

  String _helperTextForStep(_QuickStepSpec step) {
    if (step.label == 'MOOD') {
      final mood = _draft.mood;
      return mood == null
          ? 'Choose today\'s mood before continuing.'
          : '${quickCheckInMoodLabel(mood)} will be saved as today\'s mood signal.';
    }
    if (step.label == 'ENERGY') {
      final energy = _draft.energy;
      return energy == null
          ? 'Choose today\'s energy before continuing.'
          : '${_energyLabel(energy)} energy will be saved for today.';
    }
    final stress = _draft.stress;
    return stress == null
        ? 'Choose today\'s stress before continuing.'
        : '${_stressLabel(stress)} stress will be saved for today.';
  }

  String _energyLabel(int value) {
    if (value >= 8) {
      return 'High';
    }
    if (value >= 5) {
      return 'Steady';
    }
    return 'Low';
  }

  String _stressLabel(int value) {
    if (value >= 8) {
      return 'High';
    }
    if (value >= 5) {
      return 'Moderate';
    }
    return 'Low';
  }

  void _previousStep() {
    if (_stepIndex == 0) {
      return;
    }
    setState(() => _stepIndex--);
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
    if (_isSaving || !_draft.isComplete) {
      return;
    }

    final draft = _draft.copyWith(contextNote: _notesController.text);
    setState(() {
      _draft = draft;
      _isSaving = true;
      _saveError = null;
    });
    try {
      final store = ref.read(quickCheckInStoreProvider);
      await store.save(draft);
      if (store.target == QuickCheckInSaveTarget.supabase) {
        await ref
            .read(snapshotRefreshServiceProvider)
            .refreshDailyAfterUserSignal();
      }
      ref.invalidate(latestQuickCheckInProvider);
      ref.invalidate(dashboardSnapshotProvider);
      if (mounted) {
        _showMessage(
          store.target == QuickCheckInSaveTarget.guest
              ? 'Check-in saved locally.'
              : 'Check-in saved.',
        );
        context.go(AppRoutes.dashboard);
      }
    } catch (error) {
      if (mounted) {
        final message = error is QuickCheckInUnavailableException
            ? error.message
            : 'Could not save. Your choices are still here. Try again.';
        setState(() => _saveError = message);
        _showMessage(message);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  bool get _canContinue {
    if (_isLoadingDraft) {
      return false;
    }
    return switch (_stepIndex) {
      0 => _draft.mood != null,
      1 => _draft.energy != null,
      2 => _draft.sleepHours != null,
      3 => _draft.stress != null,
      _ => true,
    };
  }

  Future<void> _loadToday() async {
    try {
      final saved = await ref
          .read(quickCheckInStoreProvider)
          .loadToday(_draft.capturedAt);
      if (saved != null && mounted) {
        setState(() {
          _draft = _draft.copyWith(
            mood: saved.mood,
            energy: saved.energy,
            sleepHours: saved.sleepHours,
            stress: saved.stress,
            contextNote: saved.contextNote,
          );
          _notesController.text = saved.contextNote;
          _loadedSavedDraft = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadError =
              'Today\'s saved check-in could not be loaded. New choices can still be saved.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingDraft = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _QuickCheckInShell extends StatelessWidget {
  const _QuickCheckInShell({
    required this.progress,
    required this.step,
    required this.child,
    required this.canGoBack,
    required this.canContinue,
    required this.isLastStep,
    required this.isLoadingDraft,
    required this.isSaving,
    required this.statusMessage,
    required this.errorMessage,
    required this.compact,
    required this.ultraCompact,
    required this.onClose,
    required this.onBack,
    required this.onNext,
  });

  final double progress;
  final _QuickStepSpec step;
  final Widget child;
  final bool canGoBack;
  final bool canContinue;
  final bool isLastStep;
  final bool isLoadingDraft;
  final bool isSaving;
  final String? statusMessage;
  final String? errorMessage;
  final bool compact;
  final bool ultraCompact;
  final VoidCallback onClose;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final headerPadding = EdgeInsets.fromLTRB(
      compact ? AppSpacing.md : AppSpacing.lg,
      compact ? AppSpacing.md : AppSpacing.lg,
      compact ? AppSpacing.md : AppSpacing.lg,
      compact ? AppSpacing.sm : AppSpacing.md,
    );
    final bodyPadding = EdgeInsets.all(
      ultraCompact ? AppSpacing.sm : (compact ? AppSpacing.md : AppSpacing.lg),
    );
    final footerPadding =
        EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF102025),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFF294048), width: 2),
        boxShadow: [
          BoxShadow(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            blurRadius: 36,
            spreadRadius: -16,
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: headerPadding,
            child: Column(
              children: [
                Container(
                  width: compact ? 52 : 64,
                  height: compact ? 6 : 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A323C),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                SizedBox(height: compact ? AppSpacing.md : AppSpacing.xl),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: compact ? 8 : 10,
                    backgroundColor: const Color(0xFF2A323C),
                  ),
                ),
                SizedBox(height: compact ? AppSpacing.md : AppSpacing.xl),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.label,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: compact ? 12 : null,
                                  letterSpacing: compact ? 4 : 5,
                                ),
                          ),
                          SizedBox(
                            height: compact ? AppSpacing.sm : AppSpacing.md,
                          ),
                          Text(
                            step.title,
                            style: Theme.of(context)
                                .textTheme
                                .headlineLarge
                                ?.copyWith(
                                  fontSize:
                                      ultraCompact ? 25 : (compact ? 29 : 34),
                                  height: 1.08,
                                ),
                          ),
                          SizedBox(
                            height: compact ? AppSpacing.sm : AppSpacing.md,
                          ),
                          Text(
                            step.subtitle,
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: const Color(0xFFA8B5BE),
                                      fontSize: compact ? 14 : null,
                                      height: 1.35,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: onClose,
                      icon: Icon(Icons.close, size: compact ? 28 : 34),
                    ),
                  ],
                ),
                if (statusMessage != null) ...[
                  SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
                  _InlineStatusMessage(
                    message: statusMessage!,
                    isError: false,
                  ),
                ],
                if (errorMessage != null) ...[
                  SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
                  _InlineStatusMessage(
                    message: errorMessage!,
                    isError: true,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF294048)),
          Padding(
            padding: bodyPadding,
            child: child,
          ),
          const Divider(height: 1, color: Color(0xFF294048)),
          Padding(
            padding: footerPadding,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canGoBack ? onBack : null,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        vertical: compact ? AppSpacing.md : AppSpacing.lg,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isSaving || isLoadingDraft || !canContinue
                        ? null
                        : onNext,
                    icon: isSaving || isLoadingDraft
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isLastStep
                                ? Icons.send_outlined
                                : Icons.arrow_forward,
                          ),
                    label: Text(
                      isSaving
                          ? 'Saving...'
                          : isLoadingDraft
                              ? 'Loading...'
                              : (isLastStep ? 'Save' : 'Next'),
                    ),
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        vertical: compact ? AppSpacing.md : AppSpacing.lg,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingStep extends StatelessWidget {
  const _RatingStep({
    required this.value,
    required this.unit,
    required this.helperText,
    required this.semanticLabel,
    required this.compact,
    required this.ultraCompact,
    required this.onChanged,
  });

  final int? value;
  final String unit;
  final String helperText;
  final String semanticLabel;
  final bool compact;
  final bool ultraCompact;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: constraints.maxWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CurrentRatingCard(
                  value: value == null ? 'Not set' : '$value$unit',
                  compact: compact,
                  ultraCompact: ultraCompact,
                ),
                SizedBox(height: ultraCompact ? AppSpacing.xs : AppSpacing.sm),
                Slider(
                  value: (value ?? 5).toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  semanticFormatterCallback: (next) =>
                      '$semanticLabel ${next.round()} of 10',
                  onChanged: (next) => onChanged(next.round()),
                ),
                SizedBox(height: ultraCompact ? AppSpacing.xs : AppSpacing.xs),
                GridView.count(
                  crossAxisCount: 5,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing:
                      ultraCompact ? AppSpacing.xs : AppSpacing.sm,
                  mainAxisSpacing: ultraCompact ? AppSpacing.xs : AppSpacing.sm,
                  childAspectRatio: compact ? 1.75 : 1.55,
                  children: List.generate(10, (index) {
                    final rating = index + 1;
                    return _RatingButton(
                      rating: rating,
                      isSelected: rating == value,
                      semanticLabel: '$semanticLabel $rating of 10',
                      onTap: () => onChanged(rating),
                    );
                  }),
                ),
                SizedBox(height: ultraCompact ? AppSpacing.xs : AppSpacing.sm),
                Container(
                  width: double.infinity,
                  padding:
                      EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text.rich(
                    TextSpan(
                      text: helperText.split(' ').first,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                      children: [
                        TextSpan(
                          text: helperText.substring(helperText.indexOf(' ')),
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: const Color(0xFFA8B5BE),
                                    fontSize: compact ? 14 : null,
                                  ),
                        ),
                      ],
                    ),
                    maxLines: compact ? 2 : null,
                    overflow:
                        compact ? TextOverflow.ellipsis : TextOverflow.clip,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SleepStep extends StatelessWidget {
  const _SleepStep({
    required this.value,
    required this.compact,
    required this.ultraCompact,
    required this.onChanged,
  });

  final double? value;
  final bool compact;
  final bool ultraCompact;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CurrentRatingCard(
          value: value == null ? 'Not set' : '${_formatHours(value!)} h',
          compact: compact,
          ultraCompact: ultraCompact,
        ),
        SizedBox(height: compact ? AppSpacing.md : AppSpacing.xl),
        Semantics(
          label: 'Sleep hours',
          value: value == null ? 'Not set' : _formatHours(value!),
          child: Slider(
            value: value ?? 7,
            min: 0,
            max: 12,
            divisions: 24,
            semanticFormatterCallback: (next) => '${_formatHours(next)} hours',
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: const [4.0, 5.5, 7.0, 8.5, 10.0].map((hours) {
            final label = '${_formatHoursStatic(hours)} h';
            return SizedBox(
              width: 72,
              height: 44,
              child: OutlinedButton(
                onPressed: () => onChanged(hours),
                child: Text(label),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _formatHours(double hours) {
    return _formatHoursStatic(hours);
  }

  static String _formatHoursStatic(double hours) =>
      hours == hours.roundToDouble()
          ? hours.toInt().toString()
          : hours.toStringAsFixed(1);
}

class _NotesStep extends StatelessWidget {
  const _NotesStep({
    required this.controller,
    required this.compact,
    required this.ultraCompact,
  });

  final TextEditingController controller;
  final bool compact;
  final bool ultraCompact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What affected today?',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: compact ? 17 : null,
              ),
        ),
        SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
        SizedBox(
          height: ultraCompact ? 180 : (compact ? 220 : 300),
          child: TextField(
            controller: controller,
            expands: true,
            minLines: null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              labelText: 'Context note (optional)',
              hintText:
                  'I felt distracted after lunch, but the morning class went well...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(color: Color(0xFF303B47)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CurrentRatingCard extends StatelessWidget {
  const _CurrentRatingCard({
    required this.value,
    required this.compact,
    required this.ultraCompact,
  });

  final String value;
  final bool compact;
  final bool ultraCompact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: ultraCompact
            ? AppSpacing.md
            : (compact ? AppSpacing.lg : AppSpacing.xl),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF242D34),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Text(
            'Current rating',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFFA8B5BE),
                ),
          ),
          SizedBox(height: compact ? AppSpacing.xs : AppSpacing.md),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontSize: ultraCompact ? 46 : (compact ? 58 : 72),
                  height: 1,
                ),
          ),
        ],
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.rating,
    required this.isSelected,
    required this.semanticLabel,
    required this.onTap,
  });

  final int rating;
  final bool isSelected;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : const Color(0xFF0C1218),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : const Color(0xFF303B47),
                width: 1.5,
              ),
            ),
            child: Text(
              '$rating',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isSelected ? Colors.black : const Color(0xFFA8B5BE),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineStatusMessage extends StatelessWidget {
  const _InlineStatusMessage({
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isError ? Icons.error_outline : Icons.check_circle_outline,
          size: 18,
          color: color,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

enum _QuickStepKind { rating, sleep, notes }

class _QuickStepSpec {
  const _QuickStepSpec({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.unit,
    required this.kind,
  });

  final String label;
  final String title;
  final String subtitle;
  final String unit;
  final _QuickStepKind kind;
}
