import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/dashboard/presentation/widgets/dashboard_section_widgets.dart';
import 'package:my_life_graph/features/deadline_plans/domain/exam_plan_health.dart';
import 'package:my_life_graph/features/planner/presentation/widgets/planner_sections.dart';
import 'package:my_life_graph/core/widgets/app_surface.dart';

void main() {
  testWidgets('Today shows only non-green health and stays narrow-accessible',
      (tester) async {
    final opened = <String>[];
    await _pump(
      tester,
      TodayExamPlanHealthSection(
        value: AsyncValue.data(_health()),
        onRetry: () {},
        onOpenPlan: opened.add,
      ),
      size: const Size(320, 1900),
      textScaler: const TextScaler.linear(2),
    );

    expect(find.text('Healthy exam'), findsNothing);
    expect(find.text('Plan soon exam'), findsOneWidget);
    expect(find.text('Shortfall exam'), findsOneWidget);
    expect(find.text('Unknown exam'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey('today-info-control-Exam Plan Health'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('sleep-focused Exam week outlook'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Plan soon exam'));
    expect(opened, ['22222222-2222-4222-8222-222222222222']);
  });

  testWidgets('Today distinguishes transport failure from Unknown',
      (tester) async {
    await _pump(
      tester,
      TodayExamPlanHealthSection(
        value: AsyncValue.error(StateError('offline'), StackTrace.empty),
        onRetry: () {},
        onOpenPlan: (_) {},
      ),
    );

    expect(
      find.textContaining('transport error is not an Unknown capacity result'),
      findsOneWidget,
    );
    expect(find.text('Availability unknown'), findsNothing);
  });

  testWidgets('Today exposes refresh loading and error over prior green data',
      (tester) async {
    final previous = AsyncValue<ExamPlanHealth?>.data(_greenOnlyHealth());
    final loading =
        const AsyncValue<ExamPlanHealth?>.loading().copyWithPrevious(previous);
    await _pump(
      tester,
      TodayExamPlanHealthSection(
        value: loading,
        onRetry: () {},
        onOpenPlan: (_) {},
      ),
      settle: false,
    );
    expect(find.text('Checking current Exam capacity…'), findsOneWidget);

    final failed = AsyncValue<ExamPlanHealth?>.error(
      StateError('offline'),
      StackTrace.empty,
    ).copyWithPrevious(previous);
    await _pump(
      tester,
      TodayExamPlanHealthSection(
        value: failed,
        onRetry: () {},
        onOpenPlan: (_) {},
      ),
    );
    expect(find.textContaining('could not be loaded'), findsOneWidget);
    expect(find.text('Healthy exam'), findsNothing);
  });

  testWidgets('Planner empty copy waits for both Planner and Health',
      (tester) async {
    Future<void> show(
      AsyncValue<ExamPlanHealth?> value, {
      bool settle = true,
    }) =>
        _pump(
          tester,
          PlannerNeedsAttentionSection(
            items: const [],
            examPlanHealth: value,
            onOpen: (_) {},
            onOpenExamHealth: (_) {},
            onRetryExamHealth: () {},
          ),
          settle: settle,
        );

    await show(const AsyncValue.loading(), settle: false);
    expect(find.text('Nothing currently needs review.'), findsNothing);

    await show(AsyncValue.error(StateError('offline'), StackTrace.empty));
    expect(find.text('Nothing currently needs review.'), findsNothing);
    expect(find.text('Exam Plan Health unavailable'), findsOneWidget);

    await show(AsyncValue.data(_greenOnlyHealth()));
    expect(find.text('Nothing currently needs review.'), findsOneWidget);

    final previous = AsyncValue<ExamPlanHealth?>.data(_greenOnlyHealth());
    await show(
      const AsyncValue<ExamPlanHealth?>.loading().copyWithPrevious(previous),
      settle: false,
    );
    expect(find.text('Nothing currently needs review.'), findsNothing);
    expect(find.text('Checking Exam capacity…'), findsOneWidget);

    await show(AsyncValue.data(_health()));
    expect(find.text('Nothing currently needs review.'), findsNothing);
    expect(find.text('Healthy exam'), findsNothing);
    expect(find.text('Plan soon exam'), findsOneWidget);
    expect(find.text('Shortfall exam'), findsOneWidget);
    expect(find.text('Unknown exam'), findsOneWidget);
    expect(find.byType(AppStatusPill), findsNWidgets(3));
    expect(tester.takeException(), isNull);

    final priorWarning = AsyncValue<ExamPlanHealth?>.data(_health());
    await show(
      AsyncValue<ExamPlanHealth?>.error(
        StateError('offline'),
        StackTrace.empty,
      ).copyWithPrevious(priorWarning),
    );
    expect(find.text('Exam Plan Health unavailable'), findsOneWidget);
    expect(find.text('Plan soon exam'), findsNothing);

    final priorError = AsyncValue<ExamPlanHealth?>.error(
      StateError('offline'),
      StackTrace.empty,
    );
    await show(
      const AsyncValue<ExamPlanHealth?>.loading().copyWithPrevious(priorError),
      settle: false,
    );
    expect(find.text('Checking Exam capacity…'), findsOneWidget);
    expect(find.text('Exam Plan Health unavailable'), findsNothing);

    const priorEmpty = AsyncValue<ExamPlanHealth?>.data(null);
    await show(
      const AsyncValue<ExamPlanHealth?>.loading().copyWithPrevious(priorEmpty),
      settle: false,
    );
    expect(find.text('Checking Exam capacity…'), findsOneWidget);
    expect(find.text('Nothing currently needs review.'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(900, 1400),
  TextScaler textScaler = TextScaler.noScaling,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, current) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: current!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

ExamPlanHealth _health() => ExamPlanHealth(
      generatedAt: DateTime.utc(2026, 8, 13, 8),
      timezone: 'UTC',
      localDate: '2026-08-13',
      exams: [
        _item(
          id: '11111111-1111-4111-8111-111111111111',
          title: 'Healthy exam',
          deadline: DateTime.utc(2026, 8, 30, 18),
          status: ExamPlanHealthStatus.green,
          remaining: 300,
          capacity: 600,
          latest: '2026-08-22',
          reasons: const [],
        ),
        _item(
          id: '22222222-2222-4222-8222-222222222222',
          title: 'Plan soon exam',
          deadline: DateTime.utc(2026, 9, 1, 18),
          status: ExamPlanHealthStatus.yellow,
          remaining: 300,
          capacity: 390,
          latest: '2026-08-22',
          reasons: const ['low_session_reserve'],
        ),
        _item(
          id: '33333333-3333-4333-8333-333333333333',
          title: 'Shortfall exam',
          deadline: DateTime.utc(2026, 9, 2, 18),
          status: ExamPlanHealthStatus.red,
          remaining: 300,
          capacity: 299,
          latest: null,
          reasons: const ['capacity_deficit'],
        ),
        ExamPlanHealthItem(
          planId: '44444444-4444-4444-8444-444444444444',
          title: 'Unknown exam',
          deadlineAt: DateTime.utc(2026, 9, 3, 18),
          localDeadlineDate: '2026-09-03',
          status: ExamPlanHealthStatus.unknown,
          remainingMinutes: 300,
          preferredSessionMinutes: 50,
          sessionsNeeded: 6,
          futureReservedMinutes: 0,
          minutesToSchedule: 300,
          availableReplanCapacityMinutes: null,
          reserveMinutes: null,
          reserveFullSessions: null,
          latestSafeStartOn: null,
          recommendedStartOn: null,
          recommendedStartReason: 'Calendar import is unavailable.',
          reasons: const ['calendar_import_unavailable'],
          missingSources: const ['calendar_import'],
        ),
      ],
    );

ExamPlanHealth _greenOnlyHealth() => ExamPlanHealth(
      generatedAt: DateTime.utc(2026, 8, 13, 8),
      timezone: 'UTC',
      localDate: '2026-08-13',
      exams: [
        _item(
          id: '11111111-1111-4111-8111-111111111111',
          title: 'Healthy exam',
          deadline: DateTime.utc(2026, 8, 30, 18),
          status: ExamPlanHealthStatus.green,
          remaining: 300,
          capacity: 600,
          latest: '2026-08-22',
          reasons: const [],
        ),
      ],
    );

ExamPlanHealthItem _item({
  required String id,
  required String title,
  required DateTime deadline,
  required ExamPlanHealthStatus status,
  required int remaining,
  required int capacity,
  required String? latest,
  required List<String> reasons,
}) =>
    ExamPlanHealthItem(
      planId: id,
      title: title,
      deadlineAt: deadline,
      localDeadlineDate: deadline.toIso8601String().substring(0, 10),
      status: status,
      remainingMinutes: remaining,
      preferredSessionMinutes: 50,
      sessionsNeeded: (remaining / 50).ceil(),
      futureReservedMinutes: 0,
      minutesToSchedule: remaining,
      availableReplanCapacityMinutes: capacity,
      reserveMinutes: capacity - remaining,
      reserveFullSessions: (capacity - remaining).clamp(0, 200000) ~/ 50,
      latestSafeStartOn: latest,
      recommendedStartOn:
          status == ExamPlanHealthStatus.red ? null : '2026-08-14',
      recommendedStartReason:
          status == ExamPlanHealthStatus.red ? 'No safe start remains.' : null,
      reasons: reasons,
      missingSources: const [],
    );
