import 'package:flutter/material.dart';

import 'package:my_life_graph/core/constants/app_radii.dart';

import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_visual_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../optimization/presentation/providers/optimization_providers.dart';
import '../../domain/app_session.dart';
import '../../domain/intake_response.dart';
import '../providers/setup_providers.dart';
import '../setup_user_message.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({
    super.key,
    this.editing = false,
    this.openStudySetup = false,
  });

  final bool editing;
  final bool openStudySetup;

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
                icon: const Icon(AppIcons.arrowBack),
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
                            ? 'Update your weekday and energy window, then review setup-owned routines and fixed commitments.'
                            : 'Choose your typical weekday and best energy window. Routines, commitments, and study setup stay optional.',
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
                                key: const ValueKey('optional-focus-setup'),
                                title: 'Focus setup',
                                subtitle:
                                    'Optional · rhythm and a local start ritual',
                                initiallyExpanded: false,
                                children: [
                                  _StudyFocusEditor(
                                    rhythm: draft.studySetup?.focusRhythm,
                                    onChanged: (rhythm) {
                                      _updateStudyFocus(draft, rhythm);
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _OptionalSetupSection(
                                key: const ValueKey(
                                  'optional-semester-planning',
                                ),
                                title: 'Semester planning',
                                subtitle:
                                    'Optional · current semester and next course selection window',
                                initiallyExpanded: widget.openStudySetup,
                                children: [
                                  _StudySemesterEditor(
                                    planning:
                                        draft.studySetup?.semesterPlanning,
                                    onChanged: (planning) {
                                      _updateSemesterPlanning(draft, planning);
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _OptionalSetupSection(
                                key: const ValueKey('optional-commitments'),
                                title: 'Fixed commitments',
                                subtitle:
                                    'Optional · recurring classes, work, and other weekly blocks',
                                initiallyExpanded: widget.editing &&
                                    draft.fixedCommitments.isNotEmpty,
                                children: [
                                  _CommitmentEditors(
                                    commitments: draft.fixedCommitments,
                                    currentSemester: draft.studySetup
                                        ?.semesterPlanning?.currentSemester,
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
                              if (widget.editing ||
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
                              : const Icon(AppIcons.check),
                          label: Text(
                            state.isSaving
                                ? 'Saving setup...'
                                : state.retryLocked
                                    ? 'Retry unchanged'
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
                            icon: const Icon(AppIcons.refresh),
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

  void _updateStudyFocus(
    IntakeResponseDraft draft,
    StudyFocusRhythmDraft? rhythm,
  ) {
    final study = (draft.studySetup ??
            const StudySetupDraft(
              focusRhythm: null,
              semesterPlanning: null,
            ))
        .copyWith(focusRhythm: rhythm);
    _updateDraft(draft.copyWith(studySetup: study.isEmpty ? null : study));
  }

  void _updateSemesterPlanning(
    IntakeResponseDraft draft,
    StudySemesterPlanningDraft? planning,
  ) {
    final study = (draft.studySetup ??
            const StudySetupDraft(
              focusRhythm: null,
              semesterPlanning: null,
            ))
        .copyWith(semesterPlanning: planning);
    _updateDraft(draft.copyWith(studySetup: study.isEmpty ? null : study));
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
    final session = ref.read(setupControllerProvider.notifier).session;
    if (shouldConfirmInitialUtcTimezone(
      editing: widget.editing,
      session: session,
    )) {
      final reviewTimezone = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Confirm account timezone'),
            content: const Text(
              'This synced account currently uses UTC. Local dates, rule-based plans, briefings, reviews, and budgets follow the account timezone. Keep UTC only if it matches you, or review it in Settings. Existing preparation reservations keep their saved instants.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Keep UTC'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Review in Settings'),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      context.go(
        reviewTimezone == true ? AppRoutes.settings : AppRoutes.dashboard,
      );
      return;
    }
    context.go(widget.editing ? AppRoutes.settings : AppRoutes.dashboard);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

bool shouldConfirmInitialUtcTimezone({
  required bool editing,
  required AppSession? session,
}) {
  return !editing &&
      session?.isAuthenticated == true &&
      session?.profile.timezone == 'UTC';
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
        ],
      ),
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
                      icon: const Icon(AppIcons.deleteOutline),
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
            icon: const Icon(AppIcons.add),
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

class _StudyFocusEditor extends StatelessWidget {
  const _StudyFocusEditor({
    required this.rhythm,
    required this.onChanged,
  });

  final StudyFocusRhythmDraft? rhythm;
  final ValueChanged<StudyFocusRhythmDraft?> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = rhythm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          key: const ValueKey('study-focus-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Use a study rhythm'),
          subtitle: const Text(
            'New study plans can reserve a full recovery buffer after each focus block.',
          ),
          value: value != null,
          onChanged: (enabled) {
            onChanged(enabled ? StudyFocusRhythmDraft.defaults() : null);
          },
        ),
        if (value != null) ...[
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final fields = [
                DropdownButtonFormField<int>(
                  key: const ValueKey('study-focus-minutes'),
                  initialValue: value.focusMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Focus length',
                    helperText: '25–180 minutes',
                  ),
                  items: [
                    for (var minutes = 25; minutes <= 180; minutes += 5)
                      DropdownMenuItem(
                        value: minutes,
                        child: Text('$minutes minutes'),
                      ),
                  ],
                  onChanged: (minutes) {
                    if (minutes != null) {
                      onChanged(value.copyWith(focusMinutes: minutes));
                    }
                  },
                ),
                DropdownButtonFormField<int>(
                  key: const ValueKey('study-recovery-minutes'),
                  initialValue: value.recoveryMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Recovery length',
                    helperText: '5–60 minutes',
                  ),
                  items: [
                    for (var minutes = 5; minutes <= 60; minutes += 5)
                      DropdownMenuItem(
                        value: minutes,
                        child: Text('$minutes minutes'),
                      ),
                  ],
                  onChanged: (minutes) {
                    if (minutes != null) {
                      onChanged(value.copyWith(recoveryMinutes: minutes));
                    }
                  },
                ),
              ];
              if (constraints.maxWidth < 560) {
                return Column(
                  children: [
                    fields.first,
                    const SizedBox(height: AppSpacing.md),
                    fields.last,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: fields.first),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: fields.last),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Start ritual',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'This checklist appears before a focus session. Ready and “not needed today” choices stay on this device only for that start and are never saved or scored.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _SetupColors.muted(context),
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (var index = 0; index < value.preparationItems.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _EditorCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: ValueKey(
                          'study-ritual-${value.preparationItems[index].key}',
                        ),
                        initialValue: value.preparationItems[index].label,
                        maxLength: 120,
                        decoration: const InputDecoration(
                          labelText: 'Preparation item',
                        ),
                        onChanged: (label) {
                          _replaceItem(
                            value,
                            index,
                            value.preparationItems[index].copyWith(
                              label: label,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      children: [
                        Switch.adaptive(
                          value: value.preparationItems[index].active,
                          onChanged: (active) {
                            _replaceItem(
                              value,
                              index,
                              value.preparationItems[index].copyWith(
                                active: active,
                              ),
                            );
                          },
                        ),
                        Wrap(
                          spacing: 0,
                          children: [
                            IconButton(
                              tooltip: 'Move up',
                              onPressed: index == 0
                                  ? null
                                  : () => _moveItem(value, index, index - 1),
                              icon: const Icon(AppIcons.arrowUpward),
                            ),
                            IconButton(
                              tooltip: 'Move down',
                              onPressed: index ==
                                      value.preparationItems.length - 1
                                  ? null
                                  : () => _moveItem(value, index, index + 1),
                              icon: const Icon(AppIcons.arrowDownward),
                            ),
                            IconButton(
                              tooltip: 'Remove preparation item',
                              onPressed: () {
                                final items = [...value.preparationItems]
                                  ..removeAt(index);
                                onChanged(
                                  value.copyWith(preparationItems: items),
                                );
                              },
                              icon: const Icon(AppIcons.deleteOutline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('study-ritual-add'),
              onPressed: value.preparationItems.length >= 12
                  ? null
                  : () {
                      onChanged(
                        value.copyWith(
                          preparationItems: [
                            ...value.preparationItems,
                            StudyPreparationItemDraft(
                              key: generateSetupUuid(),
                              label: '',
                              active: true,
                            ),
                          ],
                        ),
                      );
                    },
              icon: const Icon(AppIcons.add),
              label: const Text('Add your own item'),
            ),
          ),
        ],
      ],
    );
  }

  void _replaceItem(
    StudyFocusRhythmDraft value,
    int index,
    StudyPreparationItemDraft item,
  ) {
    final items = [...value.preparationItems];
    items[index] = item;
    onChanged(value.copyWith(preparationItems: items));
  }

  void _moveItem(StudyFocusRhythmDraft value, int from, int to) {
    final items = [...value.preparationItems];
    final item = items.removeAt(from);
    items.insert(to, item);
    onChanged(value.copyWith(preparationItems: items));
  }
}

class _StudySemesterEditor extends StatelessWidget {
  const _StudySemesterEditor({
    required this.planning,
    required this.onChanged,
  });

  final StudySemesterPlanningDraft? planning;
  final ValueChanged<StudySemesterPlanningDraft?> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = planning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          key: const ValueKey('study-semester-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Track semester dates'),
          subtitle: const Text(
            'Course selection stays a reminder in Planner. It never creates tasks, changes a calendar, or sends a notification.',
          ),
          value: value != null,
          onChanged: (enabled) {
            onChanged(
              enabled ? StudySemesterPlanningDraft.empty() : null,
            );
          },
        ),
        if (value != null) ...[
          const SizedBox(height: AppSpacing.md),
          _EditorCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current semester',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const ValueKey('study-current-semester-name'),
                  initialValue: value.currentSemester.name,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (name) {
                    onChanged(
                      value.copyWith(
                        currentSemester:
                            value.currentSemester.copyWith(name: name),
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                _StudyDateButtons(
                  startKey: const ValueKey('study-current-semester-start'),
                  endKey: const ValueKey('study-current-semester-end'),
                  startLabel: 'Starts',
                  endLabel: 'Ends',
                  start: value.currentSemester.startsOn,
                  end: value.currentSemester.endsOn,
                  onStartChanged: (date) {
                    onChanged(
                      value.copyWith(
                        currentSemester:
                            value.currentSemester.copyWith(startsOn: date),
                      ),
                    );
                  },
                  onEndChanged: (date) {
                    onChanged(
                      value.copyWith(
                        currentSemester:
                            value.currentSemester.copyWith(endsOn: date),
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Only newly added fixed commitments are prefilled with these dates. Existing commitments are never changed.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _SetupColors.muted(context),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _EditorCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next semester',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const ValueKey('study-next-semester-name'),
                  initialValue: value.nextSemester.name,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (name) {
                    onChanged(
                      value.copyWith(
                        nextSemester: value.nextSemester.copyWith(name: name),
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                _StudyDateButtons(
                  startKey: const ValueKey('study-next-semester-start'),
                  endKey: const ValueKey('study-next-semester-end'),
                  startLabel: 'Starts',
                  endLabel: 'Ends',
                  start: value.nextSemester.startsOn,
                  end: value.nextSemester.endsOn,
                  onStartChanged: (date) {
                    onChanged(
                      value.copyWith(
                        nextSemester:
                            value.nextSemester.copyWith(startsOn: date),
                      ),
                    );
                  },
                  onEndChanged: (date) {
                    onChanged(
                      value.copyWith(
                        nextSemester: value.nextSemester.copyWith(endsOn: date),
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Course selection window',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                _StudyDateButtons(
                  startKey: const ValueKey('study-course-selection-start'),
                  endKey: const ValueKey('study-course-selection-end'),
                  startLabel: 'Opens',
                  endLabel: 'Closes',
                  start: value.nextSemester.courseSelectionStartsOn,
                  end: value.nextSemester.courseSelectionEndsOn,
                  onStartChanged: (date) {
                    onChanged(
                      value.copyWith(
                        nextSemester: value.nextSemester.copyWith(
                          courseSelectionStartsOn: date,
                        ),
                      ),
                    );
                  },
                  onEndChanged: (date) {
                    onChanged(
                      value.copyWith(
                        nextSemester: value.nextSemester.copyWith(
                          courseSelectionEndsOn: date,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const ValueKey('study-course-names'),
                  initialValue: value.nextSemester.courseNames.join('\n'),
                  minLines: 3,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    labelText: 'Courses optional',
                    hintText: 'One unique course name per line · up to 12',
                  ),
                  onChanged: (text) {
                    onChanged(
                      value.copyWith(
                        nextSemester: value.nextSemester.copyWith(
                          courseNames: _listFromText(text),
                        ),
                      ),
                    );
                  },
                ),
                SwitchListTile.adaptive(
                  key: const ValueKey(
                    'study-course-selection-completed',
                  ),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Course selection completed'),
                  subtitle: const Text(
                    'One status for the full selection window.',
                  ),
                  value: value.nextSemester.courseSelectionCompleted,
                  onChanged: (completed) {
                    onChanged(
                      value.copyWith(
                        nextSemester: value.nextSemester.copyWith(
                          courseSelectionCompleted: completed,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StudyDateButtons extends StatelessWidget {
  const _StudyDateButtons({
    required this.startKey,
    required this.endKey,
    required this.startLabel,
    required this.endLabel,
    required this.start,
    required this.end,
    required this.onStartChanged,
    required this.onEndChanged,
  });

  final Key startKey;
  final Key endKey;
  final String startLabel;
  final String endLabel;
  final DateTime? start;
  final DateTime? end;
  final ValueChanged<DateTime> onStartChanged;
  final ValueChanged<DateTime> onEndChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        OutlinedButton.icon(
          key: startKey,
          onPressed: () => _pick(context, start ?? end, onStartChanged),
          icon: const Icon(AppIcons.dateRangeOutlined),
          label: Text(
            start == null ? startLabel : '$startLabel ${_dateLabel(start!)}',
          ),
        ),
        OutlinedButton.icon(
          key: endKey,
          onPressed: () => _pick(context, end ?? start, onEndChanged),
          icon: const Icon(AppIcons.eventAvailableOutlined),
          label: Text(
            end == null ? endLabel : '$endLabel ${_dateLabel(end!)}',
          ),
        ),
      ],
    );
  }

  Future<void> _pick(
    BuildContext context,
    DateTime? current,
    ValueChanged<DateTime> onSelected,
  ) async {
    final now = DateTime.now();
    final initial = current ?? DateTime(now.year, now.month, now.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (selected != null) {
      onSelected(DateTime.utc(selected.year, selected.month, selected.day));
    }
  }
}

class _CommitmentEditors extends StatelessWidget {
  const _CommitmentEditors({
    required this.commitments,
    required this.currentSemester,
    required this.onChanged,
  });

  final List<IntakeCommitmentDraft> commitments;
  final StudySemesterDraft? currentSemester;
  final ValueChanged<List<IntakeCommitmentDraft>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add the weekly times when planning must stay free. Semester dates are optional; without them, a block repeats until you archive it.',
        ),
        const SizedBox(height: AppSpacing.md),
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Semester dates optional',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        OutlinedButton.icon(
                          key: ValueKey(
                            'commitment-valid-from-${commitments[index].key}',
                          ),
                          onPressed: () => _pickValidityDate(
                            context,
                            index,
                            pickStart: true,
                          ),
                          icon: const Icon(AppIcons.dateRangeOutlined),
                          label: Text(
                            commitments[index].validFrom == null
                                ? 'Valid from'
                                : 'From ${_dateLabel(commitments[index].validFrom!)}',
                          ),
                        ),
                        OutlinedButton.icon(
                          key: ValueKey(
                            'commitment-valid-until-${commitments[index].key}',
                          ),
                          onPressed: () => _pickValidityDate(
                            context,
                            index,
                            pickStart: false,
                          ),
                          icon: const Icon(AppIcons.eventAvailableOutlined),
                          label: Text(
                            commitments[index].validUntil == null
                                ? 'Valid until'
                                : 'Until ${_dateLabel(commitments[index].validUntil!)}',
                          ),
                        ),
                        if (commitments[index].validFrom != null ||
                            commitments[index].validUntil != null)
                          TextButton(
                            key: ValueKey(
                              'commitment-clear-validity-${commitments[index].key}',
                            ),
                            onPressed: () {
                              _replace(
                                index,
                                commitments[index].copyWith(
                                  validFrom: null,
                                  validUntil: null,
                                ),
                              );
                            },
                            child: const Text('Clear dates'),
                          ),
                      ],
                    ),
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
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      TextButton.icon(
                        key: ValueKey(
                          'commitment-duplicate-${commitments[index].key}',
                        ),
                        onPressed: commitments.length >= 10
                            ? null
                            : () {
                                final updated = [...commitments]..insert(
                                    index + 1,
                                    commitments[index].copyWith(
                                      key: generateSetupUuid(),
                                      weekday: null,
                                    ),
                                  );
                                onChanged(updated);
                              },
                        icon: const Icon(AppIcons.copyOutlined),
                        label: const Text('Duplicate for another day'),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          final updated = [...commitments]..removeAt(index);
                          onChanged(updated);
                        },
                        icon: const Icon(AppIcons.deleteOutline),
                        label: const Text('Remove from setup'),
                      ),
                    ],
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
                        validFrom: currentSemester?.startsOn,
                        validUntil: currentSemester?.endsOn,
                      ),
                    ]);
                  },
            icon: const Icon(AppIcons.add),
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

  Future<void> _pickValidityDate(
    BuildContext context,
    int index, {
    required bool pickStart,
  }) async {
    final commitment = commitments[index];
    final lowerBound =
        pickStart ? DateTime(2000) : commitment.validFrom ?? DateTime(2000);
    final upperBound = pickStart
        ? commitment.validUntil ?? DateTime(2100, 12, 31)
        : DateTime(2100, 12, 31);
    var initialDate = (pickStart
            ? commitment.validFrom ?? commitment.validUntil
            : commitment.validUntil ?? commitment.validFrom) ??
        DateTime.now();
    if (initialDate.isBefore(lowerBound)) initialDate = lowerBound;
    if (initialDate.isAfter(upperBound)) initialDate = upperBound;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: lowerBound,
      lastDate: upperBound,
      helpText: pickStart ? 'SELECT FIRST WEEK' : 'SELECT LAST WEEK',
    );
    if (selected == null) return;
    final normalized =
        DateTime.utc(selected.year, selected.month, selected.day);
    _replace(
      index,
      pickStart
          ? commitment.copyWith(validFrom: normalized)
          : commitment.copyWith(validUntil: normalized),
    );
  }
}

class _SetupReviewSection extends StatelessWidget {
  const _SetupReviewSection({required this.draft});

  final IntakeResponseDraft draft;

  @override
  Widget build(BuildContext context) {
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
          if (routines.isEmpty && commitments.isEmpty)
            const Text('No optional setup commitments.')
          else ...[
            for (final routine in routines)
              _ReviewRow(
                icon: AppIcons.repeat,
                title: routine.title,
                status: routine.status == IntakeRoutineStatus.candidate
                    ? 'Candidate · not active'
                    : _statusLabel(routine.status.name),
              ),
            for (final commitment in commitments)
              _ReviewRow(
                icon: AppIcons.schedule,
                title: commitment.title,
                status: _commitmentReviewStatus(commitment),
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
        borderRadius: BorderRadius.circular(AppRadii.xl),
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
    return AppSurface(
      variant: AppSurfaceVariant.subtle,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: child,
    );
  }
}

class _SetupSurface extends StatelessWidget {
  const _SetupSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      variant: AppSurfaceVariant.raised,
      padding: const EdgeInsets.all(AppSpacing.lg),
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
                icon: const Icon(AppIcons.arrowBack),
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
                  const Icon(AppIcons.cloudOffOutlined, size: 40),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Could not load setup',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    setupUserMessage(
                      error,
                      operation: SetupFailureOperation.load,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(AppIcons.refresh),
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
    return AppSurface(
      variant: AppSurfaceVariant.danger,
      child: Text(
        setupUserMessage(
          error,
          operation: SetupFailureOperation.save,
        ),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
    return AppSurface(
      variant: AppSurfaceVariant.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            retryLocked
                ? 'Setup save could not be confirmed'
                : 'Finish saving Setup',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            retryLocked
                ? 'Your answers are still here and locked for a safe retry. Retry unchanged or load the latest saved Setup.'
                : 'Your previous save may have worked. These answers stay locked until the app can confirm the result safely.',
          ),
          if (requestId != null)
            Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Technical details'),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Save reference ${requestId!.length > 8 ? requestId!.substring(0, 8) : requestId}…',
                      style: Theme.of(context).textTheme.labelSmall,
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

String _dateLabel(DateTime value) => DateFormat.yMMMd().format(value);

String _commitmentReviewStatus(IntakeCommitmentDraft commitment) {
  final status = _statusLabel(commitment.status.name);
  final validFrom = commitment.validFrom;
  final validUntil = commitment.validUntil;
  if (validFrom == null && validUntil == null) return status;
  if (validFrom != null && validUntil != null) {
    return '$status · ${_dateLabel(validFrom)}–${_dateLabel(validUntil)}';
  }
  if (validFrom != null) return '$status · from ${_dateLabel(validFrom)}';
  return '$status · until ${_dateLabel(validUntil!)}';
}

class _SetupColors {
  const _SetupColors._();

  static Color panel(BuildContext context) => context.visualTokens.surface;

  static Color muted(BuildContext context) =>
      context.visualTokens.textSecondary;
}
