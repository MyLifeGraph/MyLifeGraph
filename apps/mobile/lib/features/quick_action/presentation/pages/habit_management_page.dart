import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/utils/client_uuid.dart';
import '../../../../core/utils/local_date.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../snapshots/presentation/providers/snapshot_providers.dart';
import '../../data/habit_completion_supabase_data_source.dart';
import '../../domain/habit_v1.dart';

class HabitManagementPage extends ConsumerStatefulWidget {
  const HabitManagementPage({super.key});

  @override
  ConsumerState<HabitManagementPage> createState() =>
      _HabitManagementPageState();
}

class _HabitManagementPageState extends ConsumerState<HabitManagementPage> {
  List<HabitV1> _habits = const [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadHabits);
  }

  @override
  Widget build(BuildContext context) {
    final active = _byLifecycle(HabitLifecycle.active);
    final paused = _byLifecycle(HabitLifecycle.paused);
    final archived = _byLifecycle(HabitLifecycle.archived);
    return AppPage(
      title: 'Habit management',
      subtitle: 'Set an honest daily, weekday, or weekly cadence',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _isLoading ? null : _loadHabits,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Add habit',
          onPressed: _isSaving ? null : () => _openEditor(),
          icon: const Icon(Icons.add),
        ),
      ],
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.tune_outlined),
            title: const Text('Setup routines are managed in Setup'),
            subtitle: const Text(
              'Their definition and lifecycle stay there. Active Setup '
              'routines can still be completed or skipped in Today Habits.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('${AppRoutes.onboarding}?edit=1'),
          ),
        ),
        if (_isLoading)
          const AppCard(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: CircularProgressIndicator(),
              ),
            ),
          )
        else if (_habits.isEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No manual habits yet.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text('Add one important recurring behavior.'),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: _canUseSupabase && !_isSaving
                      ? () => _openEditor()
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Add habit'),
                ),
              ],
            ),
          )
        else ...[
          _HabitSection(
            title: 'Active',
            habits: active,
            isSaving: _isSaving,
            onEdit: (habit) => _openEditor(habit: habit),
            onLifecycle: _setLifecycle,
          ),
          _HabitSection(
            title: 'Paused',
            habits: paused,
            isSaving: _isSaving,
            onEdit: (habit) => _openEditor(habit: habit),
            onLifecycle: _setLifecycle,
          ),
          _HabitSection(
            title: 'Archived',
            habits: archived,
            isSaving: _isSaving,
            onEdit: (habit) => _openEditor(habit: habit),
            onLifecycle: _setLifecycle,
          ),
        ],
      ],
    );
  }

  List<HabitV1> _byLifecycle(HabitLifecycle lifecycle) =>
      _habits.where((habit) => habit.lifecycle == lifecycle).toList();

  bool get _canUseSupabase {
    final config = ref.read(appConfigProvider);
    final client = ref.read(supabaseClientProvider);
    return !config.useMockData && client != null;
  }

  Future<void> _loadHabits() async {
    final config = ref.read(appConfigProvider);
    final client = ref.read(supabaseClientProvider);
    if (config.useMockData || client == null) {
      if (mounted) {
        setState(() {
          _habits = const [];
          _isLoading = false;
        });
      }
      return;
    }
    setState(() => _isLoading = true);
    try {
      final habits = await HabitCompletionSupabaseDataSource(
        client,
      ).fetchHabits(excludeSetupManaged: true);
      if (mounted) {
        setState(() {
          _habits = habits;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('Could not load habits.');
      }
    }
  }

  Future<void> _openEditor({HabitV1? habit}) async {
    final result = await showModalBottomSheet<_HabitEditorResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _HabitEditorSheet(habit: habit),
    );
    if (result == null) {
      return;
    }
    await _saveEditorResult(
      habit: habit,
      result: result,
      requestId: newClientUuid(),
    );
  }

  Future<void> _saveEditorResult({
    required HabitV1? habit,
    required _HabitEditorResult result,
    required String requestId,
  }) async {
    if (_isSaving) {
      return;
    }
    final config = ref.read(appConfigProvider);
    final client = ref.read(supabaseClientProvider);
    if (config.useMockData || client == null) {
      _showMessage('Supabase is not configured.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final dataSource = HabitCompletionSupabaseDataSource(client);
      if (habit == null) {
        await dataSource.createHabit(
          habitId: requestId,
          title: result.title,
          description: result.description,
          cadence: result.cadence,
        );
      } else {
        await dataSource.updateHabit(
          habit: habit,
          title: result.title,
          description: result.description,
          cadence: result.cadence,
        );
      }
      await _afterDurableWrite();
      if (mounted) {
        _showMessage(habit == null ? 'Habit added.' : 'Habit updated.');
      }
    } catch (error) {
      if (mounted) {
        final message = error is HabitCommandException
            ? error.message
            : habit == null
                ? 'Could not add habit.'
                : 'Could not update habit.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$message Your draft is retained.'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _saveEditorResult(
                habit: habit,
                result: result,
                requestId: requestId,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _setLifecycle(
    HabitV1 habit,
    HabitLifecycle lifecycle,
  ) async {
    if (_isSaving) {
      return;
    }
    if (lifecycle == HabitLifecycle.archived) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Archive habit?'),
          content: Text(
            '${habit.title} will leave today\'s execution list. Its history '
            'is preserved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep habit'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Archive habit'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
    }
    final client = ref.read(supabaseClientProvider);
    if (client == null) {
      _showMessage('Supabase is not configured.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await HabitCompletionSupabaseDataSource(client).setHabitLifecycle(
        habit: habit,
        lifecycle: lifecycle,
      );
      await _afterDurableWrite();
      if (mounted) {
        _showMessage(
          switch (lifecycle) {
            HabitLifecycle.active => 'Habit restored.',
            HabitLifecycle.paused => 'Habit paused.',
            HabitLifecycle.archived => 'Habit archived.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not update habit.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _afterDurableWrite() async {
    await ref
        .read(snapshotRefreshServiceProvider)
        .refreshDailyAfterHabitChange(targetDate: localDateKey(DateTime.now()));
    ref.invalidate(dashboardSnapshotProvider);
    await _loadHabits();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _HabitSection extends StatelessWidget {
  const _HabitSection({
    required this.title,
    required this.habits,
    required this.isSaving,
    required this.onEdit,
    required this.onLifecycle,
  });

  final String title;
  final List<HabitV1> habits;
  final bool isSaving;
  final ValueChanged<HabitV1> onEdit;
  final void Function(HabitV1, HabitLifecycle) onLifecycle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            '$title (${habits.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (habits.isEmpty)
          AppCard(child: Text('No ${title.toLowerCase()} habits.'))
        else
          ...habits.map(
            (habit) => _HabitManagementTile(
              habit: habit,
              isSaving: isSaving,
              onEdit: () => onEdit(habit),
              onLifecycle: (lifecycle) => onLifecycle(habit, lifecycle),
            ),
          ),
      ],
    );
  }
}

class _HabitManagementTile extends StatelessWidget {
  const _HabitManagementTile({
    required this.habit,
    required this.isSaving,
    required this.onEdit,
    required this.onLifecycle,
  });

  final HabitV1 habit;
  final bool isSaving;
  final VoidCallback onEdit;
  final ValueChanged<HabitLifecycle> onLifecycle;

  @override
  Widget build(BuildContext context) {
    final progress = habit.progressAt(DateTime.now());
    return AppCard(
      child: Row(
        children: [
          Icon(
            habit.lifecycle == HabitLifecycle.active
                ? Icons.repeat
                : habit.lifecycle == HabitLifecycle.paused
                    ? Icons.pause_circle_outline
                    : Icons.archive_outlined,
            color: habit.lifecycle == HabitLifecycle.active
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  habit.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (habit.description != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(habit.description!),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${habit.cadence.label} · ${progress.label} current progress',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          PopupMenuButton<_HabitMenuAction>(
            tooltip: 'Habit actions for ${habit.title}',
            enabled: !isSaving,
            onSelected: (action) {
              switch (action) {
                case _HabitMenuAction.edit:
                  onEdit();
                case _HabitMenuAction.pause:
                  onLifecycle(HabitLifecycle.paused);
                case _HabitMenuAction.restore:
                  onLifecycle(HabitLifecycle.active);
                case _HabitMenuAction.archive:
                  onLifecycle(HabitLifecycle.archived);
              }
            },
            itemBuilder: (context) => [
              if (habit.lifecycle != HabitLifecycle.archived)
                const PopupMenuItem(
                  value: _HabitMenuAction.edit,
                  child: Text('Edit'),
                ),
              if (habit.lifecycle == HabitLifecycle.active)
                const PopupMenuItem(
                  value: _HabitMenuAction.pause,
                  child: Text('Pause'),
                ),
              if (habit.lifecycle != HabitLifecycle.active)
                const PopupMenuItem(
                  value: _HabitMenuAction.restore,
                  child: Text('Restore'),
                ),
              if (habit.lifecycle != HabitLifecycle.archived)
                const PopupMenuItem(
                  value: _HabitMenuAction.archive,
                  child: Text('Archive'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _HabitMenuAction { edit, pause, restore, archive }

class _HabitEditorSheet extends StatefulWidget {
  const _HabitEditorSheet({this.habit});

  final HabitV1? habit;

  @override
  State<_HabitEditorSheet> createState() => _HabitEditorSheetState();
}

class _HabitEditorSheetState extends State<_HabitEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _weeklyTargetController;
  late HabitCadenceKind _cadenceKind;
  late Set<int> _weekdays;

  @override
  void initState() {
    super.initState();
    final habit = widget.habit;
    _titleController = TextEditingController(text: habit?.title ?? '');
    _descriptionController = TextEditingController(
      text: habit?.description ?? '',
    );
    _weeklyTargetController = TextEditingController(
      text: (habit?.cadence.weeklyTarget ?? 3).toString(),
    );
    _cadenceKind = habit?.cadence.kind ?? HabitCadenceKind.daily;
    _weekdays = habit?.cadence.scheduledWeekdays.toSet() ?? {1, 3, 5};
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _weeklyTargetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg + bottomInset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.habit == null ? 'Add habit' : 'Edit habit',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _titleController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              maxLength: 160,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _descriptionController,
              textInputAction: TextInputAction.next,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Description optional',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<HabitCadenceKind>(
              initialValue: _cadenceKind,
              decoration: const InputDecoration(labelText: 'Cadence'),
              items: const [
                DropdownMenuItem(
                  value: HabitCadenceKind.daily,
                  child: Text('Daily'),
                ),
                DropdownMenuItem(
                  value: HabitCadenceKind.weekdays,
                  child: Text('Selected weekdays'),
                ),
                DropdownMenuItem(
                  value: HabitCadenceKind.weeklyTarget,
                  child: Text('Times per week'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _cadenceKind = value);
                }
              },
            ),
            if (_cadenceKind == HabitCadenceKind.weekdays) ...[
              const SizedBox(height: AppSpacing.md),
              const Text('Scheduled weekdays'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: List.generate(7, (index) {
                  final weekday = index + 1;
                  const labels = [
                    'Mon',
                    'Tue',
                    'Wed',
                    'Thu',
                    'Fri',
                    'Sat',
                    'Sun',
                  ];
                  return FilterChip(
                    label: Text(labels[index]),
                    selected: _weekdays.contains(weekday),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _weekdays.add(weekday);
                        } else {
                          _weekdays.remove(weekday);
                        }
                      });
                    },
                  );
                }),
              ),
            ],
            if (_cadenceKind == HabitCadenceKind.weeklyTarget) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _weeklyTargetController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Weekly target (1–7)',
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.check),
                  label: const Text('Save habit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    try {
      final cadence = switch (_cadenceKind) {
        HabitCadenceKind.daily => HabitCadence.daily(),
        HabitCadenceKind.weekdays => HabitCadence.weekdays(_weekdays),
        HabitCadenceKind.weeklyTarget => HabitCadence.weeklyTarget(
            int.tryParse(_weeklyTargetController.text.trim()) ?? 0,
          ),
      };
      final title = _titleController.text.trim();
      if (title.isEmpty) {
        throw const HabitContractException('Enter a habit title.');
      }
      Navigator.of(context).pop(
        _HabitEditorResult(
          title: title,
          description: _descriptionController.text.trim(),
          cadence: cadence,
        ),
      );
    } on HabitContractException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _HabitEditorResult {
  const _HabitEditorResult({
    required this.title,
    required this.description,
    required this.cadence,
  });

  final String title;
  final String description;
  final HabitCadence cadence;
}
