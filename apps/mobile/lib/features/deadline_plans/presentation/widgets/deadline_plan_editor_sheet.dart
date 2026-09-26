part of '../pages/deadline_plans_page.dart';

enum _DeadlineReplanContext { general, workload, missed }

class _PreparationSessionPicker extends StatefulWidget {
  const _PreparationSessionPicker({
    required this.minutes,
    required this.onChanged,
  });

  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  State<_PreparationSessionPicker> createState() =>
      _PreparationSessionPickerState();
}

class _PreparationSessionPickerState extends State<_PreparationSessionPicker> {
  static const _presets = [25, 50, 90];
  late bool _custom = !_presets.contains(widget.minutes);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Focus block'),
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final minutes in _presets)
            ChoiceChip(
              label: Text('$minutes min'),
              showCheckmark: false,
              selected: !_custom && widget.minutes == minutes,
              onSelected: (_) {
                setState(() => _custom = false);
                widget.onChanged(minutes);
              },
            ),
          ChoiceChip(
            key: const ValueKey('preparation-session-custom'),
            label: const Text('Custom'),
            showCheckmark: false,
            selected: _custom,
            onSelected: (_) => setState(() => _custom = true),
          ),
        ],
      ),
      if (_custom) ...[
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          key: const ValueKey('preparation-session-minutes'),
          initialValue: '${widget.minutes}',
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Focus block (minutes)',
            helperText: '25–180 minutes',
          ),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (value) {
            final minutes = int.tryParse(value?.trim() ?? '');
            return minutes == null || minutes < 25 || minutes > 180
                ? 'Enter 25–180 minutes.'
                : null;
          },
          onChanged: (value) =>
              widget.onChanged(int.tryParse(value.trim()) ?? 0),
        ),
      ],
    ],
  );
}

class _DeadlinePlanEditorSheet extends StatefulWidget {
  const _DeadlinePlanEditorSheet({
    this.startingAgain = false,
    this.remainingMinutes,
    required this.planId,
    required this.baseRevision,
    required this.healthPlanId,
    required this.healthBaseRevision,
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
    required this.profileTimezone,
    required this.savedExamHealth,
    required this.onOpenPlanner,
    required this.onPreviewHealth,
  });

  final String planId;
  final bool startingAgain;
  final int? remainingMinutes;
  final int baseRevision;
  final String? healthPlanId;
  final int? healthBaseRevision;
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
  final String profileTimezone;
  final ExamPlanHealthItem? savedExamHealth;
  final VoidCallback onOpenPlanner;
  final Future<ExamPlanHealthPreview> Function(ExamPlanHealthPreviewDraft draft)
  onPreviewHealth;

  @override
  State<_DeadlinePlanEditorSheet> createState() =>
      _DeadlinePlanEditorSheetState();
}

class _DeadlinePlanEditorSheetState extends State<_DeadlinePlanEditorSheet> {
  final ScrollController _wizardScrollController = ScrollController();
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
  bool _healthPreviewLoading = false;
  ExamPlanHealthPreview? _healthPreview;
  Object? _healthPreviewError;
  int _healthPreviewGeneration = 0;
  late bool _savedHealthStillMatches;
  bool _planOptionsExpanded = false;

  bool get _guidedCalendar =>
      widget.existing == null &&
      widget.sourceKind == DeadlinePlanSourceKind.calendarEvent;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final retained = widget.retainedDraft;
    _titleController = TextEditingController(
      text: retained?.title ?? existing?.title ?? widget.initialTitle ?? '',
    );
    final total =
        retained?.estimatedTotalMinutes ??
        (widget.startingAgain
            ? ((widget.remainingMinutes ?? 0) >= 30
                  ? widget.remainingMinutes
                  : null)
            : existing?.estimatedTotalMinutes);
    _totalHoursController = TextEditingController(
      text: total == null ? '' : '${total ~/ 60}',
    );
    _totalMinutesController = TextEditingController(
      text: total == null ? '' : '${total % 60}',
    );
    _creditedPriorMinutes =
        retained?.creditedPriorMinutes ??
        (widget.startingAgain ? 0 : existing?.creditedPriorMinutes ?? 0);
    _kind = widget.lockKind
        ? widget.initialKind
        : retained?.kind ?? existing?.kind ?? widget.initialKind;
    _dailyCapController = TextEditingController(
      text:
          '${retained?.maxDailyMinutes ?? existing?.maxDailyMinutes ?? defaultDeadlinePlanDailyPreparationMinutes(_kind)}',
    );
    _dailyCapWasManuallyEdited = retained != null || existing != null;
    _deadline =
        retained?.deadlineAt ??
        existing?.deadlineAt ??
        widget.initialDeadlineAt;
    _deadlineDateHint = _deadline == null
        ? DateTime.tryParse(widget.initialDeadlineOn ?? '')
        : null;
    _sessionMinutes =
        retained?.preferredSessionMinutes ??
        existing?.preferredSessionMinutes ??
        50;
    _bufferDays = retained?.bufferDays ?? existing?.bufferDays ?? 1;
    final now = _profileLocal(_now);
    final localDeadline = _deadline == null ? null : _profileLocal(_deadline!);
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
    _savedHealthStillMatches = widget.savedExamHealth != null;
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
    _planningStart = requestedPlanningStart.isBefore(today)
        ? today
        : requestedPlanningStart;
    _useCalendarAvailability =
        retained?.useCalendarAvailability ??
        existing?.useCalendarAvailability ??
        false;
  }

  DateTime get _now => widget.currentTime ?? DateTime.now();

  DateTime _profileLocal(DateTime instant) =>
      profileDateTimeAt(instant: instant, timezoneName: widget.profileTimezone);

  @override
  void dispose() {
    _wizardScrollController.dispose();
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
      controller: _wizardScrollController,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(
                _step == 1 ? 'Study time'
                    : _step == 2 ? 'Study rhythm'
                    : widget.existing != null ? 'Edit plan'
                    : widget.lockKind && _kind == DeadlinePlanKind.exam
                        ? 'New exam' : 'Plan study time',
                style: Theme.of(context).textTheme.titleLarge,
                key: const ValueKey('deadline-editor-heading'),
              )),
              const SizedBox(width: AppSpacing.sm),
              Text('${_step + 1} / 3'),
            ],
          ),
          if (_kind == DeadlinePlanKind.exam &&
              _savedHealthStillMatches &&
              widget.savedExamHealth != null) ...[
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Current saved Exam values',
              key: ValueKey('saved-exam-health-editor'),
            ),
            const SizedBox(height: AppSpacing.sm),
            _SavedExamHealthSummary(exam: widget.savedExamHealth!),
          ],
          const SizedBox(height: AppSpacing.md),
          if (_step == 0) _buildIdentityStep(context),
          if (_step == 1) ...[
            _buildEstimateStep(context),
            if (_guidedCalendar) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                !widget.accountDailyPreparationBudgetKnown
                    ? 'Your total daily budget is unavailable here. Any saved limit still applies.'
                    : widget.accountDailyPreparationBudgetMinutes == null
                    ? 'No total daily limit set in Settings.'
                    : 'Total daily budget: ${_duration(widget.accountDailyPreparationBudgetMinutes!)} across all plans.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              ExpansionTile(
                key: const ValueKey('deadline-adjust-plan'),
                tilePadding: EdgeInsets.zero,
                maintainState: true,
                title: const Text('Adjust plan'),
                subtitle: const Text(
                  'Optional · daily limit, sessions and timing',
                ),
                onExpansionChanged: (expanded) =>
                    setState(() => _planOptionsExpanded = expanded),
                children: [_buildPreferencesStep(context)],
              ),
              if (!_planOptionsExpanded) ...[
                if (_healthPreviewError != null)
                  const Text(
                    'The capacity check could not be loaded. Open Adjust plan to retry.',
                  ),
                if (_healthPreview != null)
                  _ExamPlanHealthPreviewView(exam: _healthPreview!.exam),
              ],
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Next: review suggested study sessions. Confirm only when ready.',
              ),
            ],
          ],
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
        'Daily workload needs review. A new preview reapplies your current account budget.',
      _DeadlineReplanContext.missed =>
        'Missed preparation remains. The preview starts today or later; completed linked Focus still counts.',
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
          const Text('Review saved values; use Change values to edit.'),
          if (contextCopy != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(contextCopy),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(revision.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${revision.kind == DeadlinePlanKind.exam ? 'Exam' : 'Assignment'} · '
            'finish by ${DateFormat.yMMMd().add_Hm().format(_profileLocal(revision.deadlineAt))} · ${widget.profileTimezone}',
          ),
          if (revision.kind == DeadlinePlanKind.exam &&
              widget.savedExamHealth != null) ...[
            const SizedBox(height: AppSpacing.md),
            const Text('Saved Exam status'),
            const SizedBox(height: AppSpacing.sm),
            _SavedExamHealthSummary(exam: widget.savedExamHealth!),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _ProgressValue(label: 'Estimate', value: _duration(total)),
              _ProgressValue(label: 'Tracked focus', value: _duration(tracked)),
              _ProgressValue(label: 'Remaining', value: _duration(remaining)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _ProgressValue(
                label: 'Preferred blocks',
                value: _duration(revision.preferredSessionMinutes),
              ),
              _ProgressValue(
                label: 'Daily maximum',
                value: _duration(revision.maxDailyMinutes),
              ),
              _ProgressValue(
                label: revision.bufferDays == 1 ? 'Clear day' : 'Clear days',
                value: '${revision.bufferDays}',
              ),
            ],
          ),
          if (revision.recoveryMinutes > 0)
            Text(
              '${_duration(revision.recoveryMinutes)} recovery · first block reserved until '
              '${DateFormat.Hm().format(_profileLocal(revision.blocks.isEmpty ? revision.deadlineAt : revision.blocks.first.reservedEndsAt))} ${widget.profileTimezone}',
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Plan from ${DateFormat.yMMMd().format(_planningStart)} · '
            '${revision.useCalendarAvailability ? 'Latest imported busy times: used' : 'Imported busy times: not used'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            !widget.accountDailyPreparationBudgetKnown
                ? 'Account daily budget unavailable; any saved limit still applies to confirmed plans.'
                : widget.accountDailyPreparationBudgetMinutes == null
                ? 'Account daily budget: not set.'
                : 'Account daily budget: ${_duration(widget.accountDailyPreparationBudgetMinutes!)}.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!sourceCurrent) ...[
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Imported source changed or unavailable. Change values and review the source before previewing.',
            ),
          ] else if (!deadlineFuture) ...[
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Finish-by time has passed. Change values before previewing.',
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'Preview saves a draft replacement. Current reservations stay active until you confirm; no automatic changes.',
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
          : () {
              setState(() => _step -= 1);
              _wizardScrollController.jumpTo(0);
            },
      child: Text(_step == 0 ? 'Cancel' : 'Back'),
    );
    final primary = FilledButton(
      onPressed: _step == 2 ? _submit : _next,
      child: Text(
        _step == 2 || _guidedCalendar && _step == 1
            ? 'Create preview'
            : 'Continue',
      ),
    );

    if (MediaQuery.textScalerOf(context).scale(16) >= 28) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          const SizedBox(height: AppSpacing.sm),
          secondary,
        ],
      );
    }

    return Row(children: [
      Expanded(child: secondary),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: primary),
    ]);
  }

  Widget _buildIdentityStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_guidedCalendar && !widget.lockKind)
          const AppInfoSectionDisclosure(
            heading: 'What are you preparing for?',
            compactHeading: true,
            keyPrefix: 'deadline-identity-info',
            description:
                'Choose exam or assignment yourself; calendar titles are not classified automatically. Finish-by times use your profile timezone, even on another device. Review the preview before reserving study sessions.',
          ),
        if (_guidedCalendar) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titleController.text,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _deadline == null
                      ? 'Choose a finish-by time below · ${widget.profileTimezone}'
                      : '${DateFormat.yMMMd().add_Hm().format(_profileLocal(_deadline!))} · ${widget.profileTimezone}',
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _sourceKind == DeadlinePlanSourceKind.calendarEvent
                      ? 'Linked event · original calendar unchanged'
                      : 'Independent plan · original calendar unchanged',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'What are you preparing for?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text('Add study sessions before this event.'),
        ],
        const SizedBox(height: AppSpacing.md),
        if (widget.lockKind && _kind != null)
          AppStatusPill(
            key: const ValueKey('deadline-locked-kind'),
            label: _kind == DeadlinePlanKind.exam ? 'Exam' : 'Assignment',
            tone: AppStatusTone.neutral,
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
                _clearHealthPreview();
                _kind = values.isEmpty ? null : values.single;
                if (!_dailyCapWasManuallyEdited && _kind != null) {
                  _dailyCapController.text =
                      '${defaultDeadlinePlanDailyPreparationMinutes(_kind)}';
                }
              });
            },
          ),
        const SizedBox(height: AppSpacing.md),
        if (_guidedCalendar) ...[
          if (widget.initialSourceStatus == DeadlinePlanSourceStatus.stale ||
              widget.initialSourceStatus ==
                  DeadlinePlanSourceStatus.unavailable)
            const Text(
              'The imported event changed or is unavailable. Review its details before continuing.',
            ),
          ExpansionTile(
            key: const ValueKey('deadline-event-details'),
            tilePadding: EdgeInsets.zero,
            maintainState: true,
            initiallyExpanded:
                _titleController.text.trim().isEmpty ||
                _deadline == null ||
                !_deadline!.isAfter(_now) ||
                widget.initialSourceStatus != DeadlinePlanSourceStatus.current,
            title: const Text('Edit event details'),
            subtitle: const Text('Title, date and calendar link'),
            children: [_buildIdentityFields(context)],
          ),
        ] else
          _buildIdentityFields(context),
        if (!_guidedCalendar) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text('Plan study time before this date.'),
        ],
      ],
    );
  }

  Widget _buildIdentityFields(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('deadline-plan-title'),
          controller: _titleController,
          maxLength: 160,
          onChanged: (_) => setState(_clearHealthPreview),
          decoration: const InputDecoration(
            labelText: 'Title',
            counterText: '',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text('Finish by'),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            OutlinedButton.icon(
              onPressed: _pickDeadline,
              icon: const Icon(AppIcons.eventOutlined),
              label: Text(
                _deadline != null
                    ? DateFormat.yMMMd().format(_profileLocal(_deadline!))
                    : _deadlineDateHint != null
                    ? DateFormat.yMMMd().format(_deadlineDateHint!)
                    : 'Choose date',
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _pickDeadline(timeOnly: true),
              icon: const Icon(AppIcons.schedule),
              label: Text(
                _deadline == null
                    ? 'Time'
                    : DateFormat.Hm().format(_profileLocal(_deadline!)),
              ),
            ),
          ],
        ),
        Text(
          widget.profileTimezone,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (widget.sourceKind == DeadlinePlanSourceKind.calendarEvent) ...[
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            key: const ValueKey('deadline-keep-calendar-source'),
            contentPadding: EdgeInsets.zero,
            value: _sourceKind == DeadlinePlanSourceKind.calendarEvent,
            onChanged: (value) {
              setState(() {
                _clearHealthPreview();
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
            title: const Text('Link to imported event'),
            subtitle: Text(
              widget.initialSourceStatus == DeadlinePlanSourceStatus.stale ||
                      widget.initialSourceStatus ==
                          DeadlinePlanSourceStatus.unavailable
                  ? 'The imported source changed. Turn this off to keep your reviewed title and deadline as a manual plan.'
                  : 'Off: keep this as an independent plan.',
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
        const AppInfoSectionDisclosure(
          heading: 'How much study time?',
          compactHeading: true,
          keyPrefix: 'deadline-estimate-info',
          description:
              'MyLifeGraph cannot estimate this for you. Try topics × sessions per topic × minutes per session. The hour chips are optional shortcuts, not recommendations.',
        ),
        const Text('Focused work only · no breaks or classes.'),
        const SizedBox(height: AppSpacing.md),
        _DurationFields(
          prefix: 'deadline-total',
          hours: _totalHoursController,
          minutes: _totalMinutesController,
          label: 'Total active preparation',
          onChanged: () => setState(_clearHealthPreview),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final hours in const [2, 5, 10, 20, 30])
              ChoiceChip(
                key: ValueKey('deadline-estimate-${hours}h'),
                label: Text('$hours h'),
                selected: _totalMinutes == hours * 60,
                onSelected: (_) {
                  setState(() {
                    _clearHealthPreview();
                    _totalHoursController.text = '$hours';
                    _totalMinutesController.text = '0';
                  });
                },
              ),
          ],
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
        _PreparationSessionPicker(
          minutes: _sessionMinutes,
          onChanged: (minutes) => setState(() {
            _clearHealthPreview();
            _sessionMinutes = minutes;
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        _editorPair(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('deadline-daily-cap'),
                controller: _dailyCapController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {
                  _clearHealthPreview();
                  _dailyCapWasManuallyEdited = true;
                }),
                decoration: const InputDecoration(
                  labelText: 'Daily limit',
                  suffixText: 'min',
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                !widget.accountDailyPreparationBudgetKnown
                    ? 'Your account-wide budget is temporarily unavailable here. Any saved total budget still limits confirmed plans.'
                    : widget.accountDailyPreparationBudgetMinutes == null
                    ? 'No total daily limit set in Settings.'
                    : 'All plans: ${_duration(widget.accountDailyPreparationBudgetMinutes!)} / day.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _bufferDays,
                isExpanded: true,
                itemHeight: null,
                decoration: const InputDecoration(
                  labelText: 'Clear days before deadline',
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
                  if (value != null) {
                    setState(() {
                      _clearHealthPreview();
                      _bufferDays = value;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _editorPair(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _pickPlanningStart,
                icon: const Icon(AppIcons.todayOutlined),
                label: Text(
                  'Start · ${DateFormat.yMMMd().format(_planningStart)}',
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(AppIcons.eventBusyOutlined),
                title: const Text('Busy times'),
                subtitle: const Text('Planner · no automatic sync'),
                trailing: const Icon(AppIcons.openInNewOutlined),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onOpenPlanner();
                },
              ),
            ],
          ),
        ),
        if (_kind == DeadlinePlanKind.exam) ...[
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            key: const ValueKey('exam-plan-health-preview'),
            onPressed: _healthPreviewLoading ? null : _checkExamPlanHealth,
            icon: _healthPreviewLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppIcons.autoGraphOutlined),
            label: const Text('Check capacity'),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text('No changes saved.'),
          if (_healthPreviewError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'The capacity check could not be loaded. This transport error is separate from an Availability unknown result.',
              key: ValueKey('exam-plan-health-preview-error'),
            ),
          ],
          if (_healthPreview != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ExamPlanHealthPreviewView(exam: _healthPreview!.exam),
          ],
        ],
        const SizedBox(height: AppSpacing.sm),
        const ExpansionTile(
          key: ValueKey('deadline-planning-details'),
          tilePadding: EdgeInsets.zero,
          title: Text('Details'),
          children: [
            Text(
              'Daily budget is shared with other confirmed plans.\n'
              'Clear days have no study blocks; 0 includes the deadline day.\n'
              'A past start moves to today when replanning.\n'
              'Busy times follow Planner. Re-import after calendar changes.',
            ),
          ],
        ),
        const Text('Review and confirm to reserve study time.'),
      ],
    );
  }

  Widget _editorPair(BuildContext context, Widget left, Widget right) =>
      LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 560 &&
              MediaQuery.textScalerOf(context).scale(16) < 24) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: right),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              const SizedBox(height: AppSpacing.md),
              right,
            ],
          );
        },
      );

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
      if (_guidedCalendar) {
        _submit();
        return;
      }
    }
    setState(() {
      _step += 1;
      _planOptionsExpanded = false;
    });
    _wizardScrollController.jumpTo(0);
  }

  Future<void> _pickDeadline({bool timeOnly = false}) async {
    final now = _profileLocal(_now);
    final lastDate = now.add(const Duration(days: 366));
    final dateHint = _deadlineDateHint;
    final requestedInitial =
        (_deadline == null ? null : _profileLocal(_deadline!)) ??
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
    final date = timeOnly && _deadline != null
        ? DateTime(initial.year, initial.month, initial.day)
        : await showDatePicker(
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
    try {
      final selected = profileDateTimeFromComponents(
        year: date.year,
        month: date.month,
        day: date.day,
        hour: time.hour,
        minute: time.minute,
        timezoneName: widget.profileTimezone,
      );
      setState(() {
        _clearHealthPreview();
        _deadline = selected;
        _deadlineDateHint = null;
        if (widget.existing == null &&
            widget.retainedDraft == null &&
            date.year == now.year &&
            date.month == now.month &&
            date.day == now.day) {
          _bufferDays = 0;
        }
      });
    } on ProfileTimezoneException {
      _showValidation(
        'That profile-local time is missing or ambiguous because of a daylight-saving change. Choose another time.',
      );
    }
  }

  Future<void> _pickPlanningStart() async {
    final now = _profileLocal(_now);
    final today = widget.profileToday;
    final deadlineDate = _deadline == null ? null : _profileLocal(_deadline!);
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
    if (selected != null && mounted) {
      setState(() {
        _clearHealthPreview();
        _planningStart = selected;
      });
    }
  }

  void _submit() {
    final draft = _proposalDraft();
    if (draft != null) Navigator.of(context).pop(draft);
  }

  DeadlinePlanProposalDraft? _proposalDraft() {
    if (_sessionMinutes < 25 || _sessionMinutes > 180) {
      _showValidation('Enter a focus block from 25 to 180 minutes.');
      return null;
    }
    final total = _totalMinutes;
    final dailyCap = int.tryParse(_dailyCapController.text.trim());
    if (total == null ||
        dailyCap == null ||
        _kind == null ||
        _deadline == null) {
      _showValidation('Review all required plan values.');
      return null;
    }
    if (!_deadline!.isAfter(_now)) {
      _showValidation('The finish-by time must be in the future.');
      return null;
    }
    if (_deadline!.difference(_now).inDays > 366) {
      _showValidation('Choose a finish-by time within the next 366 days.');
      return null;
    }
    final localDeadline = _profileLocal(_deadline!);
    final deadlineDate = DateTime(
      localDeadline.year,
      localDeadline.month,
      localDeadline.day,
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
      return null;
    }
    try {
      return DeadlinePlanProposalDraft(
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
      );
    } on DeadlinePlanAccessException catch (error) {
      _showValidation(error.message);
      return null;
    }
  }

  Future<void> _checkExamPlanHealth() async {
    final draft = _proposalDraft();
    if (draft == null || draft.kind != DeadlinePlanKind.exam) return;
    final generation = ++_healthPreviewGeneration;
    setState(() {
      _healthPreviewLoading = true;
      _healthPreviewError = null;
      _healthPreview = null;
    });
    try {
      final result = await widget.onPreviewHealth(
        ExamPlanHealthPreviewDraft.fromProposal(
          draft,
          activePlanId: widget.healthPlanId,
          activeBaseRevision: widget.healthBaseRevision,
        ),
      );
      if (!mounted || generation != _healthPreviewGeneration) return;
      setState(() {
        _healthPreviewLoading = false;
        _healthPreview = result;
      });
    } catch (error) {
      if (!mounted || generation != _healthPreviewGeneration) return;
      setState(() {
        _healthPreviewLoading = false;
        _healthPreviewError = error;
      });
    }
  }

  void _clearHealthPreview() {
    _healthPreviewGeneration += 1;
    _healthPreviewLoading = false;
    _healthPreview = null;
    _healthPreviewError = null;
    _savedHealthStillMatches = false;
  }

  int? get _totalMinutes =>
      _durationInput(_totalHoursController.text, _totalMinutesController.text);

  void _showValidation(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}
