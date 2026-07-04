import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../snapshots/presentation/providers/snapshot_providers.dart';
import '../../data/habit_completion_supabase_data_source.dart';

class HabitManagementPage extends ConsumerStatefulWidget {
  const HabitManagementPage({super.key});

  @override
  ConsumerState<HabitManagementPage> createState() =>
      _HabitManagementPageState();
}

class _HabitManagementPageState extends ConsumerState<HabitManagementPage> {
  List<HabitCompletionOption> _habits = const [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadHabits);
  }

  @override
  Widget build(BuildContext context) {
    final activeHabits = _habits.where((habit) => habit.active).toList();
    final pausedHabits = _habits.where((habit) => !habit.active).toList();

    return AppPage(
      title: 'Habit management',
      subtitle: 'Create and adjust consistency targets',
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
                  'No habits yet.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _canUseSupabase
                      ? 'Add your first habit to start tracking consistency.'
                      : 'Supabase is not configured.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (_canUseSupabase) ...[
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : () => _openEditor(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add habit'),
                  ),
                ],
              ],
            ),
          )
        else ...[
          _SectionHeader(title: 'Active', count: activeHabits.length),
          if (activeHabits.isEmpty)
            const AppCard(child: Text('No active habits.'))
          else
            ...activeHabits.map(
              (habit) => _HabitManagementTile(
                habit: habit,
                onEdit: () => _openEditor(habit: habit),
                onToggleActive: () => _setHabitActive(habit, active: false),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          _SectionHeader(title: 'Paused', count: pausedHabits.length),
          if (pausedHabits.isEmpty)
            const AppCard(child: Text('No paused habits.'))
          else
            ...pausedHabits.map(
              (habit) => _HabitManagementTile(
                habit: habit,
                onEdit: () => _openEditor(habit: habit),
                onToggleActive: () => _setHabitActive(habit, active: true),
              ),
            ),
        ],
      ],
    );
  }

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
      ).fetchHabits();
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

  Future<void> _openEditor({HabitCompletionOption? habit}) async {
    final result = await showModalBottomSheet<_HabitEditorResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _HabitEditorSheet(habit: habit),
    );
    if (result == null) {
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
          title: result.title,
          description: result.description,
          frequency: result.frequency,
          target: result.target,
        );
      } else {
        await dataSource.updateHabit(
          habitId: habit.id,
          title: result.title,
          description: result.description,
          frequency: result.frequency,
          target: result.target,
        );
      }
      await ref
          .read(snapshotRefreshServiceProvider)
          .refreshDailyAfterHabitChange();
      ref.invalidate(dashboardSnapshotProvider);
      await _loadHabits();
      if (mounted) {
        _showMessage(habit == null ? 'Habit added.' : 'Habit updated.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          habit == null ? 'Could not add habit.' : 'Could not update habit.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _setHabitActive(
    HabitCompletionOption habit, {
    required bool active,
  }) async {
    final config = ref.read(appConfigProvider);
    final client = ref.read(supabaseClientProvider);
    if (config.useMockData || client == null) {
      _showMessage('Supabase is not configured.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await HabitCompletionSupabaseDataSource(client).setHabitActive(
        habitId: habit.id,
        active: active,
      );
      await ref
          .read(snapshotRefreshServiceProvider)
          .refreshDailyAfterHabitChange();
      ref.invalidate(dashboardSnapshotProvider);
      await _loadHabits();
      if (mounted) {
        _showMessage(active ? 'Habit restored.' : 'Habit paused.');
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: AppSpacing.sm),
          Text('$count', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _HabitManagementTile extends StatelessWidget {
  const _HabitManagementTile({
    required this.habit,
    required this.onEdit,
    required this.onToggleActive,
  });

  final HabitCompletionOption habit;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(
            habit.active ? Icons.repeat : Icons.pause_circle_outline,
            color: habit.active ? Theme.of(context).colorScheme.primary : null,
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
                if (habit.description != null &&
                    habit.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    habit.description!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${habit.frequency} target: ${habit.target} · ${habit.completionsLast7Days}/7 days',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          PopupMenuButton<_HabitMenuAction>(
            tooltip: 'Habit actions',
            onSelected: (action) {
              switch (action) {
                case _HabitMenuAction.edit:
                  onEdit();
                case _HabitMenuAction.toggleActive:
                  onToggleActive();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _HabitMenuAction.edit,
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _HabitMenuAction.toggleActive,
                child: ListTile(
                  leading: Icon(
                    habit.active
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                  ),
                  title: Text(habit.active ? 'Pause' : 'Restore'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _HabitMenuAction { edit, toggleActive }

class _HabitEditorSheet extends StatefulWidget {
  const _HabitEditorSheet({this.habit});

  final HabitCompletionOption? habit;

  @override
  State<_HabitEditorSheet> createState() => _HabitEditorSheetState();
}

class _HabitEditorSheetState extends State<_HabitEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _targetController;
  late String _frequency;

  @override
  void initState() {
    super.initState();
    final habit = widget.habit;
    _titleController = TextEditingController(text: habit?.title ?? '');
    _descriptionController = TextEditingController(
      text: habit?.description ?? '',
    );
    _targetController = TextEditingController(
      text: (habit?.target ?? 1).toString(),
    );
    _frequency = habit?.frequency == 'weekly' ? 'weekly' : 'daily';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
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
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _descriptionController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'daily',
                  label: Text('Daily'),
                  icon: Icon(Icons.today_outlined),
                ),
                ButtonSegment(
                  value: 'weekly',
                  label: Text('Weekly'),
                  icon: Icon(Icons.calendar_view_week_outlined),
                ),
              ],
              selected: {_frequency},
              onSelectionChanged: (selected) {
                setState(() => _frequency = selected.single);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _targetController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Target'),
            ),
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
                  label: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final title = _titleController.text.trim();
    final parsedTarget = int.tryParse(_targetController.text.trim());
    if (title.isEmpty || parsedTarget == null || parsedTarget <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a title and a positive target.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      _HabitEditorResult(
        title: title,
        description: _descriptionController.text.trim(),
        frequency: _frequency,
        target: parsedTarget,
      ),
    );
  }
}

class _HabitEditorResult {
  const _HabitEditorResult({
    required this.title,
    required this.description,
    required this.frequency,
    required this.target,
  });

  final String title;
  final String description;
  final String frequency;
  final int target;
}
