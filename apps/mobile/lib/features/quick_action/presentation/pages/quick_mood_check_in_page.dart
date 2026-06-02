import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../data/quick_check_in_supabase_data_source.dart';

class QuickMoodCheckInPage extends ConsumerStatefulWidget {
  const QuickMoodCheckInPage({super.key});

  @override
  ConsumerState<QuickMoodCheckInPage> createState() =>
      _QuickMoodCheckInPageState();
}

class _QuickMoodCheckInPageState extends ConsumerState<QuickMoodCheckInPage> {
  final TextEditingController _notesController = TextEditingController();
  int _stepIndex = 0;
  int _mood = 7;
  int _energy = 6;
  double _sleepHours = 7;
  int _stress = 4;
  bool _isSaving = false;

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
      subtitle: 'This helps the coach adjust reminders and workload.',
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
      label: 'COACH NOTES',
      title: 'Anything else?',
      subtitle: 'Add context your future AI coach should remember.',
      unit: '',
      kind: _QuickStepKind.notes,
    ),
  ];

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
                      isLastStep: _stepIndex == _steps.length - 1,
                      isSaving: _isSaving,
                      compact: compact,
                      ultraCompact: ultraCompact,
                      onClose: () => context.go(AppRoutes.quickAction),
                      onBack: _previousStep,
                      onNext: _nextStep,
                      child: _buildStepContent(
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
          compact: compact,
          ultraCompact: ultraCompact,
          onChanged: _setCurrentRating,
        ),
      _QuickStepKind.sleep => _SleepStep(
          value: _sleepHours,
          compact: compact,
          ultraCompact: ultraCompact,
          onChanged: (value) => setState(() => _sleepHours = value),
        ),
      _QuickStepKind.notes => _NotesStep(
          controller: _notesController,
          compact: compact,
          ultraCompact: ultraCompact,
        ),
    };
  }

  int get _currentRating {
    return switch (_stepIndex) {
      0 => _mood,
      1 => _energy,
      3 => _stress,
      _ => _mood,
    };
  }

  void _setCurrentRating(int value) {
    setState(() {
      switch (_stepIndex) {
        case 0:
          _mood = value;
        case 1:
          _energy = value;
        case 3:
          _stress = value;
      }
    });
  }

  String _helperTextForStep(_QuickStepSpec step) {
    if (step.label == 'MOOD') {
      return '${_moodLabel(_mood)} will be saved as today\'s mood signal.';
    }
    if (step.label == 'ENERGY') {
      return '${_energyLabel(_energy)} energy will tune workload nudges.';
    }
    return '${_stressLabel(_stress)} stress will tune reminder intensity.';
  }

  String _moodLabel(int value) {
    if (value >= 8) {
      return 'Great';
    }
    if (value >= 6) {
      return 'Good';
    }
    if (value >= 4) {
      return 'Neutral';
    }
    return 'Heavy';
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
    if (_stepIndex < _steps.length - 1) {
      setState(() => _stepIndex++);
      return;
    }
    await _save();
  }

  Future<void> _save() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session?.isGuestSession == true) {
      await _saveGuestDraft();
      if (mounted) {
        _showMessage('Guest check-in saved locally.');
        context.go(AppRoutes.dashboard);
      }
      return;
    }

    final client = ref.read(supabaseClientProvider);
    if (client == null) {
      _showMessage('Supabase is not configured.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await QuickCheckInSupabaseDataSource(client).save(
        QuickCheckInDraft(
          mood: _mood,
          energy: _energy,
          sleepHours: _sleepHours,
          stress: _stress,
          coachNotes: _notesController.text,
        ),
      );
      ref.invalidate(dashboardSnapshotProvider);
      if (mounted) {
        _showMessage('Quick check-in saved.');
        context.go(AppRoutes.dashboard);
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Could not save DailyLog. Supabase rejected the main row.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveGuestDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('guest_quick_checkins');
    final values = raw == null ? <dynamic>[] : jsonDecode(raw) as List<dynamic>;
    values.add({
      'createdAt': DateTime.now().toIso8601String(),
      'mood': _mood,
      'energy': _energy,
      'sleepHours': _sleepHours,
      'stress': _stress,
      'coachNotes': _notesController.text.trim(),
    });
    await prefs.setString('guest_quick_checkins', jsonEncode(values));
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
    required this.isLastStep,
    required this.isSaving,
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
  final bool isLastStep;
  final bool isSaving;
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
                    onPressed: isSaving ? null : onNext,
                    icon: isSaving
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
                      isSaving ? 'Saving...' : (isLastStep ? 'Save' : 'Next'),
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
    required this.compact,
    required this.ultraCompact,
    required this.onChanged,
  });

  final int value;
  final String unit;
  final String helperText;
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
                  value: '$value$unit',
                  compact: compact,
                  ultraCompact: ultraCompact,
                ),
                SizedBox(height: ultraCompact ? AppSpacing.xs : AppSpacing.sm),
                Slider(
                  value: value.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
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

  final double value;
  final bool compact;
  final bool ultraCompact;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CurrentRatingCard(
          value: '${value.round()} h',
          compact: compact,
          ultraCompact: ultraCompact,
        ),
        SizedBox(height: compact ? AppSpacing.md : AppSpacing.xl),
        Slider(
          value: value,
          min: 0,
          max: 12,
          divisions: 24,
          onChanged: onChanged,
        ),
      ],
    );
  }
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
          'What should your coach know?',
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
    required this.onTap,
  });

  final int rating;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
