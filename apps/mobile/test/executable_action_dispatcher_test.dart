import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/actions/application/executable_action_dispatcher.dart';
import 'package:my_life_graph/features/actions/domain/executable_action_target.dart';
import 'package:my_life_graph/features/focus/domain/focus_session.dart';
import 'package:my_life_graph/features/quick_action/domain/habit_v1.dart';

void main() {
  group('ExecutableActionDispatcher', () {
    test('construction does not invoke handlers', () {
      final harness = _DispatchHarness();

      expect(harness.callCount, 0);
    });

    test('open_task invokes only the typed task-open handler', () async {
      final harness = _DispatchHarness();
      final target = ExecutableActionTarget(
        id: 'open_task:task-1',
        kind: ExecutableActionKind.task,
        command: ExecutableActionCommand.openTask,
        targetId: 'task-1',
        estimatedMinutes: 35,
        metadata: const {'source': 'daily_briefing'},
      );

      final result = await harness.dispatcher.dispatch(
        target,
        canUseSyncedExecution: true,
      );

      expect(result, isA<ExecutableActionHandled>());
      expect(result.actionId, target.id);
      expect(result.command, ExecutableActionCommand.openTask);
      expect(
        harness.openTaskCall,
        (
          actionId: 'open_task:task-1',
          taskId: 'task-1',
          estimatedMinutes: 35,
          source: 'daily_briefing',
        ),
      );
      expect(harness.callCount, 1);
    });

    test('complete_task invokes only the typed completion handler', () async {
      final harness = _DispatchHarness();
      final target = ExecutableActionTarget(
        id: 'complete_task:task-2',
        kind: ExecutableActionKind.task,
        command: ExecutableActionCommand.completeTask,
        targetId: 'task-2',
        metadata: const {'source': 'today'},
      );

      final result = await harness.dispatcher.dispatch(
        target,
        canUseSyncedExecution: true,
      );

      expect(result, isA<ExecutableActionHandled>());
      expect(
        harness.completeTaskCall,
        (
          actionId: 'complete_task:task-2',
          taskId: 'task-2',
          source: 'today',
        ),
      );
      expect(harness.callCount, 1);
    });

    test('log_habit maps date and outcome to typed handler values', () async {
      final harness = _DispatchHarness();
      final target = ExecutableActionTarget(
        id: 'log_habit:habit-1:2026-07-11',
        kind: ExecutableActionKind.habit,
        command: ExecutableActionCommand.logHabit,
        targetId: 'habit-1',
        metadata: const {
          'entry_date': '2026-07-11',
          'habit_outcome': 'skipped',
          'source': 'daily_briefing',
        },
      );

      final result = await harness.dispatcher.dispatch(
        target,
        canUseSyncedExecution: true,
      );

      expect(result, isA<ExecutableActionHandled>());
      expect(
        harness.logHabitCall,
        (
          actionId: 'log_habit:habit-1:2026-07-11',
          habitId: 'habit-1',
          entryDate: '2026-07-11',
          outcome: HabitOutcome.skipped,
          source: 'daily_briefing',
        ),
      );
      expect(harness.callCount, 1);
    });

    test('start_focus maps linked target and planned duration', () async {
      final harness = _DispatchHarness();
      final target = ExecutableActionTarget(
        id: 'start_focus:task-3',
        kind: ExecutableActionKind.focus,
        command: ExecutableActionCommand.startFocus,
        targetId: 'task-3',
        estimatedMinutes: 25,
        metadata: const {
          'focus_minutes': 25,
          'target_kind': 'task',
          'source': 'daily_briefing',
        },
      );

      final result = await harness.dispatcher.dispatch(
        target,
        canUseSyncedExecution: true,
      );

      expect(result, isA<ExecutableActionHandled>());
      expect(
        harness.startFocusCall,
        (
          actionId: 'start_focus:task-3',
          targetId: 'task-3',
          targetKind: FocusTargetKind.task,
          plannedMinutes: 25,
          source: 'daily_briefing',
        ),
      );
      expect(harness.callCount, 1);
    });

    test('open_capture maps the exact route without requiring sync', () async {
      final harness = _DispatchHarness();
      final target = ExecutableActionTarget(
        id: 'open_capture:morning:2026-07-11',
        kind: ExecutableActionKind.capture,
        command: ExecutableActionCommand.openCapture,
        metadata: const {
          'route': '/morning-calibration',
          'entry_date': '2026-07-11',
          'source': 'daily_briefing',
        },
      );

      final result = await harness.dispatcher.dispatch(
        target,
        canUseSyncedExecution: false,
      );

      expect(result, isA<ExecutableActionHandled>());
      expect(
        harness.openCaptureCall,
        (
          actionId: 'open_capture:morning:2026-07-11',
          route: ExecutableCaptureRoute.morningCalibration,
          entryDate: '2026-07-11',
          source: 'daily_briefing',
        ),
      );
      expect(harness.callCount, 1);
    });

    test('review_plan is explicitly unavailable and invokes no handler',
        () async {
      final harness = _DispatchHarness();
      final target = ExecutableActionTarget(
        id: 'review_plan:today',
        kind: ExecutableActionKind.planning,
        command: ExecutableActionCommand.reviewPlan,
        metadata: const {'source': 'daily_briefing'},
      );

      final result = await harness.dispatcher.dispatch(
        target,
        canUseSyncedExecution: true,
      );

      expect(result, isA<ExecutableActionUnavailable>());
      expect(result.actionId, target.id);
      expect(result.command, ExecutableActionCommand.reviewPlan);
      expect(
        (result as ExecutableActionUnavailable).reason,
        'Plan review is not available yet.',
      );
      expect(harness.callCount, 0);
    });

    test('synced commands return unavailable before invoking a handler',
        () async {
      final harness = _DispatchHarness();
      final target = ExecutableActionTarget(
        id: 'open_task:task-4',
        kind: ExecutableActionKind.task,
        command: ExecutableActionCommand.openTask,
        targetId: 'task-4',
      );

      final result = await harness.dispatcher.dispatch(
        target,
        canUseSyncedExecution: false,
      );

      expect(result, isA<ExecutableActionUnavailable>());
      expect(
        (result as ExecutableActionUnavailable).reason,
        'This action requires a synced account.',
      );
      expect(harness.callCount, 0);
    });

    test('handler failure propagates and is never reported as handled',
        () async {
      final harness = _DispatchHarness(
        completeTaskFailure: StateError('durable write failed'),
      );
      final target = ExecutableActionTarget(
        id: 'complete_task:task-5',
        kind: ExecutableActionKind.task,
        command: ExecutableActionCommand.completeTask,
        targetId: 'task-5',
      );

      await expectLater(
        harness.dispatcher.dispatch(
          target,
          canUseSyncedExecution: true,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'durable write failed',
          ),
        ),
      );
      expect(harness.callCount, 1);
    });
  });
}

class _DispatchHarness {
  _DispatchHarness({this.completeTaskFailure}) {
    dispatcher = ExecutableActionDispatcher(
      openTask: ({
        required String actionId,
        required String taskId,
        int? estimatedMinutes,
        String? source,
      }) async {
        openTaskCall = (
          actionId: actionId,
          taskId: taskId,
          estimatedMinutes: estimatedMinutes,
          source: source,
        );
      },
      completeTask: ({
        required String actionId,
        required String taskId,
        String? source,
      }) async {
        completeTaskCall = (
          actionId: actionId,
          taskId: taskId,
          source: source,
        );
        if (completeTaskFailure case final failure?) {
          throw failure;
        }
      },
      logHabit: ({
        required String actionId,
        required String habitId,
        String? entryDate,
        HabitOutcome? outcome,
        String? source,
      }) async {
        logHabitCall = (
          actionId: actionId,
          habitId: habitId,
          entryDate: entryDate,
          outcome: outcome,
          source: source,
        );
      },
      startFocus: ({
        required String actionId,
        String? targetId,
        FocusTargetKind? targetKind,
        int? plannedMinutes,
        String? source,
      }) async {
        startFocusCall = (
          actionId: actionId,
          targetId: targetId,
          targetKind: targetKind,
          plannedMinutes: plannedMinutes,
          source: source,
        );
      },
      openCapture: ({
        required String actionId,
        required ExecutableCaptureRoute route,
        String? entryDate,
        String? source,
      }) async {
        openCaptureCall = (
          actionId: actionId,
          route: route,
          entryDate: entryDate,
          source: source,
        );
      },
    );
  }

  final Object? completeTaskFailure;
  late final ExecutableActionDispatcher dispatcher;

  ({
    String actionId,
    String taskId,
    int? estimatedMinutes,
    String? source,
  })? openTaskCall;
  ({String actionId, String taskId, String? source})? completeTaskCall;
  ({
    String actionId,
    String habitId,
    String? entryDate,
    HabitOutcome? outcome,
    String? source,
  })? logHabitCall;
  ({
    String actionId,
    String? targetId,
    FocusTargetKind? targetKind,
    int? plannedMinutes,
    String? source,
  })? startFocusCall;
  ({
    String actionId,
    ExecutableCaptureRoute route,
    String? entryDate,
    String? source,
  })? openCaptureCall;

  int get callCount => [
        openTaskCall,
        completeTaskCall,
        logHabitCall,
        startFocusCall,
        openCaptureCall,
      ].where((call) => call != null).length;
}
