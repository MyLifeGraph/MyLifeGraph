import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_plan.dart';
import 'package:my_life_graph/features/deadline_plans/presentation/widgets/preparation_workload_card.dart';

import 'support/deadline_plan_fixtures.dart';

void main() {
  testWidgets('seven-day load remains readable at 320px and 200% text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workload = PreparationWorkload.fromJson(
      preparationWorkloadEnvelope(firstDayReservedMinutes: 140),
    );

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PreparationWorkloadCard(
              value: AsyncData(workload),
              onRetry: () {},
              onOpenSettings: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your next 7 days'), findsOneWidget);
    expect(find.textContaining('Needs review'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workload failure never substitutes empty or estimated data',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PreparationWorkloadCard(
            value: AsyncError(Exception('offline'), StackTrace.current),
            onRetry: () {},
            onOpenSettings: () {},
          ),
        ),
      ),
    );

    expect(find.text('Preparation load unavailable'), findsOneWidget);
    expect(
      find.textContaining('No empty or estimated workload was substituted'),
      findsOneWidget,
    );
  });

  testWidgets('over-budget day expands into exact read-only plan actions',
      (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? reviewedPlan;
    String? replannedPlan;
    final workload = PreparationWorkload.fromJson(
      preparationWorkloadEnvelope(
        firstDayReservedMinutes: 140,
        firstDayActivePlanCount: 2,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PreparationWorkloadCard(
              value: AsyncData(workload),
              onRetry: () {},
              onOpenSettings: () {},
              onLoadDayDetail: (localDate) async {
                expect(localDate, '2026-07-20');
                return PreparationWorkloadDetail.fromJson(
                  preparationWorkloadDetailEnvelope(),
                );
              },
              onReviewPlan: (planId) => reviewedPlan = planId,
              onReplanPlan: (planId) => replannedPlan = planId,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dayTile = find.byKey(
      const ValueKey('preparation-workload-day-2026-07-20'),
    );
    await tester.ensureVisible(dayTile);
    await tester.tap(dayTile);
    await tester.pumpAndSettle();

    expect(find.text('Algorithms exam'), findsOneWidget);
    expect(find.text('History paper'), findsOneWidget);
    expect(
      find.textContaining('At least 20 min must be redistributed'),
      findsOneWidget,
    );
    expect(
      find.textContaining('nothing changes automatically'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final review = find.byKey(ValueKey('workload-review-$deadlinePlanId'));
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pump();
    expect(reviewedPlan, deadlinePlanId);

    final replan = find.byKey(ValueKey('workload-replan-$deadlinePlanId'));
    await tester.ensureVisible(replan);
    await tester.tap(replan);
    await tester.pump();
    expect(replannedPlan, deadlinePlanId);
  });

  testWidgets('day-detail failure keeps the confirmed summary and retries',
      (tester) async {
    var calls = 0;
    final workload = PreparationWorkload.fromJson(
      preparationWorkloadEnvelope(firstDayReservedMinutes: 140),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PreparationWorkloadCard(
              value: AsyncData(workload),
              onRetry: () {},
              onOpenSettings: () {},
              onLoadDayDetail: (_) async {
                calls++;
                throw Exception('offline');
              },
            ),
          ),
        ),
      ),
    );
    final dayTile = find.byKey(
      const ValueKey('preparation-workload-day-2026-07-20'),
    );
    await tester.ensureVisible(dayTile);
    await tester.tap(dayTile);
    await tester.pumpAndSettle();

    expect(find.textContaining('2h 20m reserved'), findsOneWidget);
    expect(find.textContaining('Plan breakdown unavailable'), findsOneWidget);
    expect(calls, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('changed detail asks to reload the seven-day summary',
      (tester) async {
    var summaryReloads = 0;
    final workload = PreparationWorkload.fromJson(
      preparationWorkloadEnvelope(
        firstDayReservedMinutes: 140,
        firstDayActivePlanCount: 2,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PreparationWorkloadCard(
              value: AsyncData(workload),
              onRetry: () => summaryReloads++,
              onOpenSettings: () {},
              onLoadDayDetail: (_) async => PreparationWorkloadDetail.fromJson(
                preparationWorkloadDetailEnvelope(budget: 125),
              ),
            ),
          ),
        ),
      ),
    );
    final dayTile = find.byKey(
      const ValueKey('preparation-workload-day-2026-07-20'),
    );
    await tester.ensureVisible(dayTile);
    await tester.tap(dayTile);
    await tester.pumpAndSettle();

    expect(find.textContaining('Reservations changed'), findsOneWidget);
    await tester.tap(find.text('Reload 7-day load'));
    expect(summaryReloads, 1);
  });
}
