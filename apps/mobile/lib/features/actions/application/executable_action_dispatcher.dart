import '../../focus/domain/focus_session.dart';
import '../../quick_action/domain/habit_v1.dart';
import '../domain/executable_action_target.dart';

enum ExecutableCaptureRoute {
  eveningShutdown('/quick-mood-check-in'),
  morningCalibration('/morning-calibration');

  const ExecutableCaptureRoute(this.path);

  final String path;

  static ExecutableCaptureRoute? fromPath(Object? value) {
    for (final route in values) {
      if (route.path == value) {
        return route;
      }
    }
    return null;
  }
}

typedef OpenTaskActionHandler = Future<void> Function({
  required String actionId,
  required String taskId,
  int? estimatedMinutes,
  String? source,
});

typedef CompleteTaskActionHandler = Future<void> Function({
  required String actionId,
  required String taskId,
  String? source,
});

typedef LogHabitActionHandler = Future<void> Function({
  required String actionId,
  required String habitId,
  String? entryDate,
  HabitOutcome? outcome,
  String? source,
});

typedef StartFocusActionHandler = Future<void> Function({
  required String actionId,
  String? targetId,
  FocusTargetKind? targetKind,
  int? plannedMinutes,
  String? source,
});

typedef OpenCaptureActionHandler = Future<void> Function({
  required String actionId,
  required ExecutableCaptureRoute route,
  String? entryDate,
  String? source,
});

typedef ReviewPlanActionHandler = Future<void> Function({
  required String actionId,
  String? reviewId,
  int? estimatedMinutes,
  String? source,
});

class ExecutableActionDispatcher {
  const ExecutableActionDispatcher({
    required OpenTaskActionHandler openTask,
    required CompleteTaskActionHandler completeTask,
    required LogHabitActionHandler logHabit,
    required StartFocusActionHandler startFocus,
    required ReviewPlanActionHandler reviewPlan,
    required OpenCaptureActionHandler openCapture,
  })  : _openTask = openTask,
        _completeTask = completeTask,
        _logHabit = logHabit,
        _startFocus = startFocus,
        _reviewPlan = reviewPlan,
        _openCapture = openCapture;

  final OpenTaskActionHandler _openTask;
  final CompleteTaskActionHandler _completeTask;
  final LogHabitActionHandler _logHabit;
  final StartFocusActionHandler _startFocus;
  final ReviewPlanActionHandler _reviewPlan;
  final OpenCaptureActionHandler _openCapture;

  Future<ExecutableActionDispatchResult> dispatch(
    ExecutableActionTarget target, {
    required bool canUseSyncedExecution,
    bool canUseWeeklyReview = false,
  }) async {
    final availability = target.availability(
      canUseSyncedExecution: canUseSyncedExecution,
      canUseWeeklyReview: canUseWeeklyReview,
    );

    switch (target.command) {
      case ExecutableActionCommand.openTask:
        final unavailable = _unavailable(target, availability);
        if (unavailable != null) {
          return unavailable;
        }
        await _openTask(
          actionId: target.id,
          taskId: target.targetId!,
          estimatedMinutes: target.estimatedMinutes,
          source: target.metadata['source'] as String?,
        );
      case ExecutableActionCommand.completeTask:
        final unavailable = _unavailable(target, availability);
        if (unavailable != null) {
          return unavailable;
        }
        await _completeTask(
          actionId: target.id,
          taskId: target.targetId!,
          source: target.metadata['source'] as String?,
        );
      case ExecutableActionCommand.logHabit:
        final unavailable = _unavailable(target, availability);
        if (unavailable != null) {
          return unavailable;
        }
        await _logHabit(
          actionId: target.id,
          habitId: target.targetId!,
          entryDate: target.metadata['entry_date'] as String?,
          outcome: HabitOutcome.fromCode(target.metadata['habit_outcome']),
          source: target.metadata['source'] as String?,
        );
      case ExecutableActionCommand.startFocus:
        final unavailable = _unavailable(target, availability);
        if (unavailable != null) {
          return unavailable;
        }
        await _startFocus(
          actionId: target.id,
          targetId: target.targetId,
          targetKind: FocusTargetKind.fromCode(
            target.metadata['target_kind'],
          ),
          plannedMinutes: target.metadata['focus_minutes'] as int? ??
              target.estimatedMinutes,
          source: target.metadata['source'] as String?,
        );
      case ExecutableActionCommand.reviewPlan:
        final unavailable = _unavailable(target, availability);
        if (unavailable != null) {
          return unavailable;
        }
        await _reviewPlan(
          actionId: target.id,
          reviewId: target.targetId,
          estimatedMinutes: target.estimatedMinutes,
          source: target.metadata['source'] as String?,
        );
      case ExecutableActionCommand.openCapture:
        final unavailable = _unavailable(target, availability);
        if (unavailable != null) {
          return unavailable;
        }
        await _openCapture(
          actionId: target.id,
          route: ExecutableCaptureRoute.fromPath(target.metadata['route'])!,
          entryDate: target.metadata['entry_date'] as String?,
          source: target.metadata['source'] as String?,
        );
    }

    return ExecutableActionHandled(
      actionId: target.id,
      command: target.command,
    );
  }

  static ExecutableActionUnavailable? _unavailable(
    ExecutableActionTarget target,
    ExecutableActionAvailability availability,
  ) {
    if (availability.isAvailable) {
      return null;
    }
    return ExecutableActionUnavailable(
      actionId: target.id,
      command: target.command,
      reason: availability.reason ?? 'This action is unavailable.',
    );
  }
}

sealed class ExecutableActionDispatchResult {
  const ExecutableActionDispatchResult({
    required this.actionId,
    required this.command,
  });

  final String actionId;
  final ExecutableActionCommand command;
}

final class ExecutableActionHandled extends ExecutableActionDispatchResult {
  const ExecutableActionHandled({
    required super.actionId,
    required super.command,
  });
}

final class ExecutableActionUnavailable extends ExecutableActionDispatchResult {
  const ExecutableActionUnavailable({
    required super.actionId,
    required super.command,
    required this.reason,
  });

  final String reason;
}
