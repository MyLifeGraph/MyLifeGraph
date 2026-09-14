import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/planner/domain/planner.dart';
import 'package:my_life_graph/features/planner/presentation/widgets/planner_dialogs.dart';
import 'package:my_life_graph/features/planner/presentation/widgets/planner_sections.dart';

import 'support/planner_fixtures.dart';

void main() {
  for (final layout in [(320.0, 2.0), (390.0, 1.0)]) {
    testWidgets('fixed commitment stays usable at ${layout.$1}px / ${layout.$2}x',
        (tester) async {
      tester.view.physicalSize = Size(layout.$1, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const initial = PlannerCommitmentDraft(
        title: 'Seminar', location: 'Room 1', recurrence: 'weekly',
        startsAt: null, endsAt: null, weekday: 1,
        localStartsAt: '09:00:00', localEndsAt: '10:00:00',
      );
      PlannerCommitmentDraft? saved;
      await _pumpDialog<PlannerCommitmentDraft>(
        tester,
        const PlannerCommitmentDialog(initial: initial, timezone: 'Europe/Berlin'),
        (value) => saved = value,
        textScale: layout.$2,
      );
      expect(tester.takeException(), isNull);
      for (final label in ['One time', 'Every week']) {
        final repeat = find.byType(DropdownButtonFormField<String>);
        await tester.ensureVisible(repeat);
        await tester.tap(repeat);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      final weekday = find.byType(DropdownButtonFormField<int>);
      await tester.ensureVisible(weekday);
      await tester.tap(weekday);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tue').last);
      await tester.pumpAndSettle();
      final review = find.byKey(const ValueKey('planner-commitment-review'));
      await tester.ensureVisible(review);
      expect(review.hitTestable(), findsOneWidget);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(saved?.title, initial.title);
      expect(saved?.location, initial.location);
      expect(saved?.recurrence, 'weekly');
      expect(saved?.weekday, 2);
      expect(saved?.localStartsAt, initial.localStartsAt);
      expect(saved?.localEndsAt, initial.localEndsAt);
    });
  }

  testWidgets(
    'agenda keeps profile day and clock together across UTC midnight',
    (tester) async {
      final raw = plannerOverviewEnvelope();
      final item = Map<String, dynamic>.from(raw['days'][0]['items'][0] as Map)
        ..['starts_at'] = '2026-07-20T23:30:00Z'
        ..['ends_at'] = '2026-07-21T00:30:00Z'
        ..['reserved_ends_at'] = '2026-07-21T00:30:00Z';
      await _pumpContent(
        tester,
        PlannerSevenDaySection(
          days: [
            PlannerDay.fromJson({
              'local_date': '2026-07-21',
              'items': [item],
            }),
          ],
          timezone: 'Europe/Berlin',
          onItemTap: (_) {},
        ),
      );
      expect(find.text('Tuesday, July 21'), findsOneWidget);
      expect(find.text('01:30–02:30 · Setup commitment'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('planner-seven-days-list')));
      await tester.pumpAndSettle();
      expect(find.text('Tuesday, Jul 21'), findsOneWidget);
      expect(find.text('01:30–02:30 · Setup commitment'), findsOneWidget);
    },
  );

  testWidgets('preparation next block uses the supplied profile timezone', (
    tester,
  ) async {
    final overview = PlannerOverview.fromJson(plannerOverviewEnvelope());
    await _pumpContent(
      tester,
      PlannerPreparationSection(
        plans: overview.ongoingPreparation,
        timezone: 'America/New_York',
        onOpen: (_) {},
      ),
    );
    expect(find.textContaining('next Jul 21 09:00'), findsOneWidget);
  });

  testWidgets('saved preview retains its own timezone for block clocks', (
    tester,
  ) async {
    final raw = plannerActionPlanEnvelope();
    raw['plan']['pending_revision']['timezone'] = 'Asia/Tokyo';
    final plan = plannerActionPlanFromResponse(raw);
    expect(plan.pendingRevision!.timezone, 'Asia/Tokyo');
    await _pumpContent(tester, PlannerPlanPreviewDialog(plan: plan));
    expect(find.textContaining('Jul 21, 2026 17:00'), findsOneWidget);
    expect(find.textContaining('Jul 22, 2026 17:00'), findsOneWidget);
  });

  testWidgets('Task editing displays profile time and preserves the instant', (
    tester,
  ) async {
    final initial = _taskDraft();
    PlannerTaskDraft? saved;
    await _pumpDialog<PlannerTaskDraft>(
      tester,
      PlannerTaskDialog(initial: initial, timezone: 'Asia/Tokyo'),
      (value) => saved = value,
    );
    expect(find.textContaining('08:00'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('planner-task-preview')),
    );
    await tester.tap(find.byKey(const ValueKey('planner-task-preview')));
    await tester.pumpAndSettle();
    expect(saved!.deadlineAt!.toUtc(), initial.deadlineAt);
  });

  testWidgets('Task picker converts selected profile wall time to UTC', (
    tester,
  ) async {
    final initial = _taskDraft();
    PlannerTaskDraft? saved;
    await _pumpDialog<PlannerTaskDraft>(
      tester,
      PlannerTaskDialog(initial: initial, timezone: 'Asia/Tokyo'),
      (value) => saved = value,
    );
    final day = initial.deadlineAt!;
    await _chooseDateTime(tester, 'Exact deadline *', day, 14, 45);
    await tester.tap(find.byKey(const ValueKey('planner-task-preview')));
    await tester.pumpAndSettle();
    expect(
      saved!.deadlineAt!.toUtc(),
      DateTime.utc(day.year, day.month, day.day, 5, 45),
    );
  });

  testWidgets('fixed commitment keeps and edits profile-local timestamps', (
    tester,
  ) async {
    final day = _taskDraft().deadlineAt!;
    final start = DateTime.utc(day.year, day.month, day.day, 8);
    PlannerCommitmentDraft? saved;
    await _pumpDialog<PlannerCommitmentDraft>(
      tester,
      PlannerCommitmentDialog(
        timezone: 'Asia/Tokyo',
        initial: PlannerCommitmentDraft(
          title: 'Seminar',
          location: null,
          recurrence: 'one_off',
          startsAt: start,
          endsAt: start.add(const Duration(hours: 1)),
          weekday: null,
          localStartsAt: null,
          localEndsAt: null,
        ),
      ),
      (value) => saved = value,
    );
    expect(find.textContaining('17:00'), findsOneWidget);
    expect(find.textContaining('18:00'), findsOneWidget);
    await _chooseDateTime(tester, 'Starts *', day, 16, 30);
    await tester.tap(find.byKey(const ValueKey('planner-commitment-review')));
    await tester.pumpAndSettle();
    expect(
      saved!.startsAt!.toUtc(),
      DateTime.utc(day.year, day.month, day.day, 7, 30),
    );
    expect(saved!.endsAt!.toUtc(), start.add(const Duration(hours: 1)));
  });

  for (final day in [DateTime(2027, 3, 28), DateTime(2026, 10, 25)]) {
    for (final task in [true, false]) {
      testWidgets('${task ? 'Task' : 'Commitment'} rejects DST ${day.month}', (
        tester,
      ) async {
        final initial = _taskDraft();
        final dialog = task
            ? PlannerTaskDialog(initial: initial, timezone: 'Europe/Berlin')
            : const PlannerCommitmentDialog(
                initial: null,
                timezone: 'Europe/Berlin',
              );
        await _pumpDialog<Object>(tester, dialog, (_) {});
        final retainedDeadline = task
            ? (tester
                          .widget<ListTile>(
                            find.widgetWithText(ListTile, 'Exact deadline *'),
                          )
                          .subtitle!
                      as Text)
                  .data
            : null;
        if (!task) {
          await tester.tap(find.byType(DropdownButtonFormField<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('One time').last);
          await tester.pumpAndSettle();
        }
        await _chooseDateTime(
          tester,
          task ? 'Exact deadline *' : 'Starts *',
          day,
          2,
          30,
        );
        expect(
          find.text(
            'This time is skipped or repeated by a clock change. '
            'Choose another time.',
          ),
          findsOneWidget,
        );
        if (task) expect(find.text(retainedDeadline!), findsOneWidget);
      });
    }
  }
}

PlannerTaskDraft _taskDraft() {
  final now = DateTime.now().toUtc();
  return PlannerTaskDraft(
    title: 'Coursework',
    description: null,
    priority: 'medium',
    estimatedMinutes: 30,
    deadlineAt: DateTime.utc(now.year, now.month, now.day + 7, 23),
    preferredSessionMinutes: 30,
  );
}

Future<void> _pumpContent(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    ProviderScope(child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    )),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDialog<T>(
  WidgetTester tester,
  Widget dialog,
  ValueChanged<T?> onClosed, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () async {
                onClosed(
                  await showDialog<T>(context: context, builder: (_) => dialog),
                );
              },
              child: const Text('Open'),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _chooseDateTime(
  WidgetTester tester,
  String label,
  DateTime day,
  int hour,
  int minute,
) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  Navigator.of(tester.element(find.byType(DatePickerDialog))).pop(day);
  await tester.pumpAndSettle();
  Navigator.of(
    tester.element(find.byType(TimePickerDialog)),
  ).pop(TimeOfDay(hour: hour, minute: minute));
  await tester.pumpAndSettle();
}
