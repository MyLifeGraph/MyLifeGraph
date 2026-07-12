import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/quick_action/domain/habit_v1.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/habit_completion_page.dart';

void main() {
  testWidgets('completed habit exposes an independent undo button', (
    tester,
  ) async {
    final today = DateTime(2026, 7, 11, 12);
    var undoCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HabitOutcomeTile(
            habit: HabitV1(
              id: 'habit-1',
              title: 'Morning walk',
              cadence: HabitCadence.daily(),
              lifecycle: HabitLifecycle.active,
              createdAt: today.subtract(const Duration(days: 1)),
              updatedAt: today,
              isSetupManaged: false,
              metadata: const {},
              logs: [
                HabitLogEntry(
                  entryDate: today,
                  outcome: HabitOutcome.completed,
                ),
              ],
            ),
            today: today,
            isSaving: false,
            onComplete: () {},
            onSkip: () {},
            onUndo: () => undoCalls += 1,
          ),
        ),
      ),
    );

    final undo = find.bySemanticsLabel('Undo habit Morning walk');
    expect(undo, findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('completed opportunities')),
      findsOneWidget,
    );

    await tester.tap(undo);
    expect(undoCalls, 1);
  });
}
