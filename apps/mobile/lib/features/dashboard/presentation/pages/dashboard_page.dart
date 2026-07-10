import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/supabase/supabase_tables.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../optimization/domain/entities/recommendation_feed.dart';
import '../../../optimization/presentation/providers/optimization_providers.dart';
import '../../../snapshots/presentation/providers/snapshot_providers.dart';
import '../../domain/entities/dashboard_snapshot.dart';
import '../providers/dashboard_providers.dart';
import '../widgets/recommendation_card.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  final Set<String> _completedTaskIds = {};
  final Set<String> _restoredTaskIds = {};
  final Set<String> _deletedTaskIds = {};
  final Set<String> _updatingTaskIds = {};
  bool _showCompletedTasks = false;
  bool _isRefreshingRecommendations = false;
  String? _recommendationRefreshError;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(dashboardSnapshotProvider);
    final recommendations = ref.watch(recommendationFeedProvider);

    return snapshot.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _DashboardLoadError(
        onRetry: () => ref.invalidate(dashboardSnapshotProvider),
      ),
      data: (data) => _DashboardHome(
        snapshot: data,
        recommendations: recommendations,
        completedTaskIds: _completedTaskIds,
        restoredTaskIds: _restoredTaskIds,
        deletedTaskIds: _deletedTaskIds,
        updatingTaskIds: _updatingTaskIds,
        showCompletedTasks: _showCompletedTasks,
        isRefreshingRecommendations: _isRefreshingRecommendations,
        recommendationRefreshError: _recommendationRefreshError,
        onAddCheckIn: () => context.go(AppRoutes.dailyCheckIn),
        onRetryRecommendations: () {
          setState(() => _recommendationRefreshError = null);
          ref.invalidate(recommendationFeedProvider);
        },
        onRefreshRecommendations: _refreshRecommendations,
        onCompleteTask: (id) => _changeTaskStatus(id, 'done'),
        onRestoreTask: (id) => _changeTaskStatus(id, 'todo'),
        onDeleteTask: (id) => _changeTaskStatus(id, 'cancelled'),
        onToggleCompletedTasks: () {
          setState(() => _showCompletedTasks = !_showCompletedTasks);
        },
      ),
    );
  }

  Future<void> _refreshRecommendations() async {
    if (_isRefreshingRecommendations) {
      return;
    }

    setState(() {
      _isRefreshingRecommendations = true;
      _recommendationRefreshError = null;
    });
    try {
      await ref
          .read(snapshotRefreshServiceProvider)
          .refreshDailyAfterUserSignal();
      await ref
          .read(optimizationServiceProvider)
          .refreshActionableRecommendations();
      ref.invalidate(recommendationFeedProvider);
      ref.invalidate(dashboardSnapshotProvider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recommendations checked.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _recommendationRefreshError =
            'Refresh failed. Existing recommendations were kept.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recommendations could not be refreshed.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRefreshingRecommendations = false);
      }
    }
  }

  Future<void> _changeTaskStatus(String id, String status) async {
    if (_updatingTaskIds.contains(id)) {
      return;
    }

    setState(() {
      _updatingTaskIds.add(id);
      _applyLocalTaskStatus(id, status);
    });

    final client = ref.read(supabaseClientProvider);
    if (client == null) {
      if (mounted) {
        setState(() {
          _updatingTaskIds.remove(id);
          _clearLocalTaskStatus(id);
        });
      }
      return;
    }

    try {
      await client.from(SupabaseTables.tasks).update({
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
      await ref
          .read(snapshotRefreshServiceProvider)
          .refreshDailyAfterTaskChange();
      ref.invalidate(dashboardSnapshotProvider);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _clearLocalTaskStatus(id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task update could not be saved.')),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingTaskIds.remove(id));
      }
    }
  }

  void _applyLocalTaskStatus(String id, String status) {
    _completedTaskIds.remove(id);
    _restoredTaskIds.remove(id);
    _deletedTaskIds.remove(id);
    switch (status) {
      case 'done':
        _completedTaskIds.add(id);
      case 'todo':
        _restoredTaskIds.add(id);
      case 'cancelled':
        _deletedTaskIds.add(id);
    }
  }

  void _clearLocalTaskStatus(String id) {
    _completedTaskIds.remove(id);
    _restoredTaskIds.remove(id);
    _deletedTaskIds.remove(id);
  }
}

class _DashboardHome extends StatelessWidget {
  const _DashboardHome({
    required this.snapshot,
    required this.recommendations,
    required this.completedTaskIds,
    required this.restoredTaskIds,
    required this.deletedTaskIds,
    required this.updatingTaskIds,
    required this.showCompletedTasks,
    required this.isRefreshingRecommendations,
    required this.recommendationRefreshError,
    required this.onAddCheckIn,
    required this.onRetryRecommendations,
    required this.onRefreshRecommendations,
    required this.onCompleteTask,
    required this.onRestoreTask,
    required this.onDeleteTask,
    required this.onToggleCompletedTasks,
  });

  final DashboardSnapshot snapshot;
  final AsyncValue<RecommendationFeed> recommendations;
  final Set<String> completedTaskIds;
  final Set<String> restoredTaskIds;
  final Set<String> deletedTaskIds;
  final Set<String> updatingTaskIds;
  final bool showCompletedTasks;
  final bool isRefreshingRecommendations;
  final String? recommendationRefreshError;
  final VoidCallback onAddCheckIn;
  final VoidCallback onRetryRecommendations;
  final VoidCallback onRefreshRecommendations;
  final ValueChanged<String> onCompleteTask;
  final ValueChanged<String> onRestoreTask;
  final ValueChanged<String> onDeleteTask;
  final VoidCallback onToggleCompletedTasks;

  @override
  Widget build(BuildContext context) {
    final activeTasks = snapshot.todayPlan.where((item) {
      final completed = completedTaskIds.contains(item.id) ||
          (item.isCompleted && !restoredTaskIds.contains(item.id));
      return !completed && !deletedTaskIds.contains(item.id);
    }).toList();
    final completedTasks = snapshot.todayPlan.where((item) {
      final completed = completedTaskIds.contains(item.id) ||
          (item.isCompleted && !restoredTaskIds.contains(item.id));
      return completed && !deletedTaskIds.contains(item.id);
    }).toList();

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding =
              constraints.maxWidth < 600 ? AppSpacing.md : AppSpacing.xl;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  AppSpacing.md,
                  horizontalPadding,
                  AppSpacing.xxl,
                ),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DashboardHeader(snapshot: snapshot),
                          const SizedBox(height: AppSpacing.lg),
                          _LatestCheckInCard(
                            snapshot: snapshot,
                            onAddCheckIn: onAddCheckIn,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          _RecommendationsSection(
                            value: recommendations,
                            accountData:
                                snapshot.origin == DashboardOrigin.account,
                            isRefreshing: isRefreshingRecommendations,
                            refreshError: recommendationRefreshError,
                            onRetry: onRetryRecommendations,
                            onRefresh: onRefreshRecommendations,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          _TasksSection(
                            activeTasks: activeTasks,
                            completedTasks: completedTasks,
                            updatingTaskIds: updatingTaskIds,
                            showCompletedTasks: showCompletedTasks,
                            onComplete: onCompleteTask,
                            onRestore: onRestoreTask,
                            onDelete: onDeleteTask,
                            onToggleCompleted: onToggleCompletedTasks,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          _ScheduleSection(days: snapshot.scheduleDays),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('EEEE, MMMM d').format(DateTime.now());
    final sourceLabel = snapshot.origin == DashboardOrigin.localDemo
        ? 'Local data'
        : 'Your account data';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(date, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.xs),
              Text('Today', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '$sourceLabel · updated ${DateFormat.Hm().format(snapshot.loadedAt)}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
        IconButton.outlined(
          tooltip: 'Settings',
          onPressed: () => context.go(AppRoutes.settings),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }
}

class _LatestCheckInCard extends StatelessWidget {
  const _LatestCheckInCard({
    required this.snapshot,
    required this.onAddCheckIn,
  });

  final DashboardSnapshot snapshot;
  final VoidCallback onAddCheckIn;

  @override
  Widget build(BuildContext context) {
    final checkIn = snapshot.latestCheckIn;
    final metrics =
        checkIn == null ? const <_SignalMetric>[] : _metricsForCheckIn(checkIn);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Latest check-in',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      checkIn == null
                          ? 'No daily signals have been saved yet.'
                          : _checkInDateLabel(checkIn.entryDate),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (snapshot.checkInStreakDays > 0)
                _StatusPill(
                  icon: Icons.local_fire_department_outlined,
                  label: '${snapshot.checkInStreakDays} day streak',
                ),
            ],
          ),
          if (metrics.isEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onAddCheckIn,
              icon: const Icon(Icons.add_chart_outlined),
              label: const Text('Add check-in'),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children:
                  metrics.map((metric) => _SignalTile(metric: metric)).toList(),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton.icon(
              onPressed: onAddCheckIn,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Update today\'s check-in'),
            ),
          ],
        ],
      ),
    );
  }

  List<_SignalMetric> _metricsForCheckIn(DashboardCheckIn checkIn) {
    return [
      if (checkIn.mood != null)
        _SignalMetric('Mood', '${checkIn.mood}/10', Icons.mood_outlined),
      if (checkIn.energy != null)
        _SignalMetric('Energy', '${checkIn.energy}/10', Icons.bolt_outlined),
      if (checkIn.sleepHours != null)
        _SignalMetric(
          'Sleep',
          '${_formatDecimal(checkIn.sleepHours!)} h',
          Icons.bedtime_outlined,
        ),
      if (checkIn.stress != null)
        _SignalMetric(
          'Stress',
          '${checkIn.stress}/10',
          Icons.speed_outlined,
        ),
      if (checkIn.focusMinutes != null)
        _SignalMetric(
          'Focus',
          '${checkIn.focusMinutes} min',
          Icons.timer_outlined,
        ),
      if (checkIn.steps != null)
        _SignalMetric(
          'Steps',
          NumberFormat.decimalPattern().format(checkIn.steps),
          Icons.directions_walk_outlined,
        ),
      if (checkIn.activityLevel != null)
        _SignalMetric(
          'Activity',
          '${checkIn.activityLevel}/10',
          Icons.fitness_center_outlined,
        ),
      if (checkIn.screenTimeHours != null)
        _SignalMetric(
          'Screen time',
          '${_formatDecimal(checkIn.screenTimeHours!)} h',
          Icons.devices_outlined,
        ),
    ];
  }

  String _checkInDateLabel(DateTime value) {
    final now = DateTime.now();
    final date = DateTime(value.year, value.month, value.day);
    final today = DateTime(now.year, now.month, now.day);
    if (date == today) {
      return 'Today · values shown exactly as saved';
    }
    if (date == today.subtract(const Duration(days: 1))) {
      return 'Yesterday · values shown exactly as saved';
    }
    return '${DateFormat.yMMMd().format(value)} · values shown exactly as saved';
  }

  String _formatDecimal(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }
}

class _SignalTile extends StatelessWidget {
  const _SignalTile({required this.metric});

  final _SignalMetric metric;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 142,
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(metric.icon, size: 20, color: colors.primary),
          const SizedBox(height: AppSpacing.sm),
          Text(metric.value, style: Theme.of(context).textTheme.titleMedium),
          Text(metric.label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _RecommendationsSection extends StatelessWidget {
  const _RecommendationsSection({
    required this.value,
    required this.accountData,
    required this.isRefreshing,
    required this.refreshError,
    required this.onRetry,
    required this.onRefresh,
  });

  final AsyncValue<RecommendationFeed> value;
  final bool accountData;
  final bool isRefreshing;
  final String? refreshError;
  final VoidCallback onRetry;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Next actions',
          subtitle: 'A short list ranked from your available signals.',
          trailing: accountData
              ? OutlinedButton.icon(
                  onPressed: isRefreshing ? null : onRefresh,
                  icon: isRefreshing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh recommendations'),
                )
              : null,
        ),
        if (refreshError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _InlineMessage(
            icon: Icons.error_outline,
            message: refreshError!,
            color: Theme.of(context).colorScheme.error,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        value.when(
          loading: () => const AppCard(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: CircularProgressIndicator(),
              ),
            ),
          ),
          error: (error, stackTrace) => _SectionErrorCard(
            title: 'Recommendations unavailable',
            message: 'Your account data was not replaced with demo content.',
            onRetry: onRetry,
          ),
          data: (feed) => _RecommendationFeedView(feed: feed),
        ),
      ],
    );
  }
}

class _RecommendationFeedView extends StatelessWidget {
  const _RecommendationFeedView({required this.feed});

  final RecommendationFeed feed;

  @override
  Widget build(BuildContext context) {
    final isDemo = feed.provenance == RecommendationProvenance.demo;
    final freshness = switch (feed.freshness) {
      RecommendationFreshness.current => 'Current',
      RecommendationFreshness.missing => 'Not generated yet',
      RecommendationFreshness.olderThanSevenDays => 'Older than 7 days',
      RecommendationFreshness.periodMismatch => 'From an earlier period',
      RecommendationFreshness.notApplicable => 'Demo',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _StatusPill(
              icon: isDemo ? Icons.science_outlined : Icons.rule_outlined,
              label: isDemo
                  ? 'Demo recommendations'
                  : 'Deterministic recommendations',
            ),
            _StatusPill(
              icon: feed.freshness.needsRefresh
                  ? Icons.history
                  : Icons.check_circle_outline,
              label: freshness,
            ),
            if (feed.generatedAt != null)
              _StatusPill(
                icon: Icons.schedule,
                label: DateFormat.yMMMd().add_Hm().format(feed.generatedAt!),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (feed.items.isEmpty)
          const _EmptySectionCard(
            icon: Icons.lightbulb_outline,
            message: 'No current recommendations yet.',
          )
        else
          ...feed.items.take(3).map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: RecommendationCard(recommendation: item),
                ),
              ),
      ],
    );
  }
}

class _TasksSection extends StatelessWidget {
  const _TasksSection({
    required this.activeTasks,
    required this.completedTasks,
    required this.updatingTaskIds,
    required this.showCompletedTasks,
    required this.onComplete,
    required this.onRestore,
    required this.onDelete,
    required this.onToggleCompleted,
  });

  final List<PlanItem> activeTasks;
  final List<PlanItem> completedTasks;
  final Set<String> updatingTaskIds;
  final bool showCompletedTasks;
  final ValueChanged<String> onComplete;
  final ValueChanged<String> onRestore;
  final ValueChanged<String> onDelete;
  final VoidCallback onToggleCompleted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'Tasks',
          subtitle: 'Open items from your task list.',
        ),
        const SizedBox(height: AppSpacing.md),
        if (activeTasks.isEmpty)
          const _EmptySectionCard(
            icon: Icons.task_alt_outlined,
            message: 'No open tasks.',
          )
        else
          ...activeTasks.map(
            (task) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _TaskCard(
                task: task,
                isUpdating: updatingTaskIds.contains(task.id),
                onComplete: () => onComplete(task.id),
                onDelete: () => onDelete(task.id),
              ),
            ),
          ),
        if (completedTasks.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: onToggleCompleted,
            icon: Icon(
              showCompletedTasks ? Icons.expand_less : Icons.expand_more,
            ),
            label: Text('Completed (${completedTasks.length})'),
          ),
          if (showCompletedTasks)
            ...completedTasks.map(
              (task) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _TaskCard(
                  task: task,
                  isUpdating: updatingTaskIds.contains(task.id),
                  isCompleted: true,
                  onRestore: () => onRestore(task.id),
                  onDelete: () => onDelete(task.id),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.isUpdating,
    this.isCompleted = false,
    this.onComplete,
    this.onRestore,
    this.onDelete,
  });

  final PlanItem task;
  final bool isUpdating;
  final bool isCompleted;
  final VoidCallback? onComplete;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final due = task.deadline == null
        ? null
        : 'Due ${DateFormat.yMMMd().format(task.deadline!)}';
    return AppCard(
      child: Row(
        children: [
          Icon(
            isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isCompleted
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        decoration:
                            isCompleted ? TextDecoration.lineThrough : null,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  [task.priority, if (due != null) due].join(' · '),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (isUpdating)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            if (onComplete != null)
              IconButton(
                tooltip: 'Complete task',
                onPressed: onComplete,
                icon: const Icon(Icons.check),
              ),
            if (onRestore != null)
              IconButton(
                tooltip: 'Restore task',
                onPressed: onRestore,
                icon: const Icon(Icons.undo),
              ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Remove task',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ],
      ),
    );
  }
}

class _ScheduleSection extends StatelessWidget {
  const _ScheduleSection({required this.days});

  final List<ScheduleDay> days;

  @override
  Widget build(BuildContext context) {
    final daysWithEvents = days.where((day) => day.events.isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'Commitments',
          subtitle: 'Schedule entries for this week.',
        ),
        const SizedBox(height: AppSpacing.md),
        if (daysWithEvents.isEmpty)
          const _EmptySectionCard(
            icon: Icons.calendar_today_outlined,
            message: 'No schedule entries this week.',
          )
        else
          ...daysWithEvents.map(
            (day) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 70,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            day.label,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            day.dateLabel,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: day.events
                            .map(
                              (event) => Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.sm,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.event, size: 18),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(event.title),
                                          Text(
                                            event.time,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.md),
          trailing!,
        ],
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(message)),
      ],
    );
  }
}

class _SectionErrorCard extends StatelessWidget {
  const _SectionErrorCard({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _EmptySectionCard extends StatelessWidget {
  const _EmptySectionCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _DashboardLoadError extends StatelessWidget {
  const _DashboardLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 44,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Dashboard unavailable',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Your account data could not be loaded. No demo values were substituted.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignalMetric {
  const _SignalMetric(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}
