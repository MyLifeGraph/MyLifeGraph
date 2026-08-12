part of '../pages/deadline_plans_page.dart';

enum _DeadlineReplanContext { general, workload, missed }

class _DeadlinePlanEditorSheet extends StatefulWidget {
  const _DeadlinePlanEditorSheet({
    required this.planId,
    required this.baseRevision,
    required this.existing,
    required this.trackedFocusMinutes,
    required this.accountDailyPreparationBudgetKnown,
    required this.accountDailyPreparationBudgetMinutes,
    required this.retainedDraft,
    required this.initialKind,
    required this.lockKind,
    required this.initialTitle,
    required this.initialDeadlineAt,
    required this.initialDeadlineOn,
    required this.sourceKind,
    required this.sourceCalendarEventId,
    required this.sourceCalendarEventFingerprint,
    required this.initialSourceStatus,
    required this.startWithExistingSummary,
    required this.replanContext,
    required this.currentTime,
    required this.profileToday,
    required this.onOpenPlanner,
  });

  final String planId;
  final int baseRevision;
  final DeadlinePlanRevision? existing;
  final int trackedFocusMinutes;
  final bool accountDailyPreparationBudgetKnown;
  final int? accountDailyPreparationBudgetMinutes;
  final DeadlinePlanProposalDraft? retainedDraft;
  final DeadlinePlanKind? initialKind;
  final bool lockKind;
  final String? initialTitle;
  final DateTime? initialDeadlineAt;
  final String? initialDeadlineOn;
  final DeadlinePlanSourceKind sourceKind;
  final String? sourceCalendarEventId;
  final String? sourceCalendarEventFingerprint;
  final DeadlinePlanSourceStatus initialSourceStatus;
  final bool startWithExistingSummary;
  final _DeadlineReplanContext replanContext;
  final DateTime? currentTime;
  final DateTime profileToday;
  final VoidCallback onOpenPlanner;

  @override
  State<_DeadlinePlanEditorSheet> createState() =>
      _DeadlinePlanEditorSheetState();
}

class _DeadlinePlanEditorSheetState extends State<_DeadlinePlanEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _totalHoursController;
  late final TextEditingController _totalMinutesController;
  late final TextEditingController _dailyCapController;
  late final int _creditedPriorMinutes;
  DeadlinePlanKind? _kind;
  DateTime? _deadline;
  DateTime? _deadlineDateHint;
  int _step = 0;
  int _sessionMinutes = 50;
  int _bufferDays = 1;
  late DateTime _planningStart;
  late DeadlinePlanSourceKind _sourceKind;
  late bool _showExistingSummary;
  bool _useCalendarAvailability = false;
  bool _dailyCapWasManuallyEdited = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final retained = widget.retainedDraft;
    _titleController = TextEditingController(
      text: retained?.title ?? existing?.title ?? widget.initialTitle ?? '',
    );
    final total =
        retained?.estimatedTotalMinutes ?? existing?.estimatedTotalMinutes;
    _totalHoursController = TextEditingController(
      text: total == null ? '' : '${total ~/ 60}',
    );
    _totalMinutesController = TextEditingController(
      text: total == null ? '' : '${total % 60}',
    );
    _creditedPriorMinutes =
        retained?.creditedPriorMinutes ?? existing?.creditedPriorMinutes ?? 0;
    _kind = widget.lockKind
        ? widget.initialKind
        : retained?.kind ?? existing?.kind ?? widget.initialKind;
    _dailyCapController = TextEditingController(
      text:
          '${retained?.maxDailyMinutes ?? existing?.maxDailyMinutes ?? defaultDeadlinePlanDailyPreparationMinutes(_kind)}',
    );
    _dailyCapWasManuallyEdited = retained != null || existing != null;
    _deadline = retained?.deadlineAt ??
        existing?.deadlineAt ??
        widget.initialDeadlineAt;
    _deadlineDateHint = _deadline == null
        ? DateTime.tryParse(widget.initialDeadlineOn ?? '')
        : null;
    _sessionMinutes = retained?.preferredSessionMinutes ??
        existing?.preferredSessionMinutes ??
        50;
    _bufferDays = retained?.bufferDays ?? existing?.bufferDays ?? 1;
    final now = _now;
    final localDeadline = _deadline?.toLocal();
    if (retained == null &&
        existing == null &&
        localDeadline != null &&
        localDeadline.year == now.year &&
        localDeadline.month == now.month &&
        localDeadline.day == now.day) {
      _bufferDays = 0;
    }
    _sourceKind = widget.sourceKind;
    _showExistingSummary = widget.startWithExistingSummary;
    final today = widget.profileToday;
    final savedPlanningStart = DateTime.tryParse(
      retained?.planningStartOn ?? existing?.planningStartOn ?? '',
    );
    final requestedPlanningStart = savedPlanningStart == null
        ? today
        : DateTime(
            savedPlanningStart.year,
            savedPlanningStart.month,
            savedPlanningStart.day,
          );
    _planningStart =
        requestedPlanningStart.isBefore(today) ? today : requestedPlanningStart;
    _useCalendarAvailability = retained?.useCalendarAvailability ??
        existing?.useCalendarAvailability ??
        false;
  }

  DateTime get _now => widget.currentTime ?? DateTime.now();

  @override
  void dispose() {
    _titleController.dispose();
    _totalHoursController.dispose();
    _totalMinutesController.dispose();
    _dailyCapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showExistingSummary) {
      return _buildExistingSummary(context);
    }
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
            widget.existing == null
                ? 'Plan preparation'
                : 'Adjust preparation plan',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Step ${_step + 1} of 3'),
          const SizedBox(height: AppSpacing.lg),
          if (_step == 0) _buildIdentityStep(context),
          if (_step == 1) _buildEstimateStep(context),
          if (_step == 2) _buildPreferencesStep(context),
          const SizedBox(height: AppSpacing.lg),
          _buildNavigation(context),
        ],
      ),
    );
  }

  Widget _buildExistingSummary(BuildContext context) {
    final revision = widget.existing!;
    final total = revision.estimatedTotalMinutes;
    final prior = revision.creditedPriorMinutes;
    final tracked = widget.trackedFocusMinutes;
    final remaining = (total - prior - tracked).clamp(0, total).toInt();
    final sourceCurrent =
        revision.sourceKind == DeadlinePlanSourceKind.manual ||
            revision.sourceStatus == DeadlinePlanSourceStatus.current;
    final deadlineFuture = revision.deadlineAt.isAfter(_now);
    final canCreatePreview = sourceCurrent && deadlineFuture;
    final contextCopy = switch (widget.replanContext) {
      _DeadlineReplanContext.workload =>
        'You opened this from a daily workload that needs review. A fresh preview applies the current account budget again.',
      _DeadlineReplanContext.missed =>
        'This plan has missed, uncredited preparation. A fresh preview starts no earlier than today, while completed linked Focus remains counted.',
      _DeadlineReplanContext.general => null,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Replan remaining preparation',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Review the saved values below. You only need the full editor when one of them should change.',
          ),
          if (contextCopy != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(contextCopy),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(revision.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${revision.kind == DeadlinePlanKind.exam ? 'Exam' : 'Assignment'} · '
            'finish by ${DateFormat.yMMMd().add_Hm().format(revision.deadlineAt.toLocal())} · device time',
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _ProgressValue(label: 'Estimate', value: _duration(total)),
              _ProgressValue(
                label: 'Tracked focus',
                value: _duration(tracked),
              ),
              _ProgressValue(
                label: 'Remaining',
                value: _duration(remaining),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            revision.recoveryMinutes > 0
                ? '${_duration(revision.preferredSessionMinutes)} focus + '
                    '${_duration(revision.recoveryMinutes)} recovery · '
                    'reserved through ${DateFormat.Hm().format(revision.blocks.isEmpty ? revision.deadlineAt.toLocal() : revision.blocks.first.reservedEndsAt.toLocal())} for the first block'
                : '${_duration(revision.preferredSessionMinutes)} preferred blocks · '
                    '${_duration(revision.maxDailyMinutes)} maximum per day · '
                    '${revision.bufferDays} ${revision.bufferDays == 1 ? 'clear day' : 'clear days'}',
          ),
          Text(
            'Plan from ${DateFormat.yMMMd().format(_planningStart)} · '
            '${revision.useCalendarAvailability ? 'use latest imported busy times' : 'do not use imported busy times'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            !widget.accountDailyPreparationBudgetKnown
                ? 'Your account-wide budget is temporarily unavailable here. Any saved total budget still limits confirmed plans.'
                : widget.accountDailyPreparationBudgetMinutes == null
                    ? 'No account-wide daily preparation budget is set.'
                    : 'Current account-wide budget: ${_duration(widget.accountDailyPreparationBudgetMinutes!)} per day.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!sourceCurrent) ...[
            const SizedBox(height: AppSpacing.md),
            const Text(
              'The imported source changed or became unavailable. Change values and review the source before creating another preview.',
            ),
          ] else if (!deadlineFuture) ...[
            const SizedBox(height: AppSpacing.md),
            const Text(
              'The saved finish-by time has passed. Change values before creating another preview.',
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'Creating a preview stores a staged replacement. Your current reservations stay active until you confirm it. Nothing changes automatically.',
          ),
          const AppInfoSectionDisclosure(
            heading: 'How the preview is calculated',
            description:
                'MyLifeGraph uses fixed planning rules and your saved availability.',
            compactHeading: true,
            keyPrefix: 'deadline-plan-info',
          ),
          const SizedBox(height: AppSpacing.md),
          _buildExistingSummaryActions(context, canCreatePreview),
        ],
      ),
    );
  }

  Widget _buildExistingSummaryActions(
    BuildContext context,
    bool canCreatePreview,
  ) {
    final create = FilledButton.icon(
      key: const ValueKey('deadline-create-preview-existing'),
      onPressed: canCreatePreview ? _submit : null,
      icon: const Icon(AppIcons.eventRepeatOutlined),
      label: const Text('Create preview with these values'),
    );
    final change = OutlinedButton(
      key: const ValueKey('deadline-change-existing-values'),
      onPressed: () => setState(() => _showExistingSummary = false),
      child: const Text('Change values'),
    );
    final cancel = TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Cancel'),
    );
    if (_choiceDirection(context) == Axis.vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          create,
          const SizedBox(height: AppSpacing.sm),
          change,
          const SizedBox(height: AppSpacing.xs),
          cancel,
        ],
      );
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [create, change, cancel],
    );
  }

  Widget _buildNavigation(BuildContext context) {
    final secondary = TextButton(
      onPressed: _step == 0
          ? () => Navigator.of(context).pop()
          : () => setState(() => _step -= 1),
      child: Text(_step == 0 ? 'Cancel' : 'Back'),
    );
    final primary = FilledButton(
      onPressed: _step == 2 ? _submit : _next,
      child: Text(_step == 2 ? 'Create preview' : 'Continue'),
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

    return Row(
      children: [
        secondary,
        const Spacer(),
        primary,
      ],
    );
  }

  Widget _buildIdentityStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What are you preparing for?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Choose this yourself. MyLifeGraph never infers an exam or assignment from a calendar title.',
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'You enter the finish time in this device\'s timezone. The preview places blocks in the profile timezone saved in Settings.',
        ),
        const SizedBox(height: AppSpacing.md),
        if (widget.lockKind && _kind != null)
          ListTile(
            key: const ValueKey('deadline-locked-kind'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(AppIcons.checkCircleOutline),
            title: Text(
              _kind == DeadlinePlanKind.exam ? 'Exam' : 'Assignment',
            ),
            subtitle: const Text(
              'Already selected for this preparation plan.',
            ),
          )
        else
          SegmentedButton<DeadlinePlanKind>(
            direction: _choiceDirection(context),
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: DeadlinePlanKind.exam, label: Text('Exam')),
              ButtonSegment(
                value: DeadlinePlanKind.assignment,
                label: Text('Assignment'),
              ),
            ],
            selected: _kind == null ? const {} : {_kind!},
            onSelectionChanged: (values) {
              setState(() {
                _kind = values.isEmpty ? null : values.single;
                if (!_dailyCapWasManuallyEdited && _kind != null) {
                  _dailyCapController.text =
                      '${defaultDeadlinePlanDailyPreparationMinutes(_kind)}';
                }
              });
            },
          ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const ValueKey('deadline-plan-title'),
          controller: _titleController,
          maxLength: 160,
          decoration:
              const InputDecoration(labelText: 'Exam or assignment title'),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _pickDeadline,
            icon: const Icon(AppIcons.eventOutlined),
            label: Text(
              _deadline == null
                  ? _deadlineDateHint == null
                      ? 'Choose finish-by date and device time'
                      : 'Choose finish-by device time for ${DateFormat.yMMMd().format(_deadlineDateHint!)}'
                  : 'Finish by ${DateFormat.yMMMd().add_Hm().format(_deadline!.toLocal())} · device time',
            ),
          ),
        ),
        if (widget.sourceKind == DeadlinePlanSourceKind.calendarEvent) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Imported event details are prefilled for review only. The source stays read-only.',
          ),
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            key: const ValueKey('deadline-keep-calendar-source'),
            contentPadding: EdgeInsets.zero,
            value: _sourceKind == DeadlinePlanSourceKind.calendarEvent,
            onChanged: (value) {
              setState(() {
                _sourceKind = value
                    ? DeadlinePlanSourceKind.calendarEvent
                    : DeadlinePlanSourceKind.manual;
                if (!value &&
                    widget.initialSourceStatus ==
                        DeadlinePlanSourceStatus.unavailable) {
                  _useCalendarAvailability = false;
                }
              });
            },
            title: const Text('Keep this imported event linked'),
            subtitle: Text(
              widget.initialSourceStatus == DeadlinePlanSourceStatus.stale ||
                      widget.initialSourceStatus ==
                          DeadlinePlanSourceStatus.unavailable
                  ? 'The imported source changed. Turn this off to keep your reviewed title and deadline as a manual plan.'
                  : 'Turn this off if you want the reviewed title and deadline to become a manual plan.',
            ),
          ),
          if (_sourceKind == DeadlinePlanSourceKind.manual)
            const Text(
              'The next preview will no longer depend on the imported event. The event itself is never changed.',
            ),
        ],
      ],
    );
  }

  Widget _buildEstimateStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your preparation estimate',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'How much active preparation time do you think you will need in total? Count focused work, not breaks or classes.',
        ),
        const SizedBox(height: AppSpacing.md),
        _DurationFields(
          prefix: 'deadline-total',
          hours: _totalHoursController,
          minutes: _totalMinutesController,
          label: 'Total active preparation',
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final hours in const [2, 5, 10])
              ActionChip(
                key: ValueKey('deadline-estimate-${hours}h'),
                label: Text('$hours h'),
                onPressed: () {
                  setState(() {
                    _totalHoursController.text = '$hours';
                    _totalMinutesController.text = '0';
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'MyLifeGraph cannot estimate this for you. One transparent approach is topics × sessions per topic × minutes per session; these chips are only optional shortcuts.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_totalMinutes != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            '${_duration(_totalMinutes!)} total · ${_duration(widget.trackedFocusMinutes)} linked Focus · ${_duration((_totalMinutes! - _creditedPriorMinutes - widget.trackedFocusMinutes).clamp(0, _totalMinutes!).toInt())} to schedule',
            key: const ValueKey('deadline-estimate-summary'),
          ),
        ],
      ],
    );
  }

  Widget _buildPreferencesStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How should we split it?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'These controls are optional. You can adjust them before confirming any reservations.',
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
          key: const ValueKey('deadline-daily-cap'),
          controller: _dailyCapController,
          keyboardType: TextInputType.number,
          onChanged: (_) => _dailyCapWasManuallyEdited = true,
          decoration: const InputDecoration(
            labelText: 'Maximum preparation minutes per day for this plan',
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          !widget.accountDailyPreparationBudgetKnown
              ? 'Your account-wide budget is temporarily unavailable here. Any saved total budget still limits confirmed plans.'
              : widget.accountDailyPreparationBudgetMinutes == null
                  ? 'No account-wide budget is set. Only this plan cap applies; you can add a total daily limit in Settings.'
                  : 'Account-wide budget: ${_duration(widget.accountDailyPreparationBudgetMinutes!)} per day. Confirmed blocks from other plans are deducted before this plan is placed.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<int>(
          initialValue: _bufferDays,
          decoration: const InputDecoration(
            labelText: 'Clear days before finish-by date',
          ),
          items: List.generate(
            8,
            (days) => DropdownMenuItem(
              value: days,
              child: Text(
                '$days ${days == 1 ? 'clear day' : 'clear days'}',
              ),
            ),
          ),
          onChanged: (value) {
            if (value != null) setState(() => _bufferDays = value);
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'A clear day receives no preparation blocks. With 0 clear days, the finish-by day may still be used.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: _pickPlanningStart,
          icon: const Icon(AppIcons.todayOutlined),
          label: Text(
            'Start planning ${DateFormat.yMMMd().format(_planningStart)}',
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'When replanning, a saved start in the past moves to today.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(AppIcons.eventBusyOutlined),
          title: const Text('Imported busy times follow Planner'),
          subtitle: const Text(
            'Uses Planner\'s read-only imported busy-time setting. Change it in Planner before creating this preview, and re-import after calendar changes; there is no background sync.',
          ),
          trailing: const Icon(AppIcons.openInNewOutlined),
          onTap: () {
            Navigator.of(context).pop();
            widget.onOpenPlanner();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'Next, MyLifeGraph creates a staged preview. Nothing is reserved until you confirm it.',
        ),
      ],
    );
  }

  void _next() {
    if (_step == 0) {
      if (_kind == null ||
          _titleController.text.trim().isEmpty ||
          _deadline == null) {
        _showValidation('Choose a type, title, and future finish-by time.');
        return;
      }
      if (!_deadline!.isAfter(_now)) {
        _showValidation('The finish-by time must be in the future.');
        return;
      }
      if (_deadline!.difference(_now).inDays > 366) {
        _showValidation('Choose a finish-by time within the next 366 days.');
        return;
      }
    }
    if (_step == 1) {
      final total = _totalMinutes;
      if (total == null || total < 30 || total > 30000) {
        _showValidation('Enter 30 minutes to 500 hours of total preparation.');
        return;
      }
      if (_creditedPriorMinutes >= total) {
        _showValidation(
          'The estimate must remain above already accounted preparation.',
        );
        return;
      }
    }
    setState(() => _step += 1);
  }

  Future<void> _pickDeadline() async {
    final now = _now;
    final lastDate = now.add(const Duration(days: 366));
    final dateHint = _deadlineDateHint;
    final requestedInitial = _deadline?.toLocal() ??
        (dateHint == null
            ? now.add(const Duration(days: 7))
            : DateTime(
                dateHint.year,
                dateHint.month,
                dateHint.day,
                now.hour,
                now.minute,
              ));
    final initial = requestedInitial.isAfter(lastDate)
        ? lastDate
        : requestedInitial.isBefore(now)
            ? now
            : requestedInitial;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: lastDate,
      helpText: 'Preparation finish-by date',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Preparation finish-by time',
    );
    if (time == null || !mounted) return;
    setState(() {
      _deadline =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _deadlineDateHint = null;
      if (widget.existing == null &&
          widget.retainedDraft == null &&
          date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        _bufferDays = 0;
      }
    });
  }

  Future<void> _pickPlanningStart() async {
    final now = _now;
    final today = widget.profileToday;
    final deadlineDate = _deadline?.toLocal();
    final lastDate = deadlineDate == null
        ? now.add(const Duration(days: 365))
        : DateTime(deadlineDate.year, deadlineDate.month, deadlineDate.day);
    final firstDate = today;
    final initialDate = _planningStart.isAfter(lastDate)
        ? lastDate
        : _planningStart.isBefore(firstDate)
            ? firstDate
            : _planningStart;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Preparation planning start',
    );
    if (selected != null && mounted) setState(() => _planningStart = selected);
  }

  void _submit() {
    final total = _totalMinutes;
    final dailyCap = int.tryParse(_dailyCapController.text.trim());
    if (total == null ||
        dailyCap == null ||
        _kind == null ||
        _deadline == null) {
      _showValidation('Review all required plan values.');
      return;
    }
    if (!_deadline!.isAfter(_now)) {
      _showValidation('The finish-by time must be in the future.');
      return;
    }
    if (_deadline!.difference(_now).inDays > 366) {
      _showValidation('Choose a finish-by time within the next 366 days.');
      return;
    }
    final deadlineDate = DateTime(
      _deadline!.year,
      _deadline!.month,
      _deadline!.day,
    );
    final startDate = DateTime(
      _planningStart.year,
      _planningStart.month,
      _planningStart.day,
    );
    final horizonDays = deadlineDate.difference(startDate).inDays;
    if (horizonDays < 0 || horizonDays > 366) {
      _showValidation(
        'Planning must start no later than the deadline date and span at most 366 days.',
      );
      return;
    }
    try {
      Navigator.of(context).pop(
        DeadlinePlanProposalDraft(
          planId: widget.planId,
          baseRevision: widget.baseRevision,
          kind: _kind!,
          title: _titleController.text,
          deadlineAt: _deadline!,
          estimatedTotalMinutes: total,
          creditedPriorMinutes: _creditedPriorMinutes,
          preferredSessionMinutes: _sessionMinutes,
          maxDailyMinutes: dailyCap,
          planningStartOn: localDateKey(_planningStart),
          bufferDays: _bufferDays,
          sourceKind: _sourceKind,
          sourceCalendarEventId:
              _sourceKind == DeadlinePlanSourceKind.calendarEvent
                  ? widget.sourceCalendarEventId
                  : null,
          sourceCalendarEventFingerprint:
              _sourceKind == DeadlinePlanSourceKind.calendarEvent
                  ? widget.sourceCalendarEventFingerprint
                  : null,
          useCalendarAvailability: _useCalendarAvailability,
        ),
      );
    } on DeadlinePlanAccessException catch (error) {
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
