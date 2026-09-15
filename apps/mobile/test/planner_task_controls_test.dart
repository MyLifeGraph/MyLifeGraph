import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/planner/domain/planner.dart';
import 'package:my_life_graph/features/planner/presentation/widgets/planner_sections.dart';

void main() {
  testWidgets('mobile Add new exposes all options without scrolling', (tester) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = false;
    final section = PlannerAddNewSection(
      busy: false, calendarPreference: null, availabilityIncomplete: false,
      onTask: () {}, onHabit: () {}, onExam: () {}, onAssignment: () {},
      onCommitment: () => selected = true, onReviewSetup: () {},
      onCalendarPreference: null,
    );
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark,
      home: Scaffold(body: Builder(builder: section.buildCreationButton))));
    await tester.tap(find.text('Add new'));
    await tester.pumpAndSettle();
    for (final key in ['task', 'habit', 'exam', 'assignment', 'commitment']) {
      final option = find.byKey(ValueKey('planner-add-$key'));
      expect(option.hitTestable(), findsOneWidget);
      expect(tester.getBottomRight(option).dy, lessThanOrEqualTo(640));
    }
    await tester.tap(find.text('Fixed commitment'));
    await tester.pumpAndSettle();
    expect(selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unscheduled task keeps plan, completion and confirmed-removal entry points',
    (tester) async {
      final task = PlannerUnscheduledTask(
        id: 'task',
        title: 'Read chapters',
        reason: 'no_deadline',
        expectedUpdatedAt: DateTime.utc(2026),
        description: null,
        priority: 'medium',
        estimatedMinutes: 30,
        deadlineAt: null,
        preferredSessionMinutes: 25,
        useStudyRhythm: false,
      );
      var completed = 0, removed = 0, planned = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: PlannerUnscheduledTasksSection(
              items: [task],
              onOpen: (_) => planned++,
              onComplete: (_) => completed++,
              onRemove: (_) => removed++,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Complete task'));
      expect(completed, 1);
      await tester.longPress(find.text('Read chapters'));
      expect(removed, 1);
      await tester.tap(find.byTooltip('Task actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plan task'));
      await tester.pumpAndSettle();
      expect(planned, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
