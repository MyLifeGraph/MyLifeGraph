import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/deadline_plans/domain/exam_week_outlook.dart';
import 'package:my_life_graph/features/deadline_plans/presentation/providers/deadline_plan_providers.dart';
import 'package:my_life_graph/features/planner/application/planner_controller.dart';
import 'package:my_life_graph/features/planner/data/planner_api_data_source.dart';
import 'package:my_life_graph/features/planner/presentation/pages/planner_page.dart';
import 'package:my_life_graph/features/planner/presentation/providers/planner_providers.dart';

import 'support/planner_fixtures.dart';

void main() {
  testWidgets('guest Planner stays honestly locked and makes no request',
      (tester) async {
    final backend = _PlannerBackend();

    await _pumpPlanner(
      tester,
      backend: backend,
      capabilities: const AppSurfaceCapabilities(
        isLocalDemo: true,
        canUseSyncedHabits: false,
      ),
    );

    expect(find.text('Synced Planner unavailable'), findsOneWidget);
    expect(find.byKey(const ValueKey('planner-locked')), findsOneWidget);
    expect(find.byKey(const ValueKey('planner-add-new')), findsNothing);
    expect(backend.requests, isEmpty);
  });

  testWidgets('Planner renders the agreed sections and all five create flows',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend();

    await _pumpPlanner(tester, backend: backend);

    const sectionKeys = [
      'planner-add-new',
      'planner-needs-attention',
      'planner-seven-days',
      'planner-ongoing-preparation',
      'planner-unscheduled',
      'planner-history',
    ];
    final sectionTops = [
      for (final key in sectionKeys)
        tester.getTopLeft(find.byKey(ValueKey(key))).dy,
    ];
    expect(sectionTops, orderedEquals(sectionTops.toList()..sort()));

    for (final key in const [
      'planner-add-task',
      'planner-add-habit',
      'planner-add-exam',
      'planner-add-assignment',
      'planner-add-commitment',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('planner-availability-warning')),
      findsNothing,
    );
    for (final label in const [
      'Setup commitment',
      'Task',
      'Habit',
      'Fixed commitment',
      'Preparation',
      'Calendar',
    ]) {
      expect(find.textContaining(label), findsWidgets);
    }
    expect(find.text('Tuesday, Jul 21'), findsOneWidget);
    expect(find.text('Monday, Jul 27'), findsOneWidget);
    expect(find.textContaining('2 h 30 min remaining · next'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('automatic planning warns when no availability source is set',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(incompleteAvailability: true);

    await _pumpPlanner(tester, backend: backend);

    expect(
      find.byKey(const ValueKey('planner-availability-warning')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Calendar import stays optional.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('planner-add-exam')));
    await tester.pumpAndSettle();

    expect(find.text('Review your availability'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('planner-continue-without-availability')),
      findsOneWidget,
    );
    expect(
      backend.requests.where((request) => request.path.endsWith('/proposals')),
      isEmpty,
    );
  });

  testWidgets('Task proposal remains a preview until explicit confirmation',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend();

    await _pumpPlanner(tester, backend: backend);
    await tester.tap(find.byKey(const ValueKey('planner-add-task')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('planner-task-title')),
      'Read sources',
    );
    await tester.tap(find.byKey(const ValueKey('planner-task-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Review plan preview'), findsOneWidget);
    expect(find.textContaining('No time is reserved'), findsOneWidget);
    expect(
      backend.requests.where((request) => request.path.endsWith('/proposals')),
      hasLength(1),
    );
    expect(
      backend.requests.where((request) => request.path.endsWith('/confirm')),
      isEmpty,
    );

    await tester.tap(find.byKey(const ValueKey('planner-confirm-plan')));
    await tester.pumpAndSettle();

    expect(find.text('Saved under Unscheduled.'), findsOneWidget);
    expect(
      backend.requests.where((request) => request.path.endsWith('/confirm')),
      hasLength(1),
    );
    final proposal = backend.requests
        .firstWhere((request) => request.path.endsWith('/proposals'))
        .data as Map<String, dynamic>;
    final target = proposal['target'] as Map<String, dynamic>;
    expect(target['title'], 'Read sources');
    expect(target['estimated_minutes'], isNull);
    expect(target['deadline_at'], isNull);
    expect(target['preferred_session_minutes'], isNull);
  });

  testWidgets('Task preview explains learned timing evidence', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(learnedTiming: true);

    await _pumpPlanner(tester, backend: backend);
    await tester.tap(find.byKey(const ValueKey('planner-add-task')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('planner-task-title')),
      'Read sources',
    );
    await tester.tap(find.byKey(const ValueKey('planner-task-preview')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('planner-learned-timing-applied')),
      findsOneWidget,
    );
    expect(
      find.text('Learned timing applied · 24 rated sessions'),
      findsOneWidget,
    );
  });

  testWidgets('Task preview labels an actual Setup timing fallback',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(
      learnedTiming: true,
      learnedTimingFallback: true,
    );

    await _pumpPlanner(tester, backend: backend);
    await tester.tap(find.byKey(const ValueKey('planner-add-task')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('planner-task-title')),
      'Read sources',
    );
    await tester.tap(find.byKey(const ValueKey('planner-task-preview')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Learned timing considered · Setup fallback · 24 rated sessions',
      ),
      findsOneWidget,
    );
  });

  testWidgets('failed proposal retains the exact entered Task draft',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(failNextProposal: true);

    await _pumpPlanner(tester, backend: backend);
    await tester.tap(find.byKey(const ValueKey('planner-add-task')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('planner-task-title')),
      'Keep this exact title',
    );
    await tester.tap(find.byKey(const ValueKey('planner-task-preview')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Planner could not save that change. Your entered values are retained.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('planner-add-task')));
    await tester.pumpAndSettle();
    final title = tester.widget<TextField>(
      find.byKey(const ValueKey('planner-task-title')),
    );
    expect(title.controller?.text, 'Keep this exact title');
  });

  testWidgets('Unscheduled Task edits use target identity and version',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend();

    await _pumpPlanner(tester, backend: backend);
    await tester.scrollUntilVisible(find.text('Undated reading'), 400);
    await tester.tap(find.text('Undated reading'));
    await tester.pumpAndSettle();

    final title = tester.widget<TextField>(
      find.byKey(const ValueKey('planner-task-title')),
    );
    expect(title.controller?.text, 'Undated reading');
    await tester.tap(find.byKey(const ValueKey('planner-task-preview')));
    await tester.pumpAndSettle();

    final proposal = backend.requests
        .lastWhere((request) => request.path.endsWith('/proposals'))
        .data as Map<String, dynamic>;
    final target = proposal['target'] as Map<String, dynamic>;
    expect(target['operation'], 'update');
    expect(
      target['target_id'],
      '80000000-0000-4000-8000-000000000001',
    );
    expect(target['expected_updated_at'], '2026-07-20T08:00:00.000Z');
  });

  testWidgets('Planner remains usable at 320 pixels and 200 percent text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    await _pumpPlanner(
      tester,
      backend: _PlannerBackend(),
      textScale: 2,
    );

    expect(find.bySemanticsLabel('Task'), findsWidgets);
    expect(find.bySemanticsLabel('Habit'), findsWidgets);
    expect(find.bySemanticsLabel('Fixed commitment'), findsWidgets);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('exam outlook exposes loading and honest error states',
      (tester) async {
    final pending = Completer<ExamWeekOutlook?>();
    await _pumpPlanner(
      tester,
      backend: _PlannerBackend(),
      outlookLoader: () => pending.future,
      settle: false,
    );
    expect(
      find.byKey(const ValueKey('planner-exam-week-outlook-loading')),
      findsOneWidget,
    );
    pending.complete();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await _pumpPlanner(
      tester,
      backend: _PlannerBackend(),
      outlookLoader: () => Future<ExamWeekOutlook?>.error(StateError('read')),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('planner-exam-week-outlook-error')),
      300,
    );
    expect(
      find.byKey(const ValueKey('planner-exam-week-outlook-error')),
      findsOneWidget,
    );
    expect(
      find.textContaining('No status was inferred'),
      findsOneWidget,
    );
  });

  for (final mode in const ['watch', 'exam_week', 'overdue']) {
    testWidgets('Planner renders $mode outlook before Needs attention',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpPlanner(
        tester,
        backend: _PlannerBackend(),
        outlookLoader: () async => _outlook(mode: mode),
      );

      final key = ValueKey('planner-exam-week-outlook-$mode');
      expect(find.byKey(key), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(key)).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('planner-needs-attention')))
              .dy,
        ),
      );
      expect(find.text('Review plan'), findsOneWidget);
      expect(find.text('Replan remaining time'), findsOneWidget);
      expect(
        find.textContaining('Read-only outlook'),
        findsOneWidget,
      );
    });
  }

  testWidgets('unknown exam-week capacity stays explicit at narrow large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpPlanner(
      tester,
      backend: _PlannerBackend(),
      textScale: 2,
      outlookLoader: () async => _outlook(
        mode: 'exam_week',
        risk: 'unknown',
        capacity: 'unknown',
        includeSleepPlan: false,
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('planner-exam-week-outlook-exam_week')),
      300,
    );

    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('Capacity is incomplete'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('exam-outlook-evening-check-in')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPlanner(
  WidgetTester tester, {
  required _PlannerBackend backend,
  AppSurfaceCapabilities capabilities = const AppSurfaceCapabilities(
    isLocalDemo: false,
    canUseSyncedHabits: true,
    canUseSyncedExecution: true,
    canUseDeadlinePlanner: true,
  ),
  double textScale = 1,
  Future<ExamWeekOutlook?> Function()? outlookLoader,
  bool settle = true,
}) async {
  final controller = PlannerController(
    api: PlannerApiDataSource(ApiClient(backend.dio)),
    accessTokenProvider: () => 'test-token',
    canUseSyncedPlanner: capabilities.canUseSyncedExecution,
    isBackendConfigured: true,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSurfaceCapabilitiesProvider.overrideWithValue(capabilities),
        plannerControllerProvider.overrideWith((ref) => controller),
        examWeekOutlookProvider.overrideWith(
          (ref) => (outlookLoader ?? () async => null)(),
        ),
      ],
      child: MaterialApp(
        home: const Scaffold(body: PlannerPage()),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
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

class _PlannerRequest {
  const _PlannerRequest(this.method, this.path, this.data);

  final String method;
  final String path;
  final Object? data;
}

class _PlannerBackend {
  _PlannerBackend({
    this.failNextProposal = false,
    this.incompleteAvailability = false,
    this.learnedTiming = false,
    this.learnedTimingFallback = false,
  }) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests
              .add(_PlannerRequest(options.method, options.path, options.data));
          if (options.path == '/v1/planner/overview') {
            final overview = plannerOverviewEnvelope();
            if (incompleteAvailability) {
              overview['commitments'] = <dynamic>[];
              overview['preferences'] = {
                'contract_version': 'planner-preferences-v1',
                'origin': 'authenticated_backend',
                'use_calendar_busy_time': false,
                'updated_at': null,
                'current_calendar_import_id': null,
                'calendar_available': false,
              };
              for (final rawDay in overview['days'] as List<dynamic>) {
                final day = rawDay as Map<String, dynamic>;
                day['items'] = (day['items'] as List<dynamic>).where((rawItem) {
                  final item = rawItem as Map<String, dynamic>;
                  return !{
                    'setup_commitment',
                    'manual_commitment',
                    'calendar_event',
                  }.contains(item['kind']);
                }).toList(growable: false);
              }
            }
            return handler.resolve(_response(options, overview));
          }
          if (options.path.endsWith('/proposals')) {
            if (failNextProposal) {
              failNextProposal = false;
              return handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response<Object?>(
                    requestOptions: options,
                    statusCode: 422,
                    data: {'detail': 'invalid proposal'},
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            }
            return handler.resolve(
              _response(
                options,
                _unscheduledTaskPlanEnvelope(
                  learnedTiming: learnedTiming,
                  learnedTimingFallback: learnedTimingFallback,
                ),
              ),
            );
          }
          if (options.path.endsWith('/confirm')) {
            return handler.resolve(
              _response(options, _unscheduledTaskPlanEnvelope(active: true)),
            );
          }
          if (options.path == '/v1/planner/preferences') {
            return handler
                .resolve(_response(options, plannerPreferencesEnvelope()));
          }
          if (options.path == '/v1/planner/commitments' ||
              options.path.endsWith('/archive')) {
            return handler
                .resolve(_response(options, plannerCommitmentEnvelope()));
          }
          return handler.reject(
            DioException(
              requestOptions: options,
              response: Response<Object?>(
                requestOptions: options,
                statusCode: 404,
              ),
              type: DioExceptionType.badResponse,
            ),
          );
        },
      ),
    );
  }

  final Dio dio = Dio(BaseOptions(baseUrl: 'https://planner.test'));
  final List<_PlannerRequest> requests = [];
  bool failNextProposal;
  final bool incompleteAvailability;
  final bool learnedTiming;
  final bool learnedTimingFallback;

  Response<Map<String, dynamic>> _response(
    RequestOptions options,
    Map<String, dynamic> data,
  ) =>
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: data,
      );
}

ExamWeekOutlook _outlook({
  required String mode,
  String risk = 'attention',
  String capacity = 'fits_with_sleep_protected',
  bool includeSleepPlan = true,
}) {
  final overdue = mode == 'overdue';
  final days = overdue
      ? -1
      : mode == 'watch'
          ? 10
          : 5;
  return ExamWeekOutlook.fromJson({
    'contract_version': 'exam-week-outlook-v1',
    'origin': 'authenticated_backend',
    'generated_at': '2026-07-21T08:00:00Z',
    'timezone': 'Europe/Berlin',
    'local_date': '2026-07-21',
    'mode': mode,
    'risk_level': risk,
    'capacity_status': capacity,
    'current_sleep_plan': includeSleepPlan
        ? {
            'capture_id': 'evening-plan',
            'entry_date': '2026-07-20',
            'captured_at': '2026-07-20T19:00:00Z',
            'planned_sleep_time': '23:00',
            'sleep_target_minutes': 480,
          }
        : null,
    'recent_sleep_nights': [
      {
        'entry_date': '2026-07-21',
        'estimated_sleep_minutes': 420,
        'sleep_target_minutes': 480,
        'shortfall_minutes': 60,
        'at_least_one_hour_short': true,
      },
    ],
    'exams': [
      {
        'plan_id': '60000000-0000-4000-8000-000000000002',
        'kind': 'exam',
        'title': 'Mathematics',
        'deadline_at':
            overdue ? '2026-07-20T12:00:00Z' : '2026-07-26T12:00:00Z',
        'local_deadline_date': overdue ? '2026-07-20' : '2026-07-26',
        'days_remaining': days,
        'active_revision': 1,
        'pending_revision': null,
        'saved_buffer_days': 1,
        'recommended_buffer_days': 1,
        'last_preparation_date': overdue ? '2026-07-18' : '2026-07-24',
        'remaining_minutes': 120,
        'future_scheduled_minutes': 60,
        'future_minutes_after_buffer': 0,
        'missed_preparation_minutes': overdue ? 60 : 0,
        'simulated_regular_minutes': 60,
        'unscheduled_regular_minutes': 0,
        'simulated_sleep_protected_minutes':
            includeSleepPlan && capacity != 'unknown' ? 60 : null,
        'unscheduled_sleep_protected_minutes':
            includeSleepPlan && capacity != 'unknown' ? 0 : null,
        'pending_preview_sleep_overlap': false,
      },
    ],
    'assignments': [
      {
        'plan_id': '70000000-0000-4000-8000-000000000002',
        'kind': 'assignment',
        'title': 'History paper',
        'deadline_at': '2026-07-25T12:00:00Z',
        'local_deadline_date': '2026-07-25',
        'days_remaining': 4,
        'active_revision': 1,
        'pending_revision': null,
        'saved_buffer_days': 0,
        'recommended_buffer_days': 0,
        'last_preparation_date': '2026-07-25',
        'remaining_minutes': 60,
        'future_scheduled_minutes': 0,
        'future_minutes_after_buffer': 0,
        'missed_preparation_minutes': 0,
        'simulated_regular_minutes': 60,
        'unscheduled_regular_minutes': 0,
        'simulated_sleep_protected_minutes':
            includeSleepPlan && capacity != 'unknown' ? 60 : null,
        'unscheduled_sleep_protected_minutes':
            includeSleepPlan && capacity != 'unknown' ? 0 : null,
        'pending_preview_sleep_overlap': false,
      },
    ],
    'warning_codes': [
      if (overdue) 'exam_overdue',
      if (!includeSleepPlan) 'sleep_plan_missing',
      if (capacity == 'unknown') 'capacity_incomplete',
    ],
    'minutes': {
      'remaining_minutes': 180,
      'future_scheduled_minutes': 60,
      'missed_preparation_minutes': overdue ? 60 : 0,
      'simulated_regular_minutes': 120,
      'unscheduled_regular_minutes': 0,
      'simulated_sleep_protected_minutes':
          includeSleepPlan && capacity != 'unknown' ? 120 : null,
      'unscheduled_sleep_protected_minutes':
          includeSleepPlan && capacity != 'unknown' ? 0 : null,
    },
  });
}

Map<String, dynamic> _unscheduledTaskPlanEnvelope({
  bool active = false,
  bool learnedTiming = false,
  bool learnedTimingFallback = false,
}) {
  final envelope =
      plannerActionPlanEnvelope(state: active ? 'active' : 'proposed');
  final plan = Map<String, dynamic>.from(envelope['plan'] as Map);
  final revisionKey = active ? 'active_revision' : 'pending_revision';
  final revision = Map<String, dynamic>.from(plan[revisionKey] as Map);
  final target = Map<String, dynamic>.from(revision['target'] as Map);
  target
    ..['title'] = 'Read sources'
    ..['estimated_minutes'] = null
    ..['deadline_at'] = null
    ..['preferred_session_minutes'] = null;
  revision
    ..['target'] = target
    ..['planned_minutes'] = 0
    ..['unscheduled_minutes'] = 0
    ..['task_blocks'] = <dynamic>[];
  if (learnedTiming) {
    revision['timing_preference'] = {
      'source': 'learned_personal_pattern',
      'window': '09-13',
      'evidence_count': 24,
      'evidence_starts_on': '2026-06-01',
      'evidence_ends_on': '2026-07-20',
      'evidence_fingerprint': List.filled(64, 'b').join(),
      'fell_back_to_setup': learnedTimingFallback,
      'warning': null,
    };
  }
  plan[revisionKey] = revision;
  if (active) plan['status'] = 'unscheduled';
  envelope['plan'] = plan;
  return envelope;
}
