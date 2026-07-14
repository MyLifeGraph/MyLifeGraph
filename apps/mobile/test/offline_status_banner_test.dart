import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/network/network_availability.dart';
import 'package:my_life_graph/core/widgets/offline_status_banner.dart';

void main() {
  testWidgets('shows honest no-queue copy while offline', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkAvailableProvider.overrideWith((_) => Stream.value(false)),
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseSyncedExecution: true,
            ),
          ),
        ],
        child: const MaterialApp(
          home: OfflineStatusBanner(child: Text('Account content')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Account content'), findsOneWidget);
    expect(
      find.textContaining('synced account changes are not queued'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(
        find.bySemanticsLabel(
          'No network interface detected. Synced account changes are not queued. Retry after reconnecting.',
        ),
      ),
      matchesSemantics(
        label:
            'No network interface detected. Synced account changes are not queued. Retry after reconnecting.',
        isLiveRegion: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('keeps local guest persistence truthful while offline',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkAvailableProvider.overrideWith((_) => Stream.value(false)),
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: true,
              canUseSyncedHabits: false,
            ),
          ),
        ],
        child: const MaterialApp(
          home: OfflineStatusBanner(child: Text('Guest content')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Guest content'), findsOneWidget);
    expect(
      find.textContaining('local guest/demo saves remain on this device'),
      findsOneWidget,
    );
    expect(find.textContaining('not queued'), findsNothing);
  });

  testWidgets('does not claim offline state while a network is available',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkAvailableProvider.overrideWith((_) => Stream.value(true)),
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseSyncedExecution: true,
            ),
          ),
        ],
        child: const MaterialApp(
          home: OfflineStatusBanner(child: Text('Account content')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Account content'), findsOneWidget);
    expect(find.textContaining('not queued'), findsNothing);
  });
}
