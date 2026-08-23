import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/core/navigation/app_routes.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/theme/app_visual_tokens.dart';
import 'package:my_life_graph/features/dashboard/application/today_command_controller.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_full_week.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:my_life_graph/features/dashboard/presentation/widgets/dashboard_section_widgets.dart';
import 'package:my_life_graph/features/dashboard/presentation/widgets/dashboard_supporting_sections.dart';
import 'package:my_life_graph/features/dashboard/presentation/widgets/today_action_sections.dart';
import 'package:my_life_graph/features/dashboard/presentation/widgets/today_overview_sections.dart';

import 'support/dashboard_full_week_fixture.dart';

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
      'Today information keeps a 24px frame in an exact 44px target with semantics, keyboard, and bounded pointer operation',
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
    final frame = find.descendant(
      of: target,
      matching: find.byType(AnimatedContainer),
    );
    final iconFrame = find.byKey(
      const ValueKey('today-info-icon-Test section'),
    );
    expect(find.text(description), findsNothing);
    expect(find.bySemanticsLabel(description), findsNothing);
    expect(tester.getSize(target), const Size.square(44));
    expect(tester.getSize(frame), const Size.square(24));
    expect(tester.getSize(iconFrame), const Size.square(20));
    expect(tester.getRect(frame).center, tester.getRect(target).center);
    expect(tester.getRect(iconFrame).center, tester.getRect(frame).center);
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
        title: 'Long supporting section details',
        subtitle: 'Independent supporting information remains readable.',
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
        const ValueKey('today-info-control-Long supporting section details'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Independent supporting information remains readable.'),
      findsOneWidget,
    );
    expect(find.text('Lazy content'), findsNothing);
    expect(accordionToggles, 0);

    await tester.tap(
      find.byKey(
        const ValueKey(
          'dashboard-expansion-control-Long supporting section details',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(accordionToggles, 1);
    expect(find.text('Lazy content'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accordion keyboard action shows a two-pixel focus ring',
      (tester) async {
    var accordionToggles = 0;
    await _pump(
      tester,
      DashboardInlineExpansionCard(
        title: 'Keyboard review',
        subtitle: 'Independent information.',
        expanded: false,
        onToggle: () => accordionToggles += 1,
        child: const Text('Lazy content'),
      ),
      theme: AppTheme.light,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final ring = tester.widget<DecoratedBox>(
      find.byKey(
        const ValueKey('dashboard-expansion-focus-ring-Keyboard review'),
      ),
    );
    final border = (ring.decoration as BoxDecoration).border! as Border;
    expect(border.top.width, 2);
    expect(border.top.color, AppVisualTokens.light.focus);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(accordionToggles, 1);
    expect(find.text('Independent information.'), findsNothing);
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
      canUseWeeklyReview: true,
      fullWeek: null,
    );
    final actions = DashboardSupportingActions(
      onToggleFullWeek: () {},
      onOpenWeeklyReview: () => weeklyReviewCalls += 1,
      onRetryFullWeek: () {},
      onFullWeekAction: (_) {},
    );

    await _pump(
      tester,
      DashboardSupportingSections(
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
        fullWeekExpanded: false,
        state: DashboardSupportingState(
          canUseWeeklyReview: false,
          fullWeek: null,
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

  testWidgets('Full week Preparation row exposes its typed action',
      (tester) async {
    DashboardFullWeekAction? selectedAction;
    final fullWeek = dashboardFullWeekFixture(
      items: [
        dashboardFullWeekTimedItem(
          id: 'block-1',
          category: DashboardFullWeekCategory.preparation,
          localDate: DateTime.utc(2026, 8, 5),
          title: 'Algorithms exam',
          status: DashboardFullWeekItemStatus.completed,
          action: const DashboardFullWeekAction(
            kind: DashboardFullWeekActionKind.openPreparationPlan,
            targetId: 'plan-1',
          ),
        ),
      ],
    );
    await _pump(
      tester,
      DashboardSupportingSections(
        fullWeekExpanded: true,
        state: DashboardSupportingState(
          canUseWeeklyReview: false,
          fullWeek: AsyncData(fullWeek),
        ),
        actions: DashboardSupportingActions(
          onToggleFullWeek: () {},
          onOpenWeeklyReview: () {},
          onRetryFullWeek: () {},
          onFullWeekAction: (value) => selectedAction = value,
        ),
      ),
    );

    await tester.ensureVisible(find.text('Algorithms exam'));
    await tester.tap(find.text('Algorithms exam'));

    expect(selectedAction?.targetId, 'plan-1');
    expect(
      selectedAction?.kind,
      DashboardFullWeekActionKind.openPreparationPlan,
    );
  });

  testWidgets('Full week reports each unavailable source without hiding days',
      (tester) async {
    final fullWeek = dashboardFullWeekFixture(
      sourceStates: DashboardFullWeekSourceStates(
        setup: DashboardFullWeekSourceState(
          name: 'setup',
          label: 'Setup',
          status: DashboardFullWeekSourceStatus.unavailable,
          message: 'Setup commitments are unavailable.',
        ),
        preparation: dashboardFullWeekCurrentSources.preparation,
        calendar: dashboardFullWeekCurrentSources.calendar,
        focus: dashboardFullWeekCurrentSources.focus,
        tasks: dashboardFullWeekCurrentSources.tasks,
        habits: dashboardFullWeekCurrentSources.habits,
        fixedCommitments: dashboardFullWeekCurrentSources.fixedCommitments,
      ),
    );
    await _pump(
      tester,
      DashboardSupportingSections(
        fullWeekExpanded: true,
        state: DashboardSupportingState(
          canUseWeeklyReview: false,
          fullWeek: AsyncData(fullWeek),
        ),
        actions: DashboardSupportingActions(
          onToggleFullWeek: () {},
          onOpenWeeklyReview: () {},
          onRetryFullWeek: () {},
          onFullWeekAction: (_) {},
        ),
      ),
    );

    expect(
      find.text('Setup: Setup commitments are unavailable.'),
      findsOneWidget,
    );
    expect(find.text('No items from available sources.'), findsWidgets);
    expect(find.text('Nothing scheduled.'), findsNothing);
  });

  testWidgets(
      'Full week shows 2.5 normal mobile days and exactly 2 narrow days',
      (tester) async {
    final projection = dashboardFullWeekFixture(
      localToday: DateTime.utc(2026, 8, 3),
    );

    await _pump(
      tester,
      DashboardFullWeekAgenda(projection: projection, onAction: (_) {}),
      size: const Size(432, 800),
    );
    expect(find.text('Nothing scheduled.'), findsWidgets);
    final monday = find.byKey(
      const ValueKey('dashboard-full-week-day-2026-08-03'),
    );
    final tuesday = find.byKey(
      const ValueKey('dashboard-full-week-day-2026-08-04'),
    );
    final wednesday = find.byKey(
      const ValueKey('dashboard-full-week-day-2026-08-05'),
    );
    expect(tester.getTopLeft(tuesday).dx - tester.getTopLeft(monday).dx, 160);
    expect(tester.getTopLeft(wednesday).dx, lessThan(416));
    expect(tester.getTopRight(wednesday).dx, greaterThan(416));

    await _pump(
      tester,
      DashboardFullWeekAgenda(projection: projection, onAction: (_) {}),
      size: const Size(352, 800),
    );
    expect(tester.getTopLeft(tuesday).dx - tester.getTopLeft(monday).dx, 160);
    expect(tester.getTopLeft(wednesday).dx, greaterThanOrEqualTo(336));

    await _pump(
      tester,
      DashboardFullWeekAgenda(projection: projection, onAction: (_) {}),
      size: const Size(432, 800),
      textScaler: const TextScaler.linear(2),
    );
    expect(tester.getTopLeft(tuesday).dx - tester.getTopLeft(monday).dx, 200);
    expect(tester.getTopLeft(wednesday).dx, greaterThanOrEqualTo(416));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Full week switches to seven columns only at the 208px threshold',
      (tester) async {
    final projection = dashboardFullWeekFixture(
      localToday: DateTime.utc(2026, 8, 3),
    );
    const threshold =
        dashboardFullWeekMinimumWebCardWidth * 7 + dashboardFullWeekDayGap * 6;

    await _pump(
      tester,
      DashboardFullWeekAgenda(projection: projection, onAction: (_) {}),
      size: const Size(threshold + 32, 800),
    );
    expect(
      find.byKey(const ValueKey('dashboard-full-week-day-strip')),
      findsNothing,
    );
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey('dashboard-full-week-day-2026-08-03'),
            ),
          )
          .width,
      dashboardFullWeekMinimumWebCardWidth,
    );

    await _pump(
      tester,
      DashboardFullWeekAgenda(projection: projection, onAction: (_) {}),
      size: const Size(threshold + 31, 800),
    );
    expect(
      find.byKey(const ValueKey('dashboard-full-week-day-strip')),
      findsOneWidget,
    );
  });

  testWidgets('Full week clamps weekends, snaps one day, and keeps hard bounds',
      (tester) async {
    final sundayProjection = dashboardFullWeekFixture(
      localToday: DateTime.utc(2026, 8, 9),
    );
    await _pump(
      tester,
      DashboardFullWeekAgenda(
        projection: sundayProjection,
        onAction: (_) {},
      ),
      size: const Size(432, 800),
    );
    final saturday = find.byKey(
      const ValueKey('dashboard-full-week-day-2026-08-08'),
    );
    final sunday = find.byKey(
      const ValueKey('dashboard-full-week-day-2026-08-09'),
    );
    expect(tester.getTopLeft(saturday).dx, greaterThanOrEqualTo(16));
    expect(tester.getTopRight(sunday).dx, lessThanOrEqualTo(416));

    final mondayProjection = dashboardFullWeekFixture(
      localToday: DateTime.utc(2026, 8, 3),
    );
    await _pump(
      tester,
      DashboardFullWeekAgenda(
        key: const ValueKey('monday-agenda'),
        projection: mondayProjection,
        onAction: (_) {},
      ),
      size: const Size(432, 800),
    );
    final strip = find.byKey(
      const ValueKey('dashboard-full-week-day-strip'),
    );
    final monday = find.byKey(
      const ValueKey('dashboard-full-week-day-2026-08-03'),
    );
    final tuesday = find.byKey(
      const ValueKey('dashboard-full-week-day-2026-08-04'),
    );
    await tester.timedDrag(
      strip,
      const Offset(-110, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(tuesday).dx, 16);

    await tester.drag(strip, const Offset(-2000, 0));
    await tester.pumpAndSettle();
    final terminalSaturday = tester.getTopLeft(saturday).dx;
    final terminalSunday = tester.getTopLeft(sunday).dx;
    expect(terminalSaturday, greaterThanOrEqualTo(16));
    expect(tester.getTopRight(sunday).dx, lessThanOrEqualTo(416));
    await tester.drag(strip, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(saturday).dx, terminalSaturday);
    expect(tester.getTopLeft(sunday).dx, terminalSunday);

    await tester.drag(strip, const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(monday).dx, 16);
  });

  testWidgets('dense Full week stays uncut at 320px and 200 percent text',
      (tester) async {
    final items = List.generate(
      7,
      (index) => dashboardFullWeekTimedItem(
        id: 'dense-$index',
        category: DashboardFullWeekCategory.values[index],
        localDate: DateTime.utc(2026, 8, 5),
        title: 'Dense agenda item $index with full readable text',
      ),
    );
    await _pump(
      tester,
      DashboardFullWeekAgenda(
        projection: dashboardFullWeekFixture(items: items),
        onAction: (_) {},
      ),
      size: const Size(320, 900),
      textScaler: const TextScaler.linear(2),
    );

    for (var index = 0; index < items.length; index++) {
      expect(
        find.text('Dense agenda item $index with full readable text'),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Full week delegates every server-approved action identity',
      (tester) async {
    final actions = [
      const DashboardFullWeekAction(
        kind: DashboardFullWeekActionKind.startPreparationFocus,
        targetId: 'preparation-block',
        sourceKind: 'deadline_plan_block',
      ),
      const DashboardFullWeekAction(
        kind: DashboardFullWeekActionKind.startTaskFocus,
        targetId: 'task-block',
        sourceKind: 'planner_task_block',
      ),
      const DashboardFullWeekAction(
        kind: DashboardFullWeekActionKind.resumeFocus,
        targetId: 'active-focus',
      ),
      const DashboardFullWeekAction(
        kind: DashboardFullWeekActionKind.reflectFocus,
        targetId: 'terminal-focus',
      ),
      const DashboardFullWeekAction(
        kind: DashboardFullWeekActionKind.openPreparationPlan,
        targetId: 'completed-plan',
      ),
      DashboardFullWeekAction(
        kind: DashboardFullWeekActionKind.openHabit,
        targetId: 'habit-today',
        localDate: DateTime.utc(2026, 8, 5),
      ),
    ];
    const categories = [
      DashboardFullWeekCategory.preparation,
      DashboardFullWeekCategory.task,
      DashboardFullWeekCategory.focus,
      DashboardFullWeekCategory.focus,
      DashboardFullWeekCategory.preparation,
      DashboardFullWeekCategory.habit,
    ];
    final items = List.generate(
      actions.length,
      (index) => dashboardFullWeekTimedItem(
        id: actions[index].targetId,
        category: categories[index],
        localDate: DateTime.utc(2026, 8, 5),
        title: 'Agenda action $index',
        action: actions[index],
      ),
    );
    final selected = <DashboardFullWeekAction>[];
    await _pump(
      tester,
      DashboardFullWeekAgenda(
        projection: dashboardFullWeekFixture(items: items),
        onAction: selected.add,
      ),
      size: const Size(900, 1400),
    );

    for (var index = 0; index < actions.length; index++) {
      await tester.tap(find.text('Agenda action $index'));
    }
    expect(selected.map((action) => action.targetId), [
      'preparation-block',
      'task-block',
      'active-focus',
      'terminal-focus',
      'completed-plan',
      'habit-today',
    ]);
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
