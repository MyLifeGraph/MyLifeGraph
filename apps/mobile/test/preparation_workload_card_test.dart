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
}
