import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../composition/projection_refresh_providers.dart';
import '../../../../composition/today_command_providers.dart';
import '../../../../composition/briefing_providers.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import 'package:my_life_graph/composition/optimization_providers.dart';
import '../../../briefings/domain/decision_feedback.dart';
import '../../../quick_action/domain/habit_v1.dart';
import 'package:my_life_graph/composition/widgets/app_header_actions.dart';
import '../../../tasks/domain/executable_task.dart';
import '../../domain/entities/dashboard_snapshot.dart';
import 'package:my_life_graph/composition/dashboard_providers.dart';
import '../widgets/dashboard_supporting_sections.dart';
import '../widgets/dashboard_section_widgets.dart';
import '../widgets/today_action_sections.dart';
import '../widgets/today_overview_sections.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  bool _showCompletedTasks = false;
  bool _showCancelledTasks = false;
  bool _showAllTasks = false;
  bool _showRecommendations = false;
  bool _showFeedback = false;
  bool _showFullWeek = false;
  bool _isRefreshingRecommendations = false;
  String? _recommendationRefreshError;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(dashboardSnapshotProvider);
    final commands = ref.watch(todayCommandControllerProvider);
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    final visibleSnapshot = commands.displayedSnapshot ?? snapshot.valueOrNull;

    if (visibleSnapshot == null) {
      return snapshot.when(
        loading: () => const AppPage(
          title: 'Today',
          actions: [AppHeaderActions()],
          children: [
            Center(child: CircularProgressIndicator()),
          ],
        ),
        error: (error, stackTrace) => AppPage(
          title: 'Today',
          actions: const [AppHeaderActions()],
          children: [
            _DashboardLoadError(
              onRetry: () => ref.invalidate(dashboardSnapshotProvider),
            ),
          ],
        ),
        data: (_) => const SizedBox.shrink(),
      );
    }
    final projectionCurrent =
        commands.projectionStatus == TodayProjectionStatus.current &&
            !snapshot.isRefreshing;
    final data = visibleSnapshot;
    final localDate = data.localDate;
    final latestCheckIn = localDate == null
        ? AsyncValue<DashboardCheckIn?>.error(
            const DashboardUnavailableException(
              'Profile-local Today date is unavailable.',
            ),
            StackTrace.current,
          )
        : ref.watch(dashboardLatestCheckInProvider(localDate));
    final recommendations =
        _showRecommendations ? ref.watch(recommendationFeedProvider) : null;
    final feedback = _showFeedback ? ref.watch(decisionFeedbackProvider) : null;
    final fullWeek = _showFullWeek && localDate != null
        ? ref.watch(dashboardFullWeekProvider(localDate))
        : null;
    return _DashboardHome(
      snapshot: data,
      commands: commands,
      projectionCurrent: projectionCurrent,
      projectionStale:
          commands.projectionStatus == TodayProjectionStatus.staleAfterMutation,
      onReloadToday: () =>
          ref.read(todayCommandControllerProvider.notifier).reloadToday(),
      overviewActions: TodayOverviewActions(
        onAddEvening: () => context.push(AppRoutes.dailyCheckIn),
        onAddMorning: () => context.push(AppRoutes.morningCalibration),
        onOpenPreparationPlan: (planId) => context.push(
          Uri(
            path: AppRoutes.preparationPlans,
            queryParameters: {'plan_id': planId},
          ).toString(),
        ),
        onStartPreparationFocus: (blockId) => context.push(
          Uri(
            path: AppRoutes.deepWork,
            queryParameters: {
              'source_kind': 'deadline_plan_block',
              'source_block_id': blockId,
            },
          ).toString(),
        ),
      ),
      latestCheckIn: latestCheckIn,
      taskVisibility: TodayTaskVisibility(
        showAll: _showAllTasks,
        showCompleted: _showCompletedTasks,
        showCancelled: _showCancelledTasks,
      ),
      taskActions: TodayTaskActions(
        onOpenPlanner: () => context.push(AppRoutes.planner),
        onComplete: _completeTask,
        onRestore: _restoreTask,
        onStartFocus: (task) => context.push(
          '${AppRoutes.deepWork}?target_kind=task&target_id=${task.id}',
        ),
        onToggleAll: () {
          setState(() => _showAllTasks = !_showAllTasks);
        },
        onToggleCompleted: () {
          setState(() => _showCompletedTasks = !_showCompletedTasks);
        },
        onToggleCancelled: () {
          setState(() => _showCancelledTasks = !_showCancelledTasks);
        },
      ),
      habitActions: TodayHabitActions(
        onSetOutcome: (habit, outcome) => _setHabitOutcome(
          habit,
          outcome,
          data.localDate,
        ),
        onUndo: (habit) => _undoHabitOutcome(
          habit,
          data.localDate,
        ),
      ),
      supportingSections: DashboardSupportingSections(
        recommendationsExpanded: _showRecommendations,
        feedbackExpanded: _showFeedback,
        fullWeekExpanded: _showFullWeek,
        state: DashboardSupportingState(
          accountData: data.origin == DashboardOrigin.account,
          canUseWeeklyReview: capabilities.canUseWeeklyReview,
          recommendations: recommendations,
          feedback: feedback,
          fullWeek: fullWeek,
          isRefreshingRecommendations: _isRefreshingRecommendations,
          recommendationRefreshError: _recommendationRefreshError,
        ),
        actions: DashboardSupportingActions(
          onToggleRecommendations: () {
            setState(() => _showRecommendations = !_showRecommendations);
          },
          onToggleFeedback: () {
            setState(() => _showFeedback = !_showFeedback);
          },
          onToggleFullWeek: () {
            setState(() => _showFullWeek = !_showFullWeek);
          },
          onOpenWeeklyReview: () => context.push(AppRoutes.weeklyReview),
          onRetryRecommendations: () {
            setState(() => _recommendationRefreshError = null);
            ref.invalidate(recommendationFeedProvider);
          },
          onRefreshRecommendations: _refreshRecommendations,
          onRetryFeedback: () => ref.invalidate(decisionFeedbackProvider),
          onDeleteFeedback: _deleteFeedback,
          onRetryFullWeek: () {
            if (localDate != null) {
              ref.invalidate(dashboardFullWeekProvider(localDate));
            }
          },
          onOpenPreparationPlan: (planId) => context.push(
            Uri(
              path: AppRoutes.preparationPlans,
              queryParameters: {'plan_id': planId},
            ).toString(),
          ),
        ),
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
          .read(projectionRefreshCoordinatorProvider)
          .recommendationInputsChanged(
            targetDate: ref.read(profileLocalDateSourceProvider).todayKey(),
          );
      await ref
          .read(optimizationServiceProvider)
          .refreshActionableRecommendations();
      await ref
          .read(projectionRefreshCoordinatorProvider)
          .recommendationsChanged();
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

  Future<void> _deleteFeedback(DecisionFeedback item) async {
    await ref.read(feedbackRepositoryProvider).delete(item.id);
    ref.invalidate(decisionFeedbackProvider);
  }

  Future<void> _setHabitOutcome(
    TodayHabit habit,
    HabitOutcome outcome,
    DateTime? targetDate,
  ) async {
    if (targetDate == null) {
      _showTaskMessage(
        'Today is unavailable. Reload before changing habits.',
      );
      return;
    }
    final result =
        await ref.read(todayCommandControllerProvider.notifier).setHabitOutcome(
              habitId: habit.id,
              outcome: outcome,
              targetDate: targetDate,
            );
    if (!mounted || !result.accepted) return;
    _showTaskMessage(
      result.committed
          ? result.projectionCurrent
              ? outcome == HabitOutcome.completed
                  ? 'Habit completed.'
                  : 'Habit intentionally skipped.'
              : 'Saved; Today could not reload.'
          : result.error is TodayHabitCommandFailure
              ? (result.error! as TodayHabitCommandFailure).message
              : 'Habit update could not be saved.',
    );
  }

  Future<void> _undoHabitOutcome(
    TodayHabit habit,
    DateTime? targetDate,
  ) async {
    if (targetDate == null) {
      _showTaskMessage(
        'Today is unavailable. Reload before changing habits.',
      );
      return;
    }
    final result = await ref
        .read(todayCommandControllerProvider.notifier)
        .undoHabitOutcome(
          habitId: habit.id,
          targetDate: targetDate,
        );
    if (!mounted || !result.accepted) return;
    _showTaskMessage(
      result.committed
          ? result.projectionCurrent
              ? 'Habit outcome undone.'
              : 'Saved; Today could not reload.'
          : result.error is TodayHabitCommandFailure
              ? (result.error! as TodayHabitCommandFailure).message
              : 'Habit undo could not be saved.',
    );
  }

  Future<void> _completeTask(PlanItem task) async {
    if (_openManagedPreparationPlan(task)) return;
    await _mutateTaskWithUndo(
      successMessage: 'Task completed.',
      command: (controller, targetDate) => controller.completeTask(
        taskId: task.id,
        targetDate: targetDate,
      ),
    );
  }

  Future<void> _restoreTask(PlanItem task) async {
    if (_openManagedPreparationPlan(task)) return;
    await _runTaskCommand(
      successMessage: 'Task restored.',
      command: (controller, targetDate) => controller.restoreTask(
        taskId: task.id,
        targetDate: targetDate,
      ),
    );
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
    required String successMessage,
    required Future<TodayCommandResult<TaskUndoToken>> Function(
      TodayCommandController controller,
      DateTime targetDate,
    ) command,
  }) async {
    await _runTaskCommand<TaskUndoToken>(
      successMessage: successMessage,
      command: command,
      onSuccess: (token) {
        if (token == null) {
          _showTaskMessage(successMessage);
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
    await _runTaskCommand(
      successMessage: 'Task change undone.',
      command: (controller, targetDate) => controller.undoTask(
        token: token,
        targetDate: targetDate,
      ),
    );
  }

  Future<void> _runTaskCommand<T>({
    required String successMessage,
    required Future<TodayCommandResult<T>> Function(
      TodayCommandController controller,
      DateTime targetDate,
    ) command,
    void Function(T? value)? onSuccess,
  }) async {
    final targetDate = _currentAuthenticatedLocalDate();
    if (targetDate == null) {
      _showTaskMessage('Today is unavailable. Reload before changing tasks.');
      return;
    }
    final result = await command(
      ref.read(todayCommandControllerProvider.notifier),
      targetDate,
    );
    if (!mounted || !result.accepted) return;
    if (!result.committed) {
      final error = result.error;
      _showTaskMessage(
        error is TaskCommandException
            ? error.message
            : 'Task update could not be saved.',
      );
      return;
    }
    if (!result.projectionCurrent) {
      _showTaskMessage('Saved; Today could not reload.');
    } else if (onSuccess != null) {
      onSuccess(result.value);
    } else {
      _showTaskMessage(successMessage);
    }
  }

  DateTime? _currentAuthenticatedLocalDate() {
    final snapshot =
        ref.read(todayCommandControllerProvider).displayedSnapshot ??
            ref.read(dashboardSnapshotProvider).valueOrNull;
    if (snapshot?.origin != DashboardOrigin.account) return null;
    return snapshot?.localDate;
  }

  void _showTaskMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _DashboardHome extends StatelessWidget {
  const _DashboardHome({
    required this.snapshot,
    required this.commands,
    required this.projectionCurrent,
    required this.projectionStale,
    required this.onReloadToday,
    required this.overviewActions,
    required this.latestCheckIn,
    required this.taskVisibility,
    required this.taskActions,
    required this.habitActions,
    required this.supportingSections,
  });

  final DashboardSnapshot snapshot;
  final TodayCommandState commands;
  final bool projectionCurrent;
  final bool projectionStale;
  final VoidCallback onReloadToday;
  final TodayOverviewActions overviewActions;
  final AsyncValue<DashboardCheckIn?> latestCheckIn;
  final TodayTaskVisibility taskVisibility;
  final TodayTaskActions taskActions;
  final TodayHabitActions habitActions;
  final Widget supportingSections;

  @override
  Widget build(BuildContext context) {
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
                          TodayOverviewSections(
                            snapshot: snapshot,
                            canExecute: canExecute,
                            actions: overviewActions,
                            latestCheckIn: latestCheckIn,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          TodayTaskSections(
                            snapshot: snapshot,
                            commands: commands,
                            canExecute: canExecute,
                            visibility: taskVisibility,
                            actions: taskActions,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          TodayHabitSection(
                            snapshot: snapshot,
                            commands: commands,
                            canExecute: canExecute,
                            actions: habitActions,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          supportingSections,
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
    final date = DateFormat(
      'EEEE, MMMM d',
    ).format(snapshot.localDate ?? DateTime.now());
    final sourceLabel = snapshot.origin == DashboardOrigin.localDemo
        ? 'Local data'
        : 'Your account data';

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(date, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.xs),
        TodayInfoDisclosure(
          topic: 'Today',
          description:
              '$sourceLabel · updated ${DateFormat.Hm().format(snapshot.loadedAt)}',
          descriptionStyle: Theme.of(context).textTheme.labelMedium,
          headerBuilder: (context, infoButton) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'Today',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
              ),
              infoButton,
            ],
          ),
        ),
      ],
    );
    final stackActions = MediaQuery.sizeOf(context).width < 600 ||
        MediaQuery.textScalerOf(context).scale(16) >= 24;
    if (stackActions) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          copy,
          const SizedBox(height: AppSpacing.sm),
          const Align(
            alignment: Alignment.centerRight,
            child: AppHeaderActions(),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: copy),
        const SizedBox(width: AppSpacing.sm),
        const AppHeaderActions(),
      ],
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
                  'Your account data could not be loaded. Check your connection and try again.',
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
