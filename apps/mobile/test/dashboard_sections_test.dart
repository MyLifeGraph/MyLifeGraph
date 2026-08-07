import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/core/navigation/app_routes.dart';
import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/briefings/domain/decision_feedback.dart';
import 'package:my_life_graph/features/dashboard/application/today_command_controller.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_full_week.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:my_life_graph/features/dashboard/presentation/widgets/dashboard_section_widgets.dart';
import 'package:my_life_graph/features/dashboard/presentation/widgets/dashboard_supporting_sections.dart';
import 'package:my_life_graph/features/dashboard/presentation/widgets/today_action_sections.dart';
import 'package:my_life_graph/features/dashboard/presentation/widgets/today_overview_sections.dart';
import 'package:my_life_graph/features/optimization/domain/entities/recommendation_feed.dart';

void main() {
  test('Dashboard page composes section APIs instead of owning their widgets',
      () {
    final source = File(
      'lib/features/dashboard/presentation/pages/dashboard_page.dart',
    ).readAsStringSync();

    expect(source, contains('TodayOverviewSections('));
    expect(source, contains('TodayTaskSections('));
    expect(source, contains('TodayHabitSection('));
    expect(source, contains('DashboardSupportingSections('));
    expect(source, isNot(contains('DashboardMoreSection(')));
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

  testWidgets(
      'Today information keeps a 20px icon in an exact 24px target with semantics, keyboard, and bounded pointer operation',
      (tester) async {
    final semantics = tester.ensureSemantics();
    const description = 'A compact explanation for this Today section.';
    await _pump(
      tester,
      TodayInfoDisclosure(
        topic: 'Test section',
        description: description,
        headerBuilder: (context, infoButton) => Row(
          children: [
            const Text('Test section'),
            infoButton,
          ],
        ),
      ),
    );

    final target = find.byKey(
      const ValueKey('today-info-control-Test section'),
    );
    final layout = find.byKey(
      const ValueKey('today-info-layout-Test section'),
    );
    final icon = find.descendant(
      of: target,
      matching: find.byIcon(AppIcons.infoOutline),
    );
    expect(find.text(description), findsNothing);
    expect(find.bySemanticsLabel(description), findsNothing);
    expect(tester.getSize(layout), const Size(24, 44));
    expect(tester.getSize(target), const Size.square(24));
    expect(tester.getSize(icon), const Size.square(20));
    expect(tester.getRect(icon), tester.getRect(target).deflate(2));
    expect(
      find.byTooltip('Show information about Test section'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Show information about Test section'),
      ),
      isSemantics(
        label: 'Show information about Test section',
        isButton: true,
        hasTapAction: true,
        hasExpandedState: true,
        isExpanded: false,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text(description), findsOneWidget);
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Hide information about Test section'),
      ),
      isSemantics(
        label: 'Hide information about Test section',
        isButton: true,
        hasTapAction: true,
        hasExpandedState: true,
        isExpanded: true,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text(description), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text(description), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text(description), findsNothing);

    var targetRect = tester.getRect(target);
    await tester.tapAt(Offset(targetRect.left + 1, targetRect.center.dy));
    await tester.pumpAndSettle();
    expect(find.text(description), findsOneWidget);

    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(find.text(description), findsNothing);

    targetRect = tester.getRect(target);
    await tester.tapAt(Offset(targetRect.center.dx, targetRect.top - 1));
    await tester.pumpAndSettle();
    expect(find.text(description), findsNothing);
    semantics.dispose();
  });

  testWidgets('Today information uses zero-duration state motion when reduced',
      (tester) async {
    const description = 'Reduced-motion information.';
    await _pump(
      tester,
      TodayInfoDisclosure(
        topic: 'Reduced motion',
        description: description,
        headerBuilder: (context, infoButton) => Row(
          children: [const Text('Reduced motion'), infoButton],
        ),
      ),
      disableAnimations: true,
    );

    final switcher = tester.widget<AnimatedSwitcher>(
      find.descendant(
        of: find.byType(TodayInfoDisclosure),
        matching: find.byType(AnimatedSwitcher),
      ),
    );
    expect(switcher.duration, Duration.zero);
    await tester.tap(
      find.byKey(const ValueKey('today-info-control-Reduced motion')),
    );
    await tester.pump();
    expect(find.text(description), findsOneWidget);
  });

  for (final theme in <String, ThemeData>{
    'Dark': AppTheme.dark,
    'Light': AppTheme.light,
    'Space': AppTheme.space,
  }.entries) {
    testWidgets(
        '${theme.key} Today title, info, and action wrap at 320px and 200% text',
        (tester) async {
      await _pump(
        tester,
        const DashboardSectionTitle(
          title: 'A deliberately long Today section title',
          subtitle: 'Responsive explanatory copy stays readable.',
          trailing: FilledButton(
            onPressed: null,
            child: Text('Planner action'),
          ),
        ),
        size: const Size(320, 600),
        textScaler: const TextScaler.linear(2),
        theme: theme.value,
      );

      await tester.tap(
        find.byKey(
          const ValueKey(
            'today-info-control-A deliberately long Today section title',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Responsive explanatory copy stays readable.'),
        findsOneWidget,
      );
      expect(find.text('Planner action'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'long accordion title, information control, and chevron fit at 320px and 200% text',
      (tester) async {
    var accordionToggles = 0;
    await _pump(
      tester,
      DashboardInlineExpansionCard(
        title: 'Decision feedback history',
        subtitle: 'Inspect or delete previously saved feedback.',
        expanded: false,
        onToggle: () => accordionToggles += 1,
        child: const Text('Lazy content'),
      ),
      size: const Size(320, 600),
      textScaler: const TextScaler.linear(2),
      theme: AppTheme.space,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('today-info-control-Decision feedback history'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Inspect or delete previously saved feedback.'),
      findsOneWidget,
    );
    expect(find.text('Lazy content'), findsNothing);
    expect(accordionToggles, 0);

    final infoRect = tester.getRect(
      find.byKey(
        const ValueKey('today-info-control-Decision feedback history'),
      ),
    );
    await tester.tapAt(Offset(infoRect.center.dx, infoRect.top - 1));
    await tester.pumpAndSettle();
    expect(accordionToggles, 1);
    expect(find.text('Lazy content'), findsNothing);
    expect(tester.takeException(), isNull);
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
        latestCheckIn: AsyncData(
          DashboardCheckIn(
            entryDate: DateTime(2026, 7, 30),
            mood: 7,
            energy: 6,
            sleepHours: 7.5,
            sleepQuality: 8,
            stress: 3,
          ),
        ),
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
    expect(find.text('Beat yesterday'), findsOneWidget);
    expect(find.textContaining('Mood'), findsOneWidget);
    expect(find.textContaining('Energy'), findsOneWidget);
    expect(find.textContaining('Sleep duration'), findsOneWidget);
    expect(find.textContaining('Sleep quality'), findsOneWidget);
    expect(find.textContaining('Stress'), findsOneWidget);

    await tester.tap(find.text('Edit Morning check-in'));
    await tester.tap(find.text('Open plan'));

    expect(morningCalls, 1);
    expect(openedPlan, 'plan-1');
  });

  testWidgets(
      'streak and progress failures plus latest-check-in loading stay visible without opening information',
      (tester) async {
    const current = TodaySourceState(status: TodaySourceStatus.current);
    await _pump(
      tester,
      TodayOverviewSections(
        snapshot: _snapshot(
          progress: null,
          sourceStates: const TodaySourceStates(
            checkIns: TodaySourceState(
              status: TodaySourceStatus.unavailable,
              message: 'Saved check-ins are temporarily unavailable.',
            ),
            tasks: current,
            habits: current,
            setupCommitments: current,
            preparation: current,
            calendarEvents: current,
            focusSessions: current,
            planner: current,
          ),
        ),
        canExecute: true,
        latestCheckIn: const AsyncLoading<DashboardCheckIn?>(),
        actions: TodayOverviewActions(
          onAddEvening: () {},
          onAddMorning: () {},
          onOpenPreparationPlan: (_) {},
          onStartPreparationFocus: (_) {},
        ),
      ),
      settle: false,
    );

    expect(find.text('Streak unavailable'), findsOneWidget);
    expect(
      find.text('Saved check-ins are temporarily unavailable.'),
      findsOneWidget,
    );
    expect(find.text('Loading your latest saved check-in…'), findsOneWidget);
    expect(find.text('Progress unavailable'), findsOneWidget);
    expect(find.text('Edit Morning check-in'), findsOneWidget);
    expect(find.text('Add Evening check-in'), findsOneWidget);
    expect(
      find.text(
        'A day counts when both check-ins are saved. You can enter both at any time today; an unfinished current day does not end the prior streak.',
      ),
      findsNothing,
    );
  });

  testWidgets('whole missed preparation row opens its exact scheduled block',
      (tester) async {
    String? startedBlock;
    await _pump(
      tester,
      TodayOverviewSections(
        snapshot: _snapshot(
          timeline: [
            TodayTimelineItem(
              kind: TodayTimelineKind.preparation,
              id: 'block-1',
              title: 'Missed mathematics block',
              allDay: false,
              startsAt: DateTime(2026, 7, 30, 9),
              endsAt: DateTime(2026, 7, 30, 10),
              planId: 'plan-1',
              blockId: 'block-1',
              state: 'missed',
              plannedMinutes: 60,
            ),
          ],
        ),
        canExecute: true,
        actions: TodayOverviewActions(
          onAddEvening: () {},
          onAddMorning: () {},
          onOpenPreparationPlan: (_) {},
          onStartPreparationFocus: (value) => startedBlock = value,
        ),
      ),
    );

    await tester.tap(find.text('Missed mathematics block'));
    expect(startedBlock, 'block-1');
    expect(find.text('Start focus'), findsOneWidget);
  });

  testWidgets('whole Focus and Task rows navigate with exact identities',
      (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
              child: TodayOverviewSections(
                snapshot: _snapshot(
                  timeline: [
                    TodayTimelineItem(
                      kind: TodayTimelineKind.focusSession,
                      id: 'focus-session-42',
                      title: 'Running focus',
                      allDay: false,
                      startsAt: DateTime(2026, 7, 31, 9),
                      endsAt: DateTime(2026, 7, 31, 10),
                      state: 'active',
                    ),
                    TodayTimelineItem(
                      kind: TodayTimelineKind.taskBlock,
                      id: 'planner-block-7',
                      title: 'Planned reading',
                      allDay: false,
                      startsAt: DateTime(2026, 7, 31, 11),
                      endsAt: DateTime(2026, 7, 31, 11, 30),
                      taskId: 'task-7',
                      plannedMinutes: 30,
                    ),
                  ],
                ),
                canExecute: true,
                actions: TodayOverviewActions(
                  onAddEvening: () {},
                  onAddMorning: () {},
                  onOpenPreparationPlan: (_) {},
                  onStartPreparationFocus: (_) {},
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.deepWork,
          builder: (context, state) => Scaffold(
            body: Text(state.uri.queryParameters.toString()),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Running focus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Running focus'));
    await tester.pumpAndSettle();
    expect(find.textContaining('session_id: focus-session-42'), findsOneWidget);

    router.go('/');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Planned reading'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Planned reading'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('source_kind: planner_task_block'),
      findsOneWidget,
    );
    expect(
      find.textContaining('source_block_id: planner-block-7'),
      findsOneWidget,
    );
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

  testWidgets(
      'weekly review is direct and capability-gated while accordions stay independent',
      (tester) async {
    var weeklyReviewCalls = 0;
    final state = DashboardSupportingState(
      accountData: true,
      canUseWeeklyReview: true,
      recommendations: AsyncData(RecommendationFeed.demo(const [])),
      feedback: null,
      fullWeek: null,
      isRefreshingRecommendations: false,
      recommendationRefreshError: null,
    );
    final actions = DashboardSupportingActions(
      onToggleRecommendations: () {},
      onToggleFeedback: () {},
      onToggleFullWeek: () {},
      onOpenWeeklyReview: () => weeklyReviewCalls += 1,
      onRetryRecommendations: () {},
      onRefreshRecommendations: () {},
      onRetryFeedback: () {},
      onDeleteFeedback: (_) async {},
      onRetryFullWeek: () {},
      onOpenPreparationPlan: (_) {},
    );

    await _pump(
      tester,
      DashboardSupportingSections(
        recommendationsExpanded: false,
        feedbackExpanded: false,
        fullWeekExpanded: false,
        state: state,
        actions: actions,
      ),
    );

    expect(find.text('Review your week'), findsOneWidget);
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
    await tester.tap(find.text('Review your week'));
    expect(weeklyReviewCalls, 1);

    await _pump(
      tester,
      DashboardSupportingSections(
        recommendationsExpanded: true,
        feedbackExpanded: false,
        fullWeekExpanded: false,
        state: state,
        actions: actions,
      ),
    );
    expect(find.text('Example suggestions'), findsOneWidget);
    expect(find.text('Review your week'), findsOneWidget);

    await _pump(
      tester,
      DashboardSupportingSections(
        recommendationsExpanded: false,
        feedbackExpanded: false,
        fullWeekExpanded: false,
        state: DashboardSupportingState(
          accountData: true,
          canUseWeeklyReview: false,
          recommendations: null,
          feedback: null,
          fullWeek: null,
          isRefreshingRecommendations: false,
          recommendationRefreshError: null,
        ),
        actions: actions,
      ),
    );
    expect(
      find.byKey(const ValueKey('dashboard-weekly-review')),
      findsNothing,
    );
    expect(find.text('Review your week'), findsNothing);
  });

  testWidgets('feedback accordion renders its list and delete state',
      (tester) async {
    String? deletedId;
    final deletion = Completer<void>();
    final item = DecisionFeedback(
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
      createdAt: DateTime(2026, 7, 30, 8),
    );
    await _pump(
      tester,
      DashboardSupportingSections(
        recommendationsExpanded: false,
        feedbackExpanded: true,
        fullWeekExpanded: false,
        state: DashboardSupportingState(
          accountData: true,
          canUseWeeklyReview: false,
          recommendations: null,
          feedback: AsyncData([item]),
          fullWeek: null,
          isRefreshingRecommendations: false,
          recommendationRefreshError: null,
        ),
        actions: DashboardSupportingActions(
          onToggleRecommendations: () {},
          onToggleFeedback: () {},
          onToggleFullWeek: () {},
          onOpenWeeklyReview: () {},
          onRetryRecommendations: () {},
          onRefreshRecommendations: () {},
          onRetryFeedback: () {},
          onDeleteFeedback: (value) {
            deletedId = value.id;
            return deletion.future;
          },
          onRetryFullWeek: () {},
          onOpenPreparationPlan: (_) {},
        ),
      ),
    );

    expect(find.text('Later'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete feedback'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    deletion.complete();
    await tester.pumpAndSettle();
    expect(deletedId, 'feedback-1');
  });

  testWidgets('feedback accordion isolates loading and retryable error states',
      (tester) async {
    var retries = 0;

    Widget surface(AsyncValue<List<DecisionFeedback>> feedback) {
      return DashboardSupportingSections(
        recommendationsExpanded: false,
        feedbackExpanded: true,
        fullWeekExpanded: false,
        state: DashboardSupportingState(
          accountData: true,
          canUseWeeklyReview: false,
          recommendations: null,
          feedback: feedback,
          fullWeek: null,
          isRefreshingRecommendations: false,
          recommendationRefreshError: null,
        ),
        actions: DashboardSupportingActions(
          onToggleRecommendations: () {},
          onToggleFeedback: () {},
          onToggleFullWeek: () {},
          onOpenWeeklyReview: () {},
          onRetryRecommendations: () {},
          onRefreshRecommendations: () {},
          onRetryFeedback: () => retries += 1,
          onDeleteFeedback: (_) async {},
          onRetryFullWeek: () {},
          onOpenPreparationPlan: (_) {},
        ),
      );
    }

    await _pump(
      tester,
      surface(const AsyncLoading<List<DecisionFeedback>>()),
      settle: false,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pump(
      tester,
      surface(
        AsyncError<List<DecisionFeedback>>(
          StateError('offline'),
          StackTrace.current,
        ),
      ),
    );
    expect(find.text('Feedback history unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('Full week Preparation row opens its owning plan',
      (tester) async {
    String? openedPlanId;
    final fullWeek = const DashboardFullWeekProjector().project(
      displayedLocalDate: DateTime(2026, 8, 5),
      preparationBlocks: const [
        DashboardPreparationBlockFact(
          id: 'block-1',
          planId: 'plan-1',
          planTitle: 'Algorithms exam',
          localDate: '2026-08-05',
          localStartTime: '09:00',
          localEndTime: '10:00',
          sortMinutes: 540,
          state: 'completed',
          recoveryMinutes: 0,
          reservedLocalEndTime: '10:00',
        ),
      ],
    );
    await _pump(
      tester,
      DashboardSupportingSections(
        recommendationsExpanded: false,
        feedbackExpanded: false,
        fullWeekExpanded: true,
        state: DashboardSupportingState(
          accountData: true,
          canUseWeeklyReview: false,
          recommendations: null,
          feedback: null,
          fullWeek: AsyncData(fullWeek),
          isRefreshingRecommendations: false,
          recommendationRefreshError: null,
        ),
        actions: DashboardSupportingActions(
          onToggleRecommendations: () {},
          onToggleFeedback: () {},
          onToggleFullWeek: () {},
          onOpenWeeklyReview: () {},
          onRetryRecommendations: () {},
          onRefreshRecommendations: () {},
          onRetryFeedback: () {},
          onDeleteFeedback: (_) async {},
          onRetryFullWeek: () {},
          onOpenPreparationPlan: (value) => openedPlanId = value,
        ),
      ),
    );

    await tester.ensureVisible(find.text('Algorithms exam'));
    await tester.tap(find.text('Algorithms exam'));

    expect(openedPlanId, 'plan-1');
  });

  testWidgets('Full week partial-source empty days do not claim both sources',
      (tester) async {
    final fullWeek = const DashboardFullWeekProjector().project(
      displayedLocalDate: DateTime(2026, 8, 5),
      commitmentLoadError:
          'Setup commitments could not be loaded. Available Preparation items are still shown.',
    );
    await _pump(
      tester,
      DashboardSupportingSections(
        recommendationsExpanded: false,
        feedbackExpanded: false,
        fullWeekExpanded: true,
        state: DashboardSupportingState(
          accountData: true,
          canUseWeeklyReview: false,
          recommendations: null,
          feedback: null,
          fullWeek: AsyncData(fullWeek),
          isRefreshingRecommendations: false,
          recommendationRefreshError: null,
        ),
        actions: DashboardSupportingActions(
          onToggleRecommendations: () {},
          onToggleFeedback: () {},
          onToggleFullWeek: () {},
          onOpenWeeklyReview: () {},
          onRetryRecommendations: () {},
          onRefreshRecommendations: () {},
          onRetryFeedback: () {},
          onDeleteFeedback: (_) async {},
          onRetryFullWeek: () {},
          onOpenPreparationPlan: (_) {},
        ),
      ),
    );

    expect(find.text('No items from the available source.'), findsNWidgets(7));
    expect(find.text('No Setup or Preparation items.'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  List<Override> providerOverrides = const [],
  bool settle = true,
  Size size = const Size(900, 1400),
  TextScaler textScaler = TextScaler.noScaling,
  ThemeData? theme,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: providerOverrides,
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: textScaler,
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  }
}

DashboardSnapshot _snapshot({
  List<PlanItem> todayTasks = const [],
  List<PlanItem> allTasks = const [],
  List<TodayHabit> todayHabits = const [],
  List<TodayTimelineItem> timeline = const [],
  TodayProgress? progress = const TodayProgress(completed: 2, total: 4),
  TodaySourceStates? sourceStates,
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
    progress: progress,
    todayTasks: todayTasks,
    todayHabits: todayHabits,
    timeline: timeline,
    sourceStates: sourceStates,
    isTodayOverview: true,
  );
}
