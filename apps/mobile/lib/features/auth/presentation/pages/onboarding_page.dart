import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../optimization/presentation/providers/optimization_providers.dart';
import '../../domain/intake_response.dart';
import '../providers/setup_providers.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key, this.editing = false});

  final bool editing;

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(setupControllerProvider);
    if (state.isLoading) {
      return _LoadingSetupPage(editing: widget.editing);
    }
    if (state.loadError != null || state.draft == null) {
      return _SetupLoadErrorPage(
        editing: widget.editing,
        error: state.loadError,
        onRetry: ref.read(setupControllerProvider.notifier).load,
      );
    }

    final draft = state.draft!;
    return Scaffold(
      appBar: widget.editing
          ? AppBar(
              title: const Text('Setup and commitments'),
              leading: IconButton(
                tooltip: 'Back to Settings',
                onPressed: () => context.go(AppRoutes.settings),
                icon: const Icon(Icons.arrow_back),
              ),
            )
          : null,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                compact ? AppSpacing.md : AppSpacing.xl,
                AppSpacing.lg,
                compact ? AppSpacing.md : AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PERSONAL COACH',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              letterSpacing: 4,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        widget.editing
                            ? 'Review your setup'
                            : 'Build your day-aware coach',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        widget.editing
                            ? 'Update explicit answers and review only the goals, routines, and fixed commitments created by setup.'
                            : 'Start with the required choices. Goals, routines, commitments, and notes are optional and can be added later.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: _SetupColors.muted(context),
                              height: 1.5,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      if (state.isEditLocked) ...[
                        _PendingSetupNotice(
                          requestId: state.requestId,
                          retryLocked: state.retryLocked,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      IgnorePointer(
                        ignoring: state.isEditLocked,
                        child: Opacity(
                          opacity: state.isEditLocked ? 0.62 : 1,
                          child: Column(
                            children: [
                              _RequiredSetupSection(
                                draft: draft,
                                onChanged: _updateDraft,
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _OptionalSetupSection(
                                key: const ValueKey('optional-goals'),
                                title: 'Goals and friction',
                                subtitle: 'Optional · up to three goals',
                                initiallyExpanded:
                                    widget.editing && draft.goals.isNotEmpty,
                                children: [
                                  _GoalEditors(
                                    goals: draft.goals,
                                    onChanged: (goals) {
                                      _updateDraft(
                                        draft.copyWith(goals: goals),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  TextFormField(
                                    key: ValueKey(
                                      'friction-${state.readState?.revision ?? 0}',
                                    ),
                                    initialValue:
                                        draft.frictionPoints.join('\n'),
                                    minLines: 2,
                                    maxLines: 5,
                                    decoration: const InputDecoration(
                                      labelText: 'Friction points optional',
                                      hintText: 'One per line',
                                    ),
                                    onChanged: (value) {
                                      _updateDraft(
                                        draft.copyWith(
                                          frictionPoints: _listFromText(value),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _OptionalSetupSection(
                                key: const ValueKey('optional-routines'),
                                title: 'Routines',
                                subtitle:
                                    'Optional · named routines stay candidates until cadence and activation are explicit',
                                initiallyExpanded:
                                    widget.editing && draft.routines.isNotEmpty,
                                children: [
                                  _RoutineEditors(
                                    routines: draft.routines,
                                    onChanged: (routines) {
                                      _updateDraft(
                                        draft.copyWith(routines: routines),
                                      );
                                    },
                                    onInvalidActivation: _showMessage,
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _OptionalSetupSection(
                                key: const ValueKey('optional-commitments'),
                                title: 'Fixed commitments',
                                subtitle:
                                    'Optional · only real recurring blocks',
                                initiallyExpanded: widget.editing &&
                                    draft.fixedCommitments.isNotEmpty,
                                children: [
                                  _CommitmentEditors(
                                    commitments: draft.fixedCommitments,
                                    onChanged: (commitments) {
                                      _updateDraft(
                                        draft.copyWith(
                                          fixedCommitments: commitments,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _OptionalSetupSection(
                                key: const ValueKey('optional-context'),
                                title: 'More context',
                                subtitle: 'Optional note and calendar intent',
                                initiallyExpanded: widget.editing &&
                                    (draft.contextNote != null ||
                                        draft.calendarConnectionIntent != null),
                                children: [
                                  TextFormField(
                                    key: ValueKey(
                                      'context-${state.readState?.revision ?? 0}',
                                    ),
                                    initialValue: draft.contextNote,
                                    minLines: 2,
                                    maxLines: 5,
                                    decoration: const InputDecoration(
                                      labelText: 'Context note optional',
                                    ),
                                    onChanged: (value) {
                                      _updateDraft(
                                        draft.copyWith(contextNote: value),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  _NullableSelectField<String>(
                                    label: 'Calendar connection optional',
                                    value: draft.calendarConnectionIntent,
                                    values: const {
                                      'later': 'Maybe later',
                                      'not_now': 'Not now',
                                      'interested': 'Interested',
                                    },
                                    onChanged: (value) {
                                      _updateDraft(
                                        draft.copyWith(
                                          calendarConnectionIntent: value,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              if (widget.editing ||
                                  draft.goals.isNotEmpty ||
                                  draft.routines.isNotEmpty ||
                                  draft.fixedCommitments.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.lg),
                                _SetupReviewSection(draft: draft),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (state.saveError != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _InlineSetupError(error: state.saveError!),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: state.canSave ? _save : null,
                          icon: state.isSaving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: Text(
                            state.isSaving
                                ? 'Saving setup...'
                                : state.retryLocked
                                    ? 'Retry exact setup save'
                                    : state.isPending
                                        ? 'Resume pending setup'
                                        : state.saveError == null
                                            ? 'Save setup'
                                            : 'Retry setup save',
                          ),
                        ),
                      ),
                      if (state.isEditLocked || state.reloadSuggested) ...[
                        const SizedBox(height: AppSpacing.sm),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: state.isSaving
                                ? null
                                : ref
                                    .read(setupControllerProvider.notifier)
                                    .load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reload saved setup'),
                          ),
                        ),
                      ],
                      if (widget.editing) ...[
                        const SizedBox(height: AppSpacing.sm),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: state.isSaving
                                ? null
                                : () => context.go(AppRoutes.settings),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _updateDraft(IntakeResponseDraft draft) {
    ref.read(setupControllerProvider.notifier).updateDraft(draft);
  }

  Future<void> _save() async {
    final state = ref.read(setupControllerProvider);
    final draft = state.draft?.normalized();
    if (draft == null) {
      return;
    }
    final errors = draft.validationErrors();
    if (errors.isNotEmpty) {
      _showMessage(errors.first);
      return;
    }
    final saved = await ref.read(setupControllerProvider.notifier).save();
    if (!saved || !mounted) {
      return;
    }
    ref.invalidate(recommendationFeedProvider);
    ref.invalidate(dashboardSnapshotProvider);
    context.go(widget.editing ? AppRoutes.settings : AppRoutes.dashboard);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _RequiredSetupSection extends StatelessWidget {
  const _RequiredSetupSection({
    required this.draft,
    required this.onChanged,
  });

  final IntakeResponseDraft draft;
  final ValueChanged<IntakeResponseDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    const focusValues = {
      'focus': 'Focus',
      'energy': 'Energy',
      'sleep': 'Sleep',
      'stress': 'Stress',
      'planning': 'Planning',
      'movement': 'Movement',
    };
    final weekdayValues = <String, String>{
      'school_or_work': 'School or work blocks',
      'flexible': 'Flexible schedule',
      'split_day': 'Split day',
      'shift_based': 'Shift based',
    };
    final savedWeekdayShape = draft.weekdayShape;
    if (savedWeekdayShape != null &&
        !weekdayValues.containsKey(savedWeekdayShape)) {
      weekdayValues[savedWeekdayShape] = savedWeekdayShape;
    }
    return _SetupSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Required setup', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Nothing is selected for you. Choose the answers that are true now.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _SetupColors.muted(context),
                ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            key: const ValueKey('setup-display-name'),
            initialValue: draft.displayName,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Name optional'),
            onChanged: (value) => onChanged(draft.copyWith(displayName: value)),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Focus areas', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              ...focusValues.entries.map((entry) {
                final selected = draft.primaryFocusAreas.contains(entry.key);
                return ChoiceChip(
                  label: Text(entry.value),
                  selected: selected,
                  onSelected: (_) {
                    final values = {...draft.primaryFocusAreas};
                    selected ? values.remove(entry.key) : values.add(entry.key);
                    final sorted = values.toList(growable: false)..sort();
                    onChanged(draft.copyWith(primaryFocusAreas: sorted));
                  },
                );
              }),
              ...draft.primaryFocusAreas
                  .where((value) => !focusValues.containsKey(value))
                  .map(
                    (value) => InputChip(
                      label: Text('Unsupported: $value'),
                      onDeleted: () {
                        onChanged(
                          draft.copyWith(
                            primaryFocusAreas: draft.primaryFocusAreas
                                .where((item) => item != value)
                                .toList(growable: false),
                          ),
                        );
                      },
                    ),
                  ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _NullableSelectField<String>(
            label: 'Typical weekday required',
            value: draft.weekdayShape,
            values: weekdayValues,
            onChanged: (value) {
              onChanged(draft.copyWith(weekdayShape: value));
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _NullableSelectField<String>(
            label: 'Best energy window required',
            value: draft.bestEnergyWindow,
            values: const {
              'early_morning': 'Early morning',
              'morning': 'Morning',
              'afternoon': 'Afternoon',
              'evening': 'Evening',
              'variable': 'It varies',
            },
            onChanged: (value) {
              onChanged(draft.copyWith(bestEnergyWindow: value));
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _NullableSelectField<String>(
            label: 'Coaching style required',
            value: draft.coachingStyle,
            values: const {
              'direct': 'Direct',
              'gentle': 'Gentle',
              'analytical': 'Analytical',
              'accountability': 'Accountability',
            },
            onChanged: (value) {
              onChanged(draft.copyWith(coachingStyle: value));
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Reminder preference required',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'This stores your opt-in. If reminders are enabled, both quiet-hour times are required. Notification delivery is not enabled yet.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              ChoiceChip(
                label: const Text('Enable reminders'),
                selected: draft.reminderPreference?.enabled == true,
                onSelected: (_) {
                  onChanged(
                    draft.copyWith(
                      reminderPreference: const IntakeReminderPreference(
                        enabled: true,
                      ),
                    ),
                  );
                },
              ),
              ChoiceChip(
                label: const Text('No reminders'),
                selected: draft.reminderPreference?.enabled == false,
                onSelected: (_) {
                  onChanged(
                    draft.copyWith(
                      reminderPreference: const IntakeReminderPreference(
                        enabled: false,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          if (draft.reminderPreference?.enabled == true) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('setup-quiet-start'),
                    initialValue:
                        draft.reminderPreference?.quietHoursStart ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Quiet starts (HH:mm)',
                    ),
                    onChanged: (value) {
                      onChanged(
                        draft.copyWith(
                          reminderPreference:
                              draft.reminderPreference!.copyWith(
                            quietHoursStart: value,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('setup-quiet-end'),
                    initialValue: draft.reminderPreference?.quietHoursEnd ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Quiet ends (HH:mm)',
                    ),
                    onChanged: (value) {
                      onChanged(
                        draft.copyWith(
                          reminderPreference:
                              draft.reminderPreference!.copyWith(
                            quietHoursEnd: value,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GoalEditors extends StatelessWidget {
  const _GoalEditors({required this.goals, required this.onChanged});

  final List<IntakeGoalDraft> goals;
  final ValueChanged<List<IntakeGoalDraft>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < goals.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _EditorCard(
              child: Column(
                children: [
                  TextFormField(
                    key: ValueKey('goal-title-${goals[index].key}'),
                    initialValue: goals[index].title,
                    decoration: const InputDecoration(labelText: 'Goal title'),
                    onChanged: (value) {
                      final updated = [...goals];
                      updated[index] = goals[index].copyWith(title: value);
                      onChanged(updated);
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _EnumSelectField<IntakeGoalStatus>(
                    label: 'Goal status',
                    value: goals[index].status,
                    values: {
                      for (final status in IntakeGoalStatus.values)
                        status: _statusLabel(status.name),
                    },
                    onChanged: (status) {
                      final updated = [...goals];
                      updated[index] = goals[index].copyWith(status: status);
                      onChanged(updated);
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        final updated = [...goals]..removeAt(index);
                        onChanged(updated);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove from setup'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: goals.length >= 3
                ? null
                : () {
                    onChanged([
                      ...goals,
                      IntakeGoalDraft(key: generateSetupUuid(), title: ''),
                    ]);
                  },
            icon: const Icon(Icons.add),
            label: const Text('Add goal'),
          ),
        ),
      ],
    );
  }
}

class _RoutineEditors extends StatelessWidget {
  const _RoutineEditors({
    required this.routines,
    required this.onChanged,
    required this.onInvalidActivation,
  });

  final List<IntakeRoutineDraft> routines;
  final ValueChanged<List<IntakeRoutineDraft>> onChanged;
  final ValueChanged<String> onInvalidActivation;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < routines.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _EditorCard(
              child: Column(
                children: [
                  TextFormField(
                    key: ValueKey('routine-title-${routines[index].key}'),
                    initialValue: routines[index].title,
                    decoration: const InputDecoration(
                      labelText: 'Routine name',
                    ),
                    onChanged: (value) {
                      _replace(
                        index,
                        routines[index].copyWith(title: value),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _NullableSelectField<String>(
                    label: 'Cadence (required before activation)',
                    value: routines[index].frequency,
                    values: const {
                      'daily': 'Daily',
                      'weekly': 'Weekly',
                    },
                    onChanged: (frequency) {
                      _replace(
                        index,
                        routines[index].copyWith(
                          frequency: frequency,
                          cadenceConfirmed: frequency == 'daily',
                          target: frequency == 'daily' ? 1 : null,
                          status: frequency != 'daily' &&
                                  routines[index].status.requiresCadence
                              ? IntakeRoutineStatus.candidate
                              : routines[index].status,
                        ),
                      );
                    },
                  ),
                  if (routines[index].frequency != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      key: ValueKey(
                        'routine-target-${routines[index].key}-${routines[index].frequency}',
                      ),
                      initialValue: routines[index].target?.toString() ?? '',
                      enabled: routines[index].frequency == 'weekly',
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: routines[index].frequency == 'daily'
                            ? 'Daily target (fixed)'
                            : 'Weekly target (1–7)',
                      ),
                      onChanged: (value) {
                        final target = int.tryParse(value);
                        final cadenceConfirmed =
                            routines[index].frequency == 'daily'
                                ? target == 1
                                : target != null && target >= 1 && target <= 7;
                        _replace(
                          index,
                          routines[index].copyWith(
                            target: target,
                            cadenceConfirmed: cadenceConfirmed,
                            status: !cadenceConfirmed &&
                                    routines[index].status.requiresCadence
                                ? IntakeRoutineStatus.candidate
                                : routines[index].status,
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  _EnumSelectField<IntakeRoutineStatus>(
                    label: 'Routine status',
                    value: routines[index].status,
                    values: {
                      for (final status in IntakeRoutineStatus.values)
                        status: _statusLabel(status.name),
                    },
                    onChanged: (status) {
                      if (status.requiresCadence &&
                          (!routines[index].cadenceConfirmed ||
                              routines[index].frequency == null)) {
                        onInvalidActivation(
                          'Choose and confirm cadence before activating or pausing this routine.',
                        );
                        return;
                      }
                      _replace(index, routines[index].copyWith(status: status));
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        final updated = [...routines]..removeAt(index);
                        onChanged(updated);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove from setup'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: routines.length >= 5
                ? null
                : () {
                    onChanged([
                      ...routines,
                      IntakeRoutineDraft(
                        key: generateSetupUuid(),
                        title: '',
                      ),
                    ]);
                  },
            icon: const Icon(Icons.add),
            label: const Text('Add routine candidate'),
          ),
        ),
      ],
    );
  }

  void _replace(int index, IntakeRoutineDraft value) {
    final updated = [...routines];
    updated[index] = value;
    onChanged(updated);
  }
}

class _CommitmentEditors extends StatelessWidget {
  const _CommitmentEditors({
    required this.commitments,
    required this.onChanged,
  });

  final List<IntakeCommitmentDraft> commitments;
  final ValueChanged<List<IntakeCommitmentDraft>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < commitments.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _EditorCard(
              child: Column(
                children: [
                  TextFormField(
                    key: ValueKey(
                      'commitment-title-${commitments[index].key}',
                    ),
                    initialValue: commitments[index].title,
                    decoration: const InputDecoration(labelText: 'Title'),
                    onChanged: (value) {
                      _replace(
                        index,
                        commitments[index].copyWith(title: value),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: ValueKey(
                      'commitment-location-${commitments[index].key}',
                    ),
                    initialValue: commitments[index].location,
                    decoration: const InputDecoration(
                      labelText: 'Location optional',
                    ),
                    onChanged: (value) {
                      _replace(
                        index,
                        commitments[index].copyWith(location: value),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _NullableSelectField<int>(
                    label: 'Weekday',
                    value: commitments[index].weekday,
                    values: const {
                      1: 'Monday',
                      2: 'Tuesday',
                      3: 'Wednesday',
                      4: 'Thursday',
                      5: 'Friday',
                      6: 'Saturday',
                      7: 'Sunday',
                    },
                    onChanged: (weekday) {
                      _replace(
                        index,
                        commitments[index].copyWith(weekday: weekday),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey(
                            'commitment-start-${commitments[index].key}',
                          ),
                          initialValue: commitments[index].startsAt,
                          decoration: const InputDecoration(
                            labelText: 'Starts (HH:mm)',
                          ),
                          onChanged: (value) {
                            _replace(
                              index,
                              commitments[index].copyWith(startsAt: value),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey(
                            'commitment-end-${commitments[index].key}',
                          ),
                          initialValue: commitments[index].endsAt,
                          decoration: const InputDecoration(
                            labelText: 'Ends (HH:mm)',
                          ),
                          onChanged: (value) {
                            _replace(
                              index,
                              commitments[index].copyWith(endsAt: value),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _EnumSelectField<IntakeCommitmentStatus>(
                    label: 'Commitment status',
                    value: commitments[index].status,
                    values: {
                      for (final status in IntakeCommitmentStatus.values)
                        status: _statusLabel(status.name),
                    },
                    onChanged: (status) {
                      _replace(
                        index,
                        commitments[index].copyWith(status: status),
                      );
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        final updated = [...commitments]..removeAt(index);
                        onChanged(updated);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove from setup'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: commitments.length >= 10
                ? null
                : () {
                    onChanged([
                      ...commitments,
                      IntakeCommitmentDraft(
                        key: generateSetupUuid(),
                        title: '',
                        location: null,
                        weekday: null,
                        startsAt: '',
                        endsAt: '',
                      ),
                    ]);
                  },
            icon: const Icon(Icons.add),
            label: const Text('Add fixed commitment'),
          ),
        ),
      ],
    );
  }

  void _replace(int index, IntakeCommitmentDraft value) {
    final updated = [...commitments];
    updated[index] = value;
    onChanged(updated);
  }
}

class _SetupReviewSection extends StatelessWidget {
  const _SetupReviewSection({required this.draft});

  final IntakeResponseDraft draft;

  @override
  Widget build(BuildContext context) {
    final goals = draft.goals.where((goal) => goal.title.trim().isNotEmpty);
    final routines =
        draft.routines.where((routine) => routine.title.trim().isNotEmpty);
    final commitments = draft.fixedCommitments
        .where((commitment) => commitment.title.trim().isNotEmpty);
    return _SetupSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review setup-created commitments',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Status changes above are saved as the complete desired setup state. Other manually created records are not included.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _SetupColors.muted(context),
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (goals.isEmpty && routines.isEmpty && commitments.isEmpty)
            const Text('No optional setup commitments.')
          else ...[
            for (final goal in goals)
              _ReviewRow(
                icon: Icons.flag_outlined,
                title: goal.title,
                status: _statusLabel(goal.status.name),
              ),
            for (final routine in routines)
              _ReviewRow(
                icon: Icons.repeat,
                title: routine.title,
                status: routine.status == IntakeRoutineStatus.candidate
                    ? 'Candidate · not active'
                    : _statusLabel(routine.status.name),
              ),
            for (final commitment in commitments)
              _ReviewRow(
                icon: Icons.schedule,
                title: commitment.title,
                status: _statusLabel(commitment.status.name),
              ),
          ],
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.icon,
    required this.title,
    required this.status,
  });

  final IconData icon;
  final String title;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(title)),
          Text(status, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _OptionalSetupSection extends StatelessWidget {
  const _OptionalSetupSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.initiallyExpanded,
    required this.children,
  });

  final String title;
  final String subtitle;
  final bool initiallyExpanded;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _SetupColors.panel(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: _SetupColors.border(context), width: 2),
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text(title),
        subtitle: Text(subtitle),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: children,
      ),
    );
  }
}

class _NullableSelectField<T> extends StatelessWidget {
  const _NullableSelectField({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final Map<T, String> values;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final hasUnsupportedValue = value != null && !values.containsKey(value);
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: const Text('Select'),
          items: [
            DropdownMenuItem<T>(
              value: null,
              child: Text('Not set'),
            ),
            if (hasUnsupportedValue)
              DropdownMenuItem<T>(
                value: value as T,
                child: Text('Unsupported: $value'),
              ),
            ...values.entries.map(
              (entry) => DropdownMenuItem<T>(
                value: entry.key,
                child: Text(entry.value),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _EnumSelectField<T> extends StatelessWidget {
  const _EnumSelectField({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> values;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          items: values.entries
              .map(
                (entry) => DropdownMenuItem<T>(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value != null) {
              onChanged(value);
            }
          },
        ),
      ),
    );
  }
}

class _EditorCard extends StatelessWidget {
  const _EditorCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _SetupColors.row(context),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

class _SetupSurface extends StatelessWidget {
  const _SetupSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: _SetupColors.panel(context),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _SetupColors.border(context), width: 2),
      ),
      child: child,
    );
  }
}

class _LoadingSetupPage extends StatelessWidget {
  const _LoadingSetupPage({required this.editing});

  final bool editing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          editing ? AppBar(title: const Text('Setup and commitments')) : null,
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: AppSpacing.md),
            Text('Loading saved setup...'),
          ],
        ),
      ),
    );
  }
}

class _SetupLoadErrorPage extends StatelessWidget {
  const _SetupLoadErrorPage({
    required this.editing,
    required this.error,
    required this.onRetry,
  });

  final bool editing;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: editing
          ? AppBar(
              title: const Text('Setup and commitments'),
              leading: IconButton(
                onPressed: () => context.go(AppRoutes.settings),
                icon: const Icon(Icons.arrow_back),
              ),
            )
          : null,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _SetupSurface(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 40),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Could not load setup',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _errorText(error),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry setup load'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineSetupError extends StatelessWidget {
  const _InlineSetupError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        'Setup was not saved. Your draft is still here. ${_errorText(error)}',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

class _PendingSetupNotice extends StatelessWidget {
  const _PendingSetupNotice({
    required this.requestId,
    required this.retryLocked,
  });

  final String? requestId;
  final bool retryLocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            retryLocked
                ? 'Setup save needs an exact retry'
                : 'Finish the pending setup save',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            retryLocked
                ? 'The save result is unknown. Your exact submitted draft is locked; retry it unchanged or reload the server state.'
                : 'The previous request may have reached the server. The exact saved draft is locked until that same request is applied safely.',
          ),
          if (requestId != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Pending request ${requestId!.length > 8 ? requestId!.substring(0, 8) : requestId}…',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}

List<String> _listFromText(String value) {
  return value
      .split(RegExp(r'[\n,]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String _statusLabel(String value) {
  if (value.isEmpty) {
    return value;
  }
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

String _errorText(Object? error) {
  if (error == null) {
    return 'Try again.';
  }
  return '$error'.replaceFirst('Bad state: ', '');
}

class _SetupColors {
  const _SetupColors._();

  static bool _light(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  static Color panel(BuildContext context) =>
      _light(context) ? const Color(0xFFFFFFFF) : const Color(0xFF122329);

  static Color row(BuildContext context) =>
      _light(context) ? const Color(0xFFEAF1F0) : const Color(0xFF202B32);

  static Color border(BuildContext context) =>
      _light(context) ? const Color(0xFFD4E1DF) : const Color(0xFF2A424A);

  static Color muted(BuildContext context) =>
      _light(context) ? const Color(0xFF607078) : const Color(0xFFA8B5BE);
}
