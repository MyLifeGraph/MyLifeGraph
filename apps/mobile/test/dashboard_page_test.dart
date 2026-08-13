import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/today_command_providers.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/features/auth/application/profile_local_date_source.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import 'package:my_life_graph/features/briefings/domain/decision_feedback.dart';
import 'package:my_life_graph/composition/briefing_providers.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_full_week.dart';
import 'package:my_life_graph/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:my_life_graph/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:my_life_graph/composition/dashboard_providers.dart';
import 'package:my_life_graph/composition/deadline_plan_providers.dart';
import 'package:my_life_graph/features/optimization/domain/entities/recommendation.dart';
import 'package:my_life_graph/features/optimization/domain/entities/recommendation_feed.dart';
import 'package:my_life_graph/composition/optimization_providers.dart';
import 'package:my_life_graph/features/quick_action/domain/habit_v1.dart';
import 'package:my_life_graph/features/tasks/domain/executable_task.dart';

import 'support/dashboard_full_week_fixture.dart';

void main() {
  testWidgets('guest Today makes zero Exam Plan Health reads', (tester) async {
    var healthReads = 0;
    await _pumpDashboard(
      tester,
      snapshot: DashboardSnapshot.empty(
        origin: DashboardOrigin.localDemo,
        loadedAt: DateTime(2026, 7, 21, 10),
      ),
      capabilities: const AppSurfaceCapabilities(
        isLocalDemo: true,
        canUseSyncedHabits: false,
        canUseDeadlinePlanner: true,
      ),
      onHealthLoad: () => healthReads += 1,
    );

    expect(healthReads, 0);
    expect(find.byKey(const ValueKey('today-exam-plan-health')), findsNothing);
  });

  testWidgets('Today uses streak, progress, agenda, tasks, and habits order',
      (tester) async {
    await _pumpDashboard(
      tester,
      snapshot: _todaySnapshot(),
      capabilities: const AppSurfaceCapabilities(
        isLocalDemo: false,
        canUseSyncedHabits: true,
        canUseSyncedExecution: true,
        canUseWeeklyReview: true,
      ),
    );

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
    expect(find.text('More'), findsNothing);
    expect(find.text('Review your week'), findsOneWidget);
    expect(find.text('Recommendations'), findsOneWidget);
    expect(find.text('Decision feedback history'), findsOneWidget);
    await _ensureExpansionVisible(
      tester,
      const ValueKey('dashboard-full-week'),
    );
    expect(find.text('Full week'), findsOneWidget);
    expect(find.text('7-day preparation load'), findsNothing);
    expect(find.text('Beat yesterday'), findsOneWidget);

    final streakY = tester.getTopLeft(find.text('Check-in streak')).dy;
    final progressY = tester.getTopLeft(find.text("Today's progress")).dy;
    final agendaY = tester.getTopLeft(find.text('Today at a glance')).dy;
    final tasksY = tester.getTopLeft(find.text("Today's tasks")).dy;
    final habitsY = tester.getTopLeft(find.text("Today's habits")).dy;
    final weeklyReviewY = tester.getTopLeft(find.text('Review your week')).dy;
    final recommendationsY = tester.getTopLeft(find.text('Recommendations')).dy;
    final fullWeekY = tester.getTopLeft(find.text('Full week')).dy;
    expect(streakY, lessThan(progressY));
    expect(progressY, lessThan(agendaY));
    expect(agendaY, lessThan(tasksY));
    expect(tasksY, lessThan(habitsY));
    expect(habitsY, lessThan(weeklyReviewY));
    expect(weeklyReviewY, lessThan(recommendationsY));
    expect(recommendationsY, lessThan(fullWeekY));
  });

  testWidgets(
      'accordion descriptions start hidden and each disclosure opens and closes independently',
      (tester) async {
    await _pumpDashboard(
      tester,
      snapshot: _todaySnapshot(),
      capabilities: const AppSurfaceCapabilities(
        isLocalDemo: false,
        canUseSyncedHabits: true,
        canUseSyncedExecution: true,
        canUseWeeklyReview: true,
      ),
    );

    const disclosures = <String, String>{
      'Today': 'Your account data · updated 10:00',
      'Check-in streak':
          'A day counts when both check-ins are saved. You can enter both at any time today; an unfinished current day does not end the prior streak.',
      'Today\'s progress':
          'Includes both check-ins, today\'s tasks and habits, and confirmed preparation blocks. Skipped habits do not count as completed.',
      'Today at a glance': 'Your timed day in one compact agenda.',
      'Today\'s tasks': 'Due, overdue, in-progress, and completed-today tasks.',
      'Show all tasks': 'Future, undated, completed, and cancelled tasks',
      'Today\'s habits': 'Scheduled habits and still-open weekly targets.',
      'Recommendations': 'Rule-based suggestions from your available signals.',
      'Decision feedback history':
          'Inspect or delete previously saved feedback.',
      'Full week':
          'Your profile-local Monday–Sunday agenda across Setup, Preparation, Calendar, Focus, Planner Tasks, Habits, and Fixed commitments.',
    };

    for (final description in disclosures.values) {
      expect(find.text(description), findsNothing);
    }
    expect(
      find.text(
        'Completed, skipped, missed, carried, and recovery facts stay distinct.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('today-info-control-Weekly review')),
      findsNothing,
    );

    for (final entry in disclosures.entries) {
      await _tapInfo(tester, entry.key);
      expect(find.text(entry.value), findsOneWidget, reason: entry.key);
      await _tapInfo(tester, entry.key);
      expect(find.text(entry.value), findsNothing, reason: entry.key);
    }

    expect(find.text('Future task'), findsNothing);
    await _tapExpansion(tester, const ValueKey('today-all-tasks'));
    const allTasksDescription =
        'Finite actions with durable estimates and deadlines.';
    expect(find.text(allTasksDescription), findsNothing);
    await _tapInfo(tester, 'Tasks');
    expect(find.text(allTasksDescription), findsOneWidget);
    await _tapInfo(tester, 'Tasks');
    expect(find.text(allTasksDescription), findsNothing);

    await _tapInfo(tester, 'Check-in streak');
    await _tapInfo(tester, 'Today\'s progress');
    expect(find.text(disclosures['Check-in streak']!), findsOneWidget);
    expect(find.text(disclosures['Today\'s progress']!), findsOneWidget);
    await _tapInfo(tester, 'Check-in streak');
    expect(find.text(disclosures['Check-in streak']!), findsNothing);
    expect(find.text(disclosures['Today\'s progress']!), findsOneWidget);
  });

  testWidgets(
      'supporting info clicks neither open accordions nor start lazy reads',
      (tester) async {
    var recommendationLoads = 0;
    var feedbackLoads = 0;
    var fullWeekLoads = 0;
    await _pumpDashboard(
      tester,
      snapshot: _todaySnapshot(),
      capabilities: const AppSurfaceCapabilities(
        isLocalDemo: false,
        canUseSyncedHabits: true,
        canUseSyncedExecution: true,
        canUseWeeklyReview: true,
      ),
      onRecommendationsLoad: () => recommendationLoads += 1,
      onFeedbackLoad: () => feedbackLoads += 1,
      onFullWeekLoad: () => fullWeekLoads += 1,
    );

    for (final topic in const [
      'Recommendations',
      'Decision feedback history',
      'Full week',
    ]) {
      await _tapInfo(tester, topic);
    }

    expect(find.text('Review your week'), findsOneWidget);
    expect(find.text('Example suggestions'), findsNothing);
    expect(find.text('No recent feedback.'), findsNothing);
    expect(recommendationLoads, 0);
    expect(feedbackLoads, 0);
    expect(fullWeekLoads, 0);

    await _tapExpansion(tester, const ValueKey('dashboard-recommendations'));
    await _tapExpansion(
      tester,
      const ValueKey('dashboard-feedback-history'),
    );
    await _tapExpansion(tester, const ValueKey('dashboard-full-week'));

    expect(recommendationLoads, 1);
    expect(feedbackLoads, 1);
    expect(fullWeekLoads, 1);
  });

  testWidgets('Full week lazy failure retries only its own provider generation',
      (tester) async {
    var fullWeekLoads = 0;
    await _pumpDashboard(
      tester,
      snapshot: _todaySnapshot(),
      fullWeekLoader: () async {
        fullWeekLoads += 1;
        if (fullWeekLoads == 1) throw StateError('week offline');
        return dashboardFullWeekFixture(
          localToday: DateTime.utc(2026, 7, 21),
        );
      },
      capabilities: const AppSurfaceCapabilities(
        isLocalDemo: false,
        canUseSyncedHabits: true,
        canUseSyncedExecution: true,
      ),
    );

    expect(fullWeekLoads, 0);
    await _tapExpansion(tester, const ValueKey('dashboard-full-week'));
    expect(fullWeekLoads, 1);
    expect(find.text('Full week unavailable'), findsOneWidget);

    final retry = find.descendant(
      of: find.byKey(const ValueKey('dashboard-full-week')),
      matching: find.widgetWithText(TextButton, 'Retry'),
    );
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(fullWeekLoads, 2);
    expect(find.text('Full week unavailable'), findsNothing);
    expect(
      find.byKey(const ValueKey('dashboard-full-week-day-strip')),
      findsOneWidget,
    );
  });

  testWidgets('Full week Habit action fails closed after profile midnight',
      (tester) async {
    final habitAction = DashboardFullWeekAction(
      kind: DashboardFullWeekActionKind.openHabit,
      targetId: 'habit-1',
      localDate: DateTime.utc(2026, 7, 21),
    );
    await _pumpDashboard(
      tester,
      snapshot: _todaySnapshot(),
      fullWeek: dashboardFullWeekFixture(
        localToday: DateTime.utc(2026, 7, 21),
        items: [
          dashboardFullWeekTimedItem(
            id: 'habit-slot-1',
            category: DashboardFullWeekCategory.habit,
            localDate: DateTime.utc(2026, 7, 21),
            title: 'Evening walk',
            action: habitAction,
          ),
        ],
      ),
      profileDateSource: _FixedProfileDateSource(DateTime.utc(2026, 7, 22)),
    );

    await _tapExpansion(tester, const ValueKey('dashboard-full-week'));
    await tester.ensureVisible(find.text('Evening walk'));
    await tester.tap(find.text('Evening walk'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The day changed. Reload Full week before opening this habit.',
      ),
      findsOneWidget,
    );
    expect(find.text('Habit completion'), findsNothing);
  });

  testWidgets('progress failure is honest while the usable agenda remains',
      (tester) async {
    final snapshot = _todaySnapshot(
      progress: null,
      sourceStates: _sourceStates(
        checkIns: const TodaySourceState(
          status: TodaySourceStatus.unavailable,
          message: 'Check-ins could not be loaded.',
        ),
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
    expect(find.text('Streak unavailable'), findsOneWidget);
    expect(find.text('Check-ins could not be loaded.'), findsOneWidget);
    expect(find.text('Tasks unavailable'), findsOneWidget);
    expect(find.text('Lecture'), findsOneWidget);
    expect(find.text('Imported seminar'), findsOneWidget);
    expect(find.text('Edit Morning check-in'), findsOneWidget);
    expect(find.text('Edit Evening check-in'), findsOneWidget);
    expect(find.text('4/7 completed'), findsNothing);
    expect(
      find.text(
        'Includes both check-ins, today\'s tasks and habits, and confirmed preparation blocks. Skipped habits do not count as completed.',
      ),
      findsNothing,
    );
  });

  testWidgets('supporting sections are independently lazy and stay open',
      (tester) async {
    await _pumpDashboard(
      tester,
      snapshot: _todaySnapshot(),
      latestCheckIn: DashboardCheckIn(
        entryDate: DateTime(2026, 7, 21),
        mood: 7,
        energy: 8,
        sleepHours: 7.5,
        sleepQuality: 6,
        stress: 3,
        hasMorningCapture: true,
        hasEveningCapture: true,
      ),
      fullWeek: dashboardFullWeekFixture(
        localToday: DateTime.utc(2026, 7, 21),
        items: [
          dashboardFullWeekTimedItem(
            id: 'setup-1',
            category: DashboardFullWeekCategory.setup,
            localDate: DateTime.utc(2026, 7, 21),
            title: 'Full-week lecture',
            start: '10:00:00',
            end: '11:00:00',
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
      capabilities: const AppSurfaceCapabilities(
        isLocalDemo: false,
        canUseSyncedHabits: true,
        canUseSyncedExecution: true,
        canUseDeadlinePlanner: true,
        canUseWeeklyReview: true,
      ),
      feedback: [
        DecisionFeedback(
          id: 'feedback-1',
          requestId: 'request-1',
          briefingId: 'briefing-1',
          recommendationId: null,
          actionId: 'action-1',
          actionKind: 'task',
          feedbackType: DecisionFeedbackType.later,
          contextMode: 'balanced',
          estimatedMinutes: 20,
          ruleKey: 'rule-1',
          createdAt: DateTime(2026, 7, 20, 8),
        ),
      ],
    );

    expect(find.text('Rule-based example'), findsNothing);
    expect(find.text('Review your week'), findsOneWidget);
    expect(find.text('Full-week lecture'), findsNothing);
    expect(find.text('No recent feedback.'), findsNothing);
    expect(find.text('Beat yesterday'), findsOneWidget);
    expect(find.textContaining('Sleep duration'), findsOneWidget);
    expect(find.text('7-day preparation load'), findsNothing);

    await _tapExpansion(tester, const ValueKey('dashboard-recommendations'));
    await _tapExpansion(tester, const ValueKey('dashboard-feedback-history'));
    await _tapExpansion(tester, const ValueKey('dashboard-full-week'));

    expect(find.text('Review your week'), findsOneWidget);
    expect(find.text('Recommendations'), findsOneWidget);
    expect(find.text('Rule-based example'), findsOneWidget);
    expect(find.text('Decision feedback history'), findsOneWidget);
    expect(find.text('Full week'), findsOneWidget);
    expect(find.text('Full-week lecture'), findsOneWidget);
  });

  testWidgets('feedback accordion owns its empty state', (tester) async {
    await _pumpDashboard(
      tester,
      snapshot: _todaySnapshot(),
      capabilities: const AppSurfaceCapabilities(
        isLocalDemo: false,
        canUseSyncedHabits: true,
        canUseSyncedExecution: true,
      ),
    );

    await _tapExpansion(
      tester,
      const ValueKey('dashboard-feedback-history'),
    );

    expect(find.text('Decision feedback history'), findsOneWidget);
    expect(find.text('No recent feedback.'), findsOneWidget);
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

    expect(find.text('Task'), findsNWidgets(2));
    expect(find.text('Habit'), findsOneWidget);
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

    await _tapInfo(tester, 'Today\'s tasks');
    await _tapInfo(tester, 'Show all tasks');

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.text("Today's habits"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'durable Today task write locks stale projection and retry only reloads',
      (tester) async {
    final snapshot = _todaySnapshot();
    final taskCommands = _RecordingTaskCommands();
    final refresh = _RecordingProjectionRefresh();
    final repository = _FailOnceDashboardRepository(snapshot);

    await _pumpDashboard(
      tester,
      snapshot: snapshot,
      taskCommands: taskCommands,
      projectionRefresh: refresh,
      dashboardRepository: repository,
    );
    await tester.tap(find.byTooltip('Complete task Due task'));
    await tester.pumpAndSettle();

    expect(find.text('Saved; Today could not reload.'), findsWidgets);
    expect(taskCommands.completeCalls, 1);
    expect(refresh.targetDates, ['2026-07-21']);
    expect(
      find.byTooltip('Complete task Due task'),
      findsNothing,
    );

    await tester.tap(find.text('Reload Today'));
    await tester.pumpAndSettle();

    expect(find.text('Reload Today'), findsNothing);
    expect(taskCommands.completeCalls, 1);
    expect(repository.calls, 2);
  });

  testWidgets('embedded habit write and refresh use the displayed profile date',
      (tester) async {
    final snapshot = _todaySnapshot(
      todayHabits: const [
        TodayHabit(
          id: '80000000-0000-4000-8000-000000000003',
          title: 'Profile-day habit',
          cadence: 'daily',
          cadenceLabel: 'Daily',
          weeklyCompleted: 0,
          weeklyTarget: 1,
          setupManaged: false,
        ),
      ],
    );
    final habitCommands = _RecordingHabitCommands();
    final refresh = _RecordingProjectionRefresh();

    await _pumpDashboard(
      tester,
      snapshot: snapshot,
      habitCommands: habitCommands,
      projectionRefresh: refresh,
      dashboardRepository: _StaticDashboardRepository(snapshot),
    );
    final complete = find.widgetWithText(FilledButton, 'Complete');
    await tester.ensureVisible(complete);
    await tester.pumpAndSettle();
    await tester.tap(complete);
    await tester.pumpAndSettle();

    expect(habitCommands.targetDates.map(habitDateKey), ['2026-07-21']);
    expect(refresh.targetDates, ['2026-07-21']);
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
  await _ensureExpansionVisible(tester, key);
  final title = _expansionTitle(key);
  final control = find.byKey(
    ValueKey('dashboard-expansion-control-$title'),
  );
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> _ensureExpansionVisible(
  WidgetTester tester,
  ValueKey<String> key,
) async {
  final title = _expansionTitle(key);
  final control = find.byKey(
    ValueKey('dashboard-expansion-control-$title'),
  );
  await tester.scrollUntilVisible(
    control,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

String _expansionTitle(ValueKey<String> key) {
  final title = switch (key.value) {
    'dashboard-recommendations' => 'Recommendations',
    'dashboard-feedback-history' => 'Decision feedback history',
    'dashboard-full-week' => 'Full week',
    'today-all-tasks' => 'Show all tasks',
    _ => throw StateError('Unknown expansion key ${key.value}.'),
  };
  return title;
}

Future<void> _tapInfo(WidgetTester tester, String topic) async {
  final control = find.byKey(ValueKey('today-info-control-$topic'));
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  DashboardSnapshot? snapshot,
  Future<DashboardSnapshot>? snapshotFuture,
  DashboardCheckIn? latestCheckIn,
  DashboardFullWeekProjection? fullWeek,
  Future<DashboardFullWeekProjection> Function()? fullWeekLoader,
  Future<RecommendationFeed>? recommendations,
  Size size = const Size(900, 1500),
  TextScaler textScaler = TextScaler.noScaling,
  List<DecisionFeedback> feedback = const [],
  TodayTaskCommandPort? taskCommands,
  TodayHabitCommandPort? habitCommands,
  _RecordingProjectionRefresh? projectionRefresh,
  DashboardRepository? dashboardRepository,
  VoidCallback? onRecommendationsLoad,
  VoidCallback? onFeedbackLoad,
  VoidCallback? onFullWeekLoad,
  VoidCallback? onHealthLoad,
  AppSurfaceCapabilities capabilities = const AppSurfaceCapabilities(
    isLocalDemo: false,
    canUseSyncedHabits: true,
    canUseSyncedExecution: true,
  ),
  ProfileLocalDateSource profileDateSource =
      const SessionProfileLocalDateSource(session: null),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final value = snapshotFuture ?? Future.value(snapshot ?? _todaySnapshot());
  final displayedDate = snapshot?.localDate ?? DateTime(2026, 7, 21);
  final commandRepository = dashboardRepository ??
      _StaticDashboardRepository(snapshot ?? _todaySnapshot());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSurfaceCapabilitiesProvider.overrideWithValue(capabilities),
        profileLocalDateSourceProvider.overrideWithValue(
          profileDateSource,
        ),
        dashboardSnapshotProvider.overrideWith((ref) => value),
        examPlanHealthProvider.overrideWith((ref) async {
          onHealthLoad?.call();
          return null;
        }),
        dashboardLatestCheckInProvider(displayedDate).overrideWith(
          (ref) => Future.value(latestCheckIn),
        ),
        dashboardFullWeekProvider(displayedDate).overrideWith(
          (ref) {
            onFullWeekLoad?.call();
            return fullWeekLoader?.call() ??
                Future.value(
                  fullWeek ?? DashboardFullWeekProjection.empty(displayedDate),
                );
          },
        ),
        recommendationFeedProvider.overrideWith(
          (ref) {
            onRecommendationsLoad?.call();
            return recommendations ??
                Future.value(RecommendationFeed.demo(const []));
          },
        ),
        decisionFeedbackProvider.overrideWith(
          (ref) {
            onFeedbackLoad?.call();
            return Future.value(feedback);
          },
        ),
        todayCommandControllerProvider.overrideWith(
          (ref) => TodayCommandController(
            taskCommands: taskCommands,
            habitCommands: habitCommands,
            dashboardRepository: commandRepository,
            refreshAfterTask: projectionRefresh?.call ?? (_) async {},
            refreshAfterHabit: projectionRefresh?.call ?? (_) async {},
            onTodayReloaded: () {},
          ),
        ),
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

class _FixedProfileDateSource implements ProfileLocalDateSource {
  const _FixedProfileDateSource(this.value);

  final DateTime value;

  @override
  String? get timezoneName => 'Europe/Berlin';

  @override
  DateTime dateAt(DateTime instant) => value;

  @override
  String dateKeyAt(DateTime instant) => _key(value);

  @override
  DateTime today() => value;

  @override
  String todayKey() => _key(value);

  String _key(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

DashboardSnapshot _todaySnapshot({
  TodayProgress? progress = const TodayProgress(completed: 4, total: 7),
  TodaySourceStates? sourceStates,
  List<PlanItem>? todayTasks,
  List<PlanItem>? allTasks,
  List<TodayTimelineItem>? timeline,
  List<TodayHabit>? todayHabits,
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
    todayHabits: todayHabits ??
        const [
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
  TodaySourceState checkIns = const TodaySourceState(
    status: TodaySourceStatus.current,
  ),
  TodaySourceState tasks = const TodaySourceState(
    status: TodaySourceStatus.current,
  ),
}) {
  const current = TodaySourceState(status: TodaySourceStatus.current);
  return TodaySourceStates(
    checkIns: checkIns,
    tasks: tasks,
    habits: current,
    setupCommitments: current,
    preparation: current,
    calendarEvents: current,
    focusSessions: current,
    planner: current,
  );
}

class _RecordingTaskCommands implements TodayTaskCommandPort {
  int completeCalls = 0;

  @override
  Future<TaskUndoToken> completeTask(String taskId) async {
    completeCalls += 1;
    return TaskUndoToken(
      taskId: taskId,
      status: ExecutableTaskStatus.todo,
      deadline: null,
      completedAt: null,
      cancelledAt: null,
      expectedUpdatedAt: DateTime.utc(2026, 7, 21, 10),
    );
  }

  @override
  Future<TaskUndoToken> cancelTask(String taskId) => throw UnimplementedError();

  @override
  Future<ExecutableTask> createTask({
    required String taskId,
    required ExecutableTaskDraft draft,
  }) =>
      throw UnimplementedError();

  @override
  Future<ExecutableTask> editTask({
    required String taskId,
    required ExecutableTaskDraft draft,
  }) =>
      throw UnimplementedError();

  @override
  Future<TaskUndoToken> postponeTask({
    required String taskId,
    required DateTime newDeadline,
  }) =>
      throw UnimplementedError();

  @override
  Future<ExecutableTask> restoreTask(String taskId) =>
      throw UnimplementedError();

  @override
  Future<ExecutableTask> undo(TaskUndoToken token) =>
      throw UnimplementedError();
}

class _RecordingHabitCommands implements TodayHabitCommandPort {
  final List<DateTime> targetDates = [];

  @override
  Future<void> setOutcome({
    required String habitId,
    required HabitOutcome outcome,
    required DateTime targetDate,
  }) async {
    targetDates.add(targetDate);
  }

  @override
  Future<void> undoOutcome({
    required String habitId,
    required DateTime targetDate,
  }) async {}
}

class _RecordingProjectionRefresh {
  final List<String> targetDates = [];

  Future<void> call(DateTime targetDate) async {
    targetDates.add(habitDateKey(targetDate));
  }
}

class _StaticDashboardRepository implements DashboardRepository {
  const _StaticDashboardRepository(this.snapshot);

  final DashboardSnapshot snapshot;

  @override
  Future<DashboardSnapshot> getSnapshot() async => snapshot;
}

class _FailOnceDashboardRepository implements DashboardRepository {
  _FailOnceDashboardRepository(this.snapshot);

  final DashboardSnapshot snapshot;
  int calls = 0;

  @override
  Future<DashboardSnapshot> getSnapshot() async {
    calls += 1;
    if (calls == 1) {
      throw const DashboardUnavailableException(
        'Today reload failed after commit.',
      );
    }
    return snapshot;
  }
}
