import 'package:flutter/material.dart';

import 'package:my_life_graph/core/constants/app_radii.dart';

import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_category_visuals.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/theme/app_visual_tokens.dart';
import '../../../../core/utils/client_uuid.dart';
import '../../../../core/utils/local_date.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../briefings/domain/decision_feedback.dart';
import '../../../briefings/presentation/providers/briefing_providers.dart';
import '../../../deadline_plans/domain/deadline_plan.dart';
import '../../../deadline_plans/presentation/providers/deadline_plan_providers.dart';
import '../../../deadline_plans/presentation/widgets/preparation_workload_card.dart';
import '../../../optimization/domain/entities/recommendation_feed.dart';
import '../../../optimization/presentation/providers/optimization_providers.dart';
import '../../../quick_action/data/habit_completion_supabase_data_source.dart';
import '../../../quick_action/domain/habit_v1.dart';
import '../../../snapshots/presentation/providers/snapshot_providers.dart';
import '../../../tasks/data/task_supabase_data_source.dart';
import '../../../tasks/domain/executable_task.dart';
import '../../domain/entities/dashboard_snapshot.dart';
import '../providers/dashboard_providers.dart';
import '../widgets/recommendation_card.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

enum _TodayProjectionStatus {
  current,
  refreshingAfterMutation,
  staleAfterMutation
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  final Set<String> _completedTaskIds = {};
  final Set<String> _restoredTaskIds = {};
  final Set<String> _deletedTaskIds = {};
  final Set<String> _updatingTaskIds = {};
  bool _showCompletedTasks = false;
  bool _showCancelledTasks = false;
  bool _showAllTasks = false;
  bool _showMore = false;
  bool _isRefreshingRecommendations = false;
  String? _recommendationRefreshError;
  final Set<String> _updatingHabitIds = {};
  final Map<String, String?> _habitOutcomeOverrides = {};
  _TodayProjectionStatus _todayProjectionStatus =
      _TodayProjectionStatus.current;
  DashboardSnapshot? _displayedSnapshot;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(dashboardSnapshotProvider);
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    final recommendations =
        _showMore ? ref.watch(recommendationFeedProvider) : null;
    final workload = _showMore && capabilities.canUseDeadlinePlanner
        ? ref.watch(preparationWorkloadProvider)
        : null;
    final supporting =
        _showMore ? ref.watch(dashboardSupportingSnapshotProvider) : null;
    final visibleSnapshot = _displayedSnapshot ?? snapshot.valueOrNull;

    if (visibleSnapshot == null) {
      return snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _DashboardLoadError(
          onRetry: () => ref.invalidate(dashboardSnapshotProvider),
        ),
        data: (_) => const SizedBox.shrink(),
      );
    }
    final projectionCurrent =
        _todayProjectionStatus == _TodayProjectionStatus.current &&
            !snapshot.isRefreshing;
    final data = visibleSnapshot;
    return _DashboardHome(
      snapshot: data,
      recommendations: recommendations,
      workload: workload,
      supporting: supporting,
      onRetryWorkload: () => ref.invalidate(preparationWorkloadProvider),
      onLoadWorkloadDetail: (localDate) =>
          ref.read(deadlinePlanRepositoryProvider).getWorkloadDetail(localDate),
      completedTaskIds: _completedTaskIds,
      restoredTaskIds: _restoredTaskIds,
      deletedTaskIds: _deletedTaskIds,
      updatingTaskIds: _updatingTaskIds,
      showCompletedTasks: _showCompletedTasks,
      showCancelledTasks: _showCancelledTasks,
      showAllTasks: _showAllTasks,
      showMore: _showMore,
      updatingHabitIds: _updatingHabitIds,
      habitOutcomeOverrides: _habitOutcomeOverrides,
      projectionCurrent: projectionCurrent,
      projectionStale:
          _todayProjectionStatus == _TodayProjectionStatus.staleAfterMutation,
      onReloadToday: _reloadTodayOnly,
      isRefreshingRecommendations: _isRefreshingRecommendations,
      recommendationRefreshError: _recommendationRefreshError,
      onAddEvening: () => context.push(AppRoutes.dailyCheckIn),
      onAddMorning: () => context.push(AppRoutes.morningCalibration),
      canUseWeeklyReview: capabilities.canUseWeeklyReview,
      onOpenWeeklyReview: () => context.push(AppRoutes.weeklyReview),
      onRetryRecommendations: () {
        setState(() => _recommendationRefreshError = null);
        ref.invalidate(recommendationFeedProvider);
      },
      onRefreshRecommendations: _refreshRecommendations,
      onShowFeedbackHistory: _showFeedbackHistory,
      onAddTask: () => context.push(AppRoutes.planner),
      onEditTask: _openTaskOrPreparationPlan,
      onCompleteTask: _completeTask,
      onRestoreTask: _restoreTask,
      onCancelTask: _cancelTask,
      onPostponeTask: _postponeTask,
      onStartFocus: (task) => context.push(
        '${AppRoutes.deepWork}?target_kind=task&target_id=${task.id}',
      ),
      onSetHabitOutcome: (habit, outcome) => _setHabitOutcome(
        habit,
        outcome,
        data.localDate,
      ),
      onUndoHabitOutcome: (habit) => _undoHabitOutcome(
        habit,
        data.localDate,
      ),
      onOpenPreparationPlan: (planId) => context.push(
        Uri(
          path: AppRoutes.preparationPlans,
          queryParameters: {'plan_id': planId},
        ).toString(),
      ),
      onStartPreparationFocus: (taskId) => context.push(
        '${AppRoutes.deepWork}?target_kind=task&target_id=$taskId',
      ),
      onToggleAllTasks: () {
        setState(() => _showAllTasks = !_showAllTasks);
      },
      onToggleMore: () {
        setState(() => _showMore = !_showMore);
      },
      onToggleCompletedTasks: () {
        setState(() => _showCompletedTasks = !_showCompletedTasks);
      },
      onToggleCancelledTasks: () {
        setState(() => _showCancelledTasks = !_showCancelledTasks);
      },
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
          .refreshDailyAfterUserSignal(
            targetDate: localDateKey(DateTime.now()),
          );
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

  Future<void> _showFeedbackHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FeedbackHistorySheet(),
    );
  }

  Future<void> _setHabitOutcome(
    TodayHabit habit,
    HabitOutcome outcome,
    DateTime? targetDate,
  ) async {
    if (_todayProjectionStatus != _TodayProjectionStatus.current ||
        targetDate == null ||
        _updatingHabitIds.contains(habit.id)) {
      if (targetDate == null) {
        _showTaskMessage(
          'Today is unavailable. Reload before changing habits.',
        );
      }
      return;
    }
    setState(() => _updatingHabitIds.add(habit.id));
    var committed = false;
    try {
      final source = _habitSource();
      await source.setTodayOutcome(
        habitId: habit.id,
        outcome: outcome,
        targetDate: targetDate,
      );
      committed = true;
      if (mounted) {
        setState(() {
          _habitOutcomeOverrides[habit.id] = outcome.code;
          _todayProjectionStatus =
              _TodayProjectionStatus.refreshingAfterMutation;
        });
      }
      final projectionCurrent = await _refreshTodayAfterMutation(
        () => ref
            .read(snapshotRefreshServiceProvider)
            .refreshDailyAfterHabitChange(targetDate: habitDateKey(targetDate)),
      );
      if (mounted) {
        _showTaskMessage(
          projectionCurrent
              ? outcome == HabitOutcome.completed
                  ? 'Habit completed.'
                  : 'Habit intentionally skipped.'
              : 'Saved; Today could not reload.',
        );
      }
    } catch (error) {
      if (mounted) {
        _showTaskMessage(
          committed
              ? 'Saved; Today could not reload.'
              : error is HabitCommandException
                  ? error.message
                  : 'Habit update could not be saved.',
        );
      }
    } finally {
      if (mounted) setState(() => _updatingHabitIds.remove(habit.id));
    }
  }

  Future<void> _undoHabitOutcome(
    TodayHabit habit,
    DateTime? targetDate,
  ) async {
    if (_todayProjectionStatus != _TodayProjectionStatus.current ||
        targetDate == null ||
        _updatingHabitIds.contains(habit.id)) {
      if (targetDate == null) {
        _showTaskMessage(
          'Today is unavailable. Reload before changing habits.',
        );
      }
      return;
    }
    setState(() => _updatingHabitIds.add(habit.id));
    var committed = false;
    try {
      await _habitSource().undoTodayOutcome(
        habitId: habit.id,
        targetDate: targetDate,
      );
      committed = true;
      if (mounted) {
        setState(() {
          _habitOutcomeOverrides[habit.id] = null;
          _todayProjectionStatus =
              _TodayProjectionStatus.refreshingAfterMutation;
        });
      }
      final projectionCurrent = await _refreshTodayAfterMutation(
        () => ref
            .read(snapshotRefreshServiceProvider)
            .refreshDailyAfterHabitChange(targetDate: habitDateKey(targetDate)),
      );
      if (mounted) {
        _showTaskMessage(
          projectionCurrent
              ? 'Habit outcome undone.'
              : 'Saved; Today could not reload.',
        );
      }
    } catch (error) {
      if (mounted) {
        _showTaskMessage(
          committed
              ? 'Saved; Today could not reload.'
              : error is HabitCommandException
                  ? error.message
                  : 'Habit undo could not be saved.',
        );
      }
    } finally {
      if (mounted) setState(() => _updatingHabitIds.remove(habit.id));
    }
  }

  HabitCompletionSupabaseDataSource _habitSource() {
    final source = ref.read(dashboardHabitDataSourceProvider);
    if (source == null) {
      throw const HabitCommandException('Synced habits are unavailable.');
    }
    return source;
  }

  Future<void> _completeTask(PlanItem task) async {
    if (_openManagedPreparationPlan(task)) return;
    await _mutateTaskWithUndo(
      task: task,
      successStatus: 'done',
      successMessage: 'Task completed.',
      mutation: (source) => source.completeTask(task.id),
    );
  }

  Future<void> _restoreTask(PlanItem task) async {
    if (_openManagedPreparationPlan(task)) return;
    if (_todayProjectionStatus != _TodayProjectionStatus.current) return;
    final targetDate = _currentAuthenticatedLocalDate();
    if (targetDate == null) {
      _showTaskMessage('Today is unavailable. Reload before changing tasks.');
      return;
    }
    await _mutateTask(
      task.id,
      () async {
        await _taskSource().restoreTask(task.id);
      },
      targetDate: targetDate,
      successStatus: 'todo',
      successMessage: 'Task restored.',
    );
  }

  Future<void> _cancelTask(PlanItem task) async {
    if (_openManagedPreparationPlan(task)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel task?'),
        content: Text('${task.title} will be hidden but kept in task history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep task'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel task'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _mutateTaskWithUndo(
      task: task,
      successStatus: 'cancelled',
      successMessage: 'Task cancelled.',
      mutation: (source) => source.cancelTask(task.id),
    );
  }

  Future<void> _postponeTask(PlanItem task) async {
    if (_openManagedPreparationPlan(task)) return;
    final now = DateTime.now();
    final initial = (task.deadline ?? now).add(const Duration(days: 1));
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate:
          DateTime(now.year, now.month, now.day).add(const Duration(days: 1)),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'Postpone task deadline',
    );
    if (selected == null || !mounted) {
      return;
    }
    final deadline = DateTime(
      selected.year,
      selected.month,
      selected.day,
      17,
    );
    await _mutateTaskWithUndo(
      task: task,
      successStatus: 'todo',
      successMessage: 'Task postponed.',
      mutation: (source) => source.postponeTask(
        taskId: task.id,
        newDeadline: deadline,
      ),
    );
  }

  Future<void> _openTaskEditor({
    PlanItem? task,
    ExecutableTaskDraft? retainedDraft,
    String? requestId,
  }) async {
    if (_todayProjectionStatus != _TodayProjectionStatus.current) return;
    if (task != null && _openManagedPreparationPlan(task)) return;
    final draft = await showModalBottomSheet<ExecutableTaskDraft>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TaskEditorSheet(
        task: task,
        retainedDraft: retainedDraft,
      ),
    );
    if (draft == null || !mounted) {
      return;
    }
    final targetDate = _currentAuthenticatedLocalDate();
    if (targetDate == null) {
      _showTaskMessage('Today is unavailable. Reload before changing tasks.');
      return;
    }
    final id = requestId ?? newClientUuid();
    setState(() => _updatingTaskIds.add(task?.id ?? id));
    try {
      final source = _taskSource();
      if (task == null) {
        await source.createTask(taskId: id, draft: draft);
        final due = draft.deadline;
        final qualifiesForToday = due != null &&
            !DateTime(due.year, due.month, due.day).isAfter(
              DateTime(
                targetDate.year,
                targetDate.month,
                targetDate.day,
              ),
            );
        if (!qualifiesForToday && mounted) {
          setState(() => _showAllTasks = true);
        }
      } else {
        await source.editTask(taskId: task.id, draft: draft);
      }
      if (mounted) {
        setState(() {
          _todayProjectionStatus =
              _TodayProjectionStatus.refreshingAfterMutation;
        });
      }
      final projectionCurrent = await _afterTaskWrite(targetDate);
      if (mounted) {
        _showTaskMessage(
          projectionCurrent
              ? task == null
                  ? 'Task added.'
                  : 'Task updated.'
              : 'Saved; Today could not reload.',
        );
      }
    } catch (error) {
      if (mounted) {
        final message = error is TaskCommandException
            ? error.message
            : task == null
                ? 'Task could not be added.'
                : 'Task could not be updated.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$message Your draft is retained.'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _openTaskEditor(
                task: task,
                retainedDraft: draft,
                requestId: id,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updatingTaskIds.remove(task?.id ?? id));
      }
    }
  }

  Future<void> _openTaskOrPreparationPlan(PlanItem task) async {
    if (_openManagedPreparationPlan(task)) return;
    await _openTaskEditor(task: task);
  }

  bool _openManagedPreparationPlan(PlanItem task) {
    final planId = task.deadlinePlanId;
    if (!task.isDeadlinePlanManaged || planId == null) return false;
    context.push(
      Uri(
        path: AppRoutes.preparationPlans,
        queryParameters: {'plan_id': planId},
      ).toString(),
    );
    return true;
  }

  Future<void> _mutateTaskWithUndo({
    required PlanItem task,
    required String successStatus,
    required String successMessage,
    required Future<TaskUndoToken> Function(TaskSupabaseDataSource) mutation,
  }) async {
    if (_todayProjectionStatus != _TodayProjectionStatus.current) return;
    final targetDate = _currentAuthenticatedLocalDate();
    if (targetDate == null) {
      _showTaskMessage('Today is unavailable. Reload before changing tasks.');
      return;
    }
    TaskUndoToken? undo;
    await _mutateTask(
      task.id,
      () async {
        undo = await mutation(_taskSource());
      },
      targetDate: targetDate,
      successStatus: successStatus,
      successMessage: successMessage,
      onSuccess: () {
        final token = undo;
        if (token == null) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => _undoTask(token),
            ),
          ),
        );
      },
    );
  }

  Future<void> _undoTask(TaskUndoToken token) async {
    final targetDate = _currentAuthenticatedLocalDate();
    if (targetDate == null) {
      _showTaskMessage('Today is unavailable. Reload before changing tasks.');
      return;
    }
    await _mutateTask(
      token.taskId,
      () async {
        await _taskSource().undo(token);
      },
      targetDate: targetDate,
      successStatus: token.status.code,
      successMessage: 'Task change undone.',
    );
  }

  Future<void> _mutateTask(
    String id,
    Future<void> Function() mutation, {
    required DateTime targetDate,
    required String successStatus,
    required String successMessage,
    VoidCallback? onSuccess,
  }) async {
    if (_todayProjectionStatus != _TodayProjectionStatus.current ||
        _updatingTaskIds.contains(id)) {
      return;
    }
    setState(() => _updatingTaskIds.add(id));
    try {
      await mutation();
      if (mounted) {
        setState(() {
          _applyLocalTaskStatus(id, successStatus);
          _todayProjectionStatus =
              _TodayProjectionStatus.refreshingAfterMutation;
        });
      }
      final projectionCurrent = await _afterTaskWrite(targetDate);
      if (mounted) {
        if (!projectionCurrent) {
          _showTaskMessage('Saved; Today could not reload.');
        } else if (onSuccess != null) {
          onSuccess();
        } else {
          _showTaskMessage(successMessage);
        }
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showTaskMessage(
        error is TaskCommandException
            ? error.message
            : 'Task update could not be saved.',
      );
    } finally {
      if (mounted) {
        setState(() => _updatingTaskIds.remove(id));
      }
    }
  }

  TaskSupabaseDataSource _taskSource() {
    final source = ref.read(dashboardTaskDataSourceProvider);
    if (source == null) {
      throw const TaskCommandException('Synced tasks are unavailable.');
    }
    return source;
  }

  Future<bool> _afterTaskWrite(DateTime targetDate) {
    return _refreshTodayAfterMutation(
      () => ref
          .read(snapshotRefreshServiceProvider)
          .refreshDailyAfterTaskChange(targetDate: localDateKey(targetDate)),
    );
  }

  DateTime? _currentAuthenticatedLocalDate() {
    final snapshot =
        _displayedSnapshot ?? ref.read(dashboardSnapshotProvider).valueOrNull;
    if (snapshot?.origin != DashboardOrigin.account) return null;
    return snapshot?.localDate;
  }

  Future<bool> _refreshTodayAfterMutation(
    Future<void> Function() refreshProjection,
  ) async {
    try {
      await refreshProjection();
      final fresh = await ref.read(dashboardRepositoryProvider).getSnapshot();
      if (fresh.origin != DashboardOrigin.account || fresh.localDate == null) {
        throw const DashboardUnavailableException(
          'Authenticated Today projection is incomplete.',
        );
      }
      if (!mounted) return false;
      setState(() {
        _displayedSnapshot = fresh;
        _todayProjectionStatus = _TodayProjectionStatus.current;
        _completedTaskIds.clear();
        _restoredTaskIds.clear();
        _deletedTaskIds.clear();
        _habitOutcomeOverrides.clear();
      });
      ref.invalidate(dashboardSupportingSnapshotProvider);
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _todayProjectionStatus = _TodayProjectionStatus.staleAfterMutation;
        });
      }
      return false;
    }
  }

  Future<void> _reloadTodayOnly() async {
    if (_todayProjectionStatus ==
        _TodayProjectionStatus.refreshingAfterMutation) {
      return;
    }
    setState(() {
      _todayProjectionStatus = _TodayProjectionStatus.refreshingAfterMutation;
    });
    try {
      final fresh = await ref.read(dashboardRepositoryProvider).getSnapshot();
      if (fresh.origin != DashboardOrigin.account || fresh.localDate == null) {
        throw const DashboardUnavailableException(
          'Authenticated Today projection is incomplete.',
        );
      }
      if (!mounted) return;
      setState(() {
        _displayedSnapshot = fresh;
        _todayProjectionStatus = _TodayProjectionStatus.current;
        _completedTaskIds.clear();
        _restoredTaskIds.clear();
        _deletedTaskIds.clear();
        _habitOutcomeOverrides.clear();
      });
      ref.invalidate(dashboardSupportingSnapshotProvider);
    } catch (_) {
      if (mounted) {
        setState(() {
          _todayProjectionStatus = _TodayProjectionStatus.staleAfterMutation;
        });
      }
    }
  }

  void _showTaskMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
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
}

class _DashboardHome extends StatelessWidget {
  const _DashboardHome({
    required this.snapshot,
    required this.recommendations,
    required this.workload,
    required this.supporting,
    required this.onRetryWorkload,
    required this.onLoadWorkloadDetail,
    required this.completedTaskIds,
    required this.restoredTaskIds,
    required this.deletedTaskIds,
    required this.updatingTaskIds,
    required this.showCompletedTasks,
    required this.showCancelledTasks,
    required this.showAllTasks,
    required this.showMore,
    required this.updatingHabitIds,
    required this.habitOutcomeOverrides,
    required this.projectionCurrent,
    required this.projectionStale,
    required this.onReloadToday,
    required this.isRefreshingRecommendations,
    required this.recommendationRefreshError,
    required this.onAddEvening,
    required this.onAddMorning,
    required this.canUseWeeklyReview,
    required this.onOpenWeeklyReview,
    required this.onRetryRecommendations,
    required this.onRefreshRecommendations,
    required this.onShowFeedbackHistory,
    required this.onAddTask,
    required this.onEditTask,
    required this.onCompleteTask,
    required this.onRestoreTask,
    required this.onCancelTask,
    required this.onPostponeTask,
    required this.onStartFocus,
    required this.onSetHabitOutcome,
    required this.onUndoHabitOutcome,
    required this.onOpenPreparationPlan,
    required this.onStartPreparationFocus,
    required this.onToggleAllTasks,
    required this.onToggleMore,
    required this.onToggleCompletedTasks,
    required this.onToggleCancelledTasks,
  });

  final DashboardSnapshot snapshot;
  final AsyncValue<RecommendationFeed>? recommendations;
  final AsyncValue<PreparationWorkload>? workload;
  final AsyncValue<DashboardSnapshot>? supporting;
  final VoidCallback onRetryWorkload;
  final PreparationWorkloadDetailLoader onLoadWorkloadDetail;
  final Set<String> completedTaskIds;
  final Set<String> restoredTaskIds;
  final Set<String> deletedTaskIds;
  final Set<String> updatingTaskIds;
  final bool showCompletedTasks;
  final bool showCancelledTasks;
  final bool showAllTasks;
  final bool showMore;
  final Set<String> updatingHabitIds;
  final Map<String, String?> habitOutcomeOverrides;
  final bool projectionCurrent;
  final bool projectionStale;
  final VoidCallback onReloadToday;
  final bool isRefreshingRecommendations;
  final String? recommendationRefreshError;
  final VoidCallback onAddEvening;
  final VoidCallback onAddMorning;
  final bool canUseWeeklyReview;
  final VoidCallback onOpenWeeklyReview;
  final VoidCallback onRetryRecommendations;
  final VoidCallback onRefreshRecommendations;
  final VoidCallback onShowFeedbackHistory;
  final VoidCallback onAddTask;
  final ValueChanged<PlanItem> onEditTask;
  final ValueChanged<PlanItem> onCompleteTask;
  final ValueChanged<PlanItem> onRestoreTask;
  final ValueChanged<PlanItem> onCancelTask;
  final ValueChanged<PlanItem> onPostponeTask;
  final ValueChanged<PlanItem> onStartFocus;
  final void Function(TodayHabit habit, HabitOutcome outcome) onSetHabitOutcome;
  final ValueChanged<TodayHabit> onUndoHabitOutcome;
  final ValueChanged<String> onOpenPreparationPlan;
  final ValueChanged<String> onStartPreparationFocus;
  final VoidCallback onToggleAllTasks;
  final VoidCallback onToggleMore;
  final VoidCallback onToggleCompletedTasks;
  final VoidCallback onToggleCancelledTasks;

  @override
  Widget build(BuildContext context) {
    final allTasks = snapshot.allTasks;
    final activeTasks = allTasks.where((item) {
      final completed = completedTaskIds.contains(item.id) ||
          (item.isCompleted && !restoredTaskIds.contains(item.id));
      final cancelled = deletedTaskIds.contains(item.id) ||
          (item.status == 'cancelled' && !restoredTaskIds.contains(item.id));
      return !completed && !cancelled;
    }).toList();
    final cancelledTasks = allTasks.where((item) {
      return deletedTaskIds.contains(item.id) ||
          (item.status == 'cancelled' && !restoredTaskIds.contains(item.id));
    }).toList();
    final completedTasks = allTasks.where((item) {
      final completed = completedTaskIds.contains(item.id) ||
          (item.isCompleted && !restoredTaskIds.contains(item.id));
      return completed && !deletedTaskIds.contains(item.id);
    }).toList();
    final selectedTodayTasks =
        snapshot.isTodayOverview ? snapshot.todayTasks : activeTasks;
    final canExecute =
        snapshot.origin == DashboardOrigin.account && projectionCurrent;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding =
              constraints.maxWidth < 600 ? AppSpacing.md : AppSpacing.xl;
          final desktopShell = MediaQuery.sizeOf(context).width >= 1100;
          final bottomPadding = desktopShell ? AppSpacing.xxl : 116.0;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  AppSpacing.md,
                  horizontalPadding,
                  bottomPadding,
                ),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DashboardHeader(snapshot: snapshot),
                          if (projectionStale) ...[
                            const SizedBox(height: AppSpacing.md),
                            AppCard(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    AppIcons.syncProblemOutlined,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Saved; Today could not reload.',
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
                                        OutlinedButton.icon(
                                          onPressed: onReloadToday,
                                          icon: const Icon(AppIcons.refresh),
                                          label: const Text('Reload Today'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          _CheckInStreakCard(
                            snapshot: snapshot,
                            onAddMorning: onAddMorning,
                            onAddEvening: onAddEvening,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _TodayProgressCard(snapshot: snapshot),
                          const SizedBox(height: AppSpacing.lg),
                          _TodayAgenda(
                            snapshot: snapshot,
                            canExecute: canExecute,
                            onOpenPreparationPlan: onOpenPreparationPlan,
                            onStartPreparationFocus: onStartPreparationFocus,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          _TodayTasksSection(
                            tasks: selectedTodayTasks,
                            sourceState: snapshot.sourceStates?.tasks,
                            canExecute: canExecute,
                            updatingTaskIds: updatingTaskIds,
                            onAdd: onAddTask,
                            onEdit: onEditTask,
                            onComplete: onCompleteTask,
                            onRestore: onRestoreTask,
                            onStartFocus: onStartFocus,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _InlineExpansionCard(
                            key: const ValueKey('today-all-tasks'),
                            title: 'Show all tasks',
                            subtitle:
                                'Future, undated, completed, and cancelled tasks',
                            expanded: showAllTasks,
                            onToggle: onToggleAllTasks,
                            child: _TasksSection(
                              activeTasks: activeTasks,
                              completedTasks: completedTasks,
                              cancelledTasks: cancelledTasks,
                              canExecute: canExecute,
                              updatingTaskIds: updatingTaskIds,
                              showCompletedTasks: showCompletedTasks,
                              showCancelledTasks: showCancelledTasks,
                              onAdd: onAddTask,
                              onEdit: onEditTask,
                              onComplete: onCompleteTask,
                              onRestore: onRestoreTask,
                              onCancel: onCancelTask,
                              onPostpone: onPostponeTask,
                              onStartFocus: onStartFocus,
                              onToggleCompleted: onToggleCompletedTasks,
                              onToggleCancelled: onToggleCancelledTasks,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          _TodayHabitsSection(
                            habits: snapshot.todayHabits,
                            sourceState: snapshot.sourceStates?.habits,
                            canExecute: canExecute,
                            updatingHabitIds: updatingHabitIds,
                            outcomeOverrides: habitOutcomeOverrides,
                            onSetOutcome: onSetHabitOutcome,
                            onUndo: onUndoHabitOutcome,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          _InlineExpansionCard(
                            key: const ValueKey('dashboard-more'),
                            title: 'More',
                            subtitle:
                                'Workload, weekly review, saved signals, recommendations, and full week',
                            expanded: showMore,
                            onToggle: onToggleMore,
                            child: _MoreDashboardContent(
                              accountData:
                                  snapshot.origin == DashboardOrigin.account,
                              supporting: supporting,
                              recommendations: recommendations,
                              workload: workload,
                              canUseWeeklyReview: canUseWeeklyReview,
                              isRefreshingRecommendations:
                                  isRefreshingRecommendations,
                              recommendationRefreshError:
                                  recommendationRefreshError,
                              onRetryWorkload: onRetryWorkload,
                              onLoadWorkloadDetail: onLoadWorkloadDetail,
                              onOpenWeeklyReview: onOpenWeeklyReview,
                              onRetryRecommendations: onRetryRecommendations,
                              onRefreshRecommendations:
                                  onRefreshRecommendations,
                              onShowFeedbackHistory: onShowFeedbackHistory,
                              onAddMorning: onAddMorning,
                              onAddEvening: onAddEvening,
                              onOpenPreparationPlan: onOpenPreparationPlan,
                            ),
                          ),
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

class _FeedbackHistorySheet extends ConsumerWidget {
  const _FeedbackHistorySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(decisionFeedbackProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Feedback history',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(AppIcons.close),
                ),
              ],
            ),
            const Text(
              'Recent feedback can influence matching rankings for up to 28 days. Delete an entry to correct it; original briefing evidence stays unchanged.',
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: value.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    const Text('Feedback history is unavailable.'),
                data: (items) {
                  if (items.isEmpty) return const Text('No recent feedback.');
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_feedbackTypeLabel(item.feedbackType)),
                        subtitle: Text(
                          '${item.actionKind} · ${DateFormat.yMMMd().add_Hm().format(item.createdAt.toLocal())}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Delete feedback',
                          onPressed: () async {
                            try {
                              await ref
                                  .read(feedbackRepositoryProvider)
                                  .delete(item.id);
                              ref.invalidate(decisionFeedbackProvider);
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Feedback could not be deleted.'),
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(AppIcons.deleteOutline),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _feedbackTypeLabel(DecisionFeedbackType type) => switch (type) {
      DecisionFeedbackType.done => 'Done',
      DecisionFeedbackType.later => 'Later',
      DecisionFeedbackType.notHelpful => 'Not helpful',
      DecisionFeedbackType.tooMuch => 'Too much today',
      DecisionFeedbackType.doesNotFit => 'Does not fit',
    };

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat(
      'EEEE, MMMM d',
    ).format(snapshot.localDate ?? DateTime.now());
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
          onPressed: () => context.push(AppRoutes.settings),
          icon: const Icon(AppIcons.settingsOutlined),
        ),
      ],
    );
  }
}

class _WeeklyReviewEntryCard extends StatelessWidget {
  const _WeeklyReviewEntryCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          AppIcons.eventNoteOutlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: const Text('Review your week'),
        subtitle: const Text(
          'Completed, skipped, missed, carried, and recovery facts stay distinct.',
        ),
        trailing: const Icon(AppIcons.chevronRight),
        onTap: onOpen,
      ),
    );
  }
}

class _CheckInStreakCard extends StatelessWidget {
  const _CheckInStreakCard({
    required this.snapshot,
    required this.onAddMorning,
    required this.onAddEvening,
  });

  final DashboardSnapshot snapshot;
  final VoidCallback onAddMorning;
  final VoidCallback onAddEvening;

  @override
  Widget build(BuildContext context) {
    final checkIns = snapshot.checkIns;
    final unavailable =
        snapshot.sourceStates?.checkIns.status == TodaySourceStatus.unavailable;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                AppIcons.localFireDepartmentOutlined,
                color: Theme.of(context).colorScheme.primary,
                size: 30,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Check-in streak',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      unavailable
                          ? 'Streak unavailable'
                          : '${checkIns?.completedDaysStreak ?? 0} consecutive ${checkIns?.completedDaysStreak == 1 ? 'day' : 'days'}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            unavailable
                ? snapshot.sourceStates?.checkIns.message ??
                    'Check-ins could not be loaded.'
                : 'A day counts when both check-ins are saved. You can enter both at any time today; an unfinished current day does not end the prior streak.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _CheckInButton(
                label: 'Morning check-in',
                saved: checkIns?.morningSaved == true,
                icon: AppIcons.wbSunnyOutlined,
                onPressed: onAddMorning,
              ),
              _CheckInButton(
                label: 'Evening check-in',
                saved: checkIns?.eveningSaved == true,
                icon: AppIcons.nightsStayOutlined,
                onPressed: onAddEvening,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckInButton extends StatelessWidget {
  const _CheckInButton({
    required this.label,
    required this.saved,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final bool saved;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = '${saved ? 'Edit' : 'Add'} $label';
    return Semantics(
      button: true,
      label: '$text. ${saved ? 'Saved' : 'Not saved'} today.',
      child: saved
          ? OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(AppIcons.checkCircleOutline),
              label: Text(text),
            )
          : FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(text),
            ),
    );
  }
}

class _TodayProgressCard extends StatelessWidget {
  const _TodayProgressCard({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final progress = snapshot.progress;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today\'s progress',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (progress == null) ...[
            Text(
              'Progress unavailable',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'At least one counted source could not be verified, so no partial total is shown.',
            ),
          ] else ...[
            Semantics(
              label:
                  '${progress.completed} of ${progress.total} counted items completed today',
              child: ExcludeSemantics(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress.ratio),
                  duration: context.motionTokens.emphasisFor(context),
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 12,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    color: context.visualTokens.success,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${progress.completed}/${progress.total} completed',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Includes both check-ins, today\'s tasks and habits, and confirmed preparation blocks. Skipped habits do not count as completed.',
            ),
          ],
        ],
      ),
    );
  }
}

class _TodayAgenda extends StatelessWidget {
  const _TodayAgenda({
    required this.snapshot,
    required this.canExecute,
    required this.onOpenPreparationPlan,
    required this.onStartPreparationFocus,
  });

  final DashboardSnapshot snapshot;
  final bool canExecute;
  final ValueChanged<String> onOpenPreparationPlan;
  final ValueChanged<String> onStartPreparationFocus;

  @override
  Widget build(BuildContext context) {
    final sourceErrors = snapshot.sourceStates?.timelineStates
            .where((state) => state.status == TodaySourceStatus.unavailable)
            .map((state) => state.message)
            .whereType<String>()
            .toList(growable: false) ??
        const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'Today at a glance',
          subtitle: 'Your timed day in one compact agenda.',
        ),
        if (sourceErrors.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _InlineMessage(
            icon: AppIcons.warningAmberOutlined,
            message: sourceErrors.join(' '),
            color: Theme.of(context).colorScheme.error,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (snapshot.timeline.isEmpty)
          const _EmptySectionCard(
            icon: AppIcons.calendarTodayOutlined,
            message: 'No timed blocks or all-day events are available today.',
          )
        else
          ...snapshot.timeline.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _AgendaItem(
                item: item,
                canExecute: canExecute,
                onOpenPreparationPlan: onOpenPreparationPlan,
                onStartPreparationFocus: onStartPreparationFocus,
              ),
            ),
          ),
      ],
    );
  }
}

class _AgendaItem extends StatelessWidget {
  const _AgendaItem({
    required this.item,
    required this.canExecute,
    required this.onOpenPreparationPlan,
    required this.onStartPreparationFocus,
  });

  final TodayTimelineItem item;
  final bool canExecute;
  final ValueChanged<String> onOpenPreparationPlan;
  final ValueChanged<String> onStartPreparationFocus;

  @override
  Widget build(BuildContext context) {
    final appearance = _agendaAppearance(context, item.kind);
    final detail = _agendaDetail(item);
    return Semantics(
      container: true,
      label: '${appearance.label}. ${item.title}. ${_agendaTime(item)}.',
      child: Container(
        decoration: BoxDecoration(
          color: appearance.background,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border:
              Border.all(color: appearance.foreground.withValues(alpha: .3)),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: Text(
                _agendaTime(item),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: appearance.foreground,
                    ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(appearance.icon, color: appearance.foreground, size: 21),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appearance.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: appearance.foreground,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: appearance.foreground,
                        ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: appearance.foreground,
                          ),
                    ),
                  ],
                  if (item.location != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.location!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: appearance.foreground,
                          ),
                    ),
                  ],
                  if (item.kind == TodayTimelineKind.preparation &&
                      item.planId != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        OutlinedButton(
                          onPressed: () => onOpenPreparationPlan(item.planId!),
                          child: const Text('Open plan'),
                        ),
                        if (canExecute &&
                            item.managedTaskId != null &&
                            const {'upcoming', 'partial'}.contains(item.state))
                          FilledButton.tonalIcon(
                            onPressed: () => onStartPreparationFocus(
                              item.managedTaskId!,
                            ),
                            icon: const Icon(AppIcons.timerOutlined),
                            label: const Text('Start focus'),
                          ),
                      ],
                    ),
                  ],
                  if (canExecute &&
                      item.kind == TodayTimelineKind.taskBlock &&
                      item.taskId != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton.tonalIcon(
                      onPressed: () => context.push(
                        '${AppRoutes.deepWork}?target_kind=task&target_id=${item.taskId}',
                      ),
                      icon: const Icon(AppIcons.timerOutlined),
                      label: const Text('Start focus'),
                    ),
                  ],
                  if (canExecute &&
                      item.kind == TodayTimelineKind.habitSlot &&
                      item.habitId != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton.tonalIcon(
                      onPressed: () => context.push(AppRoutes.habitCompletion),
                      icon: const Icon(AppIcons.checkCircleOutline),
                      label: const Text('Log habit'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayTasksSection extends StatelessWidget {
  const _TodayTasksSection({
    required this.tasks,
    required this.sourceState,
    required this.canExecute,
    required this.updatingTaskIds,
    required this.onAdd,
    required this.onEdit,
    required this.onComplete,
    required this.onRestore,
    required this.onStartFocus,
  });

  final List<PlanItem> tasks;
  final TodaySourceState? sourceState;
  final bool canExecute;
  final Set<String> updatingTaskIds;
  final VoidCallback onAdd;
  final ValueChanged<PlanItem> onEdit;
  final ValueChanged<PlanItem> onComplete;
  final ValueChanged<PlanItem> onRestore;
  final ValueChanged<PlanItem> onStartFocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Today\'s tasks',
          subtitle: 'Due, overdue, in-progress, and completed-today tasks.',
          trailing: canExecute
              ? FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(AppIcons.calendarMonthOutlined, size: 18),
                  label: const Text('Open Planner'),
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        if (sourceState?.status == TodaySourceStatus.unavailable)
          _SectionErrorCard(
            title: 'Tasks unavailable',
            message: sourceState?.message ?? 'Tasks could not be loaded.',
          )
        else if (tasks.isEmpty)
          const _EmptySectionCard(
            icon: AppIcons.taskAltOutlined,
            message: 'No due, overdue, or in-progress tasks today.',
          )
        else
          ...tasks.map(
            (task) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _TaskCard(
                task: task,
                isUpdating: updatingTaskIds.contains(task.id),
                isCompleted: task.status == 'done',
                onComplete: canExecute && task.status != 'done'
                    ? () => onComplete(task)
                    : null,
                onRestore: canExecute && task.status == 'done'
                    ? () => onRestore(task)
                    : null,
                onEdit: null,
                onStartFocus: canExecute && task.status != 'done'
                    ? () => onStartFocus(task)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class _TodayHabitsSection extends StatelessWidget {
  const _TodayHabitsSection({
    required this.habits,
    required this.sourceState,
    required this.canExecute,
    required this.updatingHabitIds,
    required this.outcomeOverrides,
    required this.onSetOutcome,
    required this.onUndo,
  });

  final List<TodayHabit> habits;
  final TodaySourceState? sourceState;
  final bool canExecute;
  final Set<String> updatingHabitIds;
  final Map<String, String?> outcomeOverrides;
  final void Function(TodayHabit habit, HabitOutcome outcome) onSetOutcome;
  final ValueChanged<TodayHabit> onUndo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'Today\'s habits',
          subtitle: 'Scheduled habits and still-open weekly targets.',
        ),
        const SizedBox(height: AppSpacing.md),
        if (sourceState?.status == TodaySourceStatus.unavailable)
          _SectionErrorCard(
            title: 'Habits unavailable',
            message: sourceState?.message ?? 'Habits could not be loaded.',
          )
        else if (habits.isEmpty)
          const _EmptySectionCard(
            icon: AppIcons.checkCircleOutline,
            message: 'No habits need an outcome today.',
          )
        else
          ...habits.map(
            (habit) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _HabitCard(
                habit: habit,
                updating: updatingHabitIds.contains(habit.id),
                outcomeOverride: outcomeOverrides.containsKey(habit.id)
                    ? outcomeOverrides[habit.id]
                    : habit.outcome,
                canExecute: canExecute,
                onSetOutcome: onSetOutcome,
                onUndo: onUndo,
              ),
            ),
          ),
      ],
    );
  }
}

class _HabitCard extends StatelessWidget {
  const _HabitCard({
    required this.habit,
    required this.updating,
    required this.outcomeOverride,
    required this.canExecute,
    required this.onSetOutcome,
    required this.onUndo,
  });

  final TodayHabit habit;
  final bool updating;
  final String? outcomeOverride;
  final bool canExecute;
  final void Function(TodayHabit habit, HabitOutcome outcome) onSetOutcome;
  final ValueChanged<TodayHabit> onUndo;

  @override
  Widget build(BuildContext context) {
    final completed = outcomeOverride == 'completed';
    final skipped = outcomeOverride == 'skipped';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                completed
                    ? AppIcons.checkCircle
                    : skipped
                        ? AppIcons.skipNextOutlined
                        : AppIcons.radioButtonUnchecked,
                color: completed
                    ? context.visualTokens.success
                    : skipped
                        ? Theme.of(context).colorScheme.tertiary
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
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      [
                        habit.cadenceLabel,
                        if (habit.cadence == 'weekly_target')
                          '${habit.weeklyCompleted}/${habit.weeklyTarget} this week',
                        if (habit.setupManaged) 'Managed in Setup',
                      ].join(' · '),
                    ),
                  ],
                ),
              ),
              if (updating)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (canExecute && !updating) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (outcomeOverride == null) ...[
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        onSetOutcome(habit, HabitOutcome.completed),
                    icon: const Icon(AppIcons.check),
                    label: const Text('Complete'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => onSetOutcome(habit, HabitOutcome.skipped),
                    icon: const Icon(AppIcons.skipNextOutlined),
                    label: const Text('Skip'),
                  ),
                ] else
                  OutlinedButton.icon(
                    onPressed: () => onUndo(habit),
                    icon: const Icon(AppIcons.undo),
                    label: const Text('Undo outcome'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineExpansionCard extends StatelessWidget {
  const _InlineExpansionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            child: ListTile(
              title: Text(title),
              subtitle: Text(subtitle),
              trailing:
                  Icon(expanded ? AppIcons.expandLess : AppIcons.expandMore),
              onTap: onToggle,
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: child,
            ),
          ],
        ],
      ),
    );
  }
}

class _MoreDashboardContent extends ConsumerWidget {
  const _MoreDashboardContent({
    required this.accountData,
    required this.supporting,
    required this.recommendations,
    required this.workload,
    required this.canUseWeeklyReview,
    required this.isRefreshingRecommendations,
    required this.recommendationRefreshError,
    required this.onRetryWorkload,
    required this.onLoadWorkloadDetail,
    required this.onOpenWeeklyReview,
    required this.onRetryRecommendations,
    required this.onRefreshRecommendations,
    required this.onShowFeedbackHistory,
    required this.onAddMorning,
    required this.onAddEvening,
    required this.onOpenPreparationPlan,
  });

  final bool accountData;
  final AsyncValue<DashboardSnapshot>? supporting;
  final AsyncValue<RecommendationFeed>? recommendations;
  final AsyncValue<PreparationWorkload>? workload;
  final bool canUseWeeklyReview;
  final bool isRefreshingRecommendations;
  final String? recommendationRefreshError;
  final VoidCallback onRetryWorkload;
  final PreparationWorkloadDetailLoader onLoadWorkloadDetail;
  final VoidCallback onOpenWeeklyReview;
  final VoidCallback onRetryRecommendations;
  final VoidCallback onRefreshRecommendations;
  final VoidCallback onShowFeedbackHistory;
  final VoidCallback onAddMorning;
  final VoidCallback onAddEvening;
  final ValueChanged<String> onOpenPreparationPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = supporting;
    final hasFeedbackHistory = accountData &&
        (ref.watch(decisionFeedbackProvider).valueOrNull?.isNotEmpty ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (workload != null) ...[
          PreparationWorkloadCard(
            value: workload!,
            compact: true,
            onRetry: onRetryWorkload,
            onLoadDayDetail: onLoadWorkloadDetail,
            onOpenSettings: () => context.push(AppRoutes.settings),
            onOpenPlans: () => context.push(AppRoutes.preparationPlans),
            onReviewPlan: onOpenPreparationPlan,
            onReplanPlan: (planId) => context.push(
              Uri(
                path: AppRoutes.plannerReplan,
                queryParameters: {'plan_id': planId},
              ).toString(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (canUseWeeklyReview) ...[
          _WeeklyReviewEntryCard(onOpen: onOpenWeeklyReview),
          const SizedBox(height: AppSpacing.md),
        ],
        if (details == null)
          const SizedBox.shrink()
        else
          details.when(
            loading: () => const AppCard(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const _SectionErrorCard(
              title: 'Saved details unavailable',
              message:
                  'Saved check-in values and the full week could not be loaded.',
            ),
            data: (detail) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LatestCheckInCard(
                  snapshot: detail,
                  onAddEvening: onAddEvening,
                  onAddMorning: onAddMorning,
                ),
              ],
            ),
          ),
        if (recommendations != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _RecommendationsSection(
            value: recommendations!,
            accountData: accountData,
            isRefreshing: isRefreshingRecommendations,
            refreshError: recommendationRefreshError,
            onRetry: onRetryRecommendations,
            onRefresh: onRefreshRecommendations,
          ),
        ],
        if (hasFeedbackHistory) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(AppIcons.historyOutlined),
              title: const Text('Decision feedback history'),
              subtitle:
                  const Text('Inspect or delete previously saved feedback.'),
              trailing: const Icon(AppIcons.chevronRight),
              onTap: onShowFeedbackHistory,
            ),
          ),
        ],
        if (details != null)
          details.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (detail) => Padding(
              padding: const EdgeInsets.only(top: AppSpacing.lg),
              child: _ScheduleSection(
                days: detail.scheduleDays,
                preparationScheduleError: detail.preparationScheduleError,
                onOpenPreparationPlan: onOpenPreparationPlan,
              ),
            ),
          ),
      ],
    );
  }
}

String _agendaTime(TodayTimelineItem item) {
  if (item.allDay) return 'All day';
  final startsAt = item.startsAt;
  final endsAt = item.endsAt;
  if (startsAt == null || endsAt == null) return 'Time unavailable';
  return '${DateFormat.Hm().format(startsAt)}–${DateFormat.Hm().format(endsAt)}';
}

String? _agendaDetail(TodayTimelineItem item) => switch (item.kind) {
      TodayTimelineKind.setupCommitment => 'Recurring Setup commitment',
      TodayTimelineKind.preparation => [
          _preparationStateLabel(item.state ?? ''),
          if (item.creditedTrackedMinutes != null &&
              item.plannedMinutes != null)
            '${item.creditedTrackedMinutes}/${item.plannedMinutes} min tracked',
        ].join(' · '),
      TodayTimelineKind.calendarEvent => item.sourceLabel == null
          ? 'Imported calendar event'
          : 'Imported from ${item.sourceLabel}',
      TodayTimelineKind.focusSession => [
          switch (item.state) {
            'active' => 'Active',
            'completed' => 'Completed',
            'abandoned' => 'Abandoned',
            _ => 'Focus',
          },
          if (item.actualMinutes != null) '${item.actualMinutes} min',
        ].join(' · '),
      TodayTimelineKind.taskBlock => '${item.plannedMinutes} min reserved',
      TodayTimelineKind.habitSlot => '${item.plannedMinutes} min reserved',
      TodayTimelineKind.manualCommitment => 'Fixed commitment',
    };

AppCategoryVisual _agendaAppearance(
  BuildContext context,
  TodayTimelineKind kind,
) {
  final category = switch (kind) {
    TodayTimelineKind.setupCommitment => AppCategory.setup,
    TodayTimelineKind.preparation => AppCategory.preparation,
    TodayTimelineKind.calendarEvent => AppCategory.calendar,
    TodayTimelineKind.focusSession => AppCategory.focus,
    TodayTimelineKind.taskBlock => AppCategory.task,
    TodayTimelineKind.habitSlot => AppCategory.habit,
    TodayTimelineKind.manualCommitment => AppCategory.fixedCommitment,
  };
  return category.visual(context);
}

class _LatestCheckInCard extends StatelessWidget {
  const _LatestCheckInCard({
    required this.snapshot,
    required this.onAddEvening,
    required this.onAddMorning,
  });

  final DashboardSnapshot snapshot;
  final VoidCallback onAddEvening;
  final VoidCallback onAddMorning;

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
            ],
          ),
          if (metrics.isEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: onAddMorning,
                  icon: const Icon(AppIcons.wbSunnyOutlined),
                  label: const Text('Morning check-in'),
                ),
                OutlinedButton.icon(
                  onPressed: onAddEvening,
                  icon: const Icon(AppIcons.nightsStayOutlined),
                  label: const Text('Evening check-in'),
                ),
              ],
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
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                TextButton.icon(
                  onPressed: onAddMorning,
                  icon: const Icon(AppIcons.wbSunnyOutlined),
                  label: Text(
                    checkIn?.hasMorningCapture == true
                        ? 'Edit morning check-in'
                        : 'Add morning check-in',
                  ),
                ),
                TextButton.icon(
                  onPressed: onAddEvening,
                  icon: const Icon(AppIcons.nightsStayOutlined),
                  label: Text(
                    checkIn?.hasEveningCapture == true
                        ? 'Edit evening check-in'
                        : 'Add evening check-in',
                  ),
                ),
              ],
            ),
            if (checkIn?.stressSource != null &&
                checkIn?.stressControllability != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Stress source: ${_readableCaptureCode(checkIn!.stressSource!)} · '
                'influence: ${_stressInfluenceLabel(checkIn.stressControllability!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ],
      ),
    );
  }

  List<_SignalMetric> _metricsForCheckIn(DashboardCheckIn checkIn) {
    return [
      if (checkIn.mood != null)
        _SignalMetric('Mood', '${checkIn.mood}/10', AppIcons.moodOutlined),
      if (checkIn.energy != null)
        _SignalMetric(
          checkIn.hasMorningCapture ? 'Morning energy' : 'Evening energy',
          '${checkIn.energy}/10',
          AppIcons.boltOutlined,
        ),
      if (checkIn.sleepHours != null)
        _SignalMetric(
          'Previous-night sleep',
          '${_formatDecimal(checkIn.sleepHours!)} h',
          AppIcons.bedtimeOutlined,
        ),
      if (checkIn.sleepQuality != null)
        _SignalMetric(
          'Previous-night sleep quality',
          '${checkIn.sleepQuality}/10',
          AppIcons.nightsStayOutlined,
        ),
      if (checkIn.stress != null)
        _SignalMetric(
          'Stress',
          '${checkIn.stress}/10',
          AppIcons.speedOutlined,
        ),
      if (checkIn.focusMinutes != null)
        _SignalMetric(
          'Focus',
          '${checkIn.focusMinutes} min',
          AppIcons.timerOutlined,
        ),
      if (checkIn.focusBand != null)
        _SignalMetric(
          'Focus band',
          _readableCaptureCode(checkIn.focusBand!),
          AppIcons.timerOutlined,
        ),
      if (checkIn.dayShape != null)
        _SignalMetric(
          'Day shape',
          _readableCaptureCode(checkIn.dayShape!),
          AppIcons.calendarTodayOutlined,
        ),
      if (checkIn.steps != null)
        _SignalMetric(
          'Steps',
          NumberFormat.decimalPattern().format(checkIn.steps),
          AppIcons.directionsWalkOutlined,
        ),
      if (checkIn.activityLevel != null)
        _SignalMetric(
          'Activity',
          '${checkIn.activityLevel}/10',
          AppIcons.fitnessCenterOutlined,
        ),
      if (checkIn.screenTimeHours != null)
        _SignalMetric(
          'Screen time',
          '${_formatDecimal(checkIn.screenTimeHours!)} h',
          AppIcons.devicesOutlined,
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
        borderRadius: BorderRadius.circular(AppRadii.sm),
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

String _readableCaptureCode(String value) => value
    .replaceAll('_', ' ')
    .replaceFirstMapped(RegExp(r'^[a-z]'), (match) => match[0]!.toUpperCase());

String _stressInfluenceLabel(String value) => switch (value) {
      'hardly_controllable' => 'Little',
      'partly_controllable' => 'Some',
      'mostly_controllable' => 'Mostly within your influence',
      _ => _readableCaptureCode(value),
    };

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
          title: 'Recommendations',
          subtitle: 'Rule-based suggestions from your available signals.',
          trailing: accountData
              ? OutlinedButton.icon(
                  onPressed: isRefreshing ? null : onRefresh,
                  icon: isRefreshing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(AppIcons.refresh, size: 18),
                  label: const Text('Refresh recommendations'),
                )
              : null,
        ),
        if (refreshError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _InlineMessage(
            icon: AppIcons.errorOutline,
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
      RecommendationFreshness.current => 'Up to date',
      RecommendationFreshness.missing => 'Not created yet',
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
              icon: isDemo ? AppIcons.scienceOutlined : AppIcons.ruleOutlined,
              label: isDemo ? 'Example suggestions' : 'Rule-based suggestions',
            ),
            _StatusPill(
              icon: feed.freshness.needsRefresh
                  ? AppIcons.history
                  : AppIcons.checkCircleOutline,
              label: freshness,
            ),
            if (feed.generatedAt != null)
              _StatusPill(
                icon: AppIcons.schedule,
                label: DateFormat.yMMMd().add_Hm().format(feed.generatedAt!),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (feed.items.isEmpty)
          const _EmptySectionCard(
            icon: AppIcons.lightbulbOutline,
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
    required this.cancelledTasks,
    required this.canExecute,
    required this.updatingTaskIds,
    required this.showCompletedTasks,
    required this.showCancelledTasks,
    required this.onAdd,
    required this.onEdit,
    required this.onComplete,
    required this.onRestore,
    required this.onCancel,
    required this.onPostpone,
    required this.onStartFocus,
    required this.onToggleCompleted,
    required this.onToggleCancelled,
  });

  final List<PlanItem> activeTasks;
  final List<PlanItem> completedTasks;
  final List<PlanItem> cancelledTasks;
  final bool canExecute;
  final Set<String> updatingTaskIds;
  final bool showCompletedTasks;
  final bool showCancelledTasks;
  final VoidCallback onAdd;
  final ValueChanged<PlanItem> onEdit;
  final ValueChanged<PlanItem> onComplete;
  final ValueChanged<PlanItem> onRestore;
  final ValueChanged<PlanItem> onCancel;
  final ValueChanged<PlanItem> onPostpone;
  final ValueChanged<PlanItem> onStartFocus;
  final VoidCallback onToggleCompleted;
  final VoidCallback onToggleCancelled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Tasks',
          subtitle: 'Finite actions with durable estimates and deadlines.',
          trailing: canExecute
              ? FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(AppIcons.calendarMonthOutlined, size: 18),
                  label: const Text('Open Planner'),
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        if (activeTasks.isEmpty)
          const _EmptySectionCard(
            icon: AppIcons.taskAltOutlined,
            message: 'No open tasks.',
          )
        else
          ...activeTasks.map(
            (task) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _TaskCard(
                task: task,
                isUpdating: updatingTaskIds.contains(task.id),
                onEdit: null,
                onComplete: canExecute ? () => onComplete(task) : null,
                onCancel: null,
                onPostpone: null,
                onStartFocus: canExecute ? () => onStartFocus(task) : null,
              ),
            ),
          ),
        if (completedTasks.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: onToggleCompleted,
            icon: Icon(
              showCompletedTasks ? AppIcons.expandLess : AppIcons.expandMore,
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
                  onRestore: canExecute ? () => onRestore(task) : null,
                  onEdit: null,
                ),
              ),
            ),
        ],
        if (cancelledTasks.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: onToggleCancelled,
            icon: Icon(
              showCancelledTasks ? AppIcons.expandLess : AppIcons.expandMore,
            ),
            label: Text('Cancelled (${cancelledTasks.length})'),
          ),
          if (showCancelledTasks)
            ...cancelledTasks.map(
              (task) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _TaskCard(
                  task: task,
                  isUpdating: updatingTaskIds.contains(task.id),
                  isCancelled: true,
                  onRestore: canExecute ? () => onRestore(task) : null,
                  onEdit: null,
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
    this.isCancelled = false,
    this.onComplete,
    this.onRestore,
    this.onEdit,
    this.onCancel,
    this.onPostpone,
    this.onStartFocus,
  });

  final PlanItem task;
  final bool isUpdating;
  final bool isCompleted;
  final bool isCancelled;
  final VoidCallback? onComplete;
  final VoidCallback? onRestore;
  final VoidCallback? onEdit;
  final VoidCallback? onCancel;
  final VoidCallback? onPostpone;
  final VoidCallback? onStartFocus;

  @override
  Widget build(BuildContext context) {
    final due = task.deadline == null
        ? null
        : 'Due ${DateFormat.yMMMd().format(task.deadline!)}';
    final estimate =
        task.estimatedMinutes == null ? null : '${task.estimatedMinutes} min';
    return AppCard(
      child: Row(
        children: [
          Icon(
            isCompleted
                ? AppIcons.checkCircle
                : isCancelled
                    ? AppIcons.cancelOutlined
                    : AppIcons.radioButtonUnchecked,
            color: isCompleted || isCancelled
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
                        decoration: isCompleted || isCancelled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                ),
                if (task.isDeadlinePlanManaged) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Managed by a preparation plan',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  [
                    task.priority,
                    if (estimate != null) estimate,
                    if (due != null) due,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (task.description != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    task.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
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
            if (task.isDeadlinePlanManaged) ...[
              if (onStartFocus != null)
                IconButton(
                  tooltip: 'Focus on ${task.title}',
                  onPressed: onStartFocus,
                  icon: const Icon(AppIcons.timerOutlined),
                ),
              if (onEdit != null || onRestore != null || onComplete != null)
                IconButton(
                  tooltip: 'Open preparation plan',
                  onPressed: onEdit ?? onRestore ?? onComplete,
                  icon: const Icon(AppIcons.arrowForward),
                ),
            ] else ...[
              if (onComplete != null)
                IconButton(
                  tooltip: 'Complete task ${task.title}',
                  onPressed: onComplete,
                  icon: const Icon(AppIcons.check),
                ),
              if (onStartFocus != null)
                IconButton(
                  tooltip: 'Focus on ${task.title}',
                  onPressed: onStartFocus,
                  icon: const Icon(AppIcons.timerOutlined),
                ),
              if (onRestore != null)
                IconButton(
                  tooltip: 'Restore task ${task.title}',
                  onPressed: onRestore,
                  icon: const Icon(AppIcons.undo),
                ),
              if (onEdit != null || onPostpone != null || onCancel != null)
                PopupMenuButton<_TaskMenuAction>(
                  tooltip: 'Task actions for ${task.title}',
                  onSelected: (action) {
                    switch (action) {
                      case _TaskMenuAction.edit:
                        onEdit?.call();
                      case _TaskMenuAction.postpone:
                        onPostpone?.call();
                      case _TaskMenuAction.cancel:
                        onCancel?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    if (onEdit != null)
                      const PopupMenuItem(
                        value: _TaskMenuAction.edit,
                        child: Text('Edit task'),
                      ),
                    if (onPostpone != null)
                      const PopupMenuItem(
                        value: _TaskMenuAction.postpone,
                        child: Text('Postpone task'),
                      ),
                    if (onCancel != null)
                      const PopupMenuItem(
                        value: _TaskMenuAction.cancel,
                        child: Text('Cancel task'),
                      ),
                  ],
                ),
            ],
          ],
        ],
      ),
    );
  }
}

enum _TaskMenuAction { edit, postpone, cancel }

class _TaskEditorSheet extends StatefulWidget {
  const _TaskEditorSheet({this.task, this.retainedDraft});

  final PlanItem? task;
  final ExecutableTaskDraft? retainedDraft;

  @override
  State<_TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<_TaskEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _estimateController;
  late ExecutableTaskPriority _priority;
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    final retained = widget.retainedDraft;
    _titleController = TextEditingController(
      text: retained?.title ?? task?.title ?? '',
    );
    _descriptionController = TextEditingController(
      text: retained?.description ?? task?.description ?? '',
    );
    _estimateController = TextEditingController(
      text:
          (retained?.estimatedMinutes ?? task?.estimatedMinutes)?.toString() ??
              '',
    );
    _priority = retained?.priority ??
        ExecutableTaskPriority.fromCode(task?.priority) ??
        ExecutableTaskPriority.medium;
    _deadline = retained?.deadline ?? task?.deadline;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _estimateController.dispose();
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
              widget.task == null ? 'Add task' : 'Edit task',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _titleController,
              autofocus: true,
              maxLength: 160,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Task title'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _descriptionController,
              maxLength: 2000,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Task description optional',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<ExecutableTaskPriority>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Task priority'),
              items: ExecutableTaskPriority.values
                  .map(
                    (priority) => DropdownMenuItem(
                      value: priority,
                      child: Text(
                        priority.code.replaceFirstMapped(
                          RegExp(r'^[a-z]'),
                          (match) => match[0]!.toUpperCase(),
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _priority = value);
                }
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _estimateController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Estimate minutes optional (5–480)',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDeadline,
                    icon: const Icon(AppIcons.eventOutlined),
                    label: Text(
                      _deadline == null
                          ? 'Set deadline'
                          : 'Deadline ${DateFormat.yMMMd().format(_deadline!)}',
                    ),
                  ),
                ),
                if (_deadline != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    tooltip: 'Clear deadline',
                    onPressed: () => setState(() => _deadline = null),
                    icon: const Icon(AppIcons.clear),
                  ),
                ],
              ],
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
                  icon: const Icon(AppIcons.check),
                  label: const Text('Save task'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final initial = _deadline ?? now;
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'Task deadline',
    );
    if (selected != null && mounted) {
      setState(() {
        _deadline = DateTime(
          selected.year,
          selected.month,
          selected.day,
          17,
        );
      });
    }
  }

  void _submit() {
    final estimateText = _estimateController.text.trim();
    final estimate = estimateText.isEmpty ? null : int.tryParse(estimateText);
    if (estimateText.isNotEmpty && estimate == null) {
      _showValidation('Estimate must be a whole number.');
      return;
    }
    try {
      final draft = ExecutableTaskDraft(
        title: _titleController.text,
        description: _descriptionController.text,
        priority: _priority,
        deadline: _deadline,
        estimatedMinutes: estimate,
      );
      Navigator.of(context).pop(draft);
    } on TaskCommandException catch (error) {
      _showValidation(error.message);
    }
  }

  void _showValidation(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _ScheduleSection extends StatelessWidget {
  const _ScheduleSection({
    required this.days,
    required this.preparationScheduleError,
    required this.onOpenPreparationPlan,
  });

  final List<ScheduleDay> days;
  final String? preparationScheduleError;
  final ValueChanged<String> onOpenPreparationPlan;

  @override
  Widget build(BuildContext context) {
    final daysWithEvents = days.where((day) => day.events.isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'Full week',
          subtitle: 'Recurring commitments and confirmed preparation blocks.',
        ),
        if (preparationScheduleError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            preparationScheduleError!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (daysWithEvents.isEmpty)
          const _EmptySectionCard(
            icon: AppIcons.calendarTodayOutlined,
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
                                    Icon(
                                      event.isDeadlinePreparation
                                          ? AppIcons.schoolOutlined
                                          : AppIcons.event,
                                      size: 18,
                                      color: event.isDeadlinePreparation
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : null,
                                    ),
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
                                          if (event.provenanceLabel != null)
                                            Text(
                                              [
                                                event.provenanceLabel!,
                                                if (event.state != null)
                                                  _preparationStateLabel(
                                                    event.state!,
                                                  ),
                                              ].join(' · '),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (event.deadlinePlanId != null)
                                      IconButton(
                                        tooltip: 'Open preparation plan',
                                        onPressed: () => onOpenPreparationPlan(
                                          event.deadlinePlanId!,
                                        ),
                                        icon: const Icon(
                                          AppIcons.arrowForward,
                                          size: 18,
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

String _preparationStateLabel(String state) => switch (state) {
      'upcoming' => 'Upcoming',
      'partial' => 'Partly tracked',
      'completed' => 'Completed',
      'missed' => 'Missed',
      _ => 'Preparation',
    };

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
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
    if (trailing == null) return copy;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 520 ||
            MediaQuery.textScalerOf(context).scale(16) >= 24;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              copy,
              const SizedBox(height: AppSpacing.sm),
              trailing!,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: copy),
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
        );
      },
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
        borderRadius: BorderRadius.circular(AppRadii.sm),
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
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(
            AppIcons.cloudOffOutlined,
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
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(AppIcons.refresh),
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
                  AppIcons.cloudOffOutlined,
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
                  icon: const Icon(AppIcons.refresh),
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
