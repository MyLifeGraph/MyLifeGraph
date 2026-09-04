import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/composition/projection_refresh_providers.dart';
import 'package:my_life_graph/features/deadline_plans/domain/exam_week_outlook.dart';
import 'package:my_life_graph/composition/deadline_plan_providers.dart';
import 'package:my_life_graph/features/planner/application/planner_controller.dart';
import 'package:my_life_graph/features/planner/data/planner_api_data_source.dart';
import 'package:my_life_graph/features/planner/presentation/pages/planner_page.dart';
import 'package:my_life_graph/features/planner/presentation/providers/planner_providers.dart';

import 'support/planner_fixtures.dart';

void main() {
  for (final overnight in [false, true]) {
    testWidgets('weekly conflict preview includes ${overnight ? 'midnight' : 'recovery'} in profile time',
        (tester) async {
      final backend = _PlannerBackend()
        ..transformOverview = (overview) {
          final item = overview['days'][0]['items'][1] as Map<String, dynamic>;
          if (overnight) {
            item['starts_at'] = '2026-07-21T21:45:00Z';
            item['ends_at'] = '2026-07-21T22:15:00Z';
            item['reserved_ends_at'] = '2026-07-21T22:15:00Z';
          } else {
            item['recovery_minutes'] = 30;
            item['reserved_ends_at'] = '2026-07-21T10:00:00Z';
          }
        };
      await _pumpPlanner(tester, backend: backend);
      await tester.tap(find.byKey(const ValueKey('planner-add-commitment')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('planner-commitment-title')),
        'Appointment',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Every week').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<int>));
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(overnight ? 'Wed' : 'Tue').last);
      await tester.pumpAndSettle();
      for (final start in [true, false]) {
        final label = start ? 'Starts *' : 'Ends *';
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.byType(TimePickerDialog))).pop(
          TimeOfDay(
            hour: overnight ? 0 : 11,
            minute: overnight ? (start ? 5 : 10) : (start ? 45 : 55),
          ),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('planner-commitment-review')));
      await tester.pumpAndSettle();
      expect(find.text('Visible plans that need attention:'), findsOneWidget);
      expect(find.text('• Write report'), findsOneWidget);
      expect(backend.requests.where((request) => request.method != 'GET'), isEmpty);
    });
  }

  test('scheduled Planner load is ignored after immediate disposal', () async {
    final uncaughtErrors = <Object>[];
    final backend = _PlannerBackend();

    await runZonedGuarded(
      () async {
        final controller = PlannerController(
          api: PlannerApiDataSource(ApiClient(backend.dio)),
          accessTokenProvider: () => 'test-token',
          canUseSyncedPlanner: true,
          isBackendConfigured: true,
        );
        controller.dispose();
        await Future<void>.delayed(Duration.zero);
      },
      (error, _) => uncaughtErrors.add(error),
    );

    expect(uncaughtErrors, isEmpty);
    expect(backend.requests, isEmpty);
  });

  test('late Planner overview response is ignored after disposal', () async {
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    final uncaughtErrors = <Object>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://planner.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestStarted.complete();
          releaseResponse.future.then(
            (_) => handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: plannerOverviewEnvelope(),
              ),
            ),
          );
        },
      ),
    );

    await runZonedGuarded(
      () async {
        final controller = PlannerController(
          api: PlannerApiDataSource(ApiClient(dio)),
          accessTokenProvider: () => 'test-token',
          canUseSyncedPlanner: true,
          isBackendConfigured: true,
        );
        await requestStarted.future;
        controller.dispose();
        releaseResponse.complete();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
      },
      (error, _) => uncaughtErrors.add(error),
    );

    expect(uncaughtErrors, isEmpty);
  });

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
      'planner-habits',
      'planner-unscheduled-tasks',
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
    expect(find.text('2 active · 2 unplanned'), findsOneWidget);
    expect(find.text('Managed in Setup'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary header reload performs only a fresh overview read',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend();

    await _pumpPlanner(tester, backend: backend);
    final readsBeforeReload = backend.requests
        .where((request) => request.path == '/v1/planner/overview')
        .length;
    _invokeHeaderReload(tester);
    await tester.pumpAndSettle();

    expect(
      backend.requests
          .where((request) => request.path == '/v1/planner/overview'),
      hasLength(readsBeforeReload + 1),
    );
    expect(
      backend.requests.where(
        (request) =>
            request.path.endsWith('/proposals') ||
            request.path.endsWith('/confirm'),
      ),
      isEmpty,
    );
  });

  testWidgets(
      'Setup Habit keeps its definition exact while duration is editable',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend();

    await _pumpPlanner(tester, backend: backend);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('planner-habits')),
      400,
    );
    await tester.tap(find.text('Habits'));
    await tester.pumpAndSettle();
    expect(find.text('Managed in Setup'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('planner-habits')),
        matching: find.text('Read'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('planner-habit-managed-in-setup')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('planner-habit-read-only-definition')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('planner-habit-read-only-definition')),
      ),
      matchesSemantics(
        label: 'Habit definition: title Read; description '
            'Keep up with the course reader; cadence Daily.',
        isReadOnly: true,
      ),
    );
    expect(
      find.text(
        'Title, description, and cadence stay managed in Settings. '
        'You can change the duration used for this preview.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('planner-habit-title')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '25',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();

    final proposal = backend.requests
        .lastWhere((request) => request.path.endsWith('/proposals'))
        .data as Map<String, dynamic>;
    final target = proposal['target'] as Map<String, dynamic>;
    expect(target['operation'], 'update');
    expect(target['title'], 'Read');
    expect(target['description'], 'Keep up with the course reader.');
    expect(target['cadence'], {
      'kind': 'daily',
      'scheduled_weekdays': <int>[],
      'weekly_target': 1,
    });
    expect(target['duration_minutes'], 25);
    semantics.dispose();
  });

  testWidgets(
      'Setup Habit duration draft survives availability Back by target only',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(
      incompleteAvailability: true,
      secondSetupHabit: true,
    );

    await _pumpPlanner(tester, backend: backend);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('planner-habits')),
      400,
    );
    await tester.tap(find.text('Habits'));
    await tester.pumpAndSettle();
    Finder habitNamed(String title) => find.descendant(
          of: find.byKey(const ValueKey('planner-habits')),
          matching: find.text(title),
        );

    await tester.tap(habitNamed('Read'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '25',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();
    expect(find.text('Review your availability'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Back'));
    await tester.pumpAndSettle();

    await tester.tap(habitNamed('Walk'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      '35',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(habitNamed('Read'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      '25',
    );
  });

  testWidgets('failed Setup Habit proposal retains its target duration draft',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(failNextProposal: true);

    await _pumpPlanner(tester, backend: backend);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('planner-habits')),
      400,
    );
    await tester.tap(find.text('Habits'));
    await tester.pumpAndSettle();
    final setupHabit = find.descendant(
      of: find.byKey(const ValueKey('planner-habits')),
      matching: find.text('Read'),
    );
    await tester.tap(setupHabit);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '25',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Planner could not save that change. Your entered values are retained.',
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('planner-habits')),
      400,
    );
    if (setupHabit.evaluate().isEmpty) {
      await tester.tap(find.text('Habits'));
      await tester.pumpAndSettle();
    }
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('planner-habits')),
        matching: find.text('Read'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      '25',
    );
  });

  testWidgets('unrelated Task confirmation keeps Setup duration draft',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(failNextProposal: true);

    await _pumpPlanner(tester, backend: backend);
    await _openPlannerHabit(tester, 'Read');
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '25',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();

    _invokeAddNew(tester, 'planner-add-task');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('planner-task-title')),
      'Unrelated confirmed Task',
    );
    await tester.tap(find.byKey(const ValueKey('planner-task-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-confirm-plan')));
    await tester.pumpAndSettle();

    await _openPlannerHabit(tester, 'Read');
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      '25',
    );
  });

  testWidgets(
      'Setup Habit 409 locks mutations until fresh reload and retains duration',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(failNextProposalStatus: 409);

    final controller = await _pumpPlanner(tester, backend: backend);
    await _openPlannerHabit(tester, 'Read');
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '25',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Planner changed'), findsOneWidget);
    final addHabitButton = find.descendant(
      of: find.byKey(const ValueKey('planner-add-habit')),
      matching: find.byType(OutlinedButton),
    );
    expect(tester.widget<OutlinedButton>(addHabitButton).onPressed, isNull);
    var staleHabitRow = find.ancestor(
      of: find.text('Read'),
      matching: find.byType(ListTile),
    );
    if (staleHabitRow.evaluate().isEmpty) {
      await tester.tap(find.text('Habits'));
      await tester.pumpAndSettle();
      staleHabitRow = find.ancestor(
        of: find.text('Read'),
        matching: find.byType(ListTile),
      );
    }
    expect(tester.widget<ListTile>(staleHabitRow).onTap, isNull);

    backend
      ..setupHabitTitle = 'Read current chapters'
      ..setupHabitDescription = 'Use the refreshed Setup definition.'
      ..setupHabitExpectedUpdatedAt = '2026-07-22T09:15:00Z'
      ..setupHabitCadenceKind = 'weekly_target'
      ..setupHabitWeeklyTarget = 2;
    final proposalsBeforeReload = backend.requests
        .where((request) => request.path.endsWith('/proposals'))
        .length;
    backend.failNextOverview = true;
    _invokeHeaderReload(tester);
    await tester.pumpAndSettle();

    expect(controller.state.operationError, isNotNull);
    expect(controller.state.reloadSuggested, isTrue);
    expect(controller.state.canMutate, isFalse);
    expect(tester.widget<OutlinedButton>(addHabitButton).onPressed, isNull);
    expect(
      tester
          .widget<ListTile>(
            find.descendant(
              of: find.byKey(const ValueKey('planner-needs-attention')),
              matching: find.byType(ListTile),
            ),
          )
          .onTap,
      isNull,
    );
    final staleScheduleItem = find.descendant(
      of: find.byKey(const ValueKey('planner-seven-days')),
      matching: find.text('Write report'),
    );
    expect(staleScheduleItem, findsOneWidget);
    await tester.tap(staleScheduleItem);
    await tester.pumpAndSettle();
    expect(find.text('Start focus'), findsNothing);
    expect(find.text('Cancel reservations'), findsNothing);
    _invokeHeaderReload(tester);
    await tester.pumpAndSettle();

    expect(controller.state.pendingMutation, isNull);
    expect(controller.state.operationError, isNull);
    expect(controller.state.reloadSuggested, isFalse);
    expect(controller.state.canMutate, isTrue);
    expect(
      backend.requests.where((request) => request.path.endsWith('/proposals')),
      hasLength(proposalsBeforeReload),
    );
    expect(tester.widget<OutlinedButton>(addHabitButton).onPressed, isNotNull);
    expect(
      tester
          .widget<ListTile>(
            find.descendant(
              of: find.byKey(const ValueKey('planner-needs-attention')),
              matching: find.byType(ListTile),
            ),
          )
          .onTap,
      isNotNull,
    );
    await _openPlannerHabit(tester, 'Read current chapters');
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      '25',
    );
    expect(
      find.bySemanticsLabel(
        'Habit definition: title Read current chapters; description '
        'Use the refreshed Setup definition; cadence 2 times per week.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();

    final proposal = backend.requests
        .lastWhere((request) => request.path.endsWith('/proposals'))
        .data as Map<String, dynamic>;
    final target = proposal['target'] as Map<String, dynamic>;
    expect(target['title'], 'Read current chapters');
    expect(target['description'], 'Use the refreshed Setup definition.');
    expect(target['expected_updated_at'], '2026-07-22T09:15:00.000Z');
    expect(target['duration_minutes'], 25);
    expect(target['cadence'], {
      'kind': 'weekly_target',
      'scheduled_weekdays': <int>[],
      'weekly_target': 2,
    });
    semantics.dispose();
  });

  testWidgets('deferred Setup preview confirmation clears retained duration',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(
      confirmedSetupHabitDuration: 30,
    );

    await _pumpPlanner(tester, backend: backend);
    await _openPlannerHabit(tester, 'Read');
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '25',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Keep as draft'));
    await tester.pumpAndSettle();

    await _openPlannerHabit(tester, 'Read');
    expect(find.text('Review plan preview'), findsOneWidget);
    expect(find.text('Create a new preview?'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('planner-confirm-plan')));
    await tester.pumpAndSettle();

    await _openPlannerHabit(tester, 'Read');
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      '30',
    );
  });

  testWidgets('exact-retry Setup confirmation clears retained duration',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(
      failNextConfirmStatus: 503,
      confirmedSetupHabitDuration: 30,
    );

    await _pumpPlanner(tester, backend: backend);
    await _openPlannerHabit(tester, 'Read');
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '25',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-confirm-plan')));
    await tester.pumpAndSettle();

    expect(find.text('Result not confirmed'), findsOneWidget);
    expect(find.text('Create a new preview?'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Retry same change'));
    await tester.pumpAndSettle();

    await _openPlannerHabit(tester, 'Read');
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      '30',
    );
  });

  testWidgets(
      'header reload discards ambiguous confirmation without replaying it',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(failNextConfirmStatus: 503);
    final controller = await _pumpPlanner(tester, backend: backend);

    await _openPlannerHabit(tester, 'Read');
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '25',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-confirm-plan')));
    await tester.pumpAndSettle();

    expect(find.text('Result not confirmed'), findsOneWidget);
    expect(controller.state.requiresExactRetry, isTrue);
    final confirmsBeforeReload = backend.requests
        .where((request) => request.path.endsWith('/confirm'))
        .length;
    backend
      ..setupHabitTitle = 'Read refreshed material'
      ..setupHabitExpectedUpdatedAt = '2026-07-22T10:00:00Z';
    _invokeHeaderReload(tester);
    await tester.pumpAndSettle();

    expect(controller.state.pendingMutation, isNull);
    expect(controller.state.operationError, isNull);
    expect(controller.state.preview, isNull);
    expect(controller.state.reloadSuggested, isFalse);
    expect(controller.state.canMutate, isTrue);
    expect(
      controller.state.overview?.habits.first.title,
      'Read refreshed material',
    );
    expect(find.text('Result not confirmed'), findsNothing);
    expect(
      backend.requests.where((request) => request.path.endsWith('/confirm')),
      hasLength(confirmsBeforeReload),
    );
    final addHabitButton = find.descendant(
      of: find.byKey(const ValueKey('planner-add-habit')),
      matching: find.byType(OutlinedButton),
    );
    expect(tester.widget<OutlinedButton>(addHabitButton).onPressed, isNotNull);
  });

  testWidgets(
      'ambiguous Task and Habit proposals reconcile exact previews before draft cleanup',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _exerciseAmbiguousCreateReconciliation(
      tester,
      backend: _PlannerBackend(
        failNextProposalStatus: 503,
        persistFailedProposal: true,
      ),
      habit: false,
      title: 'Ambiguous exact Task',
    );
    await _exerciseAmbiguousCreateReconciliation(
      tester,
      backend: _PlannerBackend(
        failNextProposalStatus: 503,
        persistFailedProposal: true,
      ),
      habit: true,
      title: 'Ambiguous exact Habit',
    );
  });

  testWidgets(
      'ambiguous Setup proposal binds exact preview and confirmation clears duration',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(
      failNextProposalStatus: 503,
      persistFailedProposal: true,
      confirmedSetupHabitDuration: 30,
    );
    final controller = await _pumpPlanner(tester, backend: backend);

    await _openPlannerHabit(tester, 'Read');
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '25',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();
    expect(controller.state.requiresExactRetry, isTrue);
    expect(find.text('Result not confirmed'), findsOneWidget);
    _invokeHeaderReload(tester);
    await tester.pumpAndSettle();

    expect(controller.state.requiresExactRetry, isFalse);
    expect(controller.state.operationError, isNull);
    expect(
      backend.requests.where((request) => request.path.endsWith('/proposals')),
      hasLength(1),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('planner-pending-previews')),
        matching: find.text('Read'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-confirm-plan')));
    await tester.pumpAndSettle();

    await _openPlannerHabit(tester, 'Read');
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      '30',
    );
  });

  testWidgets(
      'ambiguous stale Setup replacement uses its request binding despite an equal original draft',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(
      persistFailedProposal: true,
      confirmedSetupHabitDuration: 30,
    );
    final controller = await _pumpPlanner(tester, backend: backend);

    await _openPlannerHabit(tester, 'Read');
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '25',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Keep as draft'));
    await tester.pumpAndSettle();

    backend
      ..setupHabitExpectedUpdatedAt = '2026-07-22T09:15:00Z'
      ..failNextProposalStatus = 503;
    _invokeHeaderReload(tester);
    await tester.pumpAndSettle();
    await _openPlannerHabit(tester, 'Read');
    await tester.tap(find.byKey(const ValueKey('planner-replace-preview')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      '25',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();

    expect(controller.state.requiresExactRetry, isTrue);
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Reload Planner'),
    );
    await tester.pumpAndSettle();
    expect(controller.state.requiresExactRetry, isFalse);
    expect(
      backend.requests.where((request) => request.path.endsWith('/proposals')),
      hasLength(2),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('planner-pending-previews')),
        matching: find.text('Read'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-confirm-plan')));
    await tester.pumpAndSettle();

    await _openPlannerHabit(tester, 'Read');
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      '30',
    );
  });

  testWidgets(
      'exact retry keeps stale Task manual Habit Setup and create replacements request-bound',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cases = <({
      _PlannerBackend backend,
      String pendingTitle,
      bool habit,
      bool setup,
    })>[
      (
        backend: _PlannerBackend(
          scheduledTaskPending: true,
          forcedDynamicStaleSource: 'target',
          failNextProposalStatus: 503,
        ),
        pendingTitle: 'Stale scheduled Task draft',
        habit: false,
        setup: false,
      ),
      (
        backend: _PlannerBackend(
          scheduledManualHabitPending: true,
          forcedDynamicStaleSource: 'target',
          failNextProposalStatus: 503,
        ),
        pendingTitle: 'Stale Walk draft',
        habit: true,
        setup: false,
      ),
      (
        backend: _PlannerBackend(
          coldSetupHabitPending: true,
          failNextProposalStatus: 503,
          confirmedSetupHabitDuration: 30,
        ),
        pendingTitle: 'Old persisted Setup title',
        habit: true,
        setup: true,
      ),
      (
        backend: _PlannerBackend(
          includePendingCreate: true,
          forcedDynamicStaleSource: 'calendar',
          failNextProposalStatus: 503,
        ),
        pendingTitle: 'Prepare presentation',
        habit: false,
        setup: false,
      ),
    ];

    for (final value in cases) {
      await _exerciseStaleReplacementExactRetry(
        tester,
        backend: value.backend,
        pendingTitle: value.pendingTitle,
        habit: value.habit,
        setup: value.setup,
      );
    }
  });

  testWidgets(
      'proposal exact retry classifies 409 and 422 without losing another draft',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cases = <({
      _PlannerBackend Function() backend,
      String pendingTitle,
      bool habit,
      bool setup,
      String editedTitle,
      String freshTitle,
    })>[
      (
        backend: () => _PlannerBackend(
              scheduledTaskPending: true,
              forcedDynamicStaleSource: 'target',
              failNextProposalStatus: 503,
            ),
        pendingTitle: 'Stale scheduled Task draft',
        habit: false,
        setup: false,
        editedTitle: 'Exact retry Task edit',
        freshTitle: 'Undated reading',
      ),
      (
        backend: () => _PlannerBackend(
              scheduledManualHabitPending: true,
              forcedDynamicStaleSource: 'target',
              failNextProposalStatus: 503,
            ),
        pendingTitle: 'Stale Walk draft',
        habit: true,
        setup: false,
        editedTitle: 'Exact retry Walk edit',
        freshTitle: 'Walk',
      ),
      (
        backend: () => _PlannerBackend(
              coldSetupHabitPending: true,
              failNextProposalStatus: 503,
            ),
        pendingTitle: 'Old persisted Setup title',
        habit: true,
        setup: true,
        editedTitle: 'Read',
        freshTitle: 'Read',
      ),
      (
        backend: () => _PlannerBackend(
              includePendingCreate: true,
              forcedDynamicStaleSource: 'calendar',
              failNextProposalStatus: 503,
            ),
        pendingTitle: 'Prepare presentation',
        habit: false,
        setup: false,
        editedTitle: 'Exact retry new Task',
        freshTitle: 'Prepare presentation',
      ),
      (
        backend: () => _PlannerBackend(
              includePendingHabitCreate: true,
              forcedDynamicStaleSource: 'timezone',
              failNextProposalStatus: 503,
            ),
        pendingTitle: 'Draft stretching',
        habit: true,
        setup: false,
        editedTitle: 'Exact retry new Habit',
        freshTitle: 'Draft stretching',
      ),
    ];

    for (final retryStatus in const [409, 422]) {
      for (final value in cases) {
        await _exerciseStaleReplacementExactRetryFailure(
          tester,
          backend: value.backend(),
          pendingTitle: value.pendingTitle,
          habit: value.habit,
          setup: value.setup,
          editedTitle: value.editedTitle,
          freshTitle: value.freshTitle,
          retryStatus: retryStatus,
        );
      }
    }
  });

  testWidgets('repeated ambiguous proposal retries keep one exact attempt',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(failNextProposalStatus: 503);
    final controller = await _pumpPlanner(tester, backend: backend);

    _invokeAddNew(tester, 'planner-add-task');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('planner-task-title')),
      'Repeated ambiguous Task',
    );
    await tester.tap(find.byKey(const ValueKey('planner-task-preview')));
    await tester.pumpAndSettle();
    final firstBody = backend.requests
        .lastWhere((request) => request.path.endsWith('/proposals'))
        .data;
    expect(controller.state.requiresExactRetry, isTrue);

    backend.failNextProposalStatus = 503;
    await tester.tap(find.widgetWithText(FilledButton, 'Retry same change'));
    await tester.pumpAndSettle();
    expect(controller.state.requiresExactRetry, isTrue);
    expect(find.text('Result not confirmed'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Retry same change'));
    await tester.pumpAndSettle();
    expect(controller.state.requiresExactRetry, isFalse);
    expect(find.text('Review plan preview'), findsOneWidget);
    final proposals = backend.requests
        .where((request) => request.path.endsWith('/proposals'))
        .map((request) => request.data)
        .toList(growable: false);
    expect(proposals, [firstBody, firstBody, firstBody]);

    await tester.tap(find.byKey(const ValueKey('planner-confirm-plan')));
    await tester.pumpAndSettle();
    _invokeAddNew(tester, 'planner-add-task');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('planner-task-title')))
          .controller
          ?.text,
      isEmpty,
    );
  });

  testWidgets('confirmation keeps a newer same-source Setup replacement',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const planId = 'd0000000-0000-4000-8000-000000000097';
    final backend = _PlannerBackend(
      coldSetupHabitPending: true,
      confirmedSetupHabitDuration: 30,
    );
    await _pumpPlanner(tester, backend: backend);

    Future<void> openSourceReplacement() async {
      final pending = find.descendant(
        of: find.byKey(const ValueKey('planner-pending-previews')),
        matching: find.text('Old persisted Setup title'),
      );
      await tester.scrollUntilVisible(pending, 300);
      await tester.tap(pending);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('planner-replace-preview')));
      await tester.pumpAndSettle();
    }

    await openSourceReplacement();
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '25',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Keep as draft'));
    await tester.pumpAndSettle();

    backend.suspendPendingPlan(planId);
    _invokeHeaderReload(tester);
    await tester.pumpAndSettle();
    await openSourceReplacement();
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '35',
    );
    backend.failNextProposalStatus = 422;
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();

    backend.restoreSuspendedPendingPlan(planId);
    _invokeHeaderReload(tester);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('planner-pending-previews')),
        matching: find.text('Read'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-confirm-plan')));
    await tester.pumpAndSettle();

    backend.reopenResolvedPlan(planId);
    _invokeHeaderReload(tester);
    await tester.pumpAndSettle();
    await openSourceReplacement();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      '35',
    );
  });

  testWidgets(
      'same-source confirmation clears an unsent Setup replacement while a foreign confirmation does not',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(
      coldSetupHabitPending: true,
      confirmedSetupHabitDuration: 30,
    );
    await _pumpPlanner(tester, backend: backend);

    _invokeAddNew(tester, 'planner-add-task');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('planner-task-title')),
      'Foreign pending Task',
    );
    await tester.tap(find.byKey(const ValueKey('planner-task-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Keep as draft'));
    await tester.pumpAndSettle();
    backend.failNextProposal = true;

    Future<void> openColdSetupReplacement() async {
      final pending = find.descendant(
        of: find.byKey(const ValueKey('planner-pending-previews')),
        matching: find.text('Old persisted Setup title'),
      );
      await tester.scrollUntilVisible(pending, 300);
      await tester.tap(pending);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('planner-replace-preview')));
      await tester.pumpAndSettle();
    }

    await openColdSetupReplacement();
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '35',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Planner could not save that change. Your entered values are retained.',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('planner-pending-previews')),
        matching: find.text('Foreign pending Task'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-confirm-plan')));
    await tester.pumpAndSettle();

    await openColdSetupReplacement();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      '35',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    backend.setupHabitExpectedUpdatedAt = '2026-07-19T08:00:00Z';
    _invokeHeaderReload(tester);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('planner-pending-previews')),
        matching: find.text('Old persisted Setup title'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Create a new preview?'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('planner-confirm-plan')));
    await tester.pumpAndSettle();

    backend
      ..reopenResolvedPlan('d0000000-0000-4000-8000-000000000097')
      ..setupHabitExpectedUpdatedAt = '2026-07-20T08:00:00Z';
    _invokeHeaderReload(tester);
    await tester.pumpAndSettle();
    await openColdSetupReplacement();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      '25',
    );
  });

  testWidgets('ambiguous proposal mismatch never binds or clears another draft',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(
      failNextProposalStatus: 503,
      persistFailedProposal: true,
      mismatchPersistedProposal: true,
    );
    final controller = await _pumpPlanner(tester, backend: backend);

    _invokeAddNew(tester, 'planner-add-task');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('planner-task-title')),
      'Unmatched ambiguous Task draft',
    );
    _invokeFilledButton(tester, 'planner-task-preview');
    await tester.pumpAndSettle();
    expect(controller.state.requiresExactRetry, isTrue);
    _invokeHeaderReload(tester);
    await tester.pumpAndSettle();

    expect(controller.state.requiresExactRetry, isFalse);
    expect(
      backend.requests.where((request) => request.path.endsWith('/proposals')),
      hasLength(1),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('planner-pending-previews')),
        matching: find.text('Different server proposal'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-confirm-plan')));
    await tester.pumpAndSettle();

    _invokeAddNew(tester, 'planner-add-task');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-task-title')),
          )
          .controller
          ?.text,
      'Unmatched ambiguous Task draft',
    );
  });

  testWidgets(
      'stale persisted Task preview is replaced from fresh target facts without replay',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(
      failNextConfirmStatus: 409,
    );

    final controller = await _pumpPlanner(tester, backend: backend);
    await tester.scrollUntilVisible(find.text('Undated reading'), 400);
    await tester.tap(find.text('Undated reading'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('planner-task-title')),
      'Keep my Task changes',
    );
    await tester.tap(find.byKey(const ValueKey('planner-task-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-confirm-plan')));
    await tester.pumpAndSettle();

    expect(find.text('Planner changed'), findsOneWidget);
    backend
      ..taskTitle = 'Server current Task'
      ..taskDescription = 'Fresh server description.'
      ..taskExpectedUpdatedAt = '2026-07-22T11:00:00Z'
      ..taskPriority = 'high';
    final confirmsBeforeReload = backend.requests
        .where((request) => request.path.endsWith('/confirm'))
        .length;
    _invokeHeaderReload(tester);
    await tester.pumpAndSettle();

    expect(controller.state.loadError, isNull);
    await tester.scrollUntilVisible(find.text('Server current Task'), 400);
    await tester.tap(find.text('Server current Task'));
    await tester.pumpAndSettle();
    expect(find.text('Create a new preview?'), findsOneWidget);
    expect(find.text('Review plan preview'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('planner-replace-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Plan Task'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-task-title')),
          )
          .controller
          ?.text,
      'Server current Task',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-task-description')),
          )
          .controller
          ?.text,
      'Fresh server description.',
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('planner-task-priority')),
          )
          .initialValue,
      'high',
    );
    await tester.tap(find.byKey(const ValueKey('planner-task-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Review plan preview'), findsOneWidget);
    final proposals = backend.requests
        .where((request) => request.path.endsWith('/proposals'))
        .map((request) => request.data as Map<String, dynamic>)
        .toList(growable: false);
    expect(proposals, hasLength(2));
    expect(proposals[1]['request_id'], isNot(proposals[0]['request_id']));
    expect(proposals[1]['plan_id'], proposals[0]['plan_id']);
    expect(proposals[1]['base_revision'], 1);
    final replacementTarget = proposals[1]['target'] as Map<String, dynamic>;
    expect(replacementTarget['operation'], 'update');
    expect(replacementTarget['title'], 'Server current Task');
    expect(replacementTarget['description'], 'Fresh server description.');
    expect(replacementTarget['priority'], 'high');
    expect(
      replacementTarget['expected_updated_at'],
      '2026-07-22T11:00:00.000Z',
    );
    expect(
      backend.requests.where((request) => request.path.endsWith('/confirm')),
      hasLength(confirmsBeforeReload),
    );
    expect(
      backend.requests.where((request) => request.path.endsWith('/cancel')),
      isEmpty,
    );
  });

  testWidgets(
      'stale persisted Setup preview is replaced with fresh definition and retained duration',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(
      failNextConfirmStatus: 409,
    );

    final controller = await _pumpPlanner(tester, backend: backend);
    await _openPlannerHabit(tester, 'Read');
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '25',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-confirm-plan')));
    await tester.pumpAndSettle();

    expect(find.text('Planner changed'), findsOneWidget);
    backend
      ..setupHabitTitle = 'Read current chapters'
      ..setupHabitDescription = 'Use the refreshed Setup definition.'
      ..setupHabitExpectedUpdatedAt = '2026-07-22T09:15:00Z'
      ..setupHabitCadenceKind = 'weekly_target'
      ..setupHabitWeeklyTarget = 2;
    final confirmsBeforeReload = backend.requests
        .where((request) => request.path.endsWith('/confirm'))
        .length;
    _invokeHeaderReload(tester);
    await tester.pumpAndSettle();

    expect(controller.state.loadError, isNull);
    await _openPlannerHabit(tester, 'Read current chapters');
    expect(find.text('Create a new preview?'), findsOneWidget);
    expect(find.text('Review plan preview'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('planner-replace-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Plan Habit'), findsOneWidget);
    expect(find.text('Read current chapters'), findsWidgets);
    expect(find.text('Use the refreshed Setup definition.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      '25',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Review plan preview'), findsOneWidget);
    final proposals = backend.requests
        .where((request) => request.path.endsWith('/proposals'))
        .map((request) => request.data as Map<String, dynamic>)
        .toList(growable: false);
    expect(proposals, hasLength(2));
    expect(proposals[1]['request_id'], isNot(proposals[0]['request_id']));
    expect(proposals[1]['plan_id'], proposals[0]['plan_id']);
    expect(proposals[1]['base_revision'], 1);
    final replacementTarget = proposals[1]['target'] as Map<String, dynamic>;
    expect(replacementTarget['operation'], 'update');
    expect(replacementTarget['title'], 'Read current chapters');
    expect(
      replacementTarget['description'],
      'Use the refreshed Setup definition.',
    );
    expect(
      replacementTarget['expected_updated_at'],
      '2026-07-22T09:15:00.000Z',
    );
    expect(replacementTarget['duration_minutes'], 25);
    expect(replacementTarget['cadence'], {
      'kind': 'weekly_target',
      'scheduled_weekdays': <int>[],
      'weekly_target': 2,
    });
    expect(
      backend.requests.where((request) => request.path.endsWith('/confirm')),
      hasLength(confirmsBeforeReload),
    );
    expect(
      backend.requests.where((request) => request.path.endsWith('/cancel')),
      isEmpty,
    );
  });

  testWidgets(
      'cold stale Setup replacement uses persisted duration and fresh definition',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(coldSetupHabitPending: true)
      ..setupHabitTitle = 'Cold-start current chapters'
      ..setupHabitDescription = 'Fresh Setup facts after relaunch.'
      ..setupHabitExpectedUpdatedAt = '2026-07-22T09:15:00Z'
      ..setupHabitCadenceKind = 'weekly_target'
      ..setupHabitWeeklyTarget = 2
      ..setupHabitDuration = 30;

    await _pumpPlanner(tester, backend: backend);
    await _openPlannerHabit(tester, 'Cold-start current chapters');
    expect(find.text('Create a new preview?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('planner-replace-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Cold-start current chapters'), findsWidgets);
    expect(find.text('Fresh Setup facts after relaunch.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      '25',
    );
    expect(
      find.bySemanticsLabel(
        'Habit definition: title Cold-start current chapters; description '
        'Fresh Setup facts after relaunch; cadence 2 times per week.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();

    final proposal = backend.requests
        .singleWhere((request) => request.path.endsWith('/proposals'))
        .data as Map<String, dynamic>;
    final target = proposal['target'] as Map<String, dynamic>;
    expect(proposal['plan_id'], 'd0000000-0000-4000-8000-000000000097');
    expect(proposal['base_revision'], 1);
    expect(target['title'], 'Cold-start current chapters');
    expect(target['description'], 'Fresh Setup facts after relaunch.');
    expect(target['expected_updated_at'], '2026-07-22T09:15:00.000Z');
    expect(target['duration_minutes'], 25);
    expect(target['cadence'], {
      'kind': 'weekly_target',
      'scheduled_weekdays': <int>[],
      'weekly_target': 2,
    });
  });

  testWidgets(
      'stale manual Habit replacement reviews fresh cadence without rebasing an old draft',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(
      failNextConfirmStatus: 409,
    );

    await _pumpPlanner(tester, backend: backend);
    await _openPlannerHabit(tester, 'Walk');
    await tester.tap(find.byKey(const ValueKey('planner-habit-cadence')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily').last);
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '25',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-confirm-plan')));
    await tester.pumpAndSettle();

    backend
      ..manualHabitTitle = 'Current outdoor walk'
      ..manualHabitDescription = 'Fresh saved Habit description.'
      ..manualHabitExpectedUpdatedAt = '2026-07-22T12:00:00Z'
      ..manualHabitCadenceKind = 'weekdays'
      ..manualHabitWeekdays = [2, 4]
      ..manualHabitWeeklyTarget = 1
      ..manualHabitDuration = 35;
    final confirmsBeforeReload = backend.requests
        .where((request) => request.path.endsWith('/confirm'))
        .length;
    _invokeHeaderReload(tester);
    await tester.pumpAndSettle();

    await _openPlannerHabit(tester, 'Current outdoor walk');
    expect(find.text('Create a new preview?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('planner-replace-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Plan Habit'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-title')),
          )
          .controller
          ?.text,
      'Current outdoor walk',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-description')),
          )
          .controller
          ?.text,
      'Fresh saved Habit description.',
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('planner-habit-cadence')),
          )
          .initialValue,
      'weekdays',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      '35',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Review plan preview'), findsOneWidget);
    final proposals = backend.requests
        .where((request) => request.path.endsWith('/proposals'))
        .map((request) => request.data as Map<String, dynamic>)
        .toList(growable: false);
    expect(proposals, hasLength(2));
    final target = proposals.last['target'] as Map<String, dynamic>;
    expect(target['operation'], 'update');
    expect(target['title'], 'Current outdoor walk');
    expect(target['description'], 'Fresh saved Habit description.');
    expect(target['duration_minutes'], 35);
    expect(target['expected_updated_at'], '2026-07-22T12:00:00.000Z');
    expect(target['cadence'], {
      'kind': 'weekdays',
      'scheduled_weekdays': <int>[2, 4],
      'weekly_target': 1,
    });
    expect(
      backend.requests.where((request) => request.path.endsWith('/confirm')),
      hasLength(confirmsBeforeReload),
    );
  });

  testWidgets('scheduled Task replan reviews the authoritative target snapshot',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(
      scheduledTaskPending: true,
      forcedDynamicStaleSource: 'target',
    )
      ..taskTitle = 'Current scheduled Task'
      ..taskDescription = 'Authoritative scheduled description.'
      ..taskPriority = 'critical';

    await _pumpPlanner(tester, backend: backend);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('planner-pending-previews')),
        matching: find.text('Stale scheduled Task draft'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Create a new preview?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('planner-replace-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Plan Task'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-task-title')),
          )
          .controller
          ?.text,
      'Current scheduled Task',
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('planner-task-priority')),
          )
          .initialValue,
      'critical',
    );
    await tester.tap(find.byKey(const ValueKey('planner-task-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Review plan preview'), findsOneWidget);
    final proposal = backend.requests
        .lastWhere((request) => request.path.endsWith('/proposals'))
        .data as Map<String, dynamic>;
    final target = proposal['target'] as Map<String, dynamic>;
    expect(proposal['plan_id'], 'd0000000-0000-4000-8000-000000000098');
    expect(proposal['base_revision'], 2);
    expect(target['operation'], 'update');
    expect(target['title'], 'Current scheduled Task');
    expect(target['description'], 'Authoritative scheduled description.');
    expect(target['priority'], 'critical');
    expect(target['expected_updated_at'], '2026-07-20T08:00:00.000Z');
  });

  testWidgets('stale Task pending create becomes a reviewed new create',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(
      includePendingCreate: true,
      forcedDynamicStaleSource: 'calendar',
    );

    await _pumpPlanner(tester, backend: backend);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('planner-pending-previews')),
        matching: find.text('Prepare presentation'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Create a new preview?'), findsOneWidget);
    expect(
      find.textContaining('no saved Task or Habit exists yet'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('planner-replace-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Add Task'), findsOneWidget);
    expect(
      backend.requests.where((request) => request.path.endsWith('/proposals')),
      isEmpty,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-task-title')),
          )
          .controller
          ?.text,
      'Prepare presentation',
    );
    await tester.tap(find.byKey(const ValueKey('planner-task-preview')));
    await tester.pumpAndSettle();

    final proposal = backend.requests
        .singleWhere((request) => request.path.endsWith('/proposals'))
        .data as Map<String, dynamic>;
    final target = proposal['target'] as Map<String, dynamic>;
    expect(target['operation'], 'create');
    expect(target['expected_updated_at'], isNull);
    expect(target['title'], 'Prepare presentation');
    expect(target['description'], isNull);
    expect(target['priority'], 'high');
    expect(target['estimated_minutes'], 60);
    expect(target['deadline_at'], '2027-07-24T12:00:00.000Z');
    expect(target['preferred_session_minutes'], 30);
    expect(target['use_study_rhythm'], isFalse);
    expect(target['target_id'], isNot('b0000000-0000-4000-8000-000000000001'));
    expect(proposal['plan_id'], isNot('d0000000-0000-4000-8000-000000000001'));
    expect(
      backend.requests.where((request) => request.path.endsWith('/confirm')),
      isEmpty,
    );
  });

  testWidgets('stale Habit pending create becomes a reviewed new create',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(
      includePendingHabitCreate: true,
      forcedDynamicStaleSource: 'timezone',
    );

    await _pumpPlanner(tester, backend: backend);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('planner-pending-previews')),
        matching: find.text('Draft stretching'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Create a new preview?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('planner-replace-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Add Habit'), findsOneWidget);
    expect(
      backend.requests.where((request) => request.path.endsWith('/proposals')),
      isEmpty,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-title')),
          )
          .controller
          ?.text,
      'Draft stretching',
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('planner-habit-cadence')),
          )
          .initialValue,
      'weekdays',
    );
    await tester.tap(find.byKey(const ValueKey('planner-habit-preview')));
    await tester.pumpAndSettle();

    final proposal = backend.requests
        .singleWhere((request) => request.path.endsWith('/proposals'))
        .data as Map<String, dynamic>;
    final target = proposal['target'] as Map<String, dynamic>;
    expect(target['operation'], 'create');
    expect(target['expected_updated_at'], isNull);
    expect(target['title'], 'Draft stretching');
    expect(target['description'], 'Preview-only Habit details.');
    expect(target['duration_minutes'], 25);
    expect(target['target_id'], isNot('b0000000-0000-4000-8000-000000000099'));
    expect(proposal['plan_id'], isNot('d0000000-0000-4000-8000-000000000099'));
    expect(target['cadence'], {
      'kind': 'weekdays',
      'scheduled_weekdays': <int>[2, 4],
      'weekly_target': 1,
    });
  });

  for (final source in const [
    'target',
    'calendar',
    'timezone',
    'study',
  ]) {
    testWidgets('current $source drift opens exact-revision replacement',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpPlanner(
        tester,
        backend: _PlannerBackend(
          scheduledTaskPending: true,
          forcedDynamicStaleSource: source,
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('planner-pending-previews')),
          matching: find.text('Stale scheduled Task draft'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create a new preview?'), findsOneWidget);
      expect(find.text('Review plan preview'), findsNothing);
    });
  }

  testWidgets('current stale attention must match revision and kind exactly',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpPlanner(
      tester,
      backend: _PlannerBackend(
        scheduledTaskPending: true,
        forcedDynamicStaleSource: 'target',
        forcedStaleRevisionOffset: 1,
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('planner-pending-previews')),
        matching: find.text('Stale scheduled Task draft'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Review plan preview'), findsOneWidget);
    await tester.tap(find.text('Keep as draft'));
    await tester.pumpAndSettle();

    await _pumpPlanner(
      tester,
      backend: _PlannerBackend(
        scheduledTaskPending: true,
        forcedDynamicStaleSource: 'study',
        forcedStaleKind: 'study_rhythm_changed',
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('planner-pending-previews')),
        matching: find.text('Stale scheduled Task draft'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Review plan preview'), findsOneWidget);
    expect(find.text('Create a new preview?'), findsNothing);
  });

  for (final reason in const [
    'target_changed',
    'calendar_changed',
    'timezone_changed',
    'study_rhythm_changed',
  ]) {
    testWidgets('long-lived $reason does not stale the current pending preview',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpPlanner(
        tester,
        backend: _PlannerBackend(
          scheduledTaskPending: true,
          forcedPersistedStaleReason: reason,
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('planner-pending-previews')),
          matching: find.text('Stale scheduled Task draft'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Review plan preview'), findsOneWidget);
      expect(find.text('Create a new preview?'), findsNothing);
    });
  }

  testWidgets('pending creates stay visible without becoming persisted items',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpPlanner(
      tester,
      backend: _PlannerBackend(includePendingCreate: true),
    );

    expect(
      find.byKey(const ValueKey('planner-pending-previews')),
      findsOneWidget,
    );
    expect(find.text('Prepare presentation'), findsOneWidget);
    expect(find.text('2 active · 2 unplanned'), findsOneWidget);
    expect(find.text('Undated reading'), findsOneWidget);
  });

  testWidgets('empty attention uses the exact calm-state copy', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpPlanner(
      tester,
      backend: _PlannerBackend(emptyAttention: true),
    );

    expect(find.text('Nothing currently needs review.'), findsOneWidget);
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

  testWidgets(
      'durable Planner change stays locked when only its overview reload fails',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend();

    await _pumpPlanner(tester, backend: backend);
    backend.failNextOverview = true;
    await tester.tap(
      find.byKey(const ValueKey('planner-calendar-consent')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Change saved. Planner could not reload.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('planner-calendar-consent')),
          )
          .onChanged,
      isNull,
    );
    expect(
      backend.requests
          .where((request) => request.path == '/v1/planner/preferences'),
      hasLength(1),
    );

    await tester.tap(find.text('Reload Planner'));
    await tester.pumpAndSettle();

    expect(
      find.text('Change saved. Planner could not reload.'),
      findsNothing,
    );
    expect(
      backend.requests
          .where((request) => request.path == '/v1/planner/preferences'),
      hasLength(1),
    );
  });

  testWidgets(
      'committed proposal with failed overview reload exposes no preview action',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend();
    final controller = await _pumpPlanner(tester, backend: backend);

    await tester.tap(find.byKey(const ValueKey('planner-add-task')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('planner-task-title')),
      'Proposal saved before reload failed',
    );
    backend.failNextOverview = true;
    await tester.tap(find.byKey(const ValueKey('planner-task-preview')));
    await tester.pumpAndSettle();

    expect(
      controller.state.projectionStatus,
      PlannerProjectionStatus.staleAfterMutation,
    );
    expect(controller.state.canMutate, isFalse);
    expect(find.text('Review plan preview'), findsNothing);
    expect(find.byKey(const ValueKey('planner-confirm-plan')), findsNothing);
    expect(
      tester
          .widget<ListTile>(
            find.descendant(
              of: find.byKey(const ValueKey('planner-needs-attention')),
              matching: find.byType(ListTile),
            ),
          )
          .onTap,
      isNull,
    );
    expect(
      backend.requests.where((request) => request.path.endsWith('/confirm')),
      isEmpty,
    );

    await tester.tap(find.text('Reload Planner'));
    await tester.pumpAndSettle();
    expect(controller.state.canMutate, isTrue);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('planner-pending-previews')),
        matching: find.text('Proposal saved before reload failed'),
      ),
      findsOneWidget,
    );
    expect(
      backend.requests.where((request) => request.path.endsWith('/proposals')),
      hasLength(1),
    );
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

  testWidgets('failed Task update retains only its target-bound draft',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(failNextProposal: true);

    await _pumpPlanner(tester, backend: backend);
    await tester.scrollUntilVisible(find.text('Undated reading'), 400);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Undated reading'));
    await tester.tap(find.text('Undated reading'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('planner-task-title')),
      'Retained current Task edit',
    );
    await tester.tap(find.byKey(const ValueKey('planner-task-preview')));
    await tester.pumpAndSettle();

    _invokeAddNew(tester, 'planner-add-task');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-task-title')),
          )
          .controller
          ?.text,
      isEmpty,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Undated reading'), 400);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Undated reading'));
    await tester.tap(find.text('Undated reading'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-task-title')),
          )
          .controller
          ?.text,
      'Retained current Task edit',
    );
  });

  testWidgets('failed Habit create and update drafts stay target-bound',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(failNextProposal: true);

    await _pumpPlanner(tester, backend: backend);
    _invokeAddNew(tester, 'planner-add-habit');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-title')),
      'Retained new Habit',
    );
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '15',
    );
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('planner-habit-cadence')),
        )
        .onChanged!
        .call('daily');
    await tester.pump();
    _invokeFilledButton(tester, 'planner-habit-preview');
    await tester.pumpAndSettle();

    _invokeAddNew(tester, 'planner-add-habit');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-title')),
          )
          .controller
          ?.text,
      'Retained new Habit',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    backend.failNextProposal = true;
    await _openPlannerHabit(tester, 'Walk');
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-title')),
      'Retained Walk edit',
    );
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '25',
    );
    _invokeFilledButton(tester, 'planner-habit-preview');
    await tester.pumpAndSettle();

    _invokeAddNew(tester, 'planner-add-habit');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-title')),
          )
          .controller
          ?.text,
      'Retained new Habit',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    await _openPlannerHabit(tester, 'Walk');
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-title')),
          )
          .controller
          ?.text,
      'Retained Walk edit',
    );
  });

  testWidgets('pending Task updates remain discoverable after keeping draft',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _PlannerBackend(scheduledTaskPending: true);

    await _pumpPlanner(tester, backend: backend);
    final pendingRow = find.descendant(
      of: find.byKey(const ValueKey('planner-pending-previews')),
      matching: find.text('Stale scheduled Task draft'),
    );
    expect(pendingRow, findsOneWidget);
    await tester.tap(pendingRow);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Keep as draft'));
    await tester.pumpAndSettle();

    _invokeHeaderReload(tester);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('planner-pending-previews')),
        matching: find.text('Stale scheduled Task draft'),
      ),
      findsOneWidget,
    );
    expect(
      backend.requests.where((request) => request.path.endsWith('/confirm')),
      isEmpty,
    );
  });

  testWidgets(
      'stale replacement drafts survive availability Back only for their exact preview',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cases = <({
      _PlannerBackend backend,
      String pendingTitle,
      String editedTitle,
      bool habit,
    })>[
      (
        backend: _PlannerBackend(
          scheduledTaskPending: true,
          forcedDynamicStaleSource: 'target',
          incompleteAvailability: true,
        ),
        pendingTitle: 'Stale scheduled Task draft',
        editedTitle: 'Retained exact scheduled Task',
        habit: false,
      ),
      (
        backend: _PlannerBackend(
          scheduledManualHabitPending: true,
          forcedDynamicStaleSource: 'target',
          incompleteAvailability: true,
        ),
        pendingTitle: 'Stale Walk draft',
        editedTitle: 'Retained exact Walk',
        habit: true,
      ),
      (
        backend: _PlannerBackend(
          includePendingCreate: true,
          forcedDynamicStaleSource: 'calendar',
          incompleteAvailability: true,
        ),
        pendingTitle: 'Prepare presentation',
        editedTitle: 'Retained exact new Task',
        habit: false,
      ),
      (
        backend: _PlannerBackend(
          includePendingHabitCreate: true,
          forcedDynamicStaleSource: 'timezone',
          incompleteAvailability: true,
        ),
        pendingTitle: 'Draft stretching',
        editedTitle: 'Retained exact new Habit',
        habit: true,
      ),
    ];

    for (final value in cases) {
      await _exerciseStaleReplacementRetention(
        tester,
        backend: value.backend,
        pendingTitle: value.pendingTitle,
        editedTitle: value.editedTitle,
        habit: value.habit,
        availabilityBack: true,
      );
    }
  });

  testWidgets(
      'stale replacement drafts survive ordinary 422 only for their exact preview',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cases = <({
      _PlannerBackend backend,
      String pendingTitle,
      String editedTitle,
      bool habit,
    })>[
      (
        backend: _PlannerBackend(
          scheduledTaskPending: true,
          forcedDynamicStaleSource: 'target',
          failNextProposal: true,
        ),
        pendingTitle: 'Stale scheduled Task draft',
        editedTitle: '422 exact scheduled Task',
        habit: false,
      ),
      (
        backend: _PlannerBackend(
          scheduledManualHabitPending: true,
          forcedDynamicStaleSource: 'target',
          failNextProposal: true,
        ),
        pendingTitle: 'Stale Walk draft',
        editedTitle: '422 exact Walk',
        habit: true,
      ),
      (
        backend: _PlannerBackend(
          includePendingCreate: true,
          forcedDynamicStaleSource: 'calendar',
          failNextProposal: true,
        ),
        pendingTitle: 'Prepare presentation',
        editedTitle: '422 exact new Task',
        habit: false,
      ),
      (
        backend: _PlannerBackend(
          includePendingHabitCreate: true,
          forcedDynamicStaleSource: 'timezone',
          failNextProposal: true,
        ),
        pendingTitle: 'Draft stretching',
        editedTitle: '422 exact new Habit',
        habit: true,
      ),
    ];

    for (final value in cases) {
      await _exerciseStaleReplacementRetention(
        tester,
        backend: value.backend,
        pendingTitle: value.pendingTitle,
        editedTitle: value.editedTitle,
        habit: value.habit,
        availabilityBack: false,
      );
    }
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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('planner-habits')),
      300,
    );
    await tester.tap(find.text('Habits'));
    await tester.pumpAndSettle();
    final setupHabit = find.descendant(
      of: find.byKey(const ValueKey('planner-habits')),
      matching: find.text('Read'),
    );
    await tester.scrollUntilVisible(setupHabit, 200);
    await tester.tap(setupHabit);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('planner-habit-read-only-definition')),
      findsOneWidget,
    );
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
      find.textContaining('Try loading the outlook again'),
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

void _invokeHeaderReload(WidgetTester tester) {
  final button = find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == 'Reload Planner',
    skipOffstage: false,
  );
  expect(button, findsOneWidget);
  tester.widget<IconButton>(button).onPressed?.call();
}

void _invokeAddNew(WidgetTester tester, String key) {
  final button = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(OutlinedButton),
  );
  expect(button, findsOneWidget);
  final callback = tester.widget<OutlinedButton>(button).onPressed;
  expect(callback, isNotNull);
  callback!.call();
}

void _invokeFilledButton(WidgetTester tester, String key) {
  final button = find.byKey(ValueKey(key));
  expect(button, findsOneWidget);
  final callback = tester.widget<FilledButton>(button).onPressed;
  expect(callback, isNotNull);
  callback!.call();
}

Future<void> _openPlannerHabit(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('planner-habits')),
    400,
  );
  var habit = find.descendant(
    of: find.byKey(const ValueKey('planner-habits')),
    matching: find.text(title),
  );
  if (habit.evaluate().isEmpty) {
    await tester.tap(find.text('Habits'));
    await tester.pumpAndSettle();
    habit = find.descendant(
      of: find.byKey(const ValueKey('planner-habits')),
      matching: find.text(title),
    );
  }
  await tester.scrollUntilVisible(habit, 250);
  await tester.tap(habit);
  await tester.pumpAndSettle();
}

Future<void> _exerciseAmbiguousCreateReconciliation(
  WidgetTester tester, {
  required _PlannerBackend backend,
  required bool habit,
  required String title,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  final controller = await _pumpPlanner(tester, backend: backend);
  _invokeAddNew(tester, habit ? 'planner-add-habit' : 'planner-add-task');
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(
      ValueKey(habit ? 'planner-habit-title' : 'planner-task-title'),
    ),
    title,
  );
  if (habit) {
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '25',
    );
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('planner-habit-cadence')),
        )
        .onChanged!
        .call('daily');
    await tester.pump();
  }
  _invokeFilledButton(
    tester,
    habit ? 'planner-habit-preview' : 'planner-task-preview',
  );
  await tester.pumpAndSettle();
  expect(controller.state.requiresExactRetry, isTrue, reason: title);
  expect(find.text('Result not confirmed'), findsOneWidget);

  _invokeHeaderReload(tester);
  await tester.pumpAndSettle();
  expect(controller.state.requiresExactRetry, isFalse);
  expect(controller.state.operationError, isNull);
  expect(
    backend.requests.where((request) => request.path.endsWith('/proposals')),
    hasLength(1),
  );
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey('planner-pending-previews')),
      matching: find.text(title),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('planner-confirm-plan')));
  await tester.pumpAndSettle();
  expect(
    backend.requests.where((request) => request.path.endsWith('/proposals')),
    hasLength(1),
  );

  _invokeAddNew(tester, habit ? 'planner-add-habit' : 'planner-add-task');
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<TextField>(
          find.byKey(
            ValueKey(habit ? 'planner-habit-title' : 'planner-task-title'),
          ),
        )
        .controller
        ?.text,
    isEmpty,
  );
  await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
  await tester.pumpAndSettle();
}

Future<void> _exerciseStaleReplacementRetention(
  WidgetTester tester, {
  required _PlannerBackend backend,
  required String pendingTitle,
  required String editedTitle,
  required bool habit,
  required bool availabilityBack,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await _pumpPlanner(tester, backend: backend);
  Finder pendingRow() => find.descendant(
        of: find.byKey(const ValueKey('planner-pending-previews')),
        matching: find.text(pendingTitle),
      );

  await tester.scrollUntilVisible(pendingRow(), 300);
  await tester.tap(pendingRow());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('planner-replace-preview')));
  await tester.pumpAndSettle();
  final titleKey = ValueKey(
    habit ? 'planner-habit-title' : 'planner-task-title',
  );
  await tester.enterText(find.byKey(titleKey), editedTitle);
  if (habit) {
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '25',
    );
  }
  await tester.tap(
    find.byKey(
      ValueKey(habit ? 'planner-habit-preview' : 'planner-task-preview'),
    ),
  );
  await tester.pumpAndSettle();
  if (availabilityBack) {
    expect(
      find.text('Review your availability'),
      findsOneWidget,
      reason: pendingTitle,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Back'));
    await tester.pumpAndSettle();
    expect(
      backend.requests.where((request) => request.path.endsWith('/proposals')),
      isEmpty,
    );
  } else {
    expect(
      find.text(
        'Planner could not save that change. Your entered values are retained.',
      ),
      findsOneWidget,
    );
  }

  await tester.scrollUntilVisible(pendingRow(), 300);
  await tester.tap(pendingRow());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('planner-replace-preview')));
  await tester.pumpAndSettle();
  expect(
    tester.widget<TextField>(find.byKey(titleKey)).controller?.text,
    editedTitle,
  );
  await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
  await tester.pumpAndSettle();
}

Future<void> _exerciseStaleReplacementExactRetry(
  WidgetTester tester, {
  required _PlannerBackend backend,
  required String pendingTitle,
  required bool habit,
  required bool setup,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  final controller = await _pumpPlanner(tester, backend: backend);
  final pending = find.descendant(
    of: find.byKey(const ValueKey('planner-pending-previews')),
    matching: find.text(pendingTitle),
  );
  await tester.scrollUntilVisible(pending, 300);
  await tester.tap(pending);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('planner-replace-preview')));
  await tester.pumpAndSettle();
  if (habit) {
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '25',
    );
  }
  await tester.tap(
    find.byKey(
      ValueKey(habit ? 'planner-habit-preview' : 'planner-task-preview'),
    ),
  );
  await tester.pumpAndSettle();

  expect(controller.state.requiresExactRetry, isTrue, reason: pendingTitle);
  final firstProposal = backend.requests
      .lastWhere((request) => request.path.endsWith('/proposals'))
      .data as Map<String, dynamic>;
  backend.forcedDynamicStaleSource = null;
  await tester.tap(find.widgetWithText(FilledButton, 'Retry same change'));
  await tester.pumpAndSettle();

  expect(controller.state.requiresExactRetry, isFalse, reason: pendingTitle);
  expect(find.text('Review plan preview'), findsOneWidget);
  final proposals = backend.requests
      .where((request) => request.path.endsWith('/proposals'))
      .map((request) => request.data as Map<String, dynamic>)
      .toList(growable: false);
  expect(proposals, hasLength(2), reason: pendingTitle);
  expect(proposals.last, firstProposal, reason: pendingTitle);
  await tester.tap(find.byKey(const ValueKey('planner-confirm-plan')));
  await tester.pumpAndSettle();
  expect(
    backend.requests.where((request) => request.path.endsWith('/confirm')),
    hasLength(1),
    reason: pendingTitle,
  );
  if (setup) {
    await _openPlannerHabit(tester, 'Read');
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      '30',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
  }
}

Future<void> _exerciseStaleReplacementExactRetryFailure(
  WidgetTester tester, {
  required _PlannerBackend backend,
  required String pendingTitle,
  required bool habit,
  required bool setup,
  required String editedTitle,
  required String freshTitle,
  required int retryStatus,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  final controller = await _pumpPlanner(tester, backend: backend);
  Finder pendingRow() => find.descendant(
        of: find.byKey(const ValueKey('planner-pending-previews')),
        matching: find.text(pendingTitle),
      );

  await tester.scrollUntilVisible(pendingRow(), 300);
  await tester.tap(pendingRow());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('planner-replace-preview')));
  await tester.pumpAndSettle();
  if (!setup) {
    await tester.enterText(
      find.byKey(
        ValueKey(habit ? 'planner-habit-title' : 'planner-task-title'),
      ),
      editedTitle,
    );
  }
  if (habit) {
    await tester.enterText(
      find.byKey(const ValueKey('planner-habit-duration')),
      '35',
    );
  }
  await tester.tap(
    find.byKey(
      ValueKey(habit ? 'planner-habit-preview' : 'planner-task-preview'),
    ),
  );
  await tester.pumpAndSettle();
  expect(controller.state.requiresExactRetry, isTrue, reason: pendingTitle);
  final firstBody = backend.requests
      .lastWhere((request) => request.path.endsWith('/proposals'))
      .data;

  backend.failNextProposalStatus = retryStatus;
  await tester.tap(find.widgetWithText(FilledButton, 'Retry same change'));
  await tester.pumpAndSettle();
  expect(controller.state.requiresExactRetry, isFalse, reason: pendingTitle);
  final proposalBodies = backend.requests
      .where((request) => request.path.endsWith('/proposals'))
      .map((request) => request.data)
      .toList(growable: false);
  expect(proposalBodies, [firstBody, firstBody], reason: pendingTitle);

  if (retryStatus == 409) {
    expect(controller.state.reloadSuggested, isTrue, reason: pendingTitle);
    _invokeHeaderReload(tester);
    await tester.pumpAndSettle();
    expect(controller.state.canMutate, isTrue, reason: pendingTitle);
  } else {
    expect(controller.state.reloadSuggested, isFalse, reason: pendingTitle);
  }

  await tester.scrollUntilVisible(pendingRow(), 300);
  await tester.tap(pendingRow());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('planner-replace-preview')));
  await tester.pumpAndSettle();
  if (setup) {
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('planner-habit-duration')),
          )
          .controller
          ?.text,
      retryStatus == 422 ? '35' : '25',
      reason: pendingTitle,
    );
  } else {
    expect(
      tester
          .widget<TextField>(
            find.byKey(
              ValueKey(habit ? 'planner-habit-title' : 'planner-task-title'),
            ),
          )
          .controller
          ?.text,
      retryStatus == 422 ? editedTitle : freshTitle,
      reason: pendingTitle,
    );
  }
  await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
  await tester.pumpAndSettle();
}

Future<PlannerController> _pumpPlanner(
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
        projectionRefreshCoordinatorProvider.overrideWithValue(
          ProjectionRefreshCoordinator(
            refreshDailySnapshot: (_) async {},
            invalidateProjection: (_) {},
          ),
        ),
        plannerControllerProvider.overrideWith((ref) => controller),
        examWeekOutlookProvider.overrideWith(
          (ref) => (outlookLoader ?? () async => null)(),
        ),
        examPlanHealthProvider.overrideWith((ref) async => null),
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
  return controller;
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
    this.failNextProposalStatus,
    this.persistFailedProposal = false,
    this.mismatchPersistedProposal = false,
    this.failNextConfirmStatus,
    this.incompleteAvailability = false,
    this.learnedTiming = false,
    this.learnedTimingFallback = false,
    this.includePendingCreate = false,
    this.emptyAttention = false,
    this.secondSetupHabit = false,
    this.scheduledTaskPending = false,
    this.scheduledManualHabitPending = false,
    this.includePendingHabitCreate = false,
    this.coldSetupHabitPending = false,
    this.forcedDynamicStaleSource,
    this.forcedPersistedStaleReason,
    this.forcedStaleRevisionOffset = 0,
    this.forcedStaleKind,
    this.confirmedSetupHabitDuration,
  }) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests
              .add(_PlannerRequest(options.method, options.path, options.data));
          if (options.path == '/v1/planner/overview') {
            if (failNextOverview) {
              failNextOverview = false;
              return handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response<Object?>(
                    requestOptions: options,
                    statusCode: 503,
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            }
            final overview = plannerOverviewEnvelope();
            if (emptyAttention) {
              overview['needs_attention'] = <dynamic>[];
            }
            final habits = overview['habits'] as List<dynamic>;
            final tasks = overview['unscheduled_tasks'] as List<dynamic>;
            final taskTargets = overview['task_targets'] as List<dynamic>;
            final task = tasks.first as Map<String, dynamic>;
            final taskTarget = taskTargets.first as Map<String, dynamic>;
            for (final current in [task, taskTarget]) {
              current
                ..['title'] = taskTitle
                ..['description'] = taskDescription
                ..['expected_updated_at'] = taskExpectedUpdatedAt
                ..['priority'] = taskPriority;
            }
            final setupHabit = habits.first as Map<String, dynamic>;
            setupHabit
              ..['title'] = setupHabitTitle
              ..['description'] = setupHabitDescription
              ..['expected_updated_at'] = setupHabitExpectedUpdatedAt
              ..['duration_minutes'] = setupHabitDuration
              ..['cadence'] = {
                'kind': setupHabitCadenceKind,
                'scheduled_weekdays': setupHabitCadenceKind == 'weekdays'
                    ? setupHabitWeekdays
                    : <dynamic>[],
                'weekly_target': setupHabitWeeklyTarget,
              };
            final manualHabit = habits[1] as Map<String, dynamic>;
            manualHabit
              ..['title'] = manualHabitTitle
              ..['description'] = manualHabitDescription
              ..['expected_updated_at'] = manualHabitExpectedUpdatedAt
              ..['duration_minutes'] = manualHabitDuration
              ..['cadence'] = {
                'kind': manualHabitCadenceKind,
                'scheduled_weekdays': manualHabitCadenceKind == 'weekdays'
                    ? manualHabitWeekdays
                    : <dynamic>[],
                'weekly_target': manualHabitWeeklyTarget,
              };
            final plansById = <String, Map<String, dynamic>>{};
            void includePlan(Map<String, dynamic> plan) {
              final id = plan['id'] as String;
              if (!_resolvedPlanIds.contains(id)) {
                plansById[id] = Map<String, dynamic>.from(plan);
              }
            }

            if (includePendingCreate) includePlan(_pendingTaskCreatePlan());
            if (includePendingHabitCreate) {
              includePlan(_pendingHabitCreatePlan());
            }
            if (coldSetupHabitPending &&
                !_resolvedPlanIds
                    .contains(_coldSetupHabitPendingPlan()['id']) &&
                !_pendingPlansById
                    .containsKey(_coldSetupHabitPendingPlan()['id'])) {
              includePlan(_coldSetupHabitPendingPlan());
            }
            if (scheduledTaskPending) {
              includePlan(_scheduledTaskPendingPlan());
              taskTarget
                ..['estimated_minutes'] = 60
                ..['deadline_at'] = '2027-07-24T12:00:00Z'
                ..['preferred_session_minutes'] = 30;
            }
            if (scheduledManualHabitPending &&
                !_resolvedPlanIds
                    .contains(_scheduledManualHabitPendingPlan()['id']) &&
                !_pendingPlansById
                    .containsKey(_scheduledManualHabitPendingPlan()['id'])) {
              includePlan(_scheduledManualHabitPendingPlan());
            }
            for (final plan in _pendingPlansById.values) {
              includePlan(plan);
            }
            overview['action_plans'] = plansById.values.toList();

            for (final plan in plansById.values) {
              final pending = plan['pending_revision'] as Map?;
              final active = plan['active_revision'] as Map?;
              final target = (pending?['target'] ?? active?['target']) as Map?;
              if (target == null || target['operation'] == 'create') continue;
              if (target['kind'] == 'habit') {
                final targetId = target['target_id'];
                final matches = habits.cast<Map>().where(
                      (habit) => habit['id'] == targetId,
                    );
                if (matches.isNotEmpty) {
                  matches.single
                    ..['plan_id'] = plan['id']
                    ..['has_pending_preview'] = pending != null;
                }
                continue;
              }
              final activeMinutes = _activeTaskMinutesFromPlan(plan);
              if (activeMinutes > 0) {
                overview['unscheduled_tasks'] = (overview['unscheduled_tasks']
                        as List<dynamic>)
                    .where((task) => (task as Map)['id'] != target['target_id'])
                    .toList(growable: false);
              }
            }

            String? currentExpectedUpdatedAt(Map<String, dynamic> plan) {
              final pending = plan['pending_revision'] as Map?;
              final target = pending?['target'] as Map?;
              final targetId = target?['target_id'];
              if (target?['kind'] == 'task' && targetId == taskTarget['id']) {
                return taskExpectedUpdatedAt;
              }
              if (target?['kind'] == 'habit') {
                if (targetId == setupHabit['id']) {
                  return setupHabitExpectedUpdatedAt;
                }
                if (targetId == manualHabit['id']) {
                  return manualHabitExpectedUpdatedAt;
                }
              }
              return null;
            }

            final stalePlans = plansById.values.where((plan) {
              final expectedUpdatedAt = currentExpectedUpdatedAt(plan);
              return expectedUpdatedAt != null &&
                  _persistedTargetVersionChanged(
                    plan: plan,
                    expectedUpdatedAt: expectedUpdatedAt,
                  );
            });
            for (final stalePlan in stalePlans) {
              final pending = stalePlan['pending_revision'] as Map;
              overview['needs_attention'] = <dynamic>[
                ...overview['needs_attention'] as List<dynamic>,
                {
                  'id':
                      '${stalePlan['id']}:target-stale:${pending['revision']}',
                  'kind': 'stale_preview',
                  'target': 'plan',
                  'title': (pending['target'] as Map)['title'],
                  'detail': 'The Task or Habit changed. Create a new preview.',
                  'plan_id': stalePlan['id'],
                  'unplaced_minutes': 0,
                  'conflict_source': null,
                },
              ];
            }
            final dynamicSource = forcedDynamicStaleSource;
            if (dynamicSource != null) {
              final plans = plansById.values
                  .where((plan) => plan['pending_revision'] != null)
                  .toList(growable: false);
              if (plans.isNotEmpty) {
                final stalePlan = plans.first;
                final pending = stalePlan['pending_revision'] as Map;
                final suffix = switch (dynamicSource) {
                  'calendar' => 'calendar-stale',
                  'target' => 'target-stale',
                  'study' => 'study-stale',
                  'timezone' => 'timezone-stale',
                  _ => throw StateError(
                      'Unknown dynamic stale source $dynamicSource',
                    ),
                };
                overview['needs_attention'] = <dynamic>[
                  ...overview['needs_attention'] as List<dynamic>,
                  {
                    'id': '${stalePlan['id']}:$suffix:'
                        '${(pending['revision'] as int) + forcedStaleRevisionOffset}',
                    'kind': forcedStaleKind ?? 'stale_preview',
                    'target': 'plan',
                    'title': (pending['target'] as Map)['title'],
                    'detail': 'Current inputs changed. Create a new preview.',
                    'plan_id': stalePlan['id'],
                    'unplaced_minutes': 0,
                    'conflict_source': null,
                  },
                ];
              }
            }
            final forcedReason = forcedPersistedStaleReason;
            if (forcedReason != null) {
              final plans = overview['action_plans'] as List<dynamic>;
              if (plans.isNotEmpty) {
                final stalePlan = plans.first as Map<String, dynamic>;
                final pending = stalePlan['pending_revision'] as Map;
                final revision = pending['revision'] as int;
                final kind = forcedStaleKind ??
                    (forcedReason == 'study_rhythm_changed'
                        ? 'study_rhythm_changed'
                        : 'stale_preview');
                stalePlan
                  ..['needs_attention'] = true
                  ..['attention_reasons'] = <dynamic>[forcedReason];
                overview['needs_attention'] = <dynamic>[
                  ...overview['needs_attention'] as List<dynamic>,
                  {
                    'id':
                        '${stalePlan['id']}:persisted:$forcedReason:${revision + forcedStaleRevisionOffset}',
                    'kind': kind,
                    'target': 'plan',
                    'title': (pending['target'] as Map)['title'],
                    'detail': 'Saved inputs changed. Create a new preview.',
                    'plan_id': stalePlan['id'],
                    'unplaced_minutes': 0,
                    'conflict_source': null,
                  },
                ];
              }
            }
            if (secondSetupHabit) {
              final second = habits[1] as Map<String, dynamic>;
              second['ownership'] = 'setup';
              second['duration_minutes'] = 35;
            }
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
            transformOverview?.call(overview);
            return handler.resolve(_response(options, overview));
          }
          if (options.path.endsWith('/proposals')) {
            final body = Map<String, dynamic>.from(options.data as Map);
            if (failNextProposal || failNextProposalStatus != null) {
              failNextProposal = false;
              final status = failNextProposalStatus ?? 422;
              failNextProposalStatus = null;
              if (persistFailedProposal) {
                _persistProposal(
                  body,
                  mismatch: mismatchPersistedProposal,
                );
              }
              return handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response<Object?>(
                    requestOptions: options,
                    statusCode: status,
                    data: {'detail': 'invalid proposal'},
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            }
            final envelope = _persistProposal(body);
            return handler.resolve(_response(options, envelope));
          }
          if (options.path.endsWith('/confirm')) {
            if (failNextConfirmStatus != null) {
              final status = failNextConfirmStatus!;
              failNextConfirmStatus = null;
              return handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response<Object?>(
                    requestOptions: options,
                    statusCode: status,
                    data: {'detail': 'confirmation unavailable'},
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            }
            final segments = options.path.split('/');
            final planId = segments[segments.length - 2];
            final plan =
                _pendingPlansById[planId] ?? _currentPlanForProposal(planId);
            final pending = plan?['pending_revision'] as Map?;
            final body = _proposalBodiesByPlanId[planId] ??
                (pending == null
                    ? null
                    : <String, dynamic>{
                        'request_id': 'e0000000-0000-4000-8000-000000000095',
                        'plan_id': planId,
                        'base_revision': pending['base_revision'],
                        'planning_start_on': pending['planning_start_on'],
                        'target': pending['target'],
                      });
            if (body == null || plan == null) {
              return handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response<Object?>(
                    requestOptions: options,
                    statusCode: 409,
                    data: {'detail': 'preview is no longer pending'},
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            }
            final target = body['target'] as Map<String, dynamic>;
            _pendingPlansById.remove(planId);
            _proposalBodiesByPlanId.remove(planId);
            _resolvedPlanIds.add(planId);
            if (target['kind'] == 'habit') {
              if (target['target_id'] ==
                  '40000000-0000-4000-8000-000000000002') {
                setupHabitDuration = confirmedSetupHabitDuration ??
                    target['duration_minutes'] as int;
              }
              return handler.resolve(
                _response(
                  options,
                  _habitPlanEnvelopeFromProposal(body, active: true),
                ),
              );
            }
            return handler.resolve(
              _response(options, _activeTaskPlanEnvelope(plan)),
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
  bool failNextOverview = false;
  bool failNextProposal;
  int? failNextProposalStatus;
  final bool persistFailedProposal;
  final bool mismatchPersistedProposal;
  int? failNextConfirmStatus;
  final bool incompleteAvailability;
  final bool learnedTiming;
  final bool learnedTimingFallback;
  final bool includePendingCreate;
  final bool emptyAttention;
  final bool secondSetupHabit;
  final bool scheduledTaskPending;
  final bool scheduledManualHabitPending;
  final bool includePendingHabitCreate;
  final bool coldSetupHabitPending;
  String? forcedDynamicStaleSource;
  final String? forcedPersistedStaleReason;
  final int forcedStaleRevisionOffset;
  final String? forcedStaleKind;
  final int? confirmedSetupHabitDuration;
  String taskTitle = 'Undated reading';
  String? taskDescription;
  void Function(Map<String, dynamic>)? transformOverview;
  String taskExpectedUpdatedAt = '2026-07-20T08:00:00Z';
  String taskPriority = 'medium';
  String setupHabitTitle = 'Read';
  String? setupHabitDescription = 'Keep up with the course reader.';
  String setupHabitExpectedUpdatedAt = '2026-07-20T08:00:00Z';
  String setupHabitCadenceKind = 'daily';
  List<int> setupHabitWeekdays = [];
  int setupHabitWeeklyTarget = 1;
  int setupHabitDuration = 20;
  String manualHabitTitle = 'Walk';
  String? manualHabitDescription;
  String manualHabitExpectedUpdatedAt = '2026-07-20T08:00:00Z';
  String manualHabitCadenceKind = 'weekly_target';
  List<int> manualHabitWeekdays = [];
  int manualHabitWeeklyTarget = 3;
  int? manualHabitDuration;
  final Map<String, Map<String, dynamic>> _pendingPlansById = {};
  final Map<String, Map<String, dynamic>> _proposalBodiesByPlanId = {};
  final Map<String, Map<String, dynamic>> _suspendedPendingPlansById = {};
  final Map<String, Map<String, dynamic>> _suspendedProposalBodiesByPlanId = {};
  final Set<String> _resolvedPlanIds = {};

  void reopenResolvedPlan(String planId) {
    _resolvedPlanIds.remove(planId);
  }

  void suspendPendingPlan(String planId) {
    final plan = _pendingPlansById.remove(planId);
    final body = _proposalBodiesByPlanId.remove(planId);
    if (plan == null || body == null) {
      throw StateError('No pending plan to suspend for $planId.');
    }
    _suspendedPendingPlansById[planId] = plan;
    _suspendedProposalBodiesByPlanId[planId] = body;
  }

  void restoreSuspendedPendingPlan(String planId) {
    final plan = _suspendedPendingPlansById.remove(planId);
    final body = _suspendedProposalBodiesByPlanId.remove(planId);
    if (plan == null || body == null) {
      throw StateError('No suspended pending plan for $planId.');
    }
    _pendingPlansById[planId] = plan;
    _proposalBodiesByPlanId[planId] = body;
  }

  Map<String, dynamic> _persistProposal(
    Map<String, dynamic> body, {
    bool mismatch = false,
  }) {
    final storedBody = Map<String, dynamic>.from(body);
    final target = Map<String, dynamic>.from(body['target'] as Map);
    if (mismatch) target['title'] = 'Different server proposal';
    storedBody['target'] = target;
    late final Map<String, dynamic> envelope;
    if (target['kind'] == 'habit') {
      envelope = _habitPlanEnvelopeFromProposal(storedBody);
    } else {
      final prior = _currentPlanForProposal(storedBody['plan_id'] as String);
      envelope = _taskPlanEnvelopeFromProposal(
        storedBody,
        activeRevision: prior?['active_revision'] as Map?,
        learnedTiming: learnedTiming,
        learnedTimingFallback: learnedTimingFallback,
      );
    }
    final plan = Map<String, dynamic>.from(envelope['plan'] as Map);
    final planId = storedBody['plan_id'] as String;
    _pendingPlansById[planId] = Map<String, dynamic>.from(plan);
    _proposalBodiesByPlanId[planId] = storedBody;
    _resolvedPlanIds.remove(planId);
    return envelope;
  }

  Map<String, dynamic>? _currentPlanForProposal(String planId) {
    final pending = _pendingPlansById[planId];
    if (pending != null) return pending;
    if (scheduledTaskPending &&
        _scheduledTaskPendingPlan()['id'] == planId &&
        !_resolvedPlanIds.contains(planId)) {
      return _scheduledTaskPendingPlan();
    }
    if (coldSetupHabitPending &&
        _coldSetupHabitPendingPlan()['id'] == planId &&
        !_resolvedPlanIds.contains(planId)) {
      return _coldSetupHabitPendingPlan();
    }
    if (scheduledManualHabitPending &&
        _scheduledManualHabitPendingPlan()['id'] == planId &&
        !_resolvedPlanIds.contains(planId)) {
      return _scheduledManualHabitPendingPlan();
    }
    return null;
  }

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

bool _persistedTargetVersionChanged({
  required Map<String, dynamic>? plan,
  required String expectedUpdatedAt,
}) {
  final pending = plan?['pending_revision'] as Map?;
  final target = pending?['target'] as Map?;
  final previewVersion = target?['expected_updated_at'];
  return previewVersion is String &&
      !DateTime.parse(previewVersion)
          .isAtSameMomentAs(DateTime.parse(expectedUpdatedAt));
}

int _activeTaskMinutesFromPlan(Map<String, dynamic> plan) {
  final active = plan['active_revision'] as Map?;
  if (active == null) return 0;
  return (active['task_blocks'] as List<dynamic>? ?? const <dynamic>[])
      .cast<Map>()
      .where((block) => block['state'] == 'active')
      .fold<int>(
        0,
        (total, block) => total + (block['planned_minutes'] as int),
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

Map<String, dynamic> _pendingTaskCreatePlan() {
  final plan = Map<String, dynamic>.from(plannerActionPlan());
  final revision = Map<String, dynamic>.from(
    plan['pending_revision'] as Map,
  );
  final target = Map<String, dynamic>.from(revision['target'] as Map);
  target['deadline_at'] = '2027-07-24T12:00:00Z';
  revision['target'] = target;
  plan['pending_revision'] = revision;
  return plan;
}

Map<String, dynamic> _pendingHabitCreatePlan() {
  final plan = Map<String, dynamic>.from(plannerActionPlan());
  final revision = Map<String, dynamic>.from(
    plan['pending_revision'] as Map,
  );
  revision
    ..['target'] = {
      'kind': 'habit',
      'operation': 'create',
      'target_id': 'b0000000-0000-4000-8000-000000000099',
      'expected_updated_at': null,
      'title': 'Draft stretching',
      'description': 'Preview-only Habit details.',
      'cadence': {
        'kind': 'weekdays',
        'scheduled_weekdays': <int>[2, 4],
        'weekly_target': 1,
      },
      'duration_minutes': 25,
    }
    ..['planned_minutes'] = 0
    ..['unscheduled_minutes'] = 0
    ..['task_blocks'] = <dynamic>[]
    ..['habit_slots'] = <dynamic>[];
  plan
    ..['id'] = 'd0000000-0000-4000-8000-000000000099'
    ..['target_kind'] = 'habit'
    ..['target_id'] = 'b0000000-0000-4000-8000-000000000099'
    ..['pending_revision'] = revision;
  return plan;
}

Map<String, dynamic> _coldSetupHabitPendingPlan() {
  const planId = 'd0000000-0000-4000-8000-000000000097';
  final envelope = _habitPlanEnvelopeFromProposal({
    'request_id': 'e0000000-0000-4000-8000-000000000097',
    'plan_id': planId,
    'base_revision': 0,
    'planning_start_on': '2026-07-21',
    'target': {
      'kind': 'habit',
      'operation': 'update',
      'target_id': '40000000-0000-4000-8000-000000000002',
      'expected_updated_at': '2026-07-19T08:00:00Z',
      'title': 'Old persisted Setup title',
      'description': 'Old persisted Setup description.',
      'cadence': {
        'kind': 'daily',
        'scheduled_weekdays': <int>[],
        'weekly_target': 1,
      },
      'duration_minutes': 25,
    },
  });
  return Map<String, dynamic>.from(envelope['plan'] as Map);
}

Map<String, dynamic> _scheduledTaskPendingPlan() {
  final plan = Map<String, dynamic>.from(plannerActionPlan(state: 'active'));
  final active = Map<String, dynamic>.from(plan['active_revision'] as Map);
  final activeTarget = Map<String, dynamic>.from(active['target'] as Map);
  const targetId = '80000000-0000-4000-8000-000000000001';
  activeTarget
    ..['operation'] = 'update'
    ..['target_id'] = targetId
    ..['expected_updated_at'] = '2026-07-19T08:00:00Z'
    ..['title'] = 'Earlier scheduled Task'
    ..['description'] = 'Earlier saved description.'
    ..['priority'] = 'low'
    ..['estimated_minutes'] = 60
    ..['deadline_at'] = '2027-07-24T12:00:00Z'
    ..['preferred_session_minutes'] = 30;
  active['target'] = activeTarget;

  final pending = Map<String, dynamic>.from(active);
  final pendingTarget = Map<String, dynamic>.from(activeTarget)
    ..['expected_updated_at'] = '2026-07-20T08:00:00Z'
    ..['title'] = 'Stale scheduled Task draft';
  pending
    ..['revision'] = 2
    ..['base_revision'] = 1
    ..['state'] = 'proposed'
    ..['target'] = pendingTarget
    ..['task_blocks'] = [
      for (final raw in active['task_blocks'] as List<dynamic>)
        {
          ...Map<String, dynamic>.from(raw as Map),
          'state': 'proposed',
        },
    ]
    ..['activated_at'] = null;
  plan
    ..['id'] = 'd0000000-0000-4000-8000-000000000098'
    ..['target_id'] = targetId
    ..['status'] = 'active'
    ..['current_revision'] = 1
    ..['latest_revision'] = 2
    ..['active_revision'] = active
    ..['pending_revision'] = pending;
  return plan;
}

Map<String, dynamic> _scheduledManualHabitPendingPlan() {
  const planId = 'd0000000-0000-4000-8000-000000000096';
  final envelope = _habitPlanEnvelopeFromProposal({
    'request_id': 'e0000000-0000-4000-8000-000000000096',
    'plan_id': planId,
    'base_revision': 0,
    'planning_start_on': '2026-07-21',
    'target': {
      'kind': 'habit',
      'operation': 'update',
      'target_id': '80000000-0000-4000-8000-000000000002',
      'expected_updated_at': '2026-07-20T08:00:00Z',
      'title': 'Stale Walk draft',
      'description': null,
      'cadence': {
        'kind': 'weekly_target',
        'scheduled_weekdays': <int>[],
        'weekly_target': 3,
      },
      'duration_minutes': 25,
    },
  });
  return Map<String, dynamic>.from(envelope['plan'] as Map);
}

Map<String, dynamic> _habitPlanEnvelopeFromProposal(
  Map<String, dynamic> body, {
  bool active = false,
}) {
  final base = plannerActionPlan();
  final revision = Map<String, dynamic>.from(
    base['pending_revision'] as Map,
  );
  final target = Map<String, dynamic>.from(body['target'] as Map);
  final baseRevision = body['base_revision'] as int;
  final revisionNumber = baseRevision + 1;
  revision
    ..['revision'] = revisionNumber
    ..['base_revision'] = baseRevision
    ..['state'] = active ? 'active' : 'proposed'
    ..['target'] = target
    ..['planning_start_on'] = body['planning_start_on']
    ..['planned_minutes'] = 0
    ..['unscheduled_minutes'] = 0
    ..['task_blocks'] = <dynamic>[]
    ..['habit_slots'] = <dynamic>[]
    ..['activated_at'] = active ? '2026-07-21T08:30:00Z' : null;
  return {
    'contract_version': 'planner-v1',
    'origin': 'authenticated_backend',
    'plan': {
      'id': body['plan_id'],
      'target_kind': 'habit',
      'target_id': target['target_id'],
      'status': active ? 'unscheduled' : 'draft',
      'current_revision': active ? revisionNumber : 0,
      'latest_revision': revisionNumber,
      'needs_attention': false,
      'attention_reasons': <dynamic>[],
      'active_revision': active ? revision : null,
      'pending_revision': active ? null : revision,
    },
  };
}

Map<String, dynamic> _taskPlanEnvelopeFromProposal(
  Map<String, dynamic> body, {
  Map? activeRevision,
  bool learnedTiming = false,
  bool learnedTimingFallback = false,
}) {
  final base = plannerActionPlan();
  final revision = Map<String, dynamic>.from(
    base['pending_revision'] as Map,
  );
  final target = Map<String, dynamic>.from(body['target'] as Map);
  final baseRevision = body['base_revision'] as int;
  final revisionNumber = baseRevision + 1;
  revision
    ..['revision'] = revisionNumber
    ..['base_revision'] = baseRevision
    ..['state'] = 'proposed'
    ..['target'] = target
    ..['planning_start_on'] = body['planning_start_on']
    ..['planned_minutes'] = 0
    ..['unscheduled_minutes'] = 0
    ..['task_blocks'] = <dynamic>[]
    ..['habit_slots'] = <dynamic>[]
    ..['activated_at'] = null;
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
  final active =
      activeRevision == null ? null : Map<String, dynamic>.from(activeRevision);
  final currentRevision = active?['revision'] as int? ?? 0;
  return {
    'contract_version': 'planner-v1',
    'origin': 'authenticated_backend',
    'plan': {
      'id': body['plan_id'],
      'target_kind': 'task',
      'target_id': target['target_id'],
      'status': active == null ? 'draft' : 'active',
      'current_revision': currentRevision,
      'latest_revision': revisionNumber,
      'needs_attention': false,
      'attention_reasons': <dynamic>[],
      'active_revision': active,
      'pending_revision': revision,
    },
  };
}

Map<String, dynamic> _activeTaskPlanEnvelope(Map<String, dynamic> plan) {
  final pending = Map<String, dynamic>.from(
    plan['pending_revision'] as Map,
  )
    ..['state'] = 'active'
    ..['task_blocks'] = [
      for (final raw
          in (plan['pending_revision'] as Map)['task_blocks'] as List<dynamic>)
        {
          ...Map<String, dynamic>.from(raw as Map),
          'state': 'active',
        },
    ]
    ..['habit_slots'] = <dynamic>[]
    ..['activated_at'] = '2026-07-21T08:30:00Z';
  return {
    'contract_version': 'planner-v1',
    'origin': 'authenticated_backend',
    'plan': {
      ...Map<String, dynamic>.from(plan),
      'status': pending['planned_minutes'] == 0 ? 'unscheduled' : 'active',
      'current_revision': pending['revision'],
      'latest_revision': pending['revision'],
      'active_revision': pending,
      'pending_revision': null,
    },
  };
}
