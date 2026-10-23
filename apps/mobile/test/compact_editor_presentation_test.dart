import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/planner/domain/planner.dart';
import 'package:my_life_graph/features/planner/presentation/widgets/planner_dialogs.dart';
import 'package:my_life_graph/composition/widgets/speech_settings_sheet.dart';
import 'support/ui_catalog_capture.dart';

Future<void> openEditor(
  WidgetTester tester,
  Widget editor, {
  ThemeData? theme,
  double width = 390,
  double scale = 1,
  void Function(Object?)? result,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? AppTheme.liquidGlass,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                if (editor is SpeechSettingsEntry) {
                  await showSpeechSettings(context);
                } else {
                  final value = await showDialog<Object>(
                    context: context,
                    builder: (_) => editor,
                  );
                  result?.call(value);
                }
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final theme in AppThemeId.values) {
    testWidgets(
      'Task plan switch preserves draft and unscheduled semantics: $theme',
      (tester) async {
        Object? result;
        await openEditor(
          tester,
          const PlannerTaskDialog(initial: null, timezone: 'Europe/Berlin'),
          theme: AppTheme.resolve(theme),
          width: 320,
          scale: 2,
          result: (v) => result = v,
        );
        await tester.enterText(
          find.byKey(const ValueKey('planner-task-title')),
          'Read chapter',
        );
        expect(
          find.byKey(const ValueKey('planner-task-duration')),
          findsNothing,
        );
        await tapVisible(
          tester,
          find.byKey(const ValueKey('planner-task-schedule')),
        );
        expect(
          find.byKey(const ValueKey('planner-task-duration')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const ValueKey('planner-task-duration')),
          '30',
        );
        await tapVisible(
          tester,
          find.byKey(const ValueKey('planner-task-schedule')),
        );
        expect(
          find.byKey(const ValueKey('planner-task-duration')),
          findsNothing,
        );
        await tapVisible(
          tester,
          find.byKey(const ValueKey('planner-task-schedule')),
        );
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('planner-task-duration')),
              )
              .controller!
              .text,
          '30',
        );
        await tapVisible(
          tester,
          find.byKey(const ValueKey('planner-task-schedule')),
        );
        await tapVisible(tester, find.text('Save as unscheduled'));
        final draft = result as PlannerTaskDraft;
        expect(draft.title, 'Read chapter');
        expect(draft.estimatedMinutes, isNull);
        expect(draft.deadlineAt, isNull);
        expect(draft.preferredSessionMinutes, isNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Habit explicit cadence, weekday validation and optional minutes: $theme',
      (tester) async {
        Object? result;
        await openEditor(
          tester,
          const PlannerHabitDialog(initial: null),
          theme: AppTheme.resolve(theme),
          width: 320,
          scale: 2,
          result: (v) => result = v,
        );
        await tester.enterText(
          find.byKey(const ValueKey('planner-habit-title')),
          'Walk',
        );
        expect(
          tester
              .widget<RadioGroup<String>>(
                find.byKey(const ValueKey('planner-habit-cadence')),
              )
              .groupValue,
          isNull,
        );
        await tapVisible(tester, find.text('Save habit'));
        expect(
          find.text('Enter a title and choose a cadence.'),
          findsOneWidget,
        );
        await tapVisible(
          tester,
          find.byKey(const ValueKey('planner-habit-cadence-weekdays')),
        );
        await tapVisible(tester, find.text('Save habit'));
        expect(find.text('Choose at least one weekday.'), findsOneWidget);
        await tapVisible(tester, find.text('Mon'));
        await tapVisible(tester, find.text('Save habit'));
        final draft = result as PlannerHabitDraft;
        expect(draft.scheduledWeekdays, [1]);
        expect(draft.durationMinutes, isNull);
        expect(draft.cadenceKind, 'weekdays');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Habit weekly target and cadence changes retain local values: $theme',
      (tester) async {
        Object? result;
        await openEditor(
          tester,
          const PlannerHabitDialog(initial: null),
          theme: AppTheme.resolve(theme),
          result: (v) => result = v,
        );
        await tester.enterText(
          find.byKey(const ValueKey('planner-habit-title')),
          'Practice',
        );
        await tapVisible(
          tester,
          find.byKey(const ValueKey('planner-habit-cadence-weekly_target')),
        );
        final count = find.byType(DropdownButtonFormField<int>);
        tester.widget<DropdownButtonFormField<int>>(count).onChanged!(5);
        await tester.pump();
        await tapVisible(
          tester,
          find.byKey(const ValueKey('planner-habit-cadence-daily')),
        );
        expect(count, findsNothing);
        await tapVisible(
          tester,
          find.byKey(const ValueKey('planner-habit-cadence-weekly_target')),
        );
        expect(
          tester.widget<DropdownButtonFormField<int>>(count).initialValue,
          5,
        );
        await tapVisible(tester, find.text('Save habit'));
        final draft = result as PlannerHabitDraft;
        expect(draft.weeklyTarget, 5);
        expect(draft.cadenceKind, 'weekly_target');
        expect(draft.scheduledWeekdays, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  if (captureUiCatalog) {
    for (final kind in ['task', 'habit', 'speech']) {
      testWidgets('catalog compact $kind', (tester) async {
        await loadCatalogFonts();
        await openEditor(tester, switch (kind) {
          'task' => const PlannerTaskDialog(
            initial: null,
            timezone: 'Europe/Berlin',
          ),
          'habit' => const PlannerHabitDialog(initial: null),
          _ => const SpeechSettingsEntry(),
        });
        if (kind == 'speech') await tapVisible(tester, find.text('On-device'));
        await captureCatalog(tester, 'compact-$kind');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
