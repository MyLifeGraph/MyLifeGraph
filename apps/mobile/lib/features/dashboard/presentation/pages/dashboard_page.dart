import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/utils/client_uuid.dart';
import '../../../../core/utils/local_date.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../actions/application/executable_action_dispatcher.dart';
import '../../../actions/domain/executable_action_target.dart';
import '../../../briefings/domain/daily_briefing.dart';
import '../../../briefings/domain/decision_feedback.dart';
import '../../../briefings/presentation/providers/briefing_providers.dart';
import '../../../briefings/presentation/widgets/today_briefing_section.dart';
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

class _DashboardPageState extends ConsumerState<DashboardPage> {
  final Set<String> _completedTaskIds = {};
  final Set<String> _restoredTaskIds = {};
  final Set<String> _deletedTaskIds = {};
  final Set<String> _updatingTaskIds = {};
  bool _showCompletedTasks = false;
  bool _showCancelledTasks = false;
  bool _isRefreshingRecommendations = false;
  String? _recommendationRefreshError;
  bool _isGeneratingBriefing = false;
  String? _briefingGenerationError;
  final Set<String> _executingBriefingActionIds = {};
  bool _isSubmittingFeedback = false;
  String? _feedbackError;
  DecisionFeedbackType? _submittedFeedbackType;
  final Map<String, String> _feedbackRequestIds = {};

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(dashboardSnapshotProvider);
    final recommendations = ref.watch(recommendationFeedProvider);
    final briefing = ref.watch(todayBriefingProvider);
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    final workload = capabilities.canUseDeadlinePlanner
        ? ref.watch(preparationWorkloadProvider)
        : null;

    return snapshot.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _DashboardLoadError(
        onRetry: () => ref.invalidate(dashboardSnapshotProvider),
      ),
      data: (data) => _DashboardHome(
        snapshot: data,
        recommendations: recommendations,
        briefing: briefing,
        workload: workload,
        onRetryWorkload: () => ref.invalidate(preparationWorkloadProvider),
        onLoadWorkloadDetail: (localDate) => ref
            .read(deadlinePlanRepositoryProvider)
            .getWorkloadDetail(localDate),
        isGeneratingBriefing: _isGeneratingBriefing,
        briefingGenerationError: _briefingGenerationError,
        executingBriefingActionIds: _executingBriefingActionIds,
        completedTaskIds: _completedTaskIds,
        restoredTaskIds: _restoredTaskIds,
        deletedTaskIds: _deletedTaskIds,
        updatingTaskIds: _updatingTaskIds,
        showCompletedTasks: _showCompletedTasks,
        showCancelledTasks: _showCancelledTasks,
        isRefreshingRecommendations: _isRefreshingRecommendations,
        recommendationRefreshError: _recommendationRefreshError,
        onAddEvening: () => context.go(AppRoutes.dailyCheckIn),
        onAddMorning: () => context.go(AppRoutes.morningCalibration),
        onOpenTodayHabits: () => context.go(AppRoutes.habitCompletion),
        onOpenFocus: () => context.go(AppRoutes.deepWork),
        canUseWeeklyReview: capabilities.canUseWeeklyReview,
        onOpenWeeklyReview: () => context.go(AppRoutes.weeklyReview),
        onRetryRecommendations: () {
          setState(() => _recommendationRefreshError = null);
          ref.invalidate(recommendationFeedProvider);
        },
        onRefreshRecommendations: _refreshRecommendations,
        onRetryBriefing: () => ref.invalidate(todayBriefingProvider),
        onGenerateBriefing: _generateBriefing,
        onExecuteBriefingAction: (target) => _executeBriefingAction(
          target,
          snapshot: data,
          canUseSyncedExecution: capabilities.canUseSyncedExecution,
          canUseWeeklyReview: capabilities.canUseWeeklyReview,
        ),
        isSubmittingFeedback: _isSubmittingFeedback,
        feedbackError: _feedbackError,
        submittedFeedbackType: _submittedFeedbackType,
        onSubmitFeedback: _submitFeedback,
        onShowFeedbackHistory: _showFeedbackHistory,
        onAddTask: () => _openTaskEditor(),
        onEditTask: _openTaskOrPreparationPlan,
        onCompleteTask: _completeTask,
        onRestoreTask: _restoreTask,
        onCancelTask: _cancelTask,
        onPostponeTask: _postponeTask,
        onStartFocus: (task) => context.go(
          '${AppRoutes.deepWork}?target_kind=task&target_id=${task.id}',
        ),
        onToggleCompletedTasks: () {
          setState(() => _showCompletedTasks = !_showCompletedTasks);
        },
        onToggleCancelledTasks: () {
          setState(() => _showCancelledTasks = !_showCancelledTasks);
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
          .refreshDailyAfterUserSignal(
            targetDate: localDateKey(DateTime.now()),
          );
      ref.invalidate(todayBriefingProvider);
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

  Future<void> _generateBriefing({required bool force}) async {
    if (_isGeneratingBriefing) {
      return;
    }
    setState(() {
      _isGeneratingBriefing = true;
      _briefingGenerationError = null;
    });
    try {
      await ref.read(briefingRepositoryProvider).generateToday(force: force);
      ref.invalidate(todayBriefingProvider);
      if (mounted) {
        setState(() => _submittedFeedbackType = null);
      }
      if (mounted) {
        _showTaskMessage(
          force ? 'Today\'s plan updated.' : 'Today\'s plan created.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _briefingGenerationError =
              'Today\'s plan could not be updated. Your existing plan is still here.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingBriefing = false);
      }
    }
  }

  Future<void> _submitFeedback(
    BriefingAction action,
    DecisionFeedbackType type,
  ) async {
    if (_isSubmittingFeedback) return;
    final feed = ref.read(todayBriefingProvider).value;
    final briefing = feed?.briefing;
    if (briefing == null || feed?.freshness != BriefingFreshness.current) {
      setState(() => _feedbackError = 'Refresh today before saving feedback.');
      return;
    }
    final requestKey = '${briefing.id}:${action.target.id}:${type.code}';
    final requestId =
        _feedbackRequestIds.putIfAbsent(requestKey, newClientUuid);
    setState(() {
      _isSubmittingFeedback = true;
      _feedbackError = null;
    });
    try {
      await ref.read(feedbackRepositoryProvider).create(
            requestId: requestId,
            briefingId: briefing.id,
            actionId: action.target.id,
            feedbackType: type,
          );
      _feedbackRequestIds.remove(requestKey);
      ref.invalidate(decisionFeedbackProvider);
      if (mounted) {
        setState(() => _submittedFeedbackType = type);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _feedbackError = 'Feedback was not confirmed. Retry the same choice.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmittingFeedback = false);
    }
  }

  Future<void> _showFeedbackHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FeedbackHistorySheet(),
    );
  }

  Future<void> _executeBriefingAction(
    ExecutableActionTarget target, {
    required DashboardSnapshot snapshot,
    required bool canUseSyncedExecution,
    required bool canUseWeeklyReview,
  }) async {
    if (_executingBriefingActionIds.contains(target.id)) {
      return;
    }
    setState(() => _executingBriefingActionIds.add(target.id));
    try {
      final dispatcher = ExecutableActionDispatcher(
        openTask: ({
          required actionId,
          required taskId,
          estimatedMinutes,
          source,
        }) async {
          final matches = snapshot.todayPlan.where((task) => task.id == taskId);
          if (matches.isEmpty) {
            throw StateError('The briefing task is no longer available.');
          }
          await _openTaskOrPreparationPlan(matches.first);
        },
        completeTask: ({
          required actionId,
          required taskId,
          source,
        }) async {
          final matches = snapshot.todayPlan.where((task) => task.id == taskId);
          if (matches.isEmpty) {
            throw StateError('The briefing task is no longer available.');
          }
          await _completeTask(matches.first);
        },
        logHabit: ({
          required actionId,
          required habitId,
          entryDate,
          outcome,
          source,
        }) async {
          final parsedDate = DateTime.tryParse(entryDate ?? '');
          final selectedOutcome = outcome ?? HabitOutcome.completed;
          if (parsedDate == null) {
            throw StateError('The briefing habit date is invalid.');
          }
          final client = ref.read(supabaseClientProvider);
          if (client == null) {
            throw StateError('Synced habits are unavailable.');
          }
          await HabitCompletionSupabaseDataSource(client).setTodayOutcome(
            habitId: habitId,
            outcome: selectedOutcome,
            targetDate: parsedDate,
          );
          await ref
              .read(snapshotRefreshServiceProvider)
              .refreshDailyAfterHabitChange(
                targetDate: habitDateKey(parsedDate),
              );
          ref.invalidate(dashboardSnapshotProvider);
          ref.invalidate(todayBriefingProvider);
          if (mounted) {
            _showTaskMessage(
              selectedOutcome == HabitOutcome.completed
                  ? 'Habit completed.'
                  : 'Habit intentionally skipped.',
            );
          }
        },
        startFocus: ({
          required actionId,
          targetId,
          targetKind,
          plannedMinutes,
          source,
        }) async {
          final query = <String, String>{
            if (targetKind != null) 'target_kind': targetKind.code,
            if (targetId != null) 'target_id': targetId,
          };
          final suffix = query.isEmpty
              ? ''
              : '?${query.entries.map((entry) => '${entry.key}=${Uri.encodeQueryComponent(entry.value)}').join('&')}';
          if (mounted) {
            context.go('${AppRoutes.deepWork}$suffix');
          }
        },
        reviewPlan: ({
          required actionId,
          reviewId,
          estimatedMinutes,
          source,
        }) async {
          if (mounted) context.go(AppRoutes.weeklyReview);
        },
        openCapture: ({
          required actionId,
          required route,
          entryDate,
          source,
        }) async {
          if (mounted) {
            context.go(route.path);
          }
        },
      );
      final result = await dispatcher.dispatch(
        target,
        canUseSyncedExecution: canUseSyncedExecution,
        canUseWeeklyReview: canUseWeeklyReview,
      );
      if (result is ExecutableActionUnavailable && mounted) {
        _showTaskMessage(result.reason);
      }
    } catch (error) {
      if (mounted) {
        _showTaskMessage(
          error is BriefingContractException
              ? error.message
              : 'This briefing action is no longer available. Adjust today and retry.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _executingBriefingActionIds.remove(target.id));
      }
    }
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
    await _mutateTask(
      task.id,
      () async {
        await _taskSource().restoreTask(task.id);
      },
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
    final id = requestId ?? newClientUuid();
    setState(() => _updatingTaskIds.add(task?.id ?? id));
    try {
      final source = _taskSource();
      if (task == null) {
        await source.createTask(taskId: id, draft: draft);
      } else {
        await source.editTask(taskId: task.id, draft: draft);
      }
      await _afterTaskWrite();
      if (mounted) {
        _showTaskMessage(task == null ? 'Task added.' : 'Task updated.');
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
    context.go(
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
    TaskUndoToken? undo;
    await _mutateTask(
      task.id,
      () async {
        undo = await mutation(_taskSource());
      },
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
    await _mutateTask(
      token.taskId,
      () async {
        await _taskSource().undo(token);
      },
      successStatus: token.status.code,
      successMessage: 'Task change undone.',
    );
  }

  Future<void> _mutateTask(
    String id,
    Future<void> Function() mutation, {
    required String successStatus,
    required String successMessage,
    VoidCallback? onSuccess,
  }) async {
    if (_updatingTaskIds.contains(id)) {
      return;
    }
    setState(() => _updatingTaskIds.add(id));
    try {
      await mutation();
      if (mounted) {
        setState(() => _applyLocalTaskStatus(id, successStatus));
      }
      await _afterTaskWrite();
      if (mounted) {
        if (onSuccess != null) {
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
    final client = ref.read(supabaseClientProvider);
    if (client == null) {
      throw const TaskCommandException('Synced tasks are unavailable.');
    }
    return TaskSupabaseDataSource(client);
  }

  Future<void> _afterTaskWrite() async {
    await ref
        .read(snapshotRefreshServiceProvider)
        .refreshDailyAfterTaskChange(targetDate: localDateKey(DateTime.now()));
    ref.invalidate(dashboardSnapshotProvider);
    ref.invalidate(todayBriefingProvider);
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
    required this.briefing,
    required this.workload,
    required this.onRetryWorkload,
    required this.onLoadWorkloadDetail,
    required this.isGeneratingBriefing,
    required this.briefingGenerationError,
    required this.executingBriefingActionIds,
    required this.completedTaskIds,
    required this.restoredTaskIds,
    required this.deletedTaskIds,
    required this.updatingTaskIds,
    required this.showCompletedTasks,
    required this.showCancelledTasks,
    required this.isRefreshingRecommendations,
    required this.recommendationRefreshError,
    required this.onAddEvening,
    required this.onAddMorning,
    required this.onOpenTodayHabits,
    required this.onOpenFocus,
    required this.canUseWeeklyReview,
    required this.onOpenWeeklyReview,
    required this.onRetryRecommendations,
    required this.onRefreshRecommendations,
    required this.onRetryBriefing,
    required this.onGenerateBriefing,
    required this.onExecuteBriefingAction,
    required this.isSubmittingFeedback,
    required this.feedbackError,
    required this.submittedFeedbackType,
    required this.onSubmitFeedback,
    required this.onShowFeedbackHistory,
    required this.onAddTask,
    required this.onEditTask,
    required this.onCompleteTask,
    required this.onRestoreTask,
    required this.onCancelTask,
    required this.onPostponeTask,
    required this.onStartFocus,
    required this.onToggleCompletedTasks,
    required this.onToggleCancelledTasks,
  });

  final DashboardSnapshot snapshot;
  final AsyncValue<RecommendationFeed> recommendations;
  final AsyncValue<BriefingFeed> briefing;
  final AsyncValue<PreparationWorkload>? workload;
  final VoidCallback onRetryWorkload;
  final PreparationWorkloadDetailLoader onLoadWorkloadDetail;
  final bool isGeneratingBriefing;
  final String? briefingGenerationError;
  final Set<String> executingBriefingActionIds;
  final Set<String> completedTaskIds;
  final Set<String> restoredTaskIds;
  final Set<String> deletedTaskIds;
  final Set<String> updatingTaskIds;
  final bool showCompletedTasks;
  final bool showCancelledTasks;
  final bool isRefreshingRecommendations;
  final String? recommendationRefreshError;
  final VoidCallback onAddEvening;
  final VoidCallback onAddMorning;
  final VoidCallback onOpenTodayHabits;
  final VoidCallback onOpenFocus;
  final bool canUseWeeklyReview;
  final VoidCallback onOpenWeeklyReview;
  final VoidCallback onRetryRecommendations;
  final VoidCallback onRefreshRecommendations;
  final VoidCallback onRetryBriefing;
  final GenerateBriefingCallback onGenerateBriefing;
  final ExecuteBriefingActionCallback onExecuteBriefingAction;
  final bool isSubmittingFeedback;
  final String? feedbackError;
  final DecisionFeedbackType? submittedFeedbackType;
  final SubmitFeedbackCallback onSubmitFeedback;
  final VoidCallback onShowFeedbackHistory;
  final VoidCallback onAddTask;
  final ValueChanged<PlanItem> onEditTask;
  final ValueChanged<PlanItem> onCompleteTask;
  final ValueChanged<PlanItem> onRestoreTask;
  final ValueChanged<PlanItem> onCancelTask;
  final ValueChanged<PlanItem> onPostponeTask;
  final ValueChanged<PlanItem> onStartFocus;
  final VoidCallback onToggleCompletedTasks;
  final VoidCallback onToggleCancelledTasks;

  @override
  Widget build(BuildContext context) {
    final activeTasks = snapshot.todayPlan.where((item) {
      final completed = completedTaskIds.contains(item.id) ||
          (item.isCompleted && !restoredTaskIds.contains(item.id));
      final cancelled = deletedTaskIds.contains(item.id) ||
          (item.status == 'cancelled' && !restoredTaskIds.contains(item.id));
      return !completed && !cancelled;
    }).toList();
    final cancelledTasks = snapshot.todayPlan.where((item) {
      return deletedTaskIds.contains(item.id) ||
          (item.status == 'cancelled' && !restoredTaskIds.contains(item.id));
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
                          TodayBriefingSection(
                            value: briefing,
                            isGenerating: isGeneratingBriefing,
                            generationError: briefingGenerationError,
                            executingActionIds: executingBriefingActionIds,
                            onRetryRead: onRetryBriefing,
                            onGenerate: onGenerateBriefing,
                            onExecute: onExecuteBriefingAction,
                            isSubmittingFeedback: isSubmittingFeedback,
                            feedbackError: feedbackError,
                            submittedFeedbackType: submittedFeedbackType,
                            onFeedback: onSubmitFeedback,
                            onShowFeedbackHistory: onShowFeedbackHistory,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _TodayAtAGlanceCard(
                            snapshot: snapshot,
                            canExecute:
                                snapshot.origin == DashboardOrigin.account,
                            onOpenHabits: onOpenTodayHabits,
                            onOpenFocus: onOpenFocus,
                            onAddMorning: onAddMorning,
                            onAddEvening: onAddEvening,
                          ),
                          if (workload != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            PreparationWorkloadCard(
                              value: workload!,
                              compact: true,
                              onRetry: onRetryWorkload,
                              onLoadDayDetail: onLoadWorkloadDetail,
                              onOpenSettings: () =>
                                  context.go(AppRoutes.settings),
                              onOpenPlans: () =>
                                  context.go(AppRoutes.preparationPlans),
                              onReviewPlan: (planId) => context.go(
                                Uri(
                                  path: AppRoutes.preparationPlans,
                                  queryParameters: {'plan_id': planId},
                                ).toString(),
                              ),
                              onReplanPlan: (planId) => context.go(
                                Uri(
                                  path: AppRoutes.preparationPlans,
                                  queryParameters: {
                                    'plan_id': planId,
                                    'action': 'replan',
                                  },
                                ).toString(),
                              ),
                            ),
                          ],
                          if (canUseWeeklyReview) ...[
                            const SizedBox(height: AppSpacing.md),
                            _WeeklyReviewEntryCard(
                              onOpen: onOpenWeeklyReview,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          _TasksSection(
                            activeTasks: activeTasks,
                            completedTasks: completedTasks,
                            cancelledTasks: cancelledTasks,
                            canExecute:
                                snapshot.origin == DashboardOrigin.account,
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
                          const SizedBox(height: AppSpacing.xl),
                          _SupportingDashboardDetails(
                            latestCheckIn: _LatestCheckInCard(
                              snapshot: snapshot,
                              onAddEvening: onAddEvening,
                              onAddMorning: onAddMorning,
                            ),
                            recommendations: _RecommendationsSection(
                              value: recommendations,
                              accountData:
                                  snapshot.origin == DashboardOrigin.account,
                              isRefreshing: isRefreshingRecommendations,
                              refreshError: recommendationRefreshError,
                              onRetry: onRetryRecommendations,
                              onRefresh: onRefreshRecommendations,
                            ),
                            schedule: _ScheduleSection(
                              days: snapshot.scheduleDays,
                              preparationScheduleError:
                                  snapshot.preparationScheduleError,
                              onOpenPreparationPlan: (planId) => context.go(
                                Uri(
                                  path: AppRoutes.preparationPlans,
                                  queryParameters: {'plan_id': planId},
                                ).toString(),
                              ),
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
                  icon: const Icon(Icons.close),
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
                          icon: const Icon(Icons.delete_outline),
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

class _WeeklyReviewEntryCard extends StatelessWidget {
  const _WeeklyReviewEntryCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          Icons.event_note_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: const Text('Review your week'),
        subtitle: const Text(
          'Completed, skipped, missed, carried, and recovery facts stay distinct.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpen,
      ),
    );
  }
}

class _TodayAtAGlanceCard extends StatelessWidget {
  const _TodayAtAGlanceCard({
    required this.snapshot,
    required this.canExecute,
    required this.onOpenHabits,
    required this.onOpenFocus,
    required this.onAddMorning,
    required this.onAddEvening,
  });

  final DashboardSnapshot snapshot;
  final bool canExecute;
  final VoidCallback onOpenHabits;
  final VoidCallback onOpenFocus;
  final VoidCallback onAddMorning;
  final VoidCallback onAddEvening;

  @override
  Widget build(BuildContext context) {
    final now = snapshot.loadedAt.toLocal();
    final matchingDays = snapshot.scheduleDays.where((day) {
      final date = day.date;
      return date != null &&
          date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
    });
    final today = matchingDays.firstOrNull ??
        snapshot.scheduleDays
            .where((day) => day.label.toLowerCase() == 'today')
            .firstOrNull;
    final events = today?.events ?? const <ScheduleEvent>[];
    final currentMinute = now.hour * 60 + now.minute;
    final nextEvent = events.where((event) {
      final minute = event.sortMinutes;
      final endMinute = event.endSortMinutes;
      if (endMinute != null) return endMinute > currentMinute;
      return minute == null || minute >= currentMinute;
    }).firstOrNull;
    final latestCheckIn = snapshot.latestCheckIn;
    final checkInDate = latestCheckIn?.entryDate.toLocal();
    final checkIn = checkInDate != null &&
            checkInDate.year == now.year &&
            checkInDate.month == now.month &&
            checkInDate.day == now.day
        ? latestCheckIn
        : null;
    final morningSaved = checkIn?.hasMorningCapture == true;
    final eveningSaved = checkIn?.hasEveningCapture == true;
    final captureStatus = checkIn == null
        ? 'No signal saved today'
        : [
            if (checkIn.hasMorningCapture) 'morning saved',
            if (checkIn.hasEveningCapture) 'evening saved',
          ].isEmpty
            ? 'Daily signal saved'
            : [
                if (checkIn.hasMorningCapture) 'morning saved',
                if (checkIn.hasEveningCapture) 'evening saved',
              ].join(' · ');

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today at a glance',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              nextEvent?.isDeadlinePreparation == true
                  ? Icons.school_outlined
                  : Icons.event_outlined,
            ),
            title: Text(nextEvent?.title ?? 'No more scheduled blocks today'),
            subtitle: Text(
              nextEvent == null
                  ? '${events.length} scheduled today'
                  : '${nextEvent.time} · ${events.length} scheduled today',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.monitor_heart_outlined),
            title: Text(captureStatus),
            subtitle: const Text('Details stay available below when needed.'),
            trailing: IconButton(
              tooltip: !morningSaved
                  ? 'Add morning check-in'
                  : eveningSaved
                      ? 'Edit evening check-in'
                      : 'Add evening check-in',
              onPressed: morningSaved ? onAddEvening : onAddMorning,
              icon: Icon(
                morningSaved
                    ? Icons.nights_stay_outlined
                    : Icons.wb_sunny_outlined,
              ),
            ),
          ),
          if (canExecute) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: onOpenFocus,
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('Start focus'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenHabits,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Today habits'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SupportingDashboardDetails extends StatelessWidget {
  const _SupportingDashboardDetails({
    required this.latestCheckIn,
    required this.recommendations,
    required this.schedule,
  });

  final Widget latestCheckIn;
  final Widget recommendations;
  final Widget schedule;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ExpansionTile(
            key: const ValueKey('dashboard-saved-signals'),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('Saved signals'),
            subtitle: const Text('Check-in values and edit actions'),
            childrenPadding: const EdgeInsets.all(AppSpacing.md),
            children: [latestCheckIn],
          ),
          const Divider(height: 1),
          ExpansionTile(
            key: const ValueKey('dashboard-supporting-suggestions'),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text('Supporting suggestions'),
            subtitle: const Text('Secondary guidance behind today’s action'),
            childrenPadding: const EdgeInsets.all(AppSpacing.md),
            children: [recommendations],
          ),
          const Divider(height: 1),
          ExpansionTile(
            key: const ValueKey('dashboard-full-week'),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.calendar_view_week_outlined),
            title: const Text('Full week'),
            subtitle: const Text('All commitments and preparation blocks'),
            childrenPadding: const EdgeInsets.all(AppSpacing.md),
            children: [schedule],
          ),
        ],
      ),
    );
  }
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
              if (snapshot.checkInStreakDays > 0)
                _StatusPill(
                  icon: Icons.local_fire_department_outlined,
                  label: '${snapshot.checkInStreakDays} day streak',
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
                  icon: const Icon(Icons.wb_sunny_outlined),
                  label: const Text('Morning check-in'),
                ),
                OutlinedButton.icon(
                  onPressed: onAddEvening,
                  icon: const Icon(Icons.nights_stay_outlined),
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
                  icon: const Icon(Icons.wb_sunny_outlined),
                  label: Text(
                    checkIn?.hasMorningCapture == true
                        ? 'Edit morning check-in'
                        : 'Add morning check-in',
                  ),
                ),
                TextButton.icon(
                  onPressed: onAddEvening,
                  icon: const Icon(Icons.nights_stay_outlined),
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
        _SignalMetric('Mood', '${checkIn.mood}/10', Icons.mood_outlined),
      if (checkIn.energy != null)
        _SignalMetric(
          checkIn.hasMorningCapture ? 'Morning energy' : 'Evening energy',
          '${checkIn.energy}/10',
          Icons.bolt_outlined,
        ),
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
      if (checkIn.focusBand != null)
        _SignalMetric(
          'Focus band',
          _readableCaptureCode(checkIn.focusBand!),
          Icons.timer_outlined,
        ),
      if (checkIn.dayShape != null)
        _SignalMetric(
          'Day shape',
          _readableCaptureCode(checkIn.dayShape!),
          Icons.calendar_today_outlined,
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
              icon: isDemo ? Icons.science_outlined : Icons.rule_outlined,
              label: isDemo ? 'Example suggestions' : 'Rule-based suggestions',
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
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add task'),
                )
              : null,
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
                onEdit: canExecute ? () => onEdit(task) : null,
                onComplete: canExecute ? () => onComplete(task) : null,
                onCancel: canExecute ? () => onCancel(task) : null,
                onPostpone: canExecute ? () => onPostpone(task) : null,
                onStartFocus: canExecute ? () => onStartFocus(task) : null,
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
                  onRestore: canExecute ? () => onRestore(task) : null,
                  onEdit: canExecute ? () => onEdit(task) : null,
                ),
              ),
            ),
        ],
        if (cancelledTasks.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: onToggleCancelled,
            icon: Icon(
              showCancelledTasks ? Icons.expand_less : Icons.expand_more,
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
                  onEdit: canExecute ? () => onEdit(task) : null,
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
                ? Icons.check_circle
                : isCancelled
                    ? Icons.cancel_outlined
                    : Icons.radio_button_unchecked,
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
                  icon: const Icon(Icons.timer_outlined),
                ),
              if (onEdit != null || onRestore != null || onComplete != null)
                IconButton(
                  tooltip: 'Open preparation plan',
                  onPressed: onEdit ?? onRestore ?? onComplete,
                  icon: const Icon(Icons.arrow_forward),
                ),
            ] else ...[
              if (onComplete != null)
                IconButton(
                  tooltip: 'Complete task ${task.title}',
                  onPressed: onComplete,
                  icon: const Icon(Icons.check),
                ),
              if (onStartFocus != null)
                IconButton(
                  tooltip: 'Focus on ${task.title}',
                  onPressed: onStartFocus,
                  icon: const Icon(Icons.timer_outlined),
                ),
              if (onRestore != null)
                IconButton(
                  tooltip: 'Restore task ${task.title}',
                  onPressed: onRestore,
                  icon: const Icon(Icons.undo),
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
                    icon: const Icon(Icons.event_outlined),
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
                    icon: const Icon(Icons.clear),
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
                  icon: const Icon(Icons.check),
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
          title: 'Commitments',
          subtitle: 'Schedule entries and confirmed preparation this week.',
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
                                    Icon(
                                      event.isDeadlinePreparation
                                          ? Icons.school_outlined
                                          : Icons.event,
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
                                          Icons.arrow_forward,
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
