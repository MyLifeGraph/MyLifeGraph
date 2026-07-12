import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/actions/domain/executable_action_target.dart';
import 'package:my_life_graph/features/briefings/domain/daily_briefing.dart';
import 'package:my_life_graph/features/briefings/domain/decision_feedback.dart';
import 'package:my_life_graph/features/briefings/presentation/widgets/today_briefing_section.dart';

import 'support/briefing_fixtures.dart';

void main() {
  testWidgets('current briefing puts one executable primary action first', (
    tester,
  ) async {
    ExecutableActionTarget? executed;
    await _pumpSection(
      tester,
      value: AsyncValue.data(currentBriefingFeed()),
      onExecute: (target) async => executed = target,
    );

    expect(find.text("Today's decision"), findsOneWidget);
    expect(find.text('Recover mode · Current data'), findsOneWidget);
    expect(find.text('Primary action'), findsOneWidget);
    expect(find.text('Submit the report'), findsOneWidget);
    expect(find.text('Open task'), findsOneWidget);

    await tester.tap(find.text('Open task'));
    await tester.pump();
    expect(executed?.command, ExecutableActionCommand.openTask);
  });

  testWidgets('feedback is explicit and does not execute the action',
      (tester) async {
    DecisionFeedbackType? feedback;
    var executions = 0;
    await _pumpSection(
      tester,
      value: AsyncValue.data(currentBriefingFeed()),
      onExecute: (_) async => executions++,
      onFeedback: (_, type) async => feedback = type,
    );

    await tester.tap(find.text('Too much'));
    await tester.pump();

    expect(feedback, DecisionFeedbackType.tooMuch);
    expect(executions, 0);
    expect(find.textContaining('does not complete'), findsOneWidget);
  });

  testWidgets('stale briefing stays visible but cannot execute',
      (tester) async {
    var executions = 0;
    final stale = BriefingFeed.fromJson(
      briefingResponseJson(freshness: 'stale'),
    );
    await _pumpSection(
      tester,
      value: AsyncValue.data(stale),
      onExecute: (_) async => executions += 1,
    );

    expect(find.text('Stale'), findsOneWidget);
    expect(find.textContaining('source state changed'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Open task'),
    );
    expect(button.onPressed, isNull);
    expect(executions, 0);
  });

  testWidgets('missing state generates only after an explicit tap', (
    tester,
  ) async {
    bool? forced;
    final missing = BriefingFeed.fromJson(
      briefingResponseJson(
        freshness: 'missing',
        includeBriefing: false,
      ),
    );
    await _pumpSection(
      tester,
      value: AsyncValue.data(missing),
      onGenerate: ({required force}) async => forced = force,
    );

    expect(forced, isNull);
    await tester.tap(find.text('Generate today briefing'));
    await tester.pump();
    expect(forced, isFalse);
  });

  testWidgets('demo and error states never become personalized content', (
    tester,
  ) async {
    await _pumpSection(
      tester,
      value: AsyncValue.data(
        BriefingFeed.localDemo(now: DateTime(2026, 7, 12)),
      ),
    );
    expect(
      find.textContaining('unavailable in local demo mode'),
      findsOneWidget,
    );
    expect(find.text('Submit the report'), findsNothing);

    await _pumpSection(
      tester,
      value: AsyncValue.error(StateError('backend failed'), StackTrace.empty),
    );
    expect(find.text('Today briefing unavailable'), findsOneWidget);
    expect(find.textContaining('not replaced'), findsOneWidget);
    expect(find.text('Submit the report'), findsNothing);
  });
}

Future<void> _pumpSection(
  WidgetTester tester, {
  required AsyncValue<BriefingFeed> value,
  GenerateBriefingCallback? onGenerate,
  ExecuteBriefingActionCallback? onExecute,
  SubmitFeedbackCallback? onFeedback,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TodayBriefingSection(
            value: value,
            isGenerating: false,
            generationError: null,
            executingActionIds: const {},
            onRetryRead: () {},
            onGenerate: onGenerate ?? ({required force}) async {},
            onExecute: onExecute ?? (_) async {},
            isSubmittingFeedback: false,
            feedbackError: null,
            submittedFeedbackType: null,
            onFeedback: onFeedback ?? (_, DecisionFeedbackType __) async {},
            onShowFeedbackHistory: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
