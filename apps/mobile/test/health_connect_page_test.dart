import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/composition/health_connect_providers.dart';
import 'package:my_life_graph/features/health_connect/application/health_connect_controller.dart';
import 'package:my_life_graph/features/health_connect/presentation/health_connect_page.dart';
import 'health_connect_test.dart' show Gateway, cloud;

Future<void> pumpPage(
  WidgetTester tester,
  Gateway gateway, {
  bool android = true,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSurfaceCapabilitiesProvider.overrideWithValue(
          const AppSurfaceCapabilities(
            isLocalDemo: false,
            canUseSyncedHabits: true,
            canUseSyncedExecution: true,
          ),
        ),
        healthConnectProvider.overrideWith(
          (ref) => HealthConnectController(gateway, android: android),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.liquidGlass,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Scaffold(body: HealthConnectPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'compact watch view keeps optional details and no implicit writes',
    (tester) async {
      final gateway = Gateway();
      await pumpPage(tester, gateway);
      expect(find.text('Sharing on'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
      expect(find.textContaining('last 7 days'), findsNothing);
      expect(gateway.commands, isEmpty);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Manual check-ins stay separate'),
        findsOneWidget,
      );
      await tester.tap(find.text('Sync now'));
      await tester.pumpAndSettle();
      expect(gateway.commands, ['sync']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('connect still requires separate cloud consent', (tester) async {
    final gateway = Gateway()..current = cloud(enabled: false);
    await pumpPage(tester, gateway);
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Android permission alone'), findsOneWidget);
    expect(gateway.commands, isEmpty);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(gateway.commands, isEmpty);
  });

  testWidgets('watch menu retains stop and confirmed deletion on Web', (
    tester,
  ) async {
    final gateway = Gateway();
    await pumpPage(tester, gateway, android: false);
    expect(find.text('Sync now'), findsNothing);
    expect(find.text('Android permissions'), findsNothing);
    await tester.tap(find.byTooltip('Watch data actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop sharing'));
    await tester.pumpAndSettle();
    expect(gateway.commands, ['disconnect']);
    await tester.tap(find.byTooltip('Watch data actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete imported data'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Manual check-ins and data on your watch stay unchanged',
      ),
      findsOneWidget,
    );
    expect(gateway.commands, ['disconnect']);
    await tester.tap(find.text('Delete imports'));
    await tester.pumpAndSettle();
    expect(gateway.commands, ['disconnect', 'delete_data']);
  });

  testWidgets('watch actions remain readable with 200 percent text', (
    tester,
  ) async {
    await pumpPage(tester, Gateway(), scale: 2);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Watch data actions'));
    await tester.pumpAndSettle();
    expect(find.text('Stop sharing'), findsOneWidget);
    expect(find.text('Delete imported data'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed read retains reload without enabling mutations', (
    tester,
  ) async {
    final gateway = Gateway()..failRead = true;
    await pumpPage(tester, gateway);
    expect(
      find.textContaining('Could not confirm Health Connect'),
      findsOneWidget,
    );
    expect(find.byTooltip('Watch data actions'), findsNothing);
    gateway.failRead = false;
    await tester.tap(find.byTooltip('Reload'));
    await tester.pumpAndSettle();
    expect(find.text('Sync now'), findsOneWidget);
    expect(gateway.commands, isEmpty);
  });
}
