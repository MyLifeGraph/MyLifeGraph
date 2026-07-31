import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_icons.dart';
import '../../domain/planner.dart';

class PlannerPlanPreviewDialog extends StatelessWidget {
  const PlannerPlanPreviewDialog({super.key, required this.plan});

  final PlannerActionPlan plan;

  @override
  Widget build(BuildContext context) {
    final revision = plan.pendingRevision!;
    return AlertDialog(
      title: const Text('Review plan preview'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                revision.targetTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${revision.plannedMinutes} min placed · '
                '${revision.unscheduledMinutes} min unplaced',
              ),
              if (revision.timingPreference.usedLearnedPattern) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  revision.timingPreference.fellBackToSetup
                      ? 'Learned timing considered · Setup fallback · '
                          '${revision.timingPreference.evidenceCount} rated sessions'
                      : 'Learned timing applied · '
                          '${revision.timingPreference.evidenceCount} rated sessions',
                  key: const Key('planner-learned-timing-applied'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else if (revision.timingPreference.warning != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Personal pattern unavailable · Setup timing used',
                  key: const Key('planner-learned-timing-fallback'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (revision.taskBlocks.isEmpty && revision.habitSlots.isEmpty)
                const Text(
                  'No time is reserved in this preview. Confirming saves the target under Unscheduled.',
                ),
              for (final block in revision.taskBlocks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(AppIcons.viewTimelineOutlined),
                  title: Text('${block.plannedMinutes} min'),
                  subtitle: Text(
                    block.recoveryMinutes > 0
                        ? '${DateFormat.yMMMd().add_Hm().format(block.startsAt.toLocal())} · '
                            '${block.plannedMinutes} min focus + ${block.recoveryMinutes} min recovery · '
                            'reserved until ${DateFormat.Hm().format(block.reservedEndsAt.toLocal())}'
                        : DateFormat.yMMMd()
                            .add_Hm()
                            .format(block.startsAt.toLocal()),
                  ),
                ),
              for (final slot in revision.habitSlots)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(AppIcons.repeatOutlined),
                  title: Text(
                    '${_weekdayLabel(slot.weekday)} · ${slot.durationMinutes} min',
                  ),
                  subtitle: Text(
                    '${slot.startsAt.substring(0, 5)}–${slot.endsAt.substring(0, 5)} every week',
                  ),
                ),
              if (revision.unscheduledMinutes > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Unplaced minutes stay explicit. Planner will not extend the deadline or overlap another reservation.',
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep as draft'),
        ),
        FilledButton(
          key: const ValueKey('planner-confirm-plan'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirm plan'),
        ),
      ],
    );
  }
}

class PlannerTaskDialog extends StatefulWidget {
  const PlannerTaskDialog({super.key, required this.initial});

  final PlannerTaskDraft? initial;

  @override
  State<PlannerTaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<PlannerTaskDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _duration;
  late final TextEditingController _session;
  late String _priority;
  late bool _schedule;
  late bool _useStudyRhythm;
  DateTime? _deadline;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title);
    _description = TextEditingController(text: initial?.description);
    _duration =
        TextEditingController(text: initial?.estimatedMinutes?.toString());
    _session = TextEditingController(
      text: initial?.preferredSessionMinutes?.toString(),
    );
    _priority = initial?.priority ?? 'medium';
    _deadline = initial?.deadlineAt;
    _schedule = initial?.estimatedMinutes != null ||
        initial?.deadlineAt != null ||
        initial?.preferredSessionMinutes != null;
    _useStudyRhythm = initial?.useStudyRhythm ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _duration.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add Task'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('planner-task-title'),
                  controller: _title,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Title *'),
                ),
                TextField(
                  controller: _description,
                  maxLength: 2000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(
                      value: 'critical',
                      child: Text('Critical'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _priority = value!),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _schedule,
                  onChanged: (value) => setState(() {
                    _schedule = value;
                    if (!value) _useStudyRhythm = false;
                  }),
                  title: const Text('Create a time-block preview'),
                  subtitle: const Text(
                    'Requires your duration, exact deadline, and preferred session length.',
                  ),
                ),
                if (_schedule) ...[
                  SwitchListTile.adaptive(
                    key: const ValueKey('planner-task-study-rhythm'),
                    contentPadding: EdgeInsets.zero,
                    value: _useStudyRhythm,
                    onChanged: (value) {
                      setState(() => _useStudyRhythm = value);
                    },
                    title: const Text('Use study rhythm'),
                    subtitle: const Text(
                      'Uses the exact Focus length and reserves the full recovery buffer from Settings. Habits never use this rule.',
                    ),
                  ),
                  TextField(
                    key: const ValueKey('planner-task-duration'),
                    controller: _duration,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Total duration in minutes *',
                    ),
                  ),
                  TextField(
                    key: const ValueKey('planner-task-session'),
                    controller: _session,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Preferred session in minutes *',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Exact deadline *'),
                    subtitle: Text(
                      _deadline == null
                          ? 'Not selected'
                          : DateFormat.yMMMd().add_Hm().format(_deadline!),
                    ),
                    trailing: const Icon(AppIcons.editCalendarOutlined),
                    onTap: _pickDeadline,
                  ),
                ],
                if (_error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('planner-task-preview'),
            onPressed: _submit,
            child: Text(_schedule ? 'Preview plan' : 'Save as unscheduled'),
          ),
        ],
      );

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      initialDate: _deadline ?? now.add(const Duration(days: 1)),
    );
    if (!mounted || day == null) return;
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: _deadline == null
          ? const TimeOfDay(hour: 17, minute: 0)
          : TimeOfDay.fromDateTime(_deadline!),
    );
    if (!mounted || selectedTime == null) return;
    setState(() {
      _deadline = DateTime(
        day.year,
        day.month,
        day.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  void _submit() {
    final title = _title.text.trim();
    final duration = _schedule ? int.tryParse(_duration.text.trim()) : null;
    final session = _schedule ? int.tryParse(_session.text.trim()) : null;
    if (title.isEmpty) {
      setState(() => _error = 'Enter a Task title.');
      return;
    }
    if (_schedule &&
        (duration == null ||
            duration < 5 ||
            duration > 480 ||
            session == null ||
            session < 5 ||
            session > 240 ||
            session % 5 != 0 ||
            _deadline == null ||
            !_deadline!.isAfter(DateTime.now()))) {
      setState(() {
        _error =
            'Use 5–480 total minutes, a 5–240 minute session in five-minute steps, and a future deadline.';
      });
      return;
    }
    Navigator.pop(
      context,
      PlannerTaskDraft(
        title: title,
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        priority: _priority,
        estimatedMinutes: duration,
        deadlineAt: _schedule ? _deadline : null,
        preferredSessionMinutes: session,
        useStudyRhythm: _schedule && _useStudyRhythm,
        targetId: widget.initial?.targetId,
        expectedUpdatedAt: widget.initial?.expectedUpdatedAt,
      ),
    );
  }
}

class PlannerHabitDialog extends StatefulWidget {
  const PlannerHabitDialog({super.key, required this.initial});

  final PlannerHabitDraft? initial;

  @override
  State<PlannerHabitDialog> createState() => _HabitDialogState();
}

class _HabitDialogState extends State<PlannerHabitDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _duration;
  String? _cadence;
  Set<int> _weekdays = {};
  int _weeklyTarget = 3;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title);
    _description = TextEditingController(text: initial?.description);
    _duration = TextEditingController(
      text: initial?.durationMinutes?.toString(),
    );
    _cadence = initial?.cadenceKind;
    _weekdays = initial?.scheduledWeekdays.toSet() ?? {};
    _weeklyTarget = initial?.weeklyTarget ?? 3;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add Habit'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const ValueKey('planner-habit-title'),
                  controller: _title,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Title *'),
                ),
                TextField(
                  controller: _description,
                  maxLength: 2000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _cadence,
                  decoration: const InputDecoration(labelText: 'Cadence *'),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(
                      value: 'weekdays',
                      child: Text('Selected weekdays'),
                    ),
                    DropdownMenuItem(
                      value: 'weekly_target',
                      child: Text('Times per week'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _cadence = value),
                ),
                if (_cadence == 'weekdays') ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (var day = 1; day <= 7; day++)
                        FilterChip(
                          label: Text(_weekdayLabel(day)),
                          selected: _weekdays.contains(day),
                          onSelected: (selected) => setState(() {
                            selected
                                ? _weekdays.add(day)
                                : _weekdays.remove(day);
                          }),
                        ),
                    ],
                  ),
                ],
                if (_cadence == 'weekly_target')
                  DropdownButtonFormField<int>(
                    initialValue: _weeklyTarget,
                    decoration:
                        const InputDecoration(labelText: 'Times per week'),
                    items: [
                      for (var value = 1; value <= 7; value++)
                        DropdownMenuItem(value: value, child: Text('$value')),
                    ],
                    onChanged: (value) =>
                        setState(() => _weeklyTarget = value!),
                  ),
                TextField(
                  key: const ValueKey('planner-habit-duration'),
                  controller: _duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Minutes per occurrence *',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'The same weekly time is checked across the next four weeks. Later conflicts appear under Needs attention.',
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('planner-habit-preview'),
            onPressed: _submit,
            child: const Text('Preview plan'),
          ),
        ],
      );

  void _submit() {
    final title = _title.text.trim();
    final duration = int.tryParse(_duration.text.trim());
    if (title.isEmpty || _cadence == null) {
      setState(() => _error = 'Enter a title and choose a cadence.');
      return;
    }
    if (_cadence == 'weekdays' && _weekdays.isEmpty) {
      setState(() => _error = 'Choose at least one weekday.');
      return;
    }
    if (duration == null ||
        duration < 5 ||
        duration > 240 ||
        duration % 5 != 0) {
      setState(() => _error = 'Choose 5–240 minutes in five-minute steps.');
      return;
    }
    Navigator.pop(
      context,
      PlannerHabitDraft(
        title: title,
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        cadenceKind: _cadence!,
        scheduledWeekdays:
            _cadence == 'weekdays' ? (_weekdays.toList()..sort()) : const [],
        weeklyTarget: _cadence == 'weekly_target' ? _weeklyTarget : 1,
        durationMinutes: duration,
        targetId: widget.initial?.targetId,
        expectedUpdatedAt: widget.initial?.expectedUpdatedAt,
      ),
    );
  }
}

class PlannerCommitmentDialog extends StatefulWidget {
  const PlannerCommitmentDialog({super.key, required this.initial});

  final PlannerCommitmentDraft? initial;

  @override
  State<PlannerCommitmentDialog> createState() => _CommitmentDialogState();
}

class _CommitmentDialogState extends State<PlannerCommitmentDialog> {
  late final TextEditingController _title;
  late final TextEditingController _location;
  String? _recurrence;
  DateTime? _startsAt;
  DateTime? _endsAt;
  int? _weekday;
  TimeOfDay? _weeklyStart;
  TimeOfDay? _weeklyEnd;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title);
    _location = TextEditingController(text: initial?.location);
    _recurrence = initial?.recurrence;
    _startsAt = initial?.startsAt;
    _endsAt = initial?.endsAt;
    _weekday = initial?.weekday;
    _weeklyStart = _parseTime(initial?.localStartsAt);
    _weeklyEnd = _parseTime(initial?.localEndsAt);
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add fixed commitment'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('planner-commitment-title'),
                  controller: _title,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Title *'),
                ),
                TextField(
                  controller: _location,
                  maxLength: 300,
                  decoration:
                      const InputDecoration(labelText: 'Location (optional)'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _recurrence,
                  decoration: const InputDecoration(labelText: 'Repeats *'),
                  items: const [
                    DropdownMenuItem(value: 'one_off', child: Text('One time')),
                    DropdownMenuItem(
                      value: 'weekly',
                      child: Text('Every week'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _recurrence = value),
                ),
                if (_recurrence == 'one_off') ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Starts *'),
                    subtitle: Text(
                      _startsAt == null
                          ? 'Not selected'
                          : DateFormat.yMMMd().add_Hm().format(_startsAt!),
                    ),
                    onTap: () => _pickOneOff(start: true),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ends *'),
                    subtitle: Text(
                      _endsAt == null
                          ? 'Not selected'
                          : DateFormat.yMMMd().add_Hm().format(_endsAt!),
                    ),
                    onTap: () => _pickOneOff(start: false),
                  ),
                ],
                if (_recurrence == 'weekly') ...[
                  DropdownButtonFormField<int>(
                    initialValue: _weekday,
                    decoration: const InputDecoration(labelText: 'Weekday *'),
                    items: [
                      for (var day = 1; day <= 7; day++)
                        DropdownMenuItem(
                          value: day,
                          child: Text(_weekdayLabel(day)),
                        ),
                    ],
                    onChanged: (value) => setState(() => _weekday = value),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Starts *'),
                    subtitle:
                        Text(_weeklyStart?.format(context) ?? 'Not selected'),
                    onTap: () => _pickWeekly(start: true),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ends *'),
                    subtitle:
                        Text(_weeklyEnd?.format(context) ?? 'Not selected'),
                    onTap: () => _pickWeekly(start: false),
                  ),
                ],
                if (_error != null)
                  Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('planner-commitment-review'),
            onPressed: _submit,
            child: const Text('Review commitment'),
          ),
        ],
      );

  Future<void> _pickOneOff({required bool start}) async {
    final current = start ? _startsAt : _endsAt;
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      initialDate: current ?? now,
    );
    if (!mounted || day == null) return;
    final value = await showTimePicker(
      context: context,
      initialTime: current == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay.fromDateTime(current),
    );
    if (!mounted || value == null) return;
    final instant =
        DateTime(day.year, day.month, day.day, value.hour, value.minute);
    setState(() => start ? _startsAt = instant : _endsAt = instant);
  }

  Future<void> _pickWeekly({required bool start}) async {
    final value = await showTimePicker(
      context: context,
      initialTime: (start ? _weeklyStart : _weeklyEnd) ??
          (start
              ? const TimeOfDay(hour: 9, minute: 0)
              : const TimeOfDay(hour: 10, minute: 0)),
    );
    if (!mounted || value == null) return;
    setState(() => start ? _weeklyStart = value : _weeklyEnd = value);
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty || _recurrence == null) {
      setState(() => _error = 'Enter a title and choose one time or weekly.');
      return;
    }
    if (_recurrence == 'one_off' &&
        (_startsAt == null ||
            _endsAt == null ||
            !_endsAt!.isAfter(_startsAt!))) {
      setState(() => _error = 'Choose an end after the start.');
      return;
    }
    if (_recurrence == 'weekly' &&
        (_weekday == null ||
            _weeklyStart == null ||
            _weeklyEnd == null ||
            _minuteOfDay(_weeklyEnd!) <= _minuteOfDay(_weeklyStart!))) {
      setState(() => _error = 'Choose a weekday and an end after the start.');
      return;
    }
    Navigator.pop(
      context,
      PlannerCommitmentDraft(
        title: title,
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        recurrence: _recurrence!,
        startsAt: _recurrence == 'one_off' ? _startsAt : null,
        endsAt: _recurrence == 'one_off' ? _endsAt : null,
        weekday: _recurrence == 'weekly' ? _weekday : null,
        localStartsAt:
            _recurrence == 'weekly' ? _timeString(_weeklyStart!) : null,
        localEndsAt: _recurrence == 'weekly' ? _timeString(_weeklyEnd!) : null,
      ),
    );
  }
}

String _weekdayLabel(int value) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][value - 1];

int _minuteOfDay(TimeOfDay value) => value.hour * 60 + value.minute;

String _timeString(TimeOfDay value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:00';

TimeOfDay? _parseTime(String? value) {
  if (value == null) return null;
  final parts = value.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}
