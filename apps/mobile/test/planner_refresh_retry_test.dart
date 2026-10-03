import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/deadline_plan_providers.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/core/widgets/app_page.dart';
import 'package:my_life_graph/features/planner/application/planner_controller.dart';
import 'package:my_life_graph/features/planner/data/planner_api_data_source.dart';
import 'package:my_life_graph/features/planner/domain/planner.dart';
import 'package:my_life_graph/features/planner/presentation/pages/planner_page.dart';
import 'package:my_life_graph/features/planner/presentation/providers/planner_providers.dart';

import 'support/planner_fixtures.dart';

void main() {
  for (final failLate in [false, true]) {
    test(
      'coalesced Planner read settles safely after disposal; failLate=$failLate',
      () async {
        final api = _HeldPlannerApi();
        final controller = PlannerController(
          api: api,
          accessTokenProvider: () => 'test-token',
          canUseSyncedPlanner: true,
          isBackendConfigured: true,
        );
        final first = controller.load();
        final second = controller.load();
        await api.started.future;
        expect(api.reads, 1);
        controller.dispose();
        if (failLate) {
          api.response.completeError(
            StateError('controlled late read failure'),
          );
        } else {
          api.response.complete(
            PlannerOverview.fromJson(plannerOverviewEnvelope()),
          );
        }
        await Future.wait([first, second]);
        // Neither a late success nor a late failure can re-enter the disposed
        // notifier or leave an additional caller stuck on the held load.
        await controller.load();
        expect(api.reads, 1);
      },
    );
  }
  for (final largeText in [false, true]) {
    testWidgets(
      'retained Planner error retry is single flight; largeText=$largeText',
      (tester) async {
        tester.view.physicalSize = Size(largeText ? 320 : 390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _GatedPlannerApi();
        final controller = PlannerController(
          api: api,
          accessTokenProvider: () => 'test-token',
          canUseSyncedPlanner: true,
          isBackendConfigured: true,
        );
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
              plannerControllerProvider.overrideWith((_) => controller),
              examWeekOutlookProvider.overrideWith((_) async => null),
              examPlanHealthProvider.overrideWith((_) async => null),
            ],
            child: MaterialApp(
              home: const Scaffold(body: PlannerPage()),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(largeText ? 2 : 1)),
                child: child!,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(api.reads, 1);
        final before = controller.state.overview;
        final refreshing = tester
            .widget<AppPage>(find.byType(AppPage))
            .onRefresh!();
        await tester.pumpAndSettle();
        await refreshing;
        expect(api.reads, 2);
        expect(controller.state.loadError, isNotNull);
        expect(controller.state.overview, same(before));
        expect(controller.state.canMutate, isFalse);

        final retry = find.widgetWithText(OutlinedButton, 'Retry');
        await tester.scrollUntilVisible(
          retry,
          200,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await Scrollable.ensureVisible(tester.element(retry), alignment: .5);
        await tester.pumpAndSettle();
        expect(retry.hitTestable(), findsOneWidget);
        await tester.tap(retry);
        // Both taps arrive before the next UI frame removes or disables Retry.
        // The load guard must still admit only one pending overview request.
        await tester.tap(retry);
        await tester.pump();
        expect(controller.state.isBusy, isTrue);
        expect(controller.state.canMutate, isFalse);
        final readsWhilePending = api.reads;
        api.release.complete(
          PlannerOverview.fromJson(plannerOverviewEnvelope()),
        );
        await tester.pumpAndSettle();
        expect(readsWhilePending, 3);
        expect(controller.state.loadError, isNull);
        expect(controller.state.canMutate, isTrue);
        expect(
          find.text(
            'Planner could not be loaded. Check your connection and try again.',
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _GatedPlannerApi extends PlannerApiDataSource {
  _GatedPlannerApi() : super(ApiClient(Dio()));

  int reads = 0;
  final release = Completer<PlannerOverview>();

  @override
  Future<PlannerOverview> getOverview({required String accessToken}) async {
    reads++;
    if (reads == 1) return PlannerOverview.fromJson(plannerOverviewEnvelope());
    if (reads == 2) throw StateError('controlled overview failure');
    return release.future;
  }
}

class _HeldPlannerApi extends PlannerApiDataSource {
  _HeldPlannerApi() : super(ApiClient(Dio()));

  int reads = 0;
  final started = Completer<void>();
  final response = Completer<PlannerOverview>();

  @override
  Future<PlannerOverview> getOverview({required String accessToken}) {
    reads++;
    if (!started.isCompleted) started.complete();
    return response.future;
  }
}
