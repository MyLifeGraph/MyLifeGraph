part of '../pages/deadline_plans_page.dart';

class _AssignmentSeriesEditorSheet extends StatefulWidget {
  const _AssignmentSeriesEditorSheet({
    required this.seriesId,
    required this.baseRevision,
    required this.existing,
    required this.retainedDraft,
    required this.accountDailyPreparationBudgetKnown,
    required this.accountDailyPreparationBudgetMinutes,
    required this.currentTime,
    required this.onOpenPlanner,
  });

  final String seriesId;
  final int baseRevision;
  final AssignmentSeriesRevision? existing;
  final AssignmentSeriesProposalDraft? retainedDraft;
  final bool accountDailyPreparationBudgetKnown;
  final int? accountDailyPreparationBudgetMinutes;
  final DateTime? currentTime;
  final VoidCallback onOpenPlanner;

  @override
  State<_AssignmentSeriesEditorSheet> createState() =>
      _AssignmentSeriesEditorSheetState();
}

class _AssignmentSeriesEditorSheetState
    extends State<_AssignmentSeriesEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _countController;
  late final TextEditingController _totalHoursController;
  late final TextEditingController _totalMinutesController;
  late final TextEditingController _dailyCapController;
  DateTime? _nextDeadline;
  int _step = 0;
  int _sessionMinutes = 50;
  int _bufferDays = 1;
  bool _useCalendarAvailability = false;

  DateTime get _now => widget.currentTime ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final retained = widget.retainedDraft;
    final futureOccurrences = (existing?.keptOccurrences
                .where((item) => item.deadlineAt.isAfter(_now)) ??
            const <AssignmentSeriesOccurrence>[])
        .toList();
    futureOccurrences.sort(
      (left, right) => left.deadlineAt.compareTo(right.deadlineAt),
    );
    final total =
        retained?.estimatedTotalMinutes ?? existing?.estimatedTotalMinutes;
    _titleController = TextEditingController(
      text: retained?.title ?? existing?.title ?? '',
    );
    _countController = TextEditingController(
      text:
          '${retained?.remainingOccurrences ?? (widget.baseRevision == 0 ? 12 : futureOccurrences.isEmpty ? 1 : futureOccurrences.length)}',
    );
    _totalHoursController = TextEditingController(
      text: total == null ? '' : '${total ~/ 60}',
    );
    _totalMinutesController = TextEditingController(
      text: total == null ? '' : '${total % 60}',
    );
    _dailyCapController = TextEditingController(
      text: '${retained?.maxDailyMinutes ?? existing?.maxDailyMinutes ?? 120}',
    );
    _nextDeadline = retained?.nextDeadlineAt ??
        (futureOccurrences.isEmpty
            ? existing?.nextDeadlineAt.isAfter(_now) == true
                ? existing?.nextDeadlineAt
                : null
            : futureOccurrences.first.deadlineAt);
    _sessionMinutes = retained?.preferredSessionMinutes ??
        existing?.preferredSessionMinutes ??
        50;
    _bufferDays = retained?.bufferDays ?? existing?.bufferDays ?? 1;
    _useCalendarAvailability = retained?.useCalendarAvailability ??
        existing?.useCalendarAvailability ??
        false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _countController.dispose();
    _totalHoursController.dispose();
    _totalMinutesController.dispose();
    _dailyCapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.baseRevision == 0
                ? 'Add weekly assignments'
                : 'Edit future assignments',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Step ${_step + 1} of 3'),
          const SizedBox(height: AppSpacing.lg),
          if (_step == 0) _identityStep(context),
          if (_step == 1) _workStep(context),
          if (_step == 2) _preferencesStep(context),
          const SizedBox(height: AppSpacing.lg),
          _navigation(context),
        ],
      ),
    );
  }

  Widget _identityStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Which assignment series?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        const ListTile(
          key: ValueKey('assignment-series-locked-kind'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(AppIcons.checkCircleOutline),
          title: Text('Assignment'),
          subtitle: Text('Already selected from Planner Add new.'),
        ),
        TextField(
          key: const ValueKey('assignment-series-title'),
          controller: _titleController,
          maxLength: 160,
          decoration: const InputDecoration(
            labelText: 'Shared assignment title',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('assignment-series-next-deadline'),
            onPressed: _pickDeadline,
            icon: const Icon(AppIcons.eventOutlined),
            label: Text(
              _nextDeadline == null
                  ? 'Choose next due date and device time'
                  : 'Next due ${DateFormat.yMMMd().add_Hm().format(_nextDeadline!.toLocal())} · device time',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'The backend keeps this local wall-clock time every seven days, including across daylight-saving changes.',
        ),
      ],
    );
  }

  Widget _workStep(BuildContext context) {
    final count = int.tryParse(_countController.text.trim());
    final end = count == null || count < 1 || _nextDeadline == null
        ? null
        : _nextDeadline!.add(Duration(days: 7 * (count - 1)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How many weeks and how much work?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const ValueKey('assignment-series-count'),
          controller: _countController,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: widget.baseRevision == 0
                ? 'Number of weekly assignments (2–20)'
                : 'Remaining weekly assignments (1–20)',
            helperText: '12 is the default for a typical semester.',
          ),
        ),
        if (end != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$count independent assignments · last due ${DateFormat.yMMMd().format(end)}',
            key: const ValueKey('assignment-series-end-summary'),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _DurationFields(
          prefix: 'assignment-series-estimate',
          hours: _totalHoursController,
          minutes: _totalMinutesController,
          label: 'Preparation estimate for each assignment',
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final hours in const [1, 2, 5])
              ActionChip(
                key: ValueKey('assignment-series-estimate-${hours}h'),
                label: Text('$hours h'),
                onPressed: () => setState(() {
                  _totalHoursController.text = '$hours';
                  _totalMinutesController.text = '0';
                }),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Every occurrence gets its own editable preparation plan. Preparation already completed on older occurrences is preserved.',
        ),
      ],
    );
  }

  Widget _preferencesStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Shared preparation rules',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'These values apply to every future occurrence. You can still edit one occurrence later; a later whole-series edit intentionally overwrites future deviations.',
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('Preferred focus block'),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<int>(
          direction: _choiceDirection(context),
          segments: const [
            ButtonSegment(value: 25, label: Text('25 min')),
            ButtonSegment(value: 50, label: Text('50 min')),
            ButtonSegment(value: 90, label: Text('90 min')),
          ],
          selected: {_sessionMinutes},
          onSelectionChanged: (values) =>
              setState(() => _sessionMinutes = values.single),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const ValueKey('assignment-series-daily-cap'),
          controller: _dailyCapController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Maximum preparation minutes per day per assignment',
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          !widget.accountDailyPreparationBudgetKnown
              ? 'The account-wide budget could not be read here. The backend still applies a saved budget.'
              : widget.accountDailyPreparationBudgetMinutes == null
                  ? 'No account-wide daily preparation budget is set.'
                  : 'Account-wide budget: ${_duration(widget.accountDailyPreparationBudgetMinutes!)} per day across all preparation plans.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<int>(
          initialValue: _bufferDays,
          decoration: const InputDecoration(
            labelText: 'Clear days before each due date',
          ),
          items: List.generate(
            8,
            (days) => DropdownMenuItem(
              value: days,
              child: Text('$days ${days == 1 ? 'clear day' : 'clear days'}'),
            ),
          ),
          onChanged: (value) {
            if (value != null) setState(() => _bufferDays = value);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(AppIcons.eventBusyOutlined),
          title: const Text('Imported busy times follow Planner'),
          subtitle: const Text(
            'The one read-only Planner calendar setting applies to every occurrence. External calendars are never changed.',
          ),
          trailing: const Icon(AppIcons.openInNewOutlined),
          onTap: () {
            Navigator.of(context).pop();
            widget.onOpenPlanner();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'Next, one staged series preview is created. Nothing is reserved until you confirm the whole series once.',
        ),
      ],
    );
  }

  Widget _navigation(BuildContext context) {
    final primary = FilledButton(
      key: ValueKey(
        _step == 2
            ? 'assignment-series-create-preview'
            : 'assignment-series-next',
      ),
      onPressed: _step == 2 ? _submit : _next,
      child: Text(_step == 2 ? 'Create series preview' : 'Continue'),
    );
    final secondary = TextButton(
      onPressed: _step == 0
          ? () => Navigator.of(context).pop()
          : () => setState(() => _step -= 1),
      child: Text(_step == 0 ? 'Cancel' : 'Back'),
    );
    if (_choiceDirection(context) == Axis.vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          const SizedBox(height: AppSpacing.sm),
          secondary,
        ],
      );
    }
    return Row(children: [secondary, const Spacer(), primary]);
  }

  void _next() {
    if (_step == 0) {
      if (_titleController.text.trim().isEmpty || _nextDeadline == null) {
        _showValidation('Enter a title and the next future due time.');
        return;
      }
      if (!_nextDeadline!.isAfter(_now)) {
        _showValidation('The next assignment due time must be in the future.');
        return;
      }
    } else if (_step == 1) {
      final count = int.tryParse(_countController.text.trim());
      final minimum = widget.baseRevision == 0 ? 2 : 1;
      final total = _totalMinutes;
      if (count == null || count < minimum || count > 20) {
        _showValidation(
          widget.baseRevision == 0
              ? 'Choose 2 to 20 weekly assignments.'
              : 'Choose 1 to 20 remaining weekly assignments.',
        );
        return;
      }
      if (total == null || total < 30 || total > 30000) {
        _showValidation(
          'Enter 30 minutes to 500 hours of preparation per assignment.',
        );
        return;
      }
      final last = _nextDeadline!.add(Duration(days: 7 * (count - 1)));
      if (last.difference(_now).inDays > 366) {
        _showValidation('The series must finish within the next 366 days.');
        return;
      }
    }
    setState(() => _step += 1);
  }

  Future<void> _pickDeadline() async {
    final now = _now;
    final lastDate = now.add(const Duration(days: 366));
    final initial =
        _nextDeadline?.toLocal() ?? now.add(const Duration(days: 7));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(lastDate) ? lastDate : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: lastDate,
      helpText: 'Next weekly assignment due date',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Weekly assignment due time',
    );
    if (time == null || !mounted) return;
    setState(() {
      _nextDeadline =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _submit() {
    final count = int.tryParse(_countController.text.trim());
    final total = _totalMinutes;
    final daily = int.tryParse(_dailyCapController.text.trim());
    if (count == null ||
        total == null ||
        daily == null ||
        _nextDeadline == null) {
      _showValidation('Review all required assignment series values.');
      return;
    }
    try {
      Navigator.of(context).pop(
        AssignmentSeriesProposalDraft(
          seriesId: widget.seriesId,
          baseRevision: widget.baseRevision,
          title: _titleController.text,
          nextDeadlineAt: _nextDeadline!,
          remainingOccurrences: count,
          estimatedTotalMinutes: total,
          preferredSessionMinutes: _sessionMinutes,
          maxDailyMinutes: daily,
          bufferDays: _bufferDays,
          useCalendarAvailability: _useCalendarAvailability,
        ),
      );
    } on AssignmentSeriesAccessException catch (error) {
      _showValidation(error.message);
    }
  }

  int? get _totalMinutes => _durationInput(
        _totalHoursController.text,
        _totalMinutesController.text,
      );

  void _showValidation(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _AssignmentSeriesCard extends StatelessWidget {
  const _AssignmentSeriesCard({
    super.key,
    required this.series,
    required this.plans,
    required this.expanded,
    required this.isBusy,
    required this.exactRetryLocked,
    required this.operationError,
    required this.onToggle,
    required this.onEditSeries,
    required this.onEditOccurrence,
    required this.onConfirm,
    required this.onCancelFuture,
    required this.onRetry,
    required this.onReload,
    required this.onDismissError,
  });

  final AssignmentSeries series;
  final Map<String, DeadlinePlan> plans;
  final bool expanded;
  final bool isBusy;
  final bool exactRetryLocked;
  final Object? operationError;
  final VoidCallback onToggle;
  final VoidCallback onEditSeries;
  final ValueChanged<DeadlinePlan> onEditOccurrence;
  final VoidCallback onConfirm;
  final VoidCallback onCancelFuture;
  final VoidCallback onRetry;
  final Future<void> Function() onReload;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    final revision = series.displayedRevision;
    final occurrences = revision?.occurrences ?? const [];
    final kept = occurrences
        .where((item) => item.action != AssignmentSeriesOccurrenceAction.cancel)
        .toList(growable: false);
    final removed = occurrences.length - kept.length;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    series.isCancelled
                        ? AppIcons.eventBusyOutlined
                        : AppIcons.eventRepeatOutlined,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          revision?.title ?? series.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          series.hasPendingPreview
                              ? '${revision?.remainingOccurrences ?? 0} future weekly assignments · preview'
                              : series.isCancelled
                                  ? 'Future assignments cancelled · history kept'
                                  : '${kept.length} assignment occurrences · confirmed',
                        ),
                      ],
                    ),
                  ),
                  Icon(expanded ? AppIcons.expandLess : AppIcons.expandMore),
                ],
              ),
            ),
          ),
          if (expanded && revision != null) ...[
            const Divider(),
            Text(
              '${_duration(revision.estimatedTotalMinutes)} preparation per assignment · '
              '${_duration(revision.preferredSessionMinutes)} blocks · '
              '${revision.bufferDays} ${revision.bufferDays == 1 ? 'clear day' : 'clear days'}',
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${_duration(revision.plannedMinutes)} staged across future occurrences'
              '${revision.unscheduledMinutes > 0 ? ' · ${_duration(revision.unscheduledMinutes)} could not be placed' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (removed > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$removed future ${removed == 1 ? 'occurrence is' : 'occurrences are'} removed by this preview.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            for (final occurrence in occurrences)
              _AssignmentOccurrenceRow(
                occurrence: occurrence,
                plan: plans[occurrence.planId],
                enabled: !isBusy && !exactRetryLocked,
                onEdit: onEditOccurrence,
              ),
            if (operationError != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'The whole-series operation was not completed. No partial confirmation was kept.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (exactRetryLocked)
                    OutlinedButton(
                      onPressed: isBusy ? null : onRetry,
                      child: const Text('Retry unchanged'),
                    )
                  else
                    OutlinedButton(
                      onPressed: isBusy ? null : onReload,
                      child: const Text('Reload series'),
                    ),
                  if (!exactRetryLocked)
                    TextButton(
                      onPressed: isBusy ? null : onDismissError,
                      child: const Text('Dismiss'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (!series.isCancelled)
                  OutlinedButton.icon(
                    key: const ValueKey('assignment-series-edit-future'),
                    onPressed: isBusy || exactRetryLocked ? null : onEditSeries,
                    icon: const Icon(AppIcons.editOutlined),
                    label: const Text('Edit all future'),
                  ),
                if (series.hasPendingPreview)
                  FilledButton.icon(
                    key: const ValueKey('assignment-series-confirm-preview'),
                    onPressed: isBusy || exactRetryLocked ? null : onConfirm,
                    icon: const Icon(AppIcons.checkCircleOutline),
                    label: const Text('Confirm whole series'),
                  ),
                if (!series.isCancelled)
                  TextButton.icon(
                    key: const ValueKey('assignment-series-cancel-future'),
                    onPressed:
                        isBusy || exactRetryLocked ? null : onCancelFuture,
                    icon: const Icon(AppIcons.eventBusyOutlined),
                    label: const Text('Cancel future'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AssignmentOccurrenceRow extends StatelessWidget {
  const _AssignmentOccurrenceRow({
    required this.occurrence,
    required this.plan,
    required this.enabled,
    required this.onEdit,
  });

  final AssignmentSeriesOccurrence occurrence;
  final DeadlinePlan? plan;
  final bool enabled;
  final ValueChanged<DeadlinePlan> onEdit;

  @override
  Widget build(BuildContext context) {
    final removed =
        occurrence.action == AssignmentSeriesOccurrenceAction.cancel;
    final status = removed
        ? 'Will be removed when confirmed'
        : plan == null
            ? 'Loading independent plan…'
            : switch (plan!.status) {
                DeadlinePlanStatus.draft => 'Preview',
                DeadlinePlanStatus.active => 'Confirmed',
                DeadlinePlanStatus.completed => 'Completed',
                DeadlinePlanStatus.cancelled => 'Cancelled',
              };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            removed
                ? AppIcons.removeCircleOutline
                : AppIcons.assignmentOutlined,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Week ${occurrence.position} · ${DateFormat.yMMMd().add_Hm().format(occurrence.deadlineAt.toLocal())}',
                ),
                Text(status, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (!removed && plan != null && !plan!.isTerminal)
            TextButton(
              onPressed: enabled ? () => onEdit(plan!) : null,
              child: const Text('Edit one'),
            ),
        ],
      ),
    );
  }
}
