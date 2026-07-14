import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/quick_action/domain/habit_v1.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/habit_completion_page.dart';

void main() {
  testWidgets('completed habit exposes an independent undo button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
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

    final node = tester.getSemantics(undo);
    expect(
      node,
      matchesSemantics(
        label: 'Undo habit Morning walk',
        isButton: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(undo);
    await tester.pump();
    expect(undoCalls, 1);
    semantics.dispose();
  });

  testWidgets('open habit actions wrap at 320 pixels with larger text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final today = DateTime(2026, 7, 13, 12);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.5),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: HabitOutcomeTile(
              habit: HabitV1(
                id: 'habit-responsive',
                title: 'Take a restorative walk',
                description: 'A deliberate recovery habit for this afternoon.',
                cadence: HabitCadence.daily(),
                lifecycle: HabitLifecycle.active,
                createdAt: today.subtract(const Duration(days: 3)),
                updatedAt: today,
                isSetupManaged: false,
                metadata: const {},
                logs: const [],
              ),
              today: today,
              isSaving: false,
              onComplete: () {},
              onSkip: () {},
              onUndo: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey('habit-outcome-actions-habit-responsive'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Skip habit Take a restorative walk'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Complete habit Take a restorative walk'),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('Complete today')).dy,
      greaterThan(tester.getTopLeft(find.text('Skip today')).dy),
    );
    expect(tester.takeException(), isNull);
  });
}
