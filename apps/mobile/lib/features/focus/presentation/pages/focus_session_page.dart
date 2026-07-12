import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/utils/client_uuid.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../snapshots/presentation/providers/snapshot_providers.dart';
import '../../data/focus_session_supabase_data_source.dart';
import '../../domain/focus_session.dart';

class FocusSessionPage extends ConsumerStatefulWidget {
  const FocusSessionPage({
    super.key,
    this.initialTargetKind,
    this.initialTargetId,
  });

  final FocusTargetKind? initialTargetKind;
  final String? initialTargetId;

  @override
  ConsumerState<FocusSessionPage> createState() => _FocusSessionPageState();
}

class _FocusSessionPageState extends ConsumerState<FocusSessionPage> {
  FocusSession? _active;
  List<FocusSession> _recent = const [];
  List<FocusTargetOption> _targets = const [];
  String? _selectedTargetValue;
  bool _initialTargetApplied = false;
  int _plannedMinutes = 25;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Focus session',
      subtitle: 'A real timed execution block linked to an optional action',
      actions: [
        IconButton(
          tooltip: 'Refresh focus sessions',
          onPressed: _isLoading || _isSaving ? null : _load,
          icon: const Icon(Icons.refresh),
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
        else if (_active != null)
          _ActiveFocusCard(
            session: _active!,
            target: _targetFor(_active!),
            isSaving: _isSaving,
            onFinish: _finish,
            onAbandon: _abandon,
          )
        else
          _StartFocusCard(
            plannedMinutes: _plannedMinutes,
            targets: _targets,
            selectedTargetValue: _selectedTargetValue,
            isSaving: _isSaving,
            onDurationChanged: (value) {
              setState(() => _plannedMinutes = value);
            },
            onTargetChanged: (value) {
              setState(() => _selectedTargetValue = value);
            },
            onStart: _start,
          ),
        if (!_isLoading) _FocusHistoryCard(sessions: _recent),
      ],
    );
  }

  Future<void> _load() async {
    final config = ref.read(appConfigProvider);
    final client = ref.read(supabaseClientProvider);
    if (config.useMockData || client == null) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }
    setState(() => _isLoading = true);
    try {
      final source = FocusSessionSupabaseDataSource(client);
      final results = await Future.wait([
        source.fetchActiveSession(),
        source.fetchRecentSessions(),
        source.fetchAvailableTargets(),
      ]);
      final active = results[0] as FocusSession?;
      final recent = results[1] as List<FocusSession>;
      final targets = results[2] as List<FocusTargetOption>;
      var selected = _selectedTargetValue;
      final requestedKind = widget.initialTargetKind;
      final requestedId = widget.initialTargetId;
      if (!_initialTargetApplied) {
        _initialTargetApplied = true;
        if (selected == null && requestedKind != null && requestedId != null) {
          final requested = '${requestedKind.code}:$requestedId';
          if (targets.any((target) => target.value == requested)) {
            selected = requested;
          }
        }
      }
      if (mounted) {
        setState(() {
          _active = active;
          _recent = recent;
          _targets = targets;
          _selectedTargetValue = selected;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('Could not load focus sessions.');
      }
    }
  }

  Future<void> _start() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null || _isSaving) {
      return;
    }
    final target = _targets
        .where((candidate) => candidate.value == _selectedTargetValue)
        .firstOrNull;
    final requestId = newClientUuid();
    setState(() => _isSaving = true);
    try {
      final started = await FocusSessionSupabaseDataSource(client).startSession(
        sessionId: requestId,
        draft: FocusStartDraft(
          plannedMinutes: _plannedMinutes,
          targetKind: target?.kind,
          targetId: target?.id,
          label: target?.title ?? 'Independent focus block',
        ),
      );
      await _afterDurableWrite(started);
      if (mounted) {
        _showMessage('Focus session started.');
      }
    } catch (error) {
      await _load();
      if (_active?.id == requestId) {
        await _afterDurableWrite(_active!);
        if (mounted) {
          _showMessage('Focus session started.');
        }
        return;
      }
      if (mounted) {
        _showMessage(
          error is FocusCommandException
              ? error.message
              : 'Could not start focus session.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _finish() async {
    final active = _active;
    final client = ref.read(supabaseClientProvider);
    if (active == null || client == null || _isSaving) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await FocusSessionSupabaseDataSource(client).finishSession(active.id);
      if (mounted) {
        setState(() => _selectedTargetValue = null);
      }
      await _afterDurableWrite(active);
      if (mounted) {
        _showMessage(
          'Focus session finished. Linked tasks and habits were not '
          'completed automatically.',
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is FocusCommandException
              ? error.message
              : 'Could not finish focus session.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _abandon() async {
    final active = _active;
    final client = ref.read(supabaseClientProvider);
    if (active == null || client == null || _isSaving) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abandon focus session?'),
        content: const Text(
          'Elapsed time will be kept, but this block will be marked abandoned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep focusing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Abandon session'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await FocusSessionSupabaseDataSource(client).abandonSession(active.id);
      if (mounted) {
        setState(() => _selectedTargetValue = null);
      }
      await _afterDurableWrite(active);
      if (mounted) {
        _showMessage('Focus session abandoned.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is FocusCommandException
              ? error.message
              : 'Could not abandon focus session.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _afterDurableWrite(FocusSession session) async {
    await ref.read(snapshotRefreshServiceProvider).refreshDailyAfterFocusChange(
          targetDate: session.snapshotEntryDate,
        );
    ref.invalidate(dashboardSnapshotProvider);
    await _load();
  }

  FocusTargetOption? _targetFor(FocusSession session) {
    return _targets
        .where(
          (target) =>
              target.kind == session.targetKind &&
              target.id == session.targetId,
        )
        .firstOrNull;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _StartFocusCard extends StatelessWidget {
  const _StartFocusCard({
    required this.plannedMinutes,
    required this.targets,
    required this.selectedTargetValue,
    required this.isSaving,
    required this.onDurationChanged,
    required this.onTargetChanged,
    required this.onStart,
  });

  final int plannedMinutes;
  final List<FocusTargetOption> targets;
  final String? selectedTargetValue;
  final bool isSaving;
  final ValueChanged<int> onDurationChanged;
  final ValueChanged<String?> onTargetChanged;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Start a focus block',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Finishing records focused time. It never completes a linked '
            'task or habit automatically.',
          ),
          const SizedBox(height: AppSpacing.lg),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 25, label: Text('25 min')),
              ButtonSegment(value: 50, label: Text('50 min')),
              ButtonSegment(value: 90, label: Text('90 min')),
            ],
            selected: {plannedMinutes},
            onSelectionChanged:
                isSaving ? null : (values) => onDurationChanged(values.single),
          ),
          const SizedBox(height: AppSpacing.lg),
          DropdownButtonFormField<String?>(
            initialValue: selectedTargetValue,
            decoration: const InputDecoration(
              labelText: 'Linked action optional',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Independent focus block'),
              ),
              ...targets.map(
                (target) => DropdownMenuItem<String?>(
                  value: target.value,
                  child: Text(
                    '${target.kind == FocusTargetKind.task ? 'Task' : 'Habit'}: '
                    '${target.title}',
                  ),
                ),
              ),
            ],
            onChanged: isSaving ? null : onTargetChanged,
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: isSaving ? null : onStart,
              icon: isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: const Text('Start focus session'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveFocusCard extends StatelessWidget {
  const _ActiveFocusCard({
    required this.session,
    required this.target,
    required this.isSaving,
    required this.onFinish,
    required this.onAbandon,
  });

  final FocusSession session;
  final FocusTargetOption? target;
  final bool isSaving;
  final VoidCallback onFinish;
  final VoidCallback onAbandon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.timer_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Focus active',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(session.label ?? target?.title ?? 'Independent focus block'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Started ${DateFormat.Hm().format(session.startedAt.toLocal())} · '
            '${session.plannedMinutes} planned minutes',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: isSaving ? null : onAbandon,
                child: const Text('Abandon'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                onPressed: isSaving ? null : onFinish,
                icon: const Icon(Icons.stop),
                label: const Text('Finish focus session'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FocusHistoryCard extends StatelessWidget {
  const _FocusHistoryCard({required this.sessions});

  final List<FocusSession> sessions;

  @override
  Widget build(BuildContext context) {
    final terminal = sessions.where((session) => !session.isActive).take(5);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent focus', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (terminal.isEmpty)
            const Text('No finished sessions yet.')
          else
            ...terminal.map(
              (session) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  session.status == FocusSessionStatus.completed
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
                ),
                title: Text(session.label ?? 'Focus session'),
                subtitle: Text(
                  '${session.actualMinutes ?? 0} min · ${session.status.code}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
