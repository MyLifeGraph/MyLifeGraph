import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/focus_protection/application/blocking_gateway.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';

import 'blocking_plans_test.dart' show snapshot;

class _DisconnectedWifiGateway extends BlockingGateway {
  _DisconnectedWifiGateway({required this.wifiRequired});

  bool wifiRequired;
  bool locked = false;
  final saves = <Map<String, Object>>[];

  @override
  Future<BlockingSnapshot> command(
    String name, [
    Map<String, Object>? args,
  ]) async {
    if (name == 'strict') {
      saves.add(Map<String, Object>.from(args!));
      // Mirrors the native rule: unavailable SSID prevents enabling a Wi-Fi
      // condition, but does not prevent an already-authorized edit removing it.
      if (args['wifi'] == true) throw StateError('Connect to Wi-Fi first.');
      wifiRequired = false;
      locked = true;
    }
    return BlockingSnapshot({
      ...snapshot(),
      'plans': <Map<String, Object>>[],
      'strict': {'enabled': true, 'waitSeconds': 10, 'wifi': wifiRequired},
      'locked': locked,
      'wifiReady': false,
    });
  }
}

Future<void> _openConfiguration(
  WidgetTester tester,
  _DisconnectedWifiGateway gateway,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        blockingGatewayProvider.overrideWithValue(gateway),
        focusProtectionGatewayProvider.overrideWithValue(
          UnsupportedFocusProtectionGateway(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.liquidGlass,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(body: BlockingPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, 'Strict'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Configure'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'unlocked Strict can remove retained Wi-Fi requirement while disconnected',
    (tester) async {
      final gateway = _DisconnectedWifiGateway(wifiRequired: true);
      await _openConfiguration(tester, gateway);
      final wifi = find.widgetWithText(SwitchListTile, 'Current Wi-Fi');
      expect(tester.widget<SwitchListTile>(wifi).value, isTrue);
      await tester.tap(wifi);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(wifi).value,
        isFalse,
        reason:
            'An unavailable SSID must not prevent removing a retained '
            'condition during the authorized editing window.',
      );
      expect(tester.widget<SwitchListTile>(wifi).onChanged, isNull);
      await tester.tap(wifi);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(wifi).value, isFalse);
      await tester.tap(find.widgetWithText(FilledButton, 'Enable'));
      await tester.pumpAndSettle();
      expect(gateway.saves.single['wifi'], isFalse);
      expect(gateway.wifiRequired, isFalse);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Strict cannot add a Wi-Fi requirement while disconnected', (
    tester,
  ) async {
    final gateway = _DisconnectedWifiGateway(wifiRequired: false);
    await _openConfiguration(tester, gateway);
    final wifi = find.widgetWithText(SwitchListTile, 'Current Wi-Fi');
    expect(tester.widget<SwitchListTile>(wifi).value, isFalse);
    expect(tester.widget<SwitchListTile>(wifi).onChanged, isNull);
    await tester.tap(wifi);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(wifi).value, isFalse);
    expect(gateway.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
