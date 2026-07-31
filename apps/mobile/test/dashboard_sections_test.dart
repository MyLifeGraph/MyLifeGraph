import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/briefing_providers.dart';
import 'package:my_life_graph/features/dashboard/application/today_command_controller.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:my_life_graph/features/dashboard/presentation/widgets/dashboard_more_section.dart';
import 'package:my_life_graph/features/dashboard/presentation/widgets/today_action_sections.dart';
import 'package:my_life_graph/features/dashboard/presentation/widgets/today_overview_sections.dart';

void main() {
  test('Dashboard page composes section APIs instead of owning their widgets',
      () {
    final source = File(
      'lib/features/dashboard/presentation/pages/dashboard_page.dart',
    ).readAsStringSync();

    expect(source, contains('TodayOverviewSections('));
    expect(source, contains('TodayTaskSections('));
    expect(source, contains('TodayHabitSection('));
    expect(source, contains('DashboardMoreSection('));
    expect(source, isNot(contains('class _TodayAgenda')));
    expect(source, isNot(contains('class _TaskEditorSheet')));
    expect(source, isNot(contains('class _RecommendationsSection')));

    final homeConstructor = RegExp(
      r'const _DashboardHome\(\{(?<arguments>.*?)\}\);',
      dotAll: true,
    ).firstMatch(source);
    expect(homeConstructor, isNotNull);
    expect(
      RegExp(r'required this\.')
          .allMatches(homeConstructor!.namedGroup('arguments')!)
          .length,
      lessThanOrEqualTo(14),
    );
  });

  testWidgets('Today summary owns capture, progress, and agenda callbacks',
      (tester) async {
    var morningCalls = 0;
    String? openedPlan;
    await _pump(
      tester,
      TodayOverviewSections(
        snapshot: _snapshot(
          timeline: [
            TodayTimelineItem(
              kind: TodayTimelineKind.preparation,
              id: 'block-1',
              title: 'Mathematics',
              allDay: false,
              startsAt: DateTime(2026, 7, 31, 9),
              endsAt: DateTime(2026, 7, 31, 10),
              planId: 'plan-1',
              state: 'upcoming',
              plannedMinutes: 60,
            ),
          ],
        ),
        canExecute: true,
        actions: TodayOverviewActions(
          onAddEvening: () {},
          onAddMorning: () => morningCalls += 1,
          onOpenPreparationPlan: (value) => openedPlan = value,
          onStartPreparationFocus: (_) {},
        ),
      ),
    );

    expect(find.text('Check-in streak'), findsOneWidget);
    expect(find.text("Today's progress"), findsOneWidget);
    expect(find.text('Today at a glance'), findsOneWidget);

    await tester.tap(find.text('Edit Morning check-in'));
    await tester.tap(find.text('Open plan'));

    expect(morningCalls, 1);
    expect(openedPlan, 'plan-1');
  });

  testWidgets('Task sections expose only their typed action boundary',
      (tester) async {
    var completedTaskId = '';
    var toggleAllCalls = 0;
    const task = PlanItem(
      id: 'task-1',
      title: 'Write summary',
      priority: 'high',
      isCompleted: false,
      status: 'todo',
    );
    await _pump(
      tester,
      TodayTaskSections(
        snapshot: _snapshot(todayTasks: const [task], allTasks: const [task]),
        commands: TodayCommandState.initial(),
        canExecute: true,
        visibility: const TodayTaskVisibility(
          showAll: false,
          showCompleted: false,
          showCancelled: false,
        ),
        actions: TodayTaskActions(
          onOpenPlanner: () {},
          onComplete: (value) => completedTaskId = value.id,
          onRestore: (_) {},
          onStartFocus: (_) {},
          onToggleAll: () => toggleAllCalls += 1,
          onToggleCompleted: () {},
          onToggleCancelled: () {},
        ),
      ),
    );

    await tester.tap(find.byTooltip('Complete task Write summary'));
    await tester.tap(find.byKey(const ValueKey('today-all-tasks')));

    expect(completedTaskId, 'task-1');
    expect(toggleAllCalls, 1);
  });

  testWidgets('Habit section renders optimistic outcome and delegates undo',
      (tester) async {
    var undoneHabitId = '';
    const habit = TodayHabit(
      id: 'habit-1',
      title: 'Read',
      cadence: 'daily',
      cadenceLabel: 'Daily',
      weeklyCompleted: 0,
      weeklyTarget: 1,
      setupManaged: false,
    );
    final commands = TodayCommandState.initial().copyWith(
      habitOutcomeOverrides: const {'habit-1': 'completed'},
    );
    await _pump(
      tester,
      TodayHabitSection(
        snapshot: _snapshot(todayHabits: const [habit]),
        commands: commands,
        canExecute: true,
        actions: TodayHabitActions(
          onSetOutcome: (_, __) {},
          onUndo: (value) => undoneHabitId = value.id,
        ),
      ),
    );

    expect(find.text('Undo outcome'), findsOneWidget);
    expect(find.text('Complete'), findsNothing);
    await tester.tap(find.text('Undo outcome'));
    expect(undoneHabitId, 'habit-1');
  });

  testWidgets('More section stays lazy and owns weekly-review entry',
      (tester) async {
    var toggleCalls = 0;
    var weeklyReviewCalls = 0;
    final state = DashboardMoreState(
      accountData: true,
      supporting: null,
      recommendations: null,
      workload: null,
      canUseWeeklyReview: true,
      isRefreshingRecommendations: false,
      recommendationRefreshError: null,
    );
    final actions = DashboardMoreActions(
      onRetryWorkload: () {},
      onLoadWorkloadDetail: (_) async => throw UnimplementedError(),
      onOpenWeeklyReview: () => weeklyReviewCalls += 1,
      onRetryRecommendations: () {},
      onRefreshRecommendations: () {},
      onShowFeedbackHistory: () {},
      onAddMorning: () {},
      onAddEvening: () {},
      onOpenPreparationPlan: (_) {},
    );

    await _pump(
      tester,
      DashboardMoreSection(
        expanded: false,
        onToggle: () => toggleCalls += 1,
        state: state,
        actions: actions,
      ),
      providerOverrides: [
        decisionFeedbackProvider.overrideWith((ref) => Future.value(const [])),
      ],
    );

    expect(find.text('Review your week'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dashboard-more')));
    expect(toggleCalls, 1);

    await _pump(
      tester,
      DashboardMoreSection(
        expanded: true,
        onToggle: () {},
        state: state,
        actions: actions,
      ),
      providerOverrides: [
        decisionFeedbackProvider.overrideWith((ref) => Future.value(const [])),
      ],
    );
    await tester.tap(find.text('Review your week'));
    expect(weeklyReviewCalls, 1);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  List<Override> providerOverrides = const [],
}) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: providerOverrides,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DashboardSnapshot _snapshot({
  List<PlanItem> todayTasks = const [],
  List<PlanItem> allTasks = const [],
  List<TodayHabit> todayHabits = const [],
  List<TodayTimelineItem> timeline = const [],
}) {
  return DashboardSnapshot(
    origin: DashboardOrigin.account,
    loadedAt: DateTime(2026, 7, 31, 9),
    latestCheckIn: null,
    checkInStreakDays: 3,
    todayPlan: allTasks,
    scheduleDays: const [],
    localDate: DateTime(2026, 7, 31),
    checkIns: const TodayCheckIns(
      morningSaved: true,
      eveningSaved: false,
      completedDaysStreak: 3,
    ),
    progress: const TodayProgress(completed: 2, total: 4),
    todayTasks: todayTasks,
    todayHabits: todayHabits,
    timeline: timeline,
    isTodayOverview: true,
  );
}
