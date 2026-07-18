import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/features/deadline_plans/data/deadline_calendar_prefill_data_source.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_calendar_prefill.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_plan.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_plan_repository.dart';
import 'package:my_life_graph/features/deadline_plans/presentation/pages/deadline_plans_page.dart';
import 'package:my_life_graph/features/deadline_plans/presentation/providers/deadline_plan_providers.dart';

import 'support/deadline_plan_fixtures.dart';

void main() {
  final now = DateTime(2026, 7, 18, 10);

  testWidgets('wizard requires an explicit estimate and started answer',
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
    expect(find.text('Step 2 of 3'), findsOneWidget);
    await _tap(tester, find.text('No additional prior work'));
    await _tap(tester, find.text('Continue'));
    expect(find.text('Step 3 of 3'), findsOneWidget);
    expect(
      find.text('Maximum preparation minutes per day for this plan'),
      findsOneWidget,
    );
    expect(find.textContaining('there is no background sync'), findsOneWidget);
  });

  testWidgets('three-step same-day preview needs explicit confirmation',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      proposalResults: [_plan(status: 'draft')],
      confirmResult: _plan(),
    );
    await _pumpPage(
      tester,
      repository: repository,
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

    await _tap(tester, find.text('Adjust estimate or plan'));
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
      findsOneWidget,
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

    expect(
      find.textContaining('Rule-based windows: prefers 08:00–13:00'),
      findsOneWidget,
    );
    expect(find.text('Entered prior credit'), findsOneWidget);
    expect(
      find.textContaining('Linked Focus completed after this plan'),
      findsOneWidget,
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

    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.text('Algorithms exam'), findsWidgets);
  });

  testWidgets('replanning normalizes a saved past start to today',
      (tester) async {
    final repository = _FakeDeadlinePlanRepository(
      feeds: [
        DeadlinePlanFeed(plans: [_plan()]),
      ],
    );
    await _pumpPage(
      tester,
      repository: repository,
      page: DeadlinePlansPage(currentTime: DateTime(2026, 7, 22, 10)),
    );

    await _tap(tester, find.text('Adjust estimate or plan'));
    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.text('Continue'));

    expect(find.text('Start planning Jul 22, 2026'), findsOneWidget);
    expect(find.text('Clear days before finish-by date'), findsOneWidget);
    expect(
      find.textContaining('saved start in the past moves to today'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Create preview'));

    expect(repository.proposalDrafts.single.planningStartOn, '2026-07-22');
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

    expect(find.textContaining('2026-07-20 · 10:00'), findsNothing);
    await _tap(tester, find.text('Show history details'));
    expect(find.textContaining('2026-07-20 · 10:00'), findsOneWidget);
    expect(find.text('Hide history details'), findsOneWidget);
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
    expect(find.text('Entered plan values kept'), findsOneWidget);
    await _tap(tester, find.text('Review entered values'));
    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.text('Create preview'));

    expect(repository.proposalDrafts, hasLength(2));
    expect(repository.proposalDrafts.last.baseRevision, 2);
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
      page: const DeadlinePlansPage(
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
    expect(find.text('Show history details'), findsOneWidget);
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
    expect(find.text('Step 1 of 3'), findsOneWidget);
  });
}

const deadlineCalendarEventId = '88888888-8888-4888-8888-888888888888';

Future<void> _completeNewWizard(WidgetTester tester) async {
  await _tap(tester, find.text('Plan preparation'));
  await _tap(tester, find.text('Exam'));
  await _tap(tester, find.text('Continue'));
  await _tap(tester, find.byKey(const ValueKey('deadline-estimate-5h')));
  await _tap(tester, find.text('No additional prior work'));
  await _tap(tester, find.text('Continue'));
  expect(find.text('0 clear days'), findsWidgets);
  await _tap(tester, find.text('Create preview'));
}

Future<void> _submitExistingWizard(WidgetTester tester) async {
  await _tap(tester, find.text('Adjust estimate or plan'));
  await _tap(tester, find.text('Continue'));
  await _tap(tester, find.text('Continue'));
  await _tap(tester, find.text('Create preview'));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

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
        deadlinePlanRepositoryProvider.overrideWithValue(repository),
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

DeadlinePlan _plan({String status = 'active', bool pending = false}) =>
    DeadlinePlanResponse.fromJson(
      deadlinePlanEnvelope(status: status, pending: pending),
    ).plan;

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
  final options = RequestOptions(path: '/v1/deadline-plans/proposals');
  return AppException(
    'Network request failed',
    cause: DioException(
      requestOptions: options,
      response: Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 409,
        data: {'detail': detail},
      ),
    ),
  );
}

class _FakeDeadlinePlanRepository implements DeadlinePlanRepository {
  _FakeDeadlinePlanRepository({
    List<DeadlinePlanFeed>? feeds,
    List<DeadlinePlan>? proposalResults,
    List<Object>? proposalErrors,
    this.confirmResult,
    this.targetedPlan,
    this.targetedError,
  })  : feeds = feeds ?? [DeadlinePlanFeed(plans: const [])],
        proposalResults = [...?proposalResults],
        proposalErrors = [...?proposalErrors];

  final List<DeadlinePlanFeed> feeds;
  final List<DeadlinePlan> proposalResults;
  final List<Object> proposalErrors;
  final DeadlinePlan? confirmResult;
  final DeadlinePlan? targetedPlan;
  final Object? targetedError;
  final List<DeadlinePlanProposalDraft> proposalDrafts = [];
  final List<String> proposalRequestIds = [];
  int feedCalls = 0;
  int confirmCalls = 0;
  int getPlanCalls = 0;

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
  }) async =>
      _plan(status: 'completed');

  @override
  Future<DeadlinePlan> cancel({
    required String planId,
    required String requestId,
    required int expectedRevision,
  }) async =>
      _plan(status: 'cancelled');
}

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
