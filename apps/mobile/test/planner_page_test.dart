import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/network/api_client.dart';
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
  await tester.pumpAndSettle();
}

class _PlannerRequest {
  const _PlannerRequest(this.method, this.path, this.data);

  final String method;
  final String path;
  final Object? data;
}

class _PlannerBackend {
  _PlannerBackend({this.failNextProposal = false}) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests
              .add(_PlannerRequest(options.method, options.path, options.data));
          if (options.path == '/v1/planner/overview') {
            return handler
                .resolve(_response(options, plannerOverviewEnvelope()));
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
              _response(options, _unscheduledTaskPlanEnvelope()),
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

Map<String, dynamic> _unscheduledTaskPlanEnvelope({bool active = false}) {
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
  plan[revisionKey] = revision;
  if (active) plan['status'] = 'unscheduled';
  envelope['plan'] = plan;
  return envelope;
}
