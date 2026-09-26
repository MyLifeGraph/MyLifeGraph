import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/composition/health_connect_providers.dart';
import 'package:my_life_graph/features/health_connect/application/health_connect_controller.dart';
import 'package:my_life_graph/features/health_connect/presentation/health_connect_page.dart';
import 'health_connect_test.dart' show Gateway, cloud;
import 'support/ui_catalog_capture.dart';

void main() {
  if (!captureUiCatalog) return;
  testWidgets('catalog watch screenshots', (tester) async {
    await loadCatalogFonts();
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final wide in [false, true]) {
      for (final connected in [false, true]) {
        tester.view.physicalSize = wide
            ? const Size(1280, 1000)
            : const Size(390, 1000);
        final gateway = Gateway()..current = cloud(enabled: connected);
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
                (ref) => HealthConnectController(gateway, android: true),
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.liquidGlass,
              home: const Scaffold(body: HealthConnectPage()),
            ),
          ),
        );
        await captureCatalog(
          tester,
          'watch-${connected ? 'connected' : 'off'}-${wide ? 'desktop' : 'mobile'}',
        );
        await tester.pumpWidget(const SizedBox());
      }
    }
  });
}
