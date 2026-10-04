import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/composition/health_connect_providers.dart';
import 'package:my_life_graph/features/health_connect/application/health_connect_controller.dart';
import 'package:my_life_graph/features/health_connect/presentation/health_connect_page.dart';
import 'package:my_life_graph/features/health_connect/domain/health_connect_state.dart';
import 'health_connect_test.dart' show Gateway, cloud;
import 'support/ui_catalog_capture.dart';

Future<void> pumpPage(
  WidgetTester tester,
  Gateway gateway, {
  bool android = true,
  double scale = 1,
  AppThemeId theme = AppThemeId.liquidGlass,
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
        theme: AppTheme.resolve(theme),
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
  if (captureUiCatalog) {
    testWidgets('Wearable dashboard approved design catalog', (tester) async {
      await loadCatalogFonts();
      final gateway = Gateway()..current = const HealthConnectState(
        enabled: true, revision: 1, timezone: 'Europe/Berlin',
        windowEnd: '2026-10-04', deviceId: 'device', vitalsEnabled: true,
        latest: {'date': '2026-10-04', 'steps': 6432, 'sleep_minutes': 468,
          'heart_rate': 72, 'resting_heart_rate': 58},
      );
      await pumpPage(tester, gateway);
      tester.view.physicalSize = const Size(390, 1000);
      await captureCatalog(tester, 'wearables-approved');
    });
  }
  for (final theme in AppThemeId.values) {
    testWidgets('vitals dashboard fits 320 pixels and 200% text in $theme', (tester) async {
      final gateway = Gateway()..current = const HealthConnectState(
        enabled: true, revision: 1, timezone: 'Europe/Berlin',
        windowEnd: '2026-10-04', deviceId: 'device',
        latest: {'date': '2026-10-04', 'steps': 10482, 'sleep_minutes': 468,
          'heart_rate': 78, 'resting_heart_rate': 58},
      );
      await pumpPage(tester, gateway, theme: theme, scale: 2);
      expect(find.text('7h 48m'), findsOneWidget);
      expect(find.text('10482'), findsOneWidget);
      expect(find.text('78 bpm'), findsOneWidget);
      expect(find.text('58 bpm'), findsOneWidget);
      expect(find.text('Stress · Unavailable'), findsOneWidget);
      expect(gateway.commands, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Add heart data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add heart data'));
      await tester.pumpAndSettle();
      expect(find.text('Share heart data?'), findsOneWidget);
      expect(gateway.vitalsRequests, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(gateway.commands, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  for (final (name, enabled, granted, device, android, fail, expected) in [
    ('connected', true, true, 'device', true, false, 'Connected'),
    ('off', false, true, 'device', true, false, 'Not connected'),
    ('revoked', true, false, 'device', true, false, 'Not connected'),
    ('different device', true, true, 'other', true, false, 'Other device'),
    ('web', true, true, 'device', false, false, 'Unavailable here'),
    ('failed read', true, true, 'device', true, true, 'Could not confirm'),
  ]) {
    testWidgets('watch status is honest for $name without implicit writes', (
      tester,
    ) async {
      final gateway = Gateway()
        ..current = cloud(enabled: enabled, device: device)
        ..granted = granted
        ..failRead = fail;
      await pumpPage(tester, gateway, android: android);
      expect(find.text(expected), findsOneWidget);
      expect(gateway.commands, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('watch status changes after reloading revoked permission', (
    tester,
  ) async {
    final gateway = Gateway();
    await pumpPage(tester, gateway);
    expect(find.text('Connected'), findsOneWidget);
    gateway.granted = false;
    await tester.tap(find.byTooltip('Reload'));
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsNothing);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Reconnect this device'), findsOneWidget);
    expect(gateway.commands, isEmpty);
  });

  testWidgets(
    'compact watch view keeps optional details and no implicit writes',
    (tester) async {
      final gateway = Gateway();
      await pumpPage(tester, gateway);
      expect(find.text('Sharing on'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
      expect(find.textContaining('last 7 days'), findsNothing);
      expect(gateway.commands, isEmpty);
      await tester.scrollUntilVisible(find.text('Details'), 300);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Manual check-ins stay separate'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Sync now'));
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
