import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/utils/client_uuid.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../snapshots/application/snapshot_refresh_service.dart';
import '../../../snapshots/presentation/providers/snapshot_providers.dart';
import '../../data/focus_session_supabase_data_source.dart';
import '../../domain/focus_session.dart';

final focusSessionPageDataSourceProvider =
    Provider<FocusSessionSupabaseDataSource?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : FocusSessionSupabaseDataSource(client);
});

final focusStudySettingsDataSourceProvider =
    Provider<FocusSessionSupabaseDataSource?>((ref) {
  SupabaseClient? client;
  try {
    client = ref.watch(supabaseClientProvider);
  } catch (_) {
    return null;
  }
  return client == null || client.auth.currentUser == null
      ? null
      : FocusSessionSupabaseDataSource(client);
});

const _recoveryPreferenceKey = 'focus-recovery-countdown-v1';

enum _PreparationChoice { ready, notNeeded }

class FocusSessionPage extends ConsumerStatefulWidget {
  const FocusSessionPage({
    super.key,
    this.initialTargetKind,
    this.initialTargetId,
    this.initialPlannedMinutes,
    this.initialRecoveryMinutes,
  });

  final FocusTargetKind? initialTargetKind;
  final String? initialTargetId;
  final int? initialPlannedMinutes;
  final int? initialRecoveryMinutes;

  @override
  ConsumerState<FocusSessionPage> createState() => _FocusSessionPageState();
}

class _FocusSessionPageState extends ConsumerState<FocusSessionPage> {
  FocusSession? _active;
  List<FocusSession> _recent = const [];
  List<FocusTargetOption> _targets = const [];
  String? _selectedTargetValue;
  bool _initialTargetApplied = false;
  bool _initialDurationApplied = false;
  int _plannedMinutes = 25;
  int _recoveryMinutes = 0;
  StudyFocusSettings? _studySettings;
  DateTime? _recoveryEndsAt;
  DateTime _clockNow = DateTime.now();
  Timer? _ticker;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    final requestedMinutes = widget.initialPlannedMinutes;
    if (requestedMinutes != null &&
        requestedMinutes >= 5 &&
        requestedMinutes <= 240) {
      _plannedMinutes = requestedMinutes;
    }
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
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
        else if (_loadError != null)
          _FocusLoadErrorCard(
            message: _loadError!,
            onRetry: _load,
          )
        else if (_active != null)
          _ActiveFocusCard(
            session: _active!,
            target: _targetFor(_active!),
            now: _clockNow,
            isSaving: _isSaving,
            onFinish: _finish,
            onAbandon: _abandon,
          )
        else if (_recoveryEndsAt?.isAfter(_clockNow) == true)
          _RecoveryCard(
            endsAt: _recoveryEndsAt!,
            now: _clockNow,
            onSkip: _skipRecovery,
          )
        else
          _StartFocusCard(
            plannedMinutes: _plannedMinutes,
            recoveryMinutes: _recoveryMinutes,
            suggestion: FocusPreferenceSuggestion.fromSessions(_recent),
            targets: _targets,
            selectedTargetValue: _selectedTargetValue,
            isSaving: _isSaving,
            onDurationChanged: (value) {
              setState(() => _plannedMinutes = value);
            },
            onCustomDuration: _chooseCustomDuration,
            onTargetChanged: (value) {
              setState(() => _selectedTargetValue = value);
            },
            onStart: _start,
          ),
        if (!_isLoading && _loadError == null)
          _FocusHistoryCard(sessions: _recent),
      ],
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    final config = ref.read(appConfigProvider);
    final source = ref.read(focusSessionPageDataSourceProvider);
    final studySource = ref.read(focusStudySettingsDataSourceProvider);
    if (config.useMockData) {
      if (mounted) {
        setState(() {
          _loadError = null;
          _isLoading = false;
        });
      }
      return;
    }
    if (source == null) {
      if (mounted) {
        setState(() {
          _loadError = 'Synced focus sessions are not configured.';
          _isLoading = false;
        });
      }
      return;
    }
    setState(() {
      _loadError = null;
      _isLoading = true;
    });
    try {
      final results = await Future.wait([
        source.fetchActiveSession(),
        source.fetchRecentSessions(),
        source.fetchAvailableTargets(),
        _fetchStudySettings(studySource),
      ]);
      final active = results[0] as FocusSession?;
      final recent = results[1] as List<FocusSession>;
      final targets = results[2] as List<FocusTargetOption>;
      final studySettings = results[3] as StudyFocusSettings?;
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
      if (selected != null &&
          !targets.any((target) => target.value == selected)) {
        selected = null;
      }
      var plannedMinutes = _plannedMinutes;
      if (!_initialDurationApplied) {
        _initialDurationApplied = true;
        if (widget.initialPlannedMinutes == null && active == null) {
          final terminal = recent.where((session) => !session.isActive);
          if (studySettings != null) {
            plannedMinutes = studySettings.focusMinutes;
          } else if (terminal.isNotEmpty) {
            plannedMinutes = terminal.first.plannedMinutes;
          }
        }
      }
      final requestedRecovery = widget.initialRecoveryMinutes;
      final recoveryMinutes = requestedRecovery != null &&
              (requestedRecovery == 0 ||
                  requestedRecovery >= 5 &&
                      requestedRecovery <= 60 &&
                      requestedRecovery.remainder(5) == 0)
          ? requestedRecovery
          : studySettings?.recoveryMinutes ?? 0;
      final recoveryEndsAt =
          active == null ? await _restoreRecoveryCountdown(recent) : null;
      if (mounted) {
        setState(() {
          _active = active;
          _recent = recent;
          _targets = targets;
          _selectedTargetValue = selected;
          _plannedMinutes = plannedMinutes;
          _recoveryMinutes = recoveryMinutes;
          _studySettings = studySettings;
          _recoveryEndsAt = recoveryEndsAt;
          _clockNow = DateTime.now();
          _loadError = null;
          _isLoading = false;
        });
        _syncTicker();
      }
    } catch (_) {
      if (!mounted) return;
      if (mounted) {
        setState(() {
          _loadError = 'Could not load focus sessions.';
          _isLoading = false;
        });
      }
    }
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (_active == null && _recoveryEndsAt?.isAfter(DateTime.now()) != true) {
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final recoveryEndsAt = _recoveryEndsAt;
      if (_active == null &&
          recoveryEndsAt != null &&
          !recoveryEndsAt.isAfter(now)) {
        setState(() {
          _clockNow = now;
          _recoveryEndsAt = null;
        });
        _ticker?.cancel();
        _ticker = null;
        unawaited(_clearStoredRecovery());
        return;
      }
      setState(() => _clockNow = now);
    });
  }

  Future<StudyFocusSettings?> _fetchStudySettings(
    FocusSessionSupabaseDataSource? source,
  ) async {
    if (source == null) return null;
    try {
      return await source.fetchStudyFocusSettings();
    } catch (_) {
      // Focus execution remains usable when this optional projection is absent
      // or temporarily unavailable.
      return null;
    }
  }

  Future<void> _chooseCustomDuration() async {
    final controller = TextEditingController(text: '$_plannedMinutes');
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom focus duration'),
        content: TextField(
          key: const ValueKey('custom-focus-duration'),
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minutes',
            helperText: 'Between 5 and 240 minutes',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value != null && value >= 5 && value <= 240) {
                Navigator.of(context).pop(value);
              }
            },
            child: const Text('Use duration'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (selected != null && mounted) {
      setState(() => _plannedMinutes = selected);
    }
  }

  Future<void> _start() async {
    final source = ref.read(focusSessionPageDataSourceProvider);
    if (source == null || _isSaving) {
      return;
    }
    final prepared = await _confirmPreparation();
    if (prepared != true || !mounted) {
      return;
    }
    final target = _targets
        .where((candidate) => candidate.value == _selectedTargetValue)
        .firstOrNull;
    final requestId = newClientUuid();
    final snapshotRefresh = ref.read(snapshotRefreshServiceProvider);
    setState(() => _isSaving = true);
    try {
      final started = await source.startSession(
        sessionId: requestId,
        draft: FocusStartDraft(
          plannedMinutes: _plannedMinutes,
          recoveryMinutes: _recoveryMinutes,
          targetKind: target?.kind,
          targetId: target?.id,
          label: target?.title ?? 'Independent focus block',
        ),
      );
      await _afterDurableWrite(started, snapshotRefresh);
      if (mounted) {
        _showMessage('Focus session started.');
      }
    } catch (error) {
      if (!mounted) {
        try {
          final active = await source.fetchActiveSession();
          if (active?.id == requestId) {
            await _afterDurableWrite(active!, snapshotRefresh);
          }
        } catch (_) {
          // The mutation remains honestly unconfirmed after navigation.
        }
        return;
      }
      await _load();
      if (!mounted) return;
      if (_active?.id == requestId) {
        await _afterDurableWrite(_active!, snapshotRefresh);
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
    final source = ref.read(focusSessionPageDataSourceProvider);
    if (active == null || source == null || _isSaving) {
      return;
    }
    final snapshotRefresh = ref.read(snapshotRefreshServiceProvider);
    setState(() => _isSaving = true);
    try {
      final finished = await source.finishSession(active.id);
      if (mounted) {
        setState(() => _selectedTargetValue = null);
      }
      await _startRecoveryCountdown(finished);
      await _afterDurableWrite(finished, snapshotRefresh);
      if (mounted) {
        _showMessage(
          finished.recoveryMinutes > 0
              ? 'Focus session finished. Recovery started; linked actions were not completed automatically.'
              : 'Focus session finished. Linked tasks and habits were not completed automatically.',
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

  Future<bool?> _confirmPreparation() {
    final items = _studySettings?.preparationItems
            .where((item) => item.active)
            .toList(growable: false) ??
        const <FocusPreparationItem>[];
    if (items.isEmpty) {
      return Future.value(true);
    }
    final choices = <String, _PreparationChoice?>{
      for (final item in items) item.key: null,
    };
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final complete = choices.values.every((choice) => choice != null);
          return AlertDialog(
            title: const Text('Prepare to focus'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'These choices are only for this start. They are not saved or evaluated.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppSpacing.md,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.label,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.xs,
                              children: [
                                ChoiceChip(
                                  label: const Text('Ready'),
                                  selected: choices[item.key] ==
                                      _PreparationChoice.ready,
                                  onSelected: (_) {
                                    setDialogState(() {
                                      choices[item.key] =
                                          _PreparationChoice.ready;
                                    });
                                  },
                                ),
                                ChoiceChip(
                                  label: const Text('Not needed today'),
                                  selected: choices[item.key] ==
                                      _PreparationChoice.notNeeded,
                                  onSelected: (_) {
                                    setDialogState(() {
                                      choices[item.key] =
                                          _PreparationChoice.notNeeded;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                key: const ValueKey('focus-skip-preparation'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Skip remaining and start'),
              ),
              FilledButton(
                key: const ValueKey('focus-preparation-start'),
                onPressed: complete
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: const Text('Start'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _startRecoveryCountdown(FocusSession session) async {
    if (session.recoveryMinutes <= 0 ||
        session.status != FocusSessionStatus.completed) {
      return;
    }
    final startedAt = session.endedAt ?? DateTime.now();
    final endsAt = startedAt.add(
      Duration(minutes: session.recoveryMinutes),
    );
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _recoveryPreferenceKey,
        '${session.id}|${endsAt.toUtc().toIso8601String()}',
      );
    } catch (_) {
      // The visible countdown still works for this app process.
    }
    if (mounted) {
      setState(() {
        _clockNow = DateTime.now();
        _recoveryEndsAt = endsAt;
      });
      _syncTicker();
    }
  }

  Future<DateTime?> _restoreRecoveryCountdown(
    List<FocusSession> recent,
  ) async {
    final completedRecoveryIds = recent
        .where(
          (session) =>
              session.status == FocusSessionStatus.completed &&
              session.recoveryMinutes > 0,
        )
        .map((session) => session.id)
        .toSet();
    if (completedRecoveryIds.isEmpty) {
      return null;
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_recoveryPreferenceKey);
      if (raw == null) return null;
      final separator = raw.indexOf('|');
      if (separator <= 0) {
        await preferences.remove(_recoveryPreferenceKey);
        return null;
      }
      final sessionId = raw.substring(0, separator);
      final endsAt = DateTime.tryParse(raw.substring(separator + 1));
      if (!completedRecoveryIds.contains(sessionId) ||
          endsAt == null ||
          !endsAt.isAfter(DateTime.now())) {
        await preferences.remove(_recoveryPreferenceKey);
        return null;
      }
      return endsAt.toLocal();
    } catch (_) {
      return null;
    }
  }

  Future<void> _skipRecovery() async {
    await _clearStoredRecovery();
    if (!mounted) return;
    setState(() {
      _recoveryEndsAt = null;
      _clockNow = DateTime.now();
    });
    _syncTicker();
  }

  Future<void> _clearStoredRecovery() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_recoveryPreferenceKey);
    } catch (_) {
      // Local storage availability must not block Focus.
    }
  }

  Future<void> _abandon() async {
    final active = _active;
    final source = ref.read(focusSessionPageDataSourceProvider);
    if (active == null || source == null || _isSaving) {
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
    final snapshotRefresh = ref.read(snapshotRefreshServiceProvider);
    setState(() => _isSaving = true);
    try {
      await source.abandonSession(active.id);
      if (mounted) {
        setState(() => _selectedTargetValue = null);
      }
      await _afterDurableWrite(active, snapshotRefresh);
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

  Future<void> _afterDurableWrite(
    FocusSession session,
    SnapshotRefreshService snapshotRefresh,
  ) async {
    await snapshotRefresh.refreshDailyAfterFocusChange(
      targetDate: session.snapshotEntryDate,
    );
    if (!mounted) return;
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

class _FocusLoadErrorCard extends StatelessWidget {
  const _FocusLoadErrorCard({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'No empty focus state was assumed. Check your connection and '
            'try again.',
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _StartFocusCard extends StatelessWidget {
  const _StartFocusCard({
    required this.plannedMinutes,
    required this.recoveryMinutes,
    required this.suggestion,
    required this.targets,
    required this.selectedTargetValue,
    required this.isSaving,
    required this.onDurationChanged,
    required this.onCustomDuration,
    required this.onTargetChanged,
    required this.onStart,
  });

  final int plannedMinutes;
  final int recoveryMinutes;
  final FocusPreferenceSuggestion? suggestion;
  final List<FocusTargetOption> targets;
  final String? selectedTargetValue;
  final bool isSaving;
  final ValueChanged<int> onDurationChanged;
  final VoidCallback onCustomDuration;
  final ValueChanged<String?> onTargetChanged;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final durations = <int>{
      25,
      50,
      90,
      plannedMinutes,
      if (suggestion != null) suggestion!.durationMinutes,
    }.toList()
      ..sort();
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
          if (recoveryMinutes > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '$plannedMinutes min focus + $recoveryMinutes min recovery',
              key: const ValueKey('focus-rhythm-summary'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SegmentedButton<int>(
            direction: _focusChoiceDirection(context),
            segments: [
              for (final minutes in durations)
                ButtonSegment(
                  value: minutes,
                  label: Text('$minutes min'),
                ),
            ],
            selected: {plannedMinutes},
            onSelectionChanged:
                isSaving ? null : (values) => onDurationChanged(values.single),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: isSaving ? null : onCustomDuration,
              icon: const Icon(Icons.tune),
              label: const Text('Custom duration'),
            ),
          ),
          if (suggestion != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.insights_outlined, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Your ${suggestion!.evidenceSessions} recent completed sessions cluster around '
                      '${suggestion!.durationMinutes} minutes'
                      '${suggestion!.timeWindowLabel == null ? '' : ' ${suggestion!.timeWindowLabel}'}. '
                      'This is a suggestion, not an automatic setting.',
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          DropdownButtonFormField<String?>(
            key: ValueKey('focus-target-selector-$selectedTargetValue'),
            initialValue: selectedTargetValue,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Linked action optional',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  'Independent focus block',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ...targets.map(
                (target) => DropdownMenuItem<String?>(
                  value: target.value,
                  child: Text(
                    '${target.kind == FocusTargetKind.task ? 'Task' : 'Habit'}: '
                    '${target.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
    required this.now,
    required this.isSaving,
    required this.onFinish,
    required this.onAbandon,
  });

  final FocusSession session;
  final FocusTargetOption? target;
  final DateTime now;
  final bool isSaving;
  final VoidCallback onFinish;
  final VoidCallback onAbandon;

  @override
  Widget build(BuildContext context) {
    final plannedEnd = session.startedAt.add(
      Duration(minutes: session.plannedMinutes),
    );
    final elapsed = now.isAfter(session.startedAt)
        ? now.difference(session.startedAt)
        : Duration.zero;
    final remaining =
        plannedEnd.isAfter(now) ? plannedEnd.difference(now) : Duration.zero;
    final plannedDuration = Duration(minutes: session.plannedMinutes);
    final progress = elapsed.inMilliseconds / plannedDuration.inMilliseconds;
    final reachedPlan = !plannedEnd.isAfter(now);
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
              Expanded(
                child: Text(
                  'Focus active',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(session.label ?? target?.title ?? 'Independent focus block'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Started ${DateFormat.Hm().format(session.startedAt.toLocal())} · '
            '${session.plannedMinutes} planned minutes'
            '${session.recoveryMinutes > 0 ? ' · ${session.recoveryMinutes} min recovery after completion' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            liveRegion: reachedPlan,
            label: reachedPlan
                ? 'Planned focus time reached'
                : '${_focusTimerText(remaining)} remaining',
            child: Text(
              reachedPlan
                  ? '+${_focusTimerText(now.difference(plannedEnd))}'
                  : _focusTimerText(remaining),
              key: const ValueKey('focus-countdown'),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            reachedPlan
                ? 'Planned time reached'
                : 'Ends at ${DateFormat.Hm().format(plannedEnd.toLocal())}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(value: progress.clamp(0, 1)),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            key: const ValueKey('active-focus-actions'),
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              TextButton(
                onPressed: isSaving ? null : onAbandon,
                child: const Text('Abandon'),
              ),
              FilledButton(
                onPressed: isSaving ? null : onFinish,
                child: const Text(
                  'Finish focus session',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({
    required this.endsAt,
    required this.now,
    required this.onSkip,
  });

  final DateTime endsAt;
  final DateTime now;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final remaining =
        endsAt.isAfter(now) ? endsAt.difference(now) : Duration.zero;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.self_improvement_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Recovery break',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'This local countdown is not a focus session and does not add progress or preparation time.',
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            liveRegion: true,
            label: '${_focusTimerText(remaining)} recovery remaining',
            child: Text(
              _focusTimerText(remaining),
              key: const ValueKey('recovery-countdown'),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Reserved recovery ends at ${DateFormat.Hm().format(endsAt)}',
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('skip-recovery'),
              onPressed: onSkip,
              child: const Text('Skip recovery'),
            ),
          ),
        ],
      ),
    );
  }
}

Axis _focusChoiceDirection(BuildContext context) {
  final scaledBody = MediaQuery.textScalerOf(context).scale(14);
  return MediaQuery.sizeOf(context).width < 420 || scaledBody > 20
      ? Axis.vertical
      : Axis.horizontal;
}

String _focusTimerText(Duration duration) {
  final safeSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = safeSeconds ~/ 3600;
  final minutes = safeSeconds.remainder(3600) ~/ 60;
  final seconds = safeSeconds.remainder(60);
  final minuteText = minutes.toString().padLeft(2, '0');
  final secondText = seconds.toString().padLeft(2, '0');
  return hours > 0
      ? '${hours.toString().padLeft(2, '0')}:$minuteText:$secondText'
      : '$minuteText:$secondText';
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
