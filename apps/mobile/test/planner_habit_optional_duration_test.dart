import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/planner/application/planner_controller.dart';
import 'package:my_life_graph/features/planner/data/planner_api_data_source.dart';
import 'package:my_life_graph/features/planner/domain/planner.dart';
import 'package:my_life_graph/features/planner/presentation/widgets/planner_dialogs.dart';
import 'support/planner_fixtures.dart';

void main() {
  test(
    'manual Habit single-flight and exact retry retain UUID and immutable draft',
    () async {
      final pending = Completer<void>();
      final calls = <String>[];
      final drafts = <PlannerHabitDraft>[];
      final controller = PlannerController(
        api: _OverviewApi(),
        accessTokenProvider: () => 'test-token',
        canUseSyncedPlanner: true,
        isBackendConfigured: true,
        createManualHabit: (draft, requestId) async {
          calls.add(requestId);
          drafts.add(draft);
          if (calls.length == 1) await pending.future;
        },
      );
      addTearDown(controller.dispose);
      await controller.load();
      const draft = PlannerHabitDraft(
        title: 'Read',
        description: null,
        cadenceKind: 'daily',
        scheduledWeekdays: [],
        weeklyTarget: 1,
        durationMinutes: null,
      );
      final save = controller.createUnscheduledHabit(draft);
      expect(await controller.createUnscheduledHabit(draft), isFalse);
      expect(controller.state.canMutate, isFalse);
      pending.completeError(StateError('Lost response'));
      expect(await save, isFalse);
      expect(controller.state.requiresExactRetry, isTrue);
      expect(await controller.createUnscheduledHabit(draft), isFalse);
      expect((await controller.retryExact())!.succeeded, isTrue);
      expect(calls, hasLength(2));
      expect(calls[0], calls[1]);
      expect(drafts[0], same(drafts[1]));
      expect(controller.state.canMutate, isTrue);
      expect(controller.state.mutationOutcome!.committed, isTrue);
    },
  );

  Future<void> open(
    WidgetTester tester,
    void Function(PlannerHabitDraft?) result, {
    PlannerHabitDraft? initial,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result(
                  await showDialog<PlannerHabitDraft>(
                    context: context,
                    builder: (_) => PlannerHabitDialog(initial: initial),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'new Habit saves without minutes; adding minutes retains planning',
    (tester) async {
      PlannerHabitDraft? result;
      await open(
        tester,
        (draft) => result = draft,
        initial: const PlannerHabitDraft(
          title: 'Read',
          description: null,
          cadenceKind: 'daily',
          scheduledWeekdays: [],
          weeklyTarget: 1,
          durationMinutes: null,
        ),
      );
      expect(find.text('Minutes (optional)'), findsOneWidget);
      expect(find.text('Save habit'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('planner-habit-duration')),
        '20',
      );
      await tester.pump();
      expect(find.text('Preview plan'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('planner-habit-duration')),
        '',
      );
      await tester.pump();
      await tester.tap(find.text('Save habit'));
      await tester.pumpAndSettle();
      expect(result!.durationMinutes, isNull);
      expect(result!.title, 'Read');
    },
  );

  for (final minutes in ['no', '0', '6', '245']) {
    testWidgets(
      'optional minutes still reject invalid supplied value $minutes',
      (tester) async {
        await open(
          tester,
          (_) => fail('Invalid Habit returned'),
          initial: const PlannerHabitDraft(
            title: 'Read',
            description: null,
            cadenceKind: 'daily',
            scheduledWeekdays: [],
            weeklyTarget: 1,
            durationMinutes: null,
          ),
        );
        await tester.enterText(
          find.byKey(const ValueKey('planner-habit-duration')),
          minutes,
        );
        await tester.pump();
        await tester.tap(find.text('Preview plan'));
        await tester.pump();
        expect(
          find.text('Choose 5–240 minutes in five-minute steps.'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('existing Habit planning still requires a duration', (
    tester,
  ) async {
    await open(
      tester,
      (_) => fail('Missing planned duration accepted'),
      initial: PlannerHabitDraft(
        title: 'Read',
        description: null,
        cadenceKind: 'daily',
        scheduledWeekdays: [],
        weeklyTarget: 1,
        durationMinutes: null,
        targetId: 'habit-id',
        expectedUpdatedAt: DateTime.utc(2026),
      ),
    );
    expect(find.text('Minutes per occurrence *'), findsOneWidget);
    await tester.tap(find.text('Preview plan'));
    await tester.pump();
    expect(
      find.text('Choose 5–240 minutes in five-minute steps.'),
      findsOneWidget,
    );
  });
}

class _OverviewApi extends PlannerApiDataSource {
  _OverviewApi() : super(ApiClient(Dio()));
  @override
  Future<PlannerOverview> getOverview({required String accessToken}) async =>
      PlannerOverview.fromJson(plannerOverviewEnvelope());
}
