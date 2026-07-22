import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:my_life_graph/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:my_life_graph/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_plan.dart';
import 'package:my_life_graph/features/deadline_plans/presentation/providers/deadline_plan_providers.dart';
import 'package:my_life_graph/features/optimization/domain/entities/recommendation.dart';
import 'package:my_life_graph/features/optimization/domain/entities/recommendation_feed.dart';
import 'package:my_life_graph/features/optimization/presentation/providers/optimization_providers.dart';

import 'support/deadline_plan_fixtures.dart';

void main() {
  testWidgets('Today uses streak, progress, agenda, tasks, and habits order',
      (tester) async {
    await _pumpDashboard(tester, snapshot: _todaySnapshot());

    expect(find.text("Today's decision"), findsNothing);
    expect(find.text('Check-in streak'), findsOneWidget);
    expect(find.text('6 consecutive days'), findsOneWidget);
    expect(find.text("Today's progress"), findsOneWidget);
    expect(find.text('4/7 completed'), findsOneWidget);
    expect(find.text('Today at a glance'), findsOneWidget);
    expect(find.text('Setup commitment'), findsOneWidget);
    expect(find.text('Preparation'), findsOneWidget);
    expect(find.text('Calendar'), findsNWidgets(2));
    expect(find.text('Focus'), findsOneWidget);
    expect(find.text("Today's tasks"), findsOneWidget);
    expect(find.text("Today's habits"), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Recommendations'), findsNothing);

    final streakY = tester.getTopLeft(find.text('Check-in streak')).dy;
    final progressY = tester.getTopLeft(find.text("Today's progress")).dy;
    final agendaY = tester.getTopLeft(find.text('Today at a glance')).dy;
    final tasksY = tester.getTopLeft(find.text("Today's tasks")).dy;
    final habitsY = tester.getTopLeft(find.text("Today's habits")).dy;
    expect(streakY, lessThan(progressY));
    expect(progressY, lessThan(agendaY));
    expect(agendaY, lessThan(tasksY));
    expect(tasksY, lessThan(habitsY));
  });

  testWidgets('progress failure is honest while the usable agenda remains',
      (tester) async {
    final snapshot = _todaySnapshot(
      progress: null,
      sourceStates: _sourceStates(
        tasks: const TodaySourceState(
          status: TodaySourceStatus.unavailable,
          message: 'Tasks could not be loaded.',
        ),
      ),
      todayTasks: const [],
      allTasks: const [],
    );

    await _pumpDashboard(tester, snapshot: snapshot);

    expect(find.text('Progress unavailable'), findsOneWidget);
    expect(find.text('Tasks unavailable'), findsOneWidget);
    expect(find.text('Lecture'), findsOneWidget);
    expect(find.text('Imported seminar'), findsOneWidget);
    expect(find.text('4/7 completed'), findsNothing);
  });

  testWidgets('More is lazy and preserves secondary account surfaces',
      (tester) async {
    await _pumpDashboard(
      tester,
      snapshot: _todaySnapshot(),
      supporting: DashboardSnapshot(
        origin: DashboardOrigin.account,
        loadedAt: DateTime(2026, 7, 21, 10),
        latestCheckIn: DashboardCheckIn(
          entryDate: DateTime(2026, 7, 21),
          mood: 7,
          energy: 8,
          hasMorningCapture: true,
          hasEveningCapture: true,
        ),
        checkInStreakDays: 0,
        todayPlan: const [],
        scheduleDays: [
          ScheduleDay(
            label: 'Tue',
            dateLabel: 'Jul 21',
            date: DateTime(2026, 7, 21),
            events: const [
              ScheduleEvent(title: 'Full-week lecture', time: '10:00-11:00'),
            ],
          ),
        ],
      ),
      recommendations: Future.value(
        RecommendationFeed.demo(const [
          Recommendation(
            id: 'demo-rec',
            title: 'Rule-based example',
            reason: 'Available signal.',
            actionLabel: 'Review it',
            category: RecommendationCategory.planning,
            confidence: .7,
          ),
        ]),
      ),
      workload: Future.value(
        PreparationWorkload.fromJson(preparationWorkloadEnvelope()),
      ),
      capabilities: const AppSurfaceCapabilities(
        isLocalDemo: false,
        canUseSyncedHabits: true,
        canUseSyncedExecution: true,
        canUseDeadlinePlanner: true,
        canUseWeeklyReview: true,
      ),
    );

    expect(find.text('Rule-based example'), findsNothing);
    expect(find.text('Review your week'), findsNothing);

    await _tapExpansion(tester, const ValueKey('dashboard-more'));

    expect(find.text('7-day preparation load'), findsOneWidget);
    expect(find.text('Review your week'), findsOneWidget);
    expect(find.text('Latest check-in'), findsOneWidget);
    expect(find.text('Recommendations'), findsOneWidget);
    expect(find.text('Rule-based example'), findsOneWidget);
    expect(find.text('Decision feedback history'), findsOneWidget);
    expect(find.text('Full week'), findsOneWidget);
    expect(find.text('Full-week lecture'), findsOneWidget);
    expect(find.text('Secondary guidance behind today’s action'), findsNothing);
  });

  testWidgets('Show all tasks reveals future and planner-managed tasks',
      (tester) async {
    await _pumpDashboard(tester, snapshot: _todaySnapshot());

    expect(find.text('Future task'), findsNothing);
    expect(find.text('Managed preparation task'), findsNothing);

    await _tapExpansion(tester, const ValueKey('today-all-tasks'));

    expect(find.text('Future task'), findsOneWidget);
    expect(find.text('Managed preparation task'), findsOneWidget);
    expect(find.text('Managed by a preparation plan'), findsOneWidget);
  });

  testWidgets('Planner blocks stay agenda-only and keep unique target progress',
      (tester) async {
    await _pumpDashboard(
      tester,
      snapshot: _todaySnapshot(
        timeline: [
          TodayTimelineItem(
            kind: TodayTimelineKind.taskBlock,
            id: '90000000-0000-4000-8000-000000000001',
            title: 'Due task',
            allDay: false,
            startsAt: DateTime(2026, 7, 21, 9),
            endsAt: DateTime(2026, 7, 21, 9, 30),
            plannedMinutes: 30,
            taskId: '10000000-0000-4000-8000-000000000001',
          ),
          TodayTimelineItem(
            kind: TodayTimelineKind.taskBlock,
            id: '90000000-0000-4000-8000-000000000002',
            title: 'Due task',
            allDay: false,
            startsAt: DateTime(2026, 7, 21, 10),
            endsAt: DateTime(2026, 7, 21, 10, 30),
            plannedMinutes: 30,
            taskId: '10000000-0000-4000-8000-000000000001',
          ),
          TodayTimelineItem(
            kind: TodayTimelineKind.habitSlot,
            id: '90000000-0000-4000-8000-000000000003',
            title: 'Read',
            allDay: false,
            startsAt: DateTime(2026, 7, 21, 11),
            endsAt: DateTime(2026, 7, 21, 11, 20),
            plannedMinutes: 20,
            habitId: '80000000-0000-4000-8000-000000000001',
          ),
          TodayTimelineItem(
            kind: TodayTimelineKind.manualCommitment,
            id: '90000000-0000-4000-8000-000000000004',
            title: 'Tutoring',
            allDay: false,
            startsAt: DateTime(2026, 7, 21, 12),
            endsAt: DateTime(2026, 7, 21, 13),
            commitmentId: '90000000-0000-4000-8000-000000000004',
          ),
        ],
      ),
    );

    expect(find.text('Task block'), findsNWidgets(2));
    expect(find.text('Habit slot'), findsOneWidget);
    expect(find.text('Fixed commitment'), findsNWidgets(2));
    expect(find.text('4/7 completed'), findsOneWidget);
    expect(find.text('Due task'), findsNWidgets(3));
  });

  testWidgets('small width and 200 percent text keep Today scrollable',
      (tester) async {
    await _pumpDashboard(
      tester,
      snapshot: _todaySnapshot(),
      size: const Size(320, 760),
      textScaler: const TextScaler.linear(2),
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.text("Today's habits"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard load error never substitutes example content',
      (tester) async {
    await _pumpDashboard(
      tester,
      snapshotFuture: Future<DashboardSnapshot>(
        () => throw StateError('backend unavailable'),
      ),
    );

    expect(find.text('Dashboard unavailable'), findsOneWidget);
    expect(find.text('Check-in streak'), findsNothing);
  });
}

Future<void> _tapExpansion(WidgetTester tester, ValueKey<String> key) async {
  final card = find.byKey(key);
  final tile = find.descendant(of: card, matching: find.byType(ListTile)).first;
  tester.widget<ListTile>(tile).onTap!();
  await tester.pumpAndSettle();
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  DashboardSnapshot? snapshot,
  Future<DashboardSnapshot>? snapshotFuture,
  DashboardSnapshot? supporting,
  Future<RecommendationFeed>? recommendations,
  Future<PreparationWorkload>? workload,
  Size size = const Size(900, 1500),
  TextScaler textScaler = TextScaler.noScaling,
  AppSurfaceCapabilities capabilities = const AppSurfaceCapabilities(
    isLocalDemo: false,
    canUseSyncedHabits: true,
    canUseSyncedExecution: true,
  ),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final value = snapshotFuture ?? Future.value(snapshot ?? _todaySnapshot());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSurfaceCapabilitiesProvider.overrideWithValue(capabilities),
        dashboardSnapshotProvider.overrideWith((ref) => value),
        dashboardSupportingSnapshotProvider.overrideWith(
          (ref) => Future.value(
            supporting ??
                DashboardSnapshot.empty(
                  origin: DashboardOrigin.account,
                  loadedAt: DateTime(2026, 7, 21, 10),
                ),
          ),
        ),
        recommendationFeedProvider.overrideWith(
          (ref) =>
              recommendations ??
              Future.value(RecommendationFeed.demo(const [])),
        ),
        if (workload != null)
          preparationWorkloadProvider.overrideWith((ref) => workload),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: const Scaffold(body: DashboardPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DashboardSnapshot _todaySnapshot({
  TodayProgress? progress = const TodayProgress(completed: 4, total: 7),
  TodaySourceStates? sourceStates,
  List<PlanItem>? todayTasks,
  List<PlanItem>? allTasks,
  List<TodayTimelineItem>? timeline,
}) {
  const due = PlanItem(
    id: '10000000-0000-4000-8000-000000000001',
    title: 'Due task',
    priority: 'high',
    isCompleted: false,
    status: 'todo',
    source: 'manual',
    todayReason: 'due_today',
  );
  const done = PlanItem(
    id: '10000000-0000-4000-8000-000000000002',
    title: 'Done task',
    priority: 'medium',
    isCompleted: true,
    status: 'done',
    source: 'manual',
    todayReason: 'completed_today',
  );
  const future = PlanItem(
    id: '10000000-0000-4000-8000-000000000003',
    title: 'Future task',
    priority: 'low',
    isCompleted: false,
    status: 'todo',
    source: 'manual',
  );
  const managed = PlanItem(
    id: '10000000-0000-4000-8000-000000000004',
    title: 'Managed preparation task',
    priority: 'medium',
    isCompleted: false,
    status: 'in_progress',
    source: 'deadline-plan-v1',
    deadlinePlanId: '10000000-0000-4000-8000-000000000004',
  );
  final selected = todayTasks ?? const [due, done];
  final all = allTasks ?? const [due, done, future, managed];
  return DashboardSnapshot(
    origin: DashboardOrigin.account,
    loadedAt: DateTime(2026, 7, 21, 10),
    latestCheckIn: null,
    checkInStreakDays: 6,
    todayPlan: all,
    scheduleDays: const [],
    localDate: DateTime(2026, 7, 21),
    timezone: 'Europe/Berlin',
    checkIns: const TodayCheckIns(
      morningSaved: true,
      eveningSaved: true,
      completedDaysStreak: 6,
    ),
    progress: progress,
    todayTasks: selected,
    timeline: timeline ??
        [
          TodayTimelineItem(
            kind: TodayTimelineKind.calendarEvent,
            id: '20000000-0000-4000-8000-000000000001',
            title: 'All-day event',
            allDay: true,
            startsOn: DateTime(2026, 7, 21),
            endsOn: DateTime(2026, 7, 22),
            sourceLabel: 'Studies',
          ),
          TodayTimelineItem(
            kind: TodayTimelineKind.setupCommitment,
            id: '30000000-0000-5000-8000-000000000001',
            title: 'Lecture',
            allDay: false,
            startsAt: DateTime(2026, 7, 21, 9),
            endsAt: DateTime(2026, 7, 21, 10),
          ),
          TodayTimelineItem(
            kind: TodayTimelineKind.preparation,
            id: '40000000-0000-4000-8000-000000000001',
            title: 'Mathematics',
            allDay: false,
            startsAt: DateTime(2026, 7, 21, 10),
            endsAt: DateTime(2026, 7, 21, 10, 50),
            planId: '50000000-0000-4000-8000-000000000001',
            blockId: '40000000-0000-4000-8000-000000000001',
            managedTaskId: '50000000-0000-4000-8000-000000000001',
            state: 'partial',
            plannedMinutes: 50,
            creditedTrackedMinutes: 20,
          ),
          TodayTimelineItem(
            kind: TodayTimelineKind.calendarEvent,
            id: '60000000-0000-4000-8000-000000000001',
            title: 'Imported seminar',
            allDay: false,
            startsAt: DateTime(2026, 7, 21, 11),
            endsAt: DateTime(2026, 7, 21, 12),
            sourceLabel: 'Studies',
          ),
          TodayTimelineItem(
            kind: TodayTimelineKind.focusSession,
            id: '70000000-0000-4000-8000-000000000001',
            title: 'Essay focus',
            allDay: false,
            startsAt: DateTime(2026, 7, 21, 12),
            endsAt: DateTime(2026, 7, 21, 12, 30),
            state: 'completed',
            actualMinutes: 30,
          ),
        ],
    todayHabits: const [
      TodayHabit(
        id: '80000000-0000-4000-8000-000000000001',
        title: 'Read',
        cadence: 'daily',
        cadenceLabel: 'Daily',
        weeklyCompleted: 1,
        weeklyTarget: 1,
        setupManaged: false,
        outcome: 'completed',
      ),
      TodayHabit(
        id: '80000000-0000-4000-8000-000000000002',
        title: 'Exercise',
        cadence: 'weekly_target',
        cadenceLabel: '3 times per week',
        weeklyCompleted: 1,
        weeklyTarget: 3,
        setupManaged: true,
      ),
    ],
    sourceStates: sourceStates ?? _sourceStates(),
    isTodayOverview: true,
  );
}

TodaySourceStates _sourceStates({
  TodaySourceState tasks = const TodaySourceState(
    status: TodaySourceStatus.current,
  ),
}) {
  const current = TodaySourceState(status: TodaySourceStatus.current);
  return TodaySourceStates(
    checkIns: current,
    tasks: tasks,
    habits: current,
    setupCommitments: current,
    preparation: current,
    calendarEvents: current,
    focusSessions: current,
    planner: current,
  );
}
