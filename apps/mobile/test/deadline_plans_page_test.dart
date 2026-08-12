import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/core/network/api_failure.dart';
import 'package:my_life_graph/core/navigation/app_routes.dart';
import 'package:my_life_graph/core/widgets/app_surface.dart';
import 'package:my_life_graph/features/auth/application/profile_local_date_source.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import 'package:my_life_graph/features/deadline_plans/data/deadline_calendar_prefill_data_source.dart';
import 'package:my_life_graph/features/deadline_plans/domain/assignment_series.dart';
import 'package:my_life_graph/features/deadline_plans/domain/assignment_series_repository.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_calendar_prefill.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_plan.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_plan_repository.dart';
import 'package:my_life_graph/features/deadline_plans/presentation/pages/deadline_plans_page.dart';
import 'package:my_life_graph/composition/deadline_plan_providers.dart';
import 'package:my_life_graph/features/snapshots/application/snapshot_refresh_service.dart';
import 'package:my_life_graph/features/snapshots/presentation/providers/snapshot_providers.dart';

import 'support/deadline_plan_fixtures.dart';
import 'support/assignment_series_fixtures.dart';

void main() {
  final now = DateTime(2026, 7, 18, 10);

  testWidgets('Planner Assignment opens a finite series without type choice',
      (tester) async {
    final seriesRepository = _FakeAssignmentSeriesRepository(
      proposalResult: AssignmentSeriesResponse.fromJson(
        assignmentSeriesEnvelope(),
      ).series,
    );
    await _pumpPage(
      tester,
      repository: _FakeDeadlinePlanRepository(),
      assignmentSeriesRepository: seriesRepository,
      page: DeadlinePlansPage(
        initialKind: DeadlinePlanKind.assignment,
        currentTime: now,
      ),
    );

    expect(find.text('Which assignment series?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('assignment-series-locked-kind')),
      findsOneWidget,
    );
    expect(find.byType(SegmentedButton<DeadlinePlanKind>), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('assignment-series-title')),
      'Weekly algorithms sheet',
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('assignment-series-next-deadline')),
    );
    await _tap(tester, find.text('OK'));
    await _tap(tester, find.text('OK'));
    await _tap(tester, find.text('Continue'));

    final count = tester.widget<TextField>(
      find.byKey(const ValueKey('assignment-series-count')),
    );
    expect(count.controller!.text, '12');
    expect(
      find.text('12 is the default for a typical semester.'),
      findsOneWidget,
    );
    expect(find.textContaining('prior work'), findsNothing);
    expect(find.textContaining('prior-work'), findsNothing);

    await _tap(
      tester,
      find.byKey(const ValueKey('assignment-series-estimate-1h')),
    );
    await _tap(tester, find.text('Continue'));
    final dailyCap = tester.widget<TextField>(
      find.byKey(const ValueKey('assignment-series-daily-cap')),
    );
    expect(dailyCap.controller!.text, '360');
    await _tap(tester, find.text('Create series preview'));
    expect(seriesRepository.proposalDrafts.single.maxDailyMinutes, 360);
  });

  testWidgets('Planner Exam keeps the selected kind without type choice',
      (tester) async {
    await _pumpPage(
      tester,
      repository: _FakeDeadlinePlanRepository(),
      page: DeadlinePlansPage(
        initialKind: DeadlinePlanKind.exam,
        currentTime: now,
      ),
    );

    expect(find.text('What are you preparing for?'), findsOneWidget);
    expect(find.byKey(const ValueKey('deadline-locked-kind')), findsOneWidget);
    expect(find.byType(SegmentedButton<DeadlinePlanKind>), findsNothing);
  });

  testWidgets('new Exam keeps the 120 minute daily default', (tester) async {
    final repository = _FakeDeadlinePlanRepository();
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(
        initialKind: DeadlinePlanKind.exam,
        initialTitle: 'Algorithms exam',
        initialDeadlineAt: DateTime(2026, 7, 25, 17),
        currentTime: now,
      ),
    );

    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.byKey(const ValueKey('deadline-estimate-2h')));
    await _tap(tester, find.text('Continue'));

    final dailyCap = tester.widget<TextField>(
      find.byKey(const ValueKey('deadline-daily-cap')),
    );
    expect(dailyCap.controller!.text, '120');
    await _tap(tester, find.text('Create preview'));
    expect(repository.proposalDrafts.single.maxDailyMinutes, 120);
    expect(repository.proposalDrafts.single.kind, DeadlinePlanKind.exam);
  });

  testWidgets('new calendar Assignment submits the 360 minute daily default',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository();
    final prefill = _FakeCalendarPrefillDataSource(
      result: DeadlineCalendarPrefill.current(
        eventId: deadlineCalendarEventId,
        title: 'Imported coursework',
        sourceFingerprint: deadlineFingerprint,
        kind: DeadlineCalendarEventKind.timed,
        startsAt: DateTime.parse('2026-07-25T15:00:00Z'),
        startsOn: null,
      ),
    );
    await _pumpPage(
      tester,
      repository: repository,
      prefillDataSource: prefill,
      page: DeadlinePlansPage(
        sourceCalendarEventId: deadlineCalendarEventId,
        currentTime: now,
      ),
    );

    await _tap(tester, find.text('Assignment'));
    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.byKey(const ValueKey('deadline-estimate-2h')));
    await _tap(tester, find.text('Continue'));
    final dailyCap = tester.widget<TextField>(
      find.byKey(const ValueKey('deadline-daily-cap')),
    );
    expect(dailyCap.controller!.text, '360');
    await _tap(tester, find.text('Create preview'));
    expect(repository.proposalDrafts.single.maxDailyMinutes, 360);
    expect(repository.proposalDrafts.single.kind, DeadlinePlanKind.assignment);
  });

  testWidgets('manual daily cap survives kind changes and is submitted',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository();
    final prefill = _FakeCalendarPrefillDataSource(
      result: DeadlineCalendarPrefill.current(
        eventId: deadlineCalendarEventId,
        title: 'Imported coursework',
        sourceFingerprint: deadlineFingerprint,
        kind: DeadlineCalendarEventKind.timed,
        startsAt: DateTime.parse('2026-07-25T15:00:00Z'),
        startsOn: null,
      ),
    );
    await _pumpPage(
      tester,
      repository: repository,
      prefillDataSource: prefill,
      page: DeadlinePlansPage(
        sourceCalendarEventId: deadlineCalendarEventId,
        currentTime: now,
      ),
    );

    await _tap(tester, find.text('Assignment'));
    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.byKey(const ValueKey('deadline-estimate-2h')));
    await _tap(tester, find.text('Continue'));

    await tester.enterText(
      find.byKey(const ValueKey('deadline-daily-cap')),
      '275',
    );
    await _tap(tester, find.text('Back'));
    await _tap(tester, find.text('Back'));
    await _tap(tester, find.text('Exam'));
    await _tap(tester, find.text('Assignment'));
    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.text('Continue'));
    final dailyCap = tester.widget<TextField>(
      find.byKey(const ValueKey('deadline-daily-cap')),
    );
    expect(dailyCap.controller!.text, '275');
    await _tap(tester, find.text('Create preview'));
    expect(repository.proposalDrafts.single.maxDailyMinutes, 275);
    expect(repository.proposalDrafts.single.kind, DeadlinePlanKind.assignment);
  });

  testWidgets('existing and retained Assignment Series keep their custom cap',
      (tester) async {
    final series = AssignmentSeriesResponse.fromJson(
      assignmentSeriesEnvelope(status: 'active'),
    ).series;
    final seriesRepository = _FakeAssignmentSeriesRepository(
      series: [series],
      proposalErrors: [
        AppException(
          'Invalid request',
          cause: const ApiFailure(
            kind: ApiFailureKind.response,
            statusCode: 400,
          ),
        ),
      ],
    );
    await _pumpPage(
      tester,
      repository: _FakeDeadlinePlanRepository(),
      assignmentSeriesRepository: seriesRepository,
      page: DeadlinePlansPage(currentTime: now),
    );

    await _tap(tester, find.text(series.title));
    await _tap(tester, find.text('Edit all future'));
    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.text('Continue'));
    var dailyCap = tester.widget<TextField>(
      find.byKey(const ValueKey('assignment-series-daily-cap')),
    );
    expect(dailyCap.controller!.text, '60');

    await tester.enterText(
      find.byKey(const ValueKey('assignment-series-daily-cap')),
      '275',
    );
    await _tap(tester, find.text('Create series preview'));
    expect(seriesRepository.proposalDrafts.single.maxDailyMinutes, 275);
    await _tap(tester, find.text('Dismiss'));
    await _tap(tester, find.text('Review series values'));
    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.text('Continue'));
    dailyCap = tester.widget<TextField>(
      find.byKey(const ValueKey('assignment-series-daily-cap')),
    );
    expect(dailyCap.controller!.text, '275');
  });

  testWidgets('Assignment Series Edit one keeps the occurrence kind locked',
      (tester) async {
    final series = AssignmentSeriesResponse.fromJson(
      assignmentSeriesEnvelope(status: 'active'),
    ).series;
    final occurrencePlan = _planWithIdentity(
      id: '40000000-0000-4000-8000-000000000001',
      title: 'Weekly algorithms sheet · 1',
      kind: DeadlinePlanKind.assignment,
    );
    await _pumpPage(
      tester,
      repository: _FakeDeadlinePlanRepository(
        feeds: [
          DeadlinePlanFeed(plans: [occurrencePlan]),
        ],
      ),
      assignmentSeriesRepository: _FakeAssignmentSeriesRepository(
        series: [series],
      ),
      page: DeadlinePlansPage(currentTime: now),
    );

    await _tap(
      tester,
      find.descendant(
        of: find.byKey(ValueKey('assignment-series-${series.id}')),
        matching: find.text(series.title),
      ),
    );
    await _tap(tester, find.text('Edit one'));
    await _tap(tester, find.text('Change values'));

    final locked = find.byKey(const ValueKey('deadline-locked-kind'));
    expect(locked, findsOneWidget);
    expect(
      find.descendant(of: locked, matching: find.text('Assignment')),
      findsOneWidget,
    );
    expect(find.byType(SegmentedButton<DeadlinePlanKind>), findsNothing);
  });

  testWidgets(
      'general preparation action offers Exam and weekly Assignment after a direct entry',
      (tester) async {
    await _pumpPage(
      tester,
      repository: _FakeDeadlinePlanRepository(),
      page: DeadlinePlansPage(
        initialKind: DeadlinePlanKind.assignment,
        currentTime: now,
      ),
    );

    expect(find.text('Which assignment series?'), findsOneWidget);
    await _tap(tester, find.text('Cancel'));
    await _tap(tester, find.text('Plan preparation'));

    expect(
      find.byKey(const ValueKey('preparation-kind-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('preparation-kind-exam')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('preparation-kind-assignment')),
      findsOneWidget,
    );

    await _tap(
      tester,
      find.byKey(const ValueKey('preparation-kind-exam')),
    );
    expect(find.byKey(const ValueKey('deadline-locked-kind')), findsOneWidget);
    expect(find.text('One preparation plan with one deadline.'), findsNothing);
    expect(find.text('Exam'), findsOneWidget);

    await _tap(tester, find.text('Cancel'));
    await _tap(tester, find.text('Plan preparation'));
    await _tap(
      tester,
      find.byKey(const ValueKey('preparation-kind-assignment')),
    );
    expect(find.text('Which assignment series?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('assignment-series-locked-kind')),
      findsOneWidget,
    );
  });

  testWidgets('wizard requires an explicit estimate without prior-work choice',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository();
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(
        initialTitle: 'Algorithms exam',
        initialDeadlineAt: DateTime(2026, 7, 18, 18),
        currentTime: now,
      ),
    );

    await _tap(tester, find.text('Plan preparation'));
    await _tap(tester, find.text('Exam'));
    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.text('Continue'));
    expect(
      find.text('Enter 30 minutes to 500 hours of total preparation.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));

    await _tap(tester, find.byKey(const ValueKey('deadline-estimate-5h')));
    expect(find.textContaining('cannot estimate this for you'), findsOneWidget);
    await _tap(tester, find.text('Continue'));
    expect(find.text('Step 3 of 3'), findsOneWidget);
    expect(find.textContaining('prior work'), findsNothing);
    expect(
      find.text('Maximum preparation minutes per day for this plan'),
      findsOneWidget,
    );
    expect(find.textContaining('there is no background sync'), findsOneWidget);
  });

  testWidgets('hides seven-day load but keeps its budget in the editor',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository();
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(
        initialTitle: 'Algorithms exam',
        initialDeadlineAt: DateTime(2026, 7, 18, 18),
        currentTime: now,
      ),
    );

    expect(find.text('Your next 7 days'), findsNothing);
    expect(
      find.text('2h total preparation per day across confirmed plans.'),
      findsNothing,
    );
    expect(find.textContaining('50 min reserved'), findsNothing);

    await _tap(tester, find.text('Plan preparation'));
    await _tap(tester, find.text('Exam'));
    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.byKey(const ValueKey('deadline-estimate-5h')));
    await _tap(tester, find.text('Continue'));

    expect(
      find.textContaining('Account-wide budget: 2 h per day'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Confirmed blocks from other plans are deducted'),
      findsOneWidget,
    );
  });

  testWidgets('three-step same-day preview needs explicit confirmation',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      proposalResults: [_plan(status: 'draft')],
      confirmResult: _plan(),
    );
    final snapshotRefresh = _RecordingSnapshotRefresh();
    await _pumpPage(
      tester,
      repository: repository,
      snapshotRefresh: snapshotRefresh,
      profileDateSource: SessionProfileLocalDateSource(
        session: null,
        currentInstant: () => DateTime(2026, 7, 18, 10),
      ),
      page: DeadlinePlansPage(
        initialTitle: 'Algorithms exam',
        initialDeadlineAt: DateTime(2026, 7, 18, 18),
        currentTime: now,
      ),
    );

    await _completeNewWizard(tester);

    expect(repository.proposalDrafts, hasLength(1));
    expect(repository.proposalDrafts.single.bufferDays, 0);
    expect(repository.confirmCalls, 0);
    expect(find.text('Confirm reservations'), findsOneWidget);

    await _tap(tester, find.text('Confirm reservations'));
    expect(find.text('Reserve these focus blocks?'), findsOneWidget);
    await _tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Confirm reservations'),
      ),
    );

    expect(repository.confirmCalls, 1);
    expect(snapshotRefresh.taskTargetDates, ['2026-07-18']);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Preview'), findsNothing);
  });

  testWidgets('unavailable calendar source can detach to a manual proposal',
      (tester) async {
    final sourcePlan = _calendarPlan(DeadlinePlanSourceStatus.unavailable);
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [sourcePlan]),
      ],
      proposalResults: [sourcePlan],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: now),
    );

    await _tapPlanAction(tester, 'Adjust estimate or plan');
    expect(
      find.textContaining('imported source changed or became unavailable'),
      findsOneWidget,
    );
    final quickPreview = tester.widget<FilledButton>(
      find.byKey(const ValueKey('deadline-create-preview-existing')),
    );
    expect(quickPreview.onPressed, isNull);
    expect(repository.proposalDrafts, isEmpty);
    await _tap(tester, find.text('Change values'));
    expect(
      find.textContaining('Turn this off to keep your reviewed title'),
      findsOneWidget,
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('deadline-keep-calendar-source')),
    );
    expect(
      find.textContaining('will no longer depend on the imported event'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Continue'));
    expect(
      find.textContaining('before this plan was first activated'),
      findsNothing,
    );
    expect(find.textContaining('25 min linked Focus'), findsOneWidget);
    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.text('Create preview'));

    final draft = repository.proposalDrafts.single;
    expect(draft.sourceKind, DeadlinePlanSourceKind.manual);
    expect(draft.sourceCalendarEventId, isNull);
    expect(draft.sourceCalendarEventFingerprint, isNull);
    expect(draft.useCalendarAvailability, isFalse);
  });

  testWidgets('active blocks stay visible and startable under staged replan',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(
          plans: [_plan(pending: true)],
        ),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: now),
    );

    expect(find.text('Revised algorithms exam'), findsOneWidget);
    expect(find.text('Currently reserved until you confirm'), findsOneWidget);
    expect(find.text('Algorithms exam'), findsOneWidget);
    expect(
      find.byTooltip('Start plan focus with this remaining duration'),
      findsOneWidget,
    );

    await _tap(tester, find.text('Adjust estimate or plan'));
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.text('Create preview with these values'), findsNothing);
    expect(repository.proposalDrafts, isEmpty);
  });

  testWidgets('preparation preview explains learned timing evidence',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [_learnedPendingPlan()]),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: now),
    );

    await _expandPlan(tester);
    expect(
      find.byKey(const Key('deadline-learned-timing-applied')),
      findsOneWidget,
    );
    expect(
      find.text('Learned timing applied · 24 rated sessions'),
      findsOneWidget,
    );
  });

  testWidgets('preparation preview labels an actual Setup timing fallback',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [_learnedPendingPlan(fellBackToSetup: true)]),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: now),
    );

    expect(
      find.text(
        'Learned timing considered · Setup fallback · 24 rated sessions',
      ),
      findsOneWidget,
    );
  });

  testWidgets('active missed warning remains visible under staged replan',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [_pendingPlanWithMissedActiveBlock()]),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: now),
    );

    expect(find.text('Plan needs attention'), findsOneWidget);
    expect(
      find.textContaining('replacement remains an unconfirmed preview'),
      findsOneWidget,
    );
  });

  testWidgets('active plan exposes deterministic planning and credit rules',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [_plan()]),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: now),
    );

    await _expandPlan(tester);
    expect(
      find.textContaining('Rule-based windows: prefers 08:00–13:00'),
      findsNothing,
    );
    await tester.tap(
      find.byKey(
        const ValueKey(
          'deadline-plan-info-control-How new previews place time',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Rule-based windows: prefers 08:00–13:00'),
      findsOneWidget,
    );
    expect(
      find.textContaining('A new or replanned Exam preview spreads'),
      findsOneWidget,
    );
    expect(find.text('Entered prior credit'), findsNothing);
    expect(
      find.textContaining('Linked Focus completed after this plan'),
      findsOneWidget,
    );
  });

  testWidgets('active Assignment describes only the next preview allocation',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(
          plans: [
            _planWithKind(
              DeadlinePlanKind.assignment,
              maxDailyMinutes: 275,
            ),
          ],
        ),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: now),
    );

    await _expandPlan(tester);
    await tester.tap(
      find.byKey(
        const ValueKey(
          'deadline-plan-info-control-How new previews place time',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('A new or replanned Assignment preview fills'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Assignment preparation fills'),
      findsNothing,
    );
  });

  testWidgets('missed preparation blocks offer deliberate recovery replanning',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [_missedPlan()]),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: now),
    );

    await _expandPlan(tester);
    expect(find.text('Plan needs attention'), findsOneWidget);
    expect(find.textContaining('50 min still uncredited'), findsOneWidget);

    await _tap(
      tester,
      find.byKey(
        const ValueKey(
          'deadline-replan-missed-11111111-1111-4111-8111-111111111111',
        ),
      ),
    );

    expect(find.text('Replan remaining preparation'), findsOneWidget);
    expect(
      find.textContaining('missed, uncredited preparation'),
      findsOneWidget,
    );
    expect(
      find.text('Create preview with these values'),
      findsOneWidget,
    );
    expect(find.text('Algorithms exam'), findsWidgets);
    expect(repository.proposalDrafts, isEmpty);
  });

  testWidgets('compact replan keeps saved values and normalizes past start',
      (tester) async {
    final sourcePlan = _plan();
    final revision = sourcePlan.activeRevision!;
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [sourcePlan]),
      ],
      proposalResults: [_plan(pending: true)],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: DateTime(2026, 7, 22, 10)),
    );

    await _tapPlanAction(tester, 'Adjust estimate or plan');
    expect(find.text('Replan remaining preparation'), findsOneWidget);
    expect(find.textContaining('Plan from Jul 22, 2026'), findsOneWidget);
    expect(find.textContaining('fixed planning rules'), findsNothing);
    await tester.tap(
      find.byKey(
        const ValueKey(
          'deadline-plan-info-control-How the preview is calculated',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('fixed planning rules'),
      findsOneWidget,
    );
    expect(repository.proposalDrafts, isEmpty);
    await _tap(tester, find.text('Create preview with these values'));

    final draft = repository.proposalDrafts.single;
    expect(draft.planId, sourcePlan.id);
    expect(draft.baseRevision, sourcePlan.latestRevision);
    expect(draft.kind, revision.kind);
    expect(draft.title, revision.title);
    expect(draft.deadlineAt, revision.deadlineAt);
    expect(draft.estimatedTotalMinutes, revision.estimatedTotalMinutes);
    expect(draft.creditedPriorMinutes, revision.creditedPriorMinutes);
    expect(draft.preferredSessionMinutes, revision.preferredSessionMinutes);
    expect(draft.maxDailyMinutes, revision.maxDailyMinutes);
    expect(draft.planningStartOn, '2026-07-22');
    expect(draft.bufferDays, revision.bufferDays);
    expect(draft.sourceKind, revision.sourceKind);
    expect(draft.sourceCalendarEventId, revision.sourceCalendarEventId);
    expect(
      draft.sourceCalendarEventFingerprint,
      revision.sourceCalendarEventFingerprint,
    );
    expect(
      draft.useCalendarAvailability,
      revision.useCalendarAvailability,
    );
    expect(repository.confirmCalls, 0);
    expect(find.text('Confirm reservations'), findsOneWidget);
    expect(find.text('Currently reserved until you confirm'), findsOneWidget);
  });

  testWidgets('compact replan blocks a saved finish-by time in the past',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(
          plans: [_planWithDeadline('2026-07-18T07:00:00Z')],
        ),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: now),
    );

    await _tapPlanAction(tester, 'Adjust estimate or plan');
    expect(
      find.textContaining('saved finish-by time has passed'),
      findsOneWidget,
    );
    final quickPreview = tester.widget<FilledButton>(
      find.byKey(const ValueKey('deadline-create-preview-existing')),
    );
    expect(quickPreview.onPressed, isNull);
    expect(repository.proposalDrafts, isEmpty);

    await _tap(tester, find.text('Change values'));
    expect(find.text('Step 1 of 3'), findsOneWidget);
  });

  testWidgets('large active plan initially renders only six block rows',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [_planWithEightBlocks()]),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: now),
    );

    await _expandPlan(tester);
    expect(
      find.byKey(
        const ValueKey(
          'deadline-block-00000006-0000-4000-8000-000000000006',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'deadline-block-00000007-0000-4000-8000-000000000007',
        ),
      ),
      findsNothing,
    );
    await tester.drag(_pageScrollable(), const Offset(0, -240));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Show all 8 blocks'));
    expect(
      find.byKey(
        const ValueKey(
          'deadline-block-00000008-0000-4000-8000-000000000008',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Show fewer blocks'), findsOneWidget);
  });

  testWidgets('terminal history is collapsed until explicitly expanded',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [_plan(status: 'completed')]),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: now),
    );

    expect(find.text('History'), findsOneWidget);
    expect(find.textContaining('2026-07-20 · 10:00'), findsNothing);
    await _expandPlan(tester);
    expect(find.textContaining('2026-07-20 · 10:00'), findsOneWidget);
  });

  testWidgets('open plans and history keep exactly one accordion expanded',
      (tester) async {
    const secondId = '55555555-5555-4555-8555-555555555555';
    const historyId = '66666666-6666-4666-8666-666666666666';
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(
          plans: [
            _plan(),
            _planWithIdentity(
              id: secondId,
              title: 'History assignment',
            ),
            _planWithIdentity(
              id: historyId,
              title: 'Completed statistics exam',
              status: 'completed',
            ),
          ],
        ),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: now),
    );

    expect(find.text('Open plans'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.textContaining('Finish by'), findsNothing);

    await _tap(
      tester,
      find.byKey(const ValueKey('deadline-toggle-plan-$secondId')),
    );
    expect(find.textContaining('Finish by'), findsOneWidget);
    await _tap(
      tester,
      find.byKey(const ValueKey('deadline-toggle-plan-$deadlinePlanId')),
    );
    expect(find.textContaining('Finish by'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('deadline-block-$deadlineBlockId')),
      findsOneWidget,
    );
  });

  testWidgets('status and type pills use their semantic tones', (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(
          plans: [
            _plan(pending: true),
            _planWithIdentity(
              id: '55555555-5555-4555-8555-555555555555',
              title: 'Completed assignment',
              status: 'completed',
            ),
            _planWithIdentity(
              id: '66666666-6666-4666-8666-666666666666',
              title: 'Cancelled exam',
              status: 'cancelled',
            ),
          ],
        ),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: now),
    );

    AppStatusTone tone(String label) => tester
        .widget<AppStatusPill>(
          find
              .byWidgetPredicate(
                (widget) => widget is AppStatusPill && widget.label == label,
              )
              .first,
        )
        .tone;
    expect(tone('Preview'), AppStatusTone.attention);
    expect(tone('Completed'), AppStatusTone.success);
    expect(tone('Cancelled'), AppStatusTone.danger);
    expect(tone('Exam'), AppStatusTone.info);
  });

  testWidgets('completing a long scrolled plan leaves a visible history card',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [_planWithEightBlocks()]),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: now),
      size: const Size(1200, 650),
    );
    await _expandPlan(tester);
    await _tap(tester, find.text('Mark preparation complete'));
    await _tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Mark complete'),
      ),
    );

    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Algorithms exam').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('deadline-plan-inline-error')),
      findsNothing,
    );
  });

  testWidgets('failed completion preserves the active card and inline error',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [_plan()]),
      ],
      completeError: StateError('offline'),
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: now),
    );
    await _expandPlan(tester);
    await _tap(tester, find.text('Mark preparation complete'));
    await _tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Mark complete'),
      ),
    );

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Mark preparation complete'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('deadline-plan-inline-error')),
      findsOneWidget,
    );
  });

  testWidgets('409 reload retains values and rebases against latest revision',
      (tester) async {
    final conflict = _conflict(
      'Deadline plan changed. Reload before replanning.',
    );
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [_plan()]),
        DeadlinePlanFeed(plans: [_plan(pending: true)]),
      ],
      proposalErrors: [conflict],
      proposalResults: [_plan(pending: true)],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: now),
    );

    await _submitExistingWizard(tester);
    expect(repository.proposalDrafts.single.baseRevision, 1);
    expect(
      find.textContaining('Load the latest saved plan before reviewing'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Load latest plan'));
    await tester.scrollUntilVisible(
      find.text('Entered plan values kept'),
      400,
      scrollable: _pageScrollable(),
    );
    expect(find.text('Entered plan values kept'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Review entered values'),
      find.byType(CustomScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    final reviewValues = find.text('Review entered values').hitTestable();
    expect(reviewValues, findsOneWidget);
    await tester.tap(reviewValues);
    await tester.pumpAndSettle();
    final locked = find.byKey(const ValueKey('deadline-locked-kind'));
    expect(locked, findsOneWidget);
    expect(
      find.descendant(of: locked, matching: find.text('Exam')),
      findsOneWidget,
    );
    expect(find.byType(SegmentedButton<DeadlinePlanKind>), findsNothing);
    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.text('Continue'));
    final dailyCap = tester.widget<TextField>(
      find.byKey(const ValueKey('deadline-daily-cap')),
    );
    expect(dailyCap.controller!.text, '120');
    await _tap(tester, find.text('Create preview'));

    expect(repository.proposalDrafts, hasLength(2));
    expect(repository.proposalDrafts.last.baseRevision, 2);
    expect(repository.proposalDrafts.last.kind, DeadlinePlanKind.exam);
    expect(repository.proposalRequestIds.toSet(), hasLength(2));
  });

  testWidgets('current calendar prefill is loaded outside the URL',
      (tester) async {
    final source = _FakeCalendarPrefillDataSource(
      result: DeadlineCalendarPrefill.current(
        eventId: deadlineCalendarEventId,
        title: 'Private algorithms exam',
        sourceFingerprint: deadlineFingerprint,
        kind: DeadlineCalendarEventKind.timed,
        startsAt: DateTime.parse('2026-07-25T15:00:00Z'),
        startsOn: null,
      ),
    );
    await _pumpPage(
      tester,
      repository: _FakeDeadlinePlanRepository(),
      prefillDataSource: source,
      page: DeadlinePlansPage(
        sourceCalendarEventId: deadlineCalendarEventId,
        currentTime: now,
      ),
    );

    expect(source.calls, 1);
    final title = tester.widget<TextField>(
      find.byKey(const ValueKey('deadline-plan-title')),
    );
    expect(title.controller!.text, 'Private algorithms exam');
    expect(find.textContaining("this device's timezone"), findsOneWidget);
    expect(
      find.byKey(const ValueKey('deadline-keep-calendar-source')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('deadline-locked-kind')), findsNothing);
    expect(
      find.byType(SegmentedButton<DeadlinePlanKind>),
      findsOneWidget,
    );
  });

  testWidgets('prefill error retries, while guest mode remains zero-call',
      (tester) async {
    final source = _FakeCalendarPrefillDataSource(
      result: DeadlineCalendarPrefill.current(
        eventId: deadlineCalendarEventId,
        title: 'Private algorithms exam',
        sourceFingerprint: deadlineFingerprint,
        kind: DeadlineCalendarEventKind.timed,
        startsAt: DateTime.parse('2026-07-25T15:00:00Z'),
        startsOn: null,
      ),
      errorsRemaining: 1,
    );
    await _pumpPage(
      tester,
      repository: _FakeDeadlinePlanRepository(),
      prefillDataSource: source,
      page: DeadlinePlansPage(
        sourceCalendarEventId: deadlineCalendarEventId,
        currentTime: now,
      ),
    );
    expect(find.text('Imported event unavailable'), findsOneWidget);
    await _tap(tester, find.text('Retry event'));
    expect(source.calls, 2);
    expect(
      find.byKey(const ValueKey('deadline-plan-title')),
      findsOneWidget,
    );

    final guestSource = _FakeCalendarPrefillDataSource(result: source.result);
    await _pumpPage(
      tester,
      repository: _FakeDeadlinePlanRepository(),
      prefillDataSource: guestSource,
      capabilities: const AppSurfaceCapabilities(
        isLocalDemo: true,
        canUseSyncedHabits: false,
      ),
      page: DeadlinePlansPage(
        sourceCalendarEventId: deadlineCalendarEventId,
      ),
    );
    expect(guestSource.calls, 0);
  });

  testWidgets('loading prefill disables generic CTA and opens one editor',
      (tester) async {
    final completer = Completer<DeadlineCalendarPrefill>();
    final result = DeadlineCalendarPrefill.current(
      eventId: deadlineCalendarEventId,
      title: 'Private algorithms exam',
      sourceFingerprint: deadlineFingerprint,
      kind: DeadlineCalendarEventKind.timed,
      startsAt: DateTime.parse('2026-07-25T15:00:00Z'),
      startsOn: null,
    );
    final source = _FakeCalendarPrefillDataSource(
      result: result,
      completer: completer,
    );
    await _pumpPage(
      tester,
      repository: _FakeDeadlinePlanRepository(),
      prefillDataSource: source,
      page: DeadlinePlansPage(
        sourceCalendarEventId: deadlineCalendarEventId,
        currentTime: now,
      ),
      settle: false,
    );

    final genericCta = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Plan preparation'),
    );
    expect(genericCta.onPressed, isNull);
    completer.complete(result);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('deadline-plan-title')),
      findsOneWidget,
    );
    expect(find.text('Step 1 of 3'), findsOneWidget);
  });

  testWidgets('missing deep-linked terminal plan gets one targeted read',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      targetedPlan: _plan(status: 'completed'),
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: const DeadlinePlansPage(initialPlanId: deadlinePlanId),
    );

    expect(repository.getPlanCalls, 1);
    expect(find.text('Algorithms exam'), findsOneWidget);
    expect(find.textContaining('2026-07-20 · 10:00'), findsOneWidget);
  });

  testWidgets('deep-linked plan is immediately visible before supporting load',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [_plan()]),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: const DeadlinePlansPage(initialPlanId: deadlinePlanId),
      size: const Size(1200, 700),
    );

    expect(find.text('Algorithms exam').hitTestable(), findsOneWidget);
  });

  testWidgets('deep-linked replan opens review without changing reservations',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [_plan()]),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: const DeadlinePlansPage(
        initialPlanId: deadlinePlanId,
        openInitialReplan: true,
      ),
    );

    expect(find.text('Replan remaining preparation'), findsOneWidget);
    expect(
      find.text('Create preview with these values'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('deadline-plan-title')), findsNothing);
    expect(repository.proposalDrafts, isEmpty);

    await _tap(tester, find.text('Change values'));
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('deadline-plan-title')), findsOneWidget);
    expect(repository.proposalDrafts, isEmpty);
  });

  for (final kind in DeadlinePlanKind.values) {
    final label = kind == DeadlinePlanKind.exam ? 'Exam' : 'Assignment';
    final expectedDailyCap = kind == DeadlinePlanKind.exam ? 120 : 275;
    testWidgets(
        'existing $label stays root-kind locked in edit and deep-link replan',
        (tester) async {
      final plan = _planWithKind(kind, maxDailyMinutes: expectedDailyCap);
      final repository = _FakeDeadlinePlanRepository(
        feeds: [
          DeadlinePlanFeed(plans: [plan]),
        ],
      );
      await _pumpPage(
        tester,
        repository: repository,
        page: DeadlinePlansPage(currentTime: now),
      );

      await _tapPlanAction(tester, 'Adjust estimate or plan');
      await _tap(tester, find.text('Change values'));
      var locked = find.byKey(const ValueKey('deadline-locked-kind'));
      expect(locked, findsOneWidget);
      expect(
        find.descendant(of: locked, matching: find.text(label)),
        findsOneWidget,
      );
      expect(find.byType(SegmentedButton<DeadlinePlanKind>), findsNothing);

      await _tap(tester, find.text('Continue'));
      await _tap(tester, find.text('Continue'));
      final dailyCap = tester.widget<TextField>(
        find.byKey(const ValueKey('deadline-daily-cap')),
      );
      expect(dailyCap.controller!.text, '$expectedDailyCap');
      await _tap(tester, find.text('Create preview'));
      expect(repository.proposalDrafts.single.kind, kind);

      await _pumpPage(
        tester,
        repository: _FakeDeadlinePlanRepository(
          feeds: [
            DeadlinePlanFeed(plans: [plan]),
          ],
        ),
        page: DeadlinePlansPage(
          initialPlanId: deadlinePlanId,
          openInitialReplan: true,
          currentTime: now,
        ),
      );
      await _tap(tester, find.text('Change values'));
      locked = find.byKey(const ValueKey('deadline-locked-kind'));
      expect(locked, findsOneWidget);
      expect(
        find.descendant(of: locked, matching: find.text(label)),
        findsOneWidget,
      );
      expect(find.byType(SegmentedButton<DeadlinePlanKind>), findsNothing);
    });
  }

  testWidgets('focused replan isolates one plan and keeps preview staged',
      (tester) async {
    const otherPlanId = '55555555-5555-4555-8555-555555555555';
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(
          plans: [
            _plan(),
            _planWithIdentity(
              id: otherPlanId,
              title: 'Hidden history assignment',
            ),
          ],
        ),
      ],
      proposalResults: [_plan(pending: true)],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(
        initialPlanId: deadlinePlanId,
        openInitialReplan: true,
        focusedReplan: true,
        currentTime: now,
      ),
    );

    expect(find.text('Replan preparation'), findsOneWidget);
    expect(find.text('Hidden history assignment'), findsNothing);
    expect(find.text('Plan preparation'), findsNothing);
    expect(find.text('Replan remaining preparation'), findsOneWidget);
    expect(repository.proposalDrafts, isEmpty);

    await _tap(tester, find.text('Create preview with these values'));
    expect(repository.proposalDrafts, hasLength(1));
    expect(repository.confirmCalls, 0);
    expect(
      find.text('Currently reserved until you confirm'),
      findsOneWidget,
    );
    expect(
      find.text('Confirm reservations and return to Planner'),
      findsOneWidget,
    );
  });

  testWidgets('focused replan gives terminal plans an inline return path',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [_plan(status: 'completed')]),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: const DeadlinePlansPage(
        initialPlanId: deadlinePlanId,
        openInitialReplan: true,
        focusedReplan: true,
      ),
    );

    expect(find.text('This plan can no longer be replanned'), findsOneWidget);
    expect(find.text('Return to Planner'), findsOneWidget);
    expect(find.text('Replan remaining preparation'), findsNothing);
  });

  testWidgets('focused confirmation returns to Planner after explicit confirm',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [_plan()]),
      ],
      proposalResults: [_plan(pending: true)],
      confirmResult: _plan(),
    );
    final router = GoRouter(
      initialLocation: AppRoutes.planner,
      routes: [
        GoRoute(
          path: AppRoutes.planner,
          builder: (context, state) => Scaffold(
            body: FilledButton(
              onPressed: () => context.push(
                '${AppRoutes.plannerReplan}?plan_id=$deadlinePlanId',
              ),
              child: const Text('Begin focused replan'),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.plannerReplan,
          builder: (context, state) => DeadlinePlansPage(
            initialPlanId: state.uri.queryParameters['plan_id'],
            openInitialReplan: true,
            focusedReplan: true,
            currentTime: now,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseSyncedExecution: true,
              canUseDeadlinePlanner: true,
            ),
          ),
          profileLocalDateSourceProvider.overrideWithValue(
            const SessionProfileLocalDateSource(session: null),
          ),
          deadlinePlanRepositoryProvider.overrideWithValue(repository),
          assignmentSeriesRepositoryProvider.overrideWithValue(
            _FakeAssignmentSeriesRepository(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await _tap(tester, find.text('Begin focused replan'));
    await _tap(tester, find.text('Create preview with these values'));
    await _tap(
      tester,
      find.text('Confirm reservations and return to Planner').first,
    );
    await _tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Confirm reservations and return to Planner'),
      ),
    );

    expect(repository.proposalDrafts, hasLength(1));
    expect(repository.confirmCalls, 1);
    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutes.planner,
    );
    expect(find.text('Begin focused replan'), findsOneWidget);
  });

  testWidgets('replan editor blocks shell navigation and cancel stays on page',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [_plan()]),
      ],
    );
    final router = GoRouter(
      initialLocation: '/insights',
      routes: [
        ShellRoute(
          builder: (context, state, child) => Scaffold(
            body: child,
            bottomNavigationBar: TextButton(
              onPressed: () => context.go('/insights'),
              child: const Text('Shell Insights'),
            ),
          ),
          routes: [
            GoRoute(
              path: '/insights',
              builder: (context, state) => const Text('Insights route'),
            ),
            GoRoute(
              path: '/preparation-plans',
              builder: (context, state) => DeadlinePlansPage(
                currentTime: now,
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseSyncedExecution: true,
              canUseDeadlinePlanner: true,
            ),
          ),
          profileLocalDateSourceProvider.overrideWithValue(
            const SessionProfileLocalDateSource(session: null),
          ),
          deadlinePlanRepositoryProvider.overrideWithValue(repository),
          assignmentSeriesRepositoryProvider.overrideWithValue(
            _FakeAssignmentSeriesRepository(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go('/preparation-plans');
    await tester.pumpAndSettle();
    await _tapPlanAction(tester, 'Adjust estimate or plan');
    expect(find.text('Replan remaining preparation'), findsOneWidget);

    await tester.tap(find.text('Shell Insights'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/preparation-plans',
    );
    expect(find.text('Preparation plans'), findsOneWidget);
    expect(find.text('Replan remaining preparation'), findsOneWidget);

    await _tap(tester, find.text('Change values'));
    expect(find.text('Adjust preparation plan'), findsOneWidget);

    await _tap(tester, find.text('Cancel'));
    expect(
      router.routeInformationProvider.value.uri.path,
      '/preparation-plans',
    );
    expect(find.text('Preparation plans'), findsOneWidget);
  });

  testWidgets('failed targeted plan read stays account-scoped and retryable',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      targetedError: StateError('other owner'),
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: const DeadlinePlansPage(initialPlanId: deadlinePlanId),
    );

    expect(
      find.text('Requested preparation plan unavailable'),
      findsOneWidget,
    );
    expect(
      find.textContaining('may not belong to the signed-in user'),
      findsOneWidget,
    );
    expect(find.text('Retry requested plan'), findsOneWidget);
  });

  testWidgets('narrow high-text-scale wizard does not overflow',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository();
    await _pumpPage(
      tester,
      repository: repository,
      size: const Size(320, 700),
      textScaler: const TextScaler.linear(2),
      page: DeadlinePlansPage(
        initialTitle: 'Algorithms exam',
        initialDeadlineAt: DateTime(2026, 7, 18, 18),
        currentTime: now,
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Plan preparation'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan preparation'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('preparation-kind-dialog')),
      findsOneWidget,
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('preparation-kind-exam')),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Step 1 of 3'), findsOneWidget);
  });

  testWidgets('narrow high-text-scale replan summary does not overflow',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [_plan()]),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      size: const Size(320, 700),
      textScaler: const TextScaler.linear(2),
      page: DeadlinePlansPage(currentTime: now),
    );
    await _tapPlanAction(tester, 'Adjust estimate or plan');

    expect(tester.takeException(), isNull);
    expect(find.text('Replan remaining preparation'), findsOneWidget);
    expect(repository.proposalDrafts, isEmpty);

    await _tap(tester, find.text('Change values'));
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('deadline-locked-kind')),
      findsOneWidget,
    );
    expect(find.byType(SegmentedButton<DeadlinePlanKind>), findsNothing);
  });
}

const deadlineCalendarEventId = '88888888-8888-4888-8888-888888888888';

Future<void> _completeNewWizard(WidgetTester tester) async {
  await _tap(tester, find.text('Plan preparation'));
  await _tap(tester, find.text('Exam'));
  await _tap(tester, find.text('Continue'));
  await _tap(tester, find.byKey(const ValueKey('deadline-estimate-5h')));
  await _tap(tester, find.text('Continue'));
  expect(find.text('0 clear days'), findsWidgets);
  await _tap(tester, find.text('Create preview'));
}

Future<void> _submitExistingWizard(WidgetTester tester) async {
  await _tapPlanAction(tester, 'Adjust estimate or plan');
  await _tap(tester, find.text('Create preview with these values'));
}

Future<void> _expandPlan(WidgetTester tester) async {
  if (find.textContaining('Finish by').evaluate().isNotEmpty) {
    return;
  }
  final toggle = find.byKey(
    const ValueKey('deadline-toggle-plan-$deadlinePlanId'),
  );
  if (toggle.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      toggle,
      500,
      scrollable: _pageScrollable(),
    );
    await tester.pumpAndSettle();
  }
  if (toggle.evaluate().isNotEmpty) {
    await _tap(tester, toggle);
  }
}

Future<void> _tapPlanAction(WidgetTester tester, String label) async {
  final action = find.text(label);
  if (action.evaluate().isEmpty) {
    await _expandPlan(tester);
  }
  await _tap(tester, action);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Finder _pageScrollable() => find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeDeadlinePlanRepository repository,
  required DeadlinePlansPage page,
  DeadlineCalendarPrefillDataSource? prefillDataSource,
  AppSurfaceCapabilities capabilities = const AppSurfaceCapabilities(
    isLocalDemo: false,
    canUseSyncedHabits: true,
    canUseSyncedExecution: true,
    canUseDeadlinePlanner: true,
  ),
  Size size = const Size(1200, 1800),
  TextScaler textScaler = TextScaler.noScaling,
  bool settle = true,
  ProfileLocalDateSource profileDateSource =
      const SessionProfileLocalDateSource(session: null),
  SnapshotRefreshService? snapshotRefresh,
  AssignmentSeriesRepository? assignmentSeriesRepository,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSurfaceCapabilitiesProvider.overrideWithValue(capabilities),
        profileLocalDateSourceProvider.overrideWithValue(profileDateSource),
        deadlinePlanRepositoryProvider.overrideWithValue(repository),
        assignmentSeriesRepositoryProvider.overrideWithValue(
          assignmentSeriesRepository ?? _FakeAssignmentSeriesRepository(),
        ),
        if (snapshotRefresh != null)
          snapshotRefreshServiceProvider.overrideWithValue(snapshotRefresh),
        if (prefillDataSource != null)
          deadlineCalendarPrefillDataSourceProvider.overrideWithValue(
            prefillDataSource,
          ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: Scaffold(body: page),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

class _FakeAssignmentSeriesRepository implements AssignmentSeriesRepository {
  _FakeAssignmentSeriesRepository({
    this.series = const [],
    this.proposalResult,
    List<Object>? proposalErrors,
  }) : proposalErrors = [...?proposalErrors];

  final List<AssignmentSeries> series;
  final AssignmentSeries? proposalResult;
  final List<Object> proposalErrors;
  final List<AssignmentSeriesProposalDraft> proposalDrafts = [];

  @override
  Future<AssignmentSeriesFeed> getSeries() async =>
      AssignmentSeriesFeed(series);

  @override
  Future<AssignmentSeries> propose({
    required String requestId,
    required AssignmentSeriesProposalDraft draft,
  }) async {
    proposalDrafts.add(draft);
    if (proposalErrors.isNotEmpty) throw proposalErrors.removeAt(0);
    if (proposalResult case final result?) return result;
    if (series.isNotEmpty) return series.first;
    throw StateError('Missing assignment series proposal result');
  }

  @override
  Future<AssignmentSeries> confirm({
    required String seriesId,
    required String requestId,
    required int expectedRevision,
  }) =>
      throw UnimplementedError();

  @override
  Future<AssignmentSeries> cancelFuture({
    required String seriesId,
    required String requestId,
    required int expectedRevision,
  }) =>
      throw UnimplementedError();
}

class _RecordingSnapshotRefresh implements SnapshotRefreshService {
  final List<String> taskTargetDates = [];

  @override
  Future<void> refreshDailyAfterUserSignal({String? targetDate}) async {
    if (targetDate != null) taskTargetDates.add(targetDate);
  }
}

DeadlinePlan _plan({String status = 'active', bool pending = false}) =>
    DeadlinePlanResponse.fromJson(
      deadlinePlanEnvelope(status: status, pending: pending),
    ).plan;

DeadlinePlan _planWithKind(
  DeadlinePlanKind kind, {
  int maxDailyMinutes = 120,
}) {
  final json = deadlinePlanEnvelope();
  (json['plan'] as Map<String, dynamic>)['kind'] = kind.code;
  for (final key in ['active_revision', 'pending_revision']) {
    final revision = json[key];
    if (revision is Map<String, dynamic>) {
      revision
        ..['kind'] = kind.code
        ..['max_daily_minutes'] = maxDailyMinutes;
    }
  }
  return DeadlinePlanResponse.fromJson(json).plan;
}

DeadlinePlan _planWithIdentity({
  required String id,
  required String title,
  String status = 'active',
  DeadlinePlanKind kind = DeadlinePlanKind.exam,
}) {
  final json = deadlinePlanEnvelope(status: status, activeTitle: title);
  final record = json['plan'] as Map<String, dynamic>;
  record
    ..['id'] = id
    ..['kind'] = kind.code;
  if (record.containsKey('managed_task_id')) {
    record['managed_task_id'] = id;
  }
  for (final key in ['active_revision', 'pending_revision']) {
    final revision = json[key];
    if (revision is Map<String, dynamic>) {
      revision
        ..['plan_id'] = id
        ..['kind'] = kind.code;
    }
  }
  return DeadlinePlanResponse.fromJson(json).plan;
}

DeadlinePlan _planWithDeadline(String deadlineAt) {
  final json = deadlinePlanEnvelope();
  final revision = json['active_revision'] as Map<String, dynamic>;
  revision['deadline_at'] = deadlineAt;
  return DeadlinePlanResponse.fromJson(json).plan;
}

DeadlinePlan _missedPlan() {
  final json = deadlinePlanEnvelope();
  final revision = json['active_revision'] as Map<String, dynamic>;
  revision['blocks'] = [deadlineBlock(state: 'missed')];
  return DeadlinePlanResponse.fromJson(json).plan;
}

DeadlinePlan _pendingPlanWithMissedActiveBlock() {
  final json = deadlinePlanEnvelope(pending: true);
  final revision = json['active_revision'] as Map<String, dynamic>;
  revision['blocks'] = [deadlineBlock(state: 'missed')];
  return DeadlinePlanResponse.fromJson(json).plan;
}

DeadlinePlan _learnedPendingPlan({bool fellBackToSetup = false}) {
  final json = deadlinePlanEnvelope(pending: true);
  final revision = json['pending_revision'] as Map<String, dynamic>;
  revision['timing_preference'] = {
    'source': 'learned_personal_pattern',
    'window': '09-13',
    'evidence_count': 24,
    'evidence_starts_on': '2026-06-01',
    'evidence_ends_on': '2026-07-20',
    'evidence_fingerprint': List.filled(64, 'b').join(),
    'fell_back_to_setup': fellBackToSetup,
    'warning': null,
  };
  return DeadlinePlanResponse.fromJson(json).plan;
}

DeadlinePlan _planWithEightBlocks() {
  final json = deadlinePlanEnvelope();
  final plan = json['plan'] as Map<String, dynamic>;
  plan
    ..['original_estimated_total_minutes'] = 500
    ..['original_credited_prior_minutes'] = 50;
  final revision = json['active_revision'] as Map<String, dynamic>;
  revision
    ..['estimated_total_minutes'] = 500
    ..['credited_prior_minutes'] = 50
    ..['tracked_focus_minutes_at_proposal'] = 50
    ..['remaining_minutes_at_proposal'] = 400
    ..['planned_minutes'] = 400
    ..['unscheduled_minutes'] = 0
    ..['blocks'] = [
      for (var sequence = 1; sequence <= 8; sequence++)
        deadlineBlock(
          id: '${sequence.toString().padLeft(8, '0')}-0000-4000-8000-${sequence.toString().padLeft(12, '0')}',
          sequence: sequence,
        ),
    ];
  final progress = json['progress'] as Map<String, dynamic>;
  progress
    ..['estimated_total_minutes'] = 500
    ..['credited_prior_minutes'] = 50
    ..['tracked_focus_minutes'] = 50
    ..['accounted_minutes'] = 100
    ..['remaining_minutes'] = 400;
  return DeadlinePlanResponse.fromJson(json).plan;
}

DeadlinePlan _calendarPlan(DeadlinePlanSourceStatus status) {
  final json = deadlinePlanEnvelope();
  final revision = json['active_revision'] as Map<String, dynamic>;
  revision
    ..['source_kind'] = 'calendar_event'
    ..['source_calendar_event_id'] = deadlineCalendarEventId
    ..['source_calendar_event_fingerprint'] = deadlineFingerprint
    ..['source_status'] = status.code;
  return DeadlinePlanResponse.fromJson(json).plan;
}

AppException _conflict(String detail) {
  return AppException(
    'Network request failed',
    cause: ApiFailure(
      kind: ApiFailureKind.response,
      statusCode: 409,
      responseData: {'detail': detail},
    ),
  );
}

class _FakeDeadlinePlanRepository implements DeadlinePlanRepository {
  _FakeDeadlinePlanRepository({
    List<DeadlinePlanFeed>? feeds,
    List<DeadlinePlan>? proposalResults,
    List<Object>? proposalErrors,
    this.confirmResult,
    this.completeError,
    this.targetedPlan,
    this.targetedError,
  })  : feeds = feeds ?? [DeadlinePlanFeed(plans: const [])],
        proposalResults = [...?proposalResults],
        proposalErrors = [...?proposalErrors];

  final List<DeadlinePlanFeed> feeds;
  final List<DeadlinePlan> proposalResults;
  final List<Object> proposalErrors;
  final DeadlinePlan? confirmResult;
  final Object? completeError;
  final DeadlinePlan? targetedPlan;
  final Object? targetedError;
  final List<DeadlinePlanProposalDraft> proposalDrafts = [];
  final List<String> proposalRequestIds = [];
  int feedCalls = 0;
  int confirmCalls = 0;
  int getPlanCalls = 0;

  @override
  Future<PreparationWorkload> getWorkload() async => _workload();

  @override
  Future<PreparationWorkloadDetail> getWorkloadDetail(String localDate) async {
    return PreparationWorkloadDetail.fromJson(
      preparationWorkloadDetailEnvelope(),
    );
  }

  @override
  Future<DeadlinePlanFeed> getPlans() async {
    final index = feedCalls.clamp(0, feeds.length - 1);
    feedCalls++;
    return feeds[index];
  }

  @override
  Future<DeadlinePlan> getPlan(String planId) async {
    getPlanCalls++;
    if (targetedError case final error?) throw error;
    return targetedPlan ?? (throw StateError('Missing targeted plan'));
  }

  @override
  Future<DeadlinePlan> propose({
    required String requestId,
    required DeadlinePlanProposalDraft draft,
  }) async {
    proposalRequestIds.add(requestId);
    proposalDrafts.add(draft);
    if (proposalErrors.isNotEmpty) throw proposalErrors.removeAt(0);
    if (proposalResults.isNotEmpty) return proposalResults.removeAt(0);
    return _plan(status: 'draft');
  }

  @override
  Future<DeadlinePlan> confirm({
    required String planId,
    required String requestId,
    required int expectedRevision,
  }) async {
    confirmCalls++;
    return confirmResult ?? _plan();
  }

  @override
  Future<DeadlinePlan> complete({
    required String planId,
    required String requestId,
    required int expectedRevision,
  }) async {
    if (completeError case final error?) throw error;
    return _plan(status: 'completed');
  }

  @override
  Future<DeadlinePlan> cancel({
    required String planId,
    required String requestId,
    required int expectedRevision,
  }) async =>
      _plan(status: 'cancelled');
}

PreparationWorkload _workload({int? budget = 120}) => PreparationWorkload(
      generatedAt: DateTime.parse('2026-07-18T08:00:00Z'),
      timezone: 'Europe/Berlin',
      dailyPreparationBudgetMinutes: budget,
      days: [
        for (var day = 0; day < 7; day++)
          PreparationWorkloadDay(
            localDate: DateTime(2026, 7, 18 + day),
            reservedPreparationMinutes: day == 0 ? 50 : 0,
            remainingBudgetMinutes:
                budget == null ? null : budget - (day == 0 ? 50 : 0),
            overBudgetMinutes: 0,
            activePlanCount: day == 0 ? 1 : 0,
            fixedCommitmentMinutes: day == 0 ? 90 : 0,
          ),
      ],
    );

class _FakeCalendarPrefillDataSource
    implements DeadlineCalendarPrefillDataSource {
  _FakeCalendarPrefillDataSource({
    required this.result,
    this.errorsRemaining = 0,
    this.completer,
  });

  final DeadlineCalendarPrefill result;
  int errorsRemaining;
  final Completer<DeadlineCalendarPrefill>? completer;
  int calls = 0;

  @override
  Future<DeadlineCalendarPrefill> getEvent(String eventId) async {
    calls++;
    if (errorsRemaining > 0) {
      errorsRemaining--;
      throw StateError('prefill unavailable');
    }
    return completer?.future ?? result;
  }
}
