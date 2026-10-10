import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/focus_protection/application/blocking_gateway.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_unlock_settings_page.dart';

import 'blocking_plans_test.dart' show snapshot;
import 'support/ui_catalog_capture.dart';

class _SettingsGateway extends BlockingGateway {
  _SettingsGateway({this.enabled = false, this.fail = false});
  final bool enabled;
  bool fail;
  bool stay = false;
  int revision = 3;
  int writes = 0;
  BlockingSnapshot get value => BlockingSnapshot({
    ...snapshot(),
    'revision': revision,
    'locked': false,
    'strict': {'enabled': enabled, 'stayOnScreen': stay, 'waitSeconds': 180},
  });
  @override
  Future<BlockingSnapshot> command(
    String name, [
    Map<String, Object>? args,
  ]) async {
    if (name == 'stayOnScreen') {
      writes++;
      if (fail || enabled || args!['revision'] != revision) {
        throw StateError('Save failed');
      }
      stay = args['enabled'] as bool;
      revision++;
    }
    return value;
  }
}

Future<void> _open(
  WidgetTester tester,
  _SettingsGateway gateway,
  ThemeData theme, {
  bool large = false,
  bool focusLocked = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(large ? 320 : 390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
        child: child!,
      ),
      home: BlockingUnlockSettingsPage(
        snapshot: gateway.value,
        gateway: gateway,
        methodSummary: (_) => '3m · NFC',
        editMethod: (_, _) async {},
        focusLocked: focusLocked,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final (label, theme) in [
    ('glass', AppTheme.liquidGlass),
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
    ('space', AppTheme.space),
  ]) {
    for (final large in [false, true]) {
      testWidgets(
        'Unlock settings $label ${large ? 'large' : 'normal'} default off and toggle persists',
        (tester) async {
          if (captureUiCatalog) await loadCatalogFonts();
          final gateway = _SettingsGateway();
          await _open(tester, gateway, theme, large: large);
          expect(
            tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
            isFalse,
          );
          if (captureUiCatalog && !large) {
            await captureCatalog(tester, 'unlock-settings-$label');
          }
          await tester.tap(find.byType(SwitchListTile));
          await tester.pumpAndSettle();
          expect(gateway.stay, isTrue);
          expect(find.text('Leaving resets the timer.'), findsOneWidget);
          await tester.tap(find.byType(SwitchListTile));
          await tester.pumpAndSettle();
          expect(gateway.stay, isFalse);
          expect(gateway.writes, 2);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('Temporary release cannot change stay policy', (tester) async {
    final gateway = _SettingsGateway(enabled: true);
    await _open(tester, gateway, AppTheme.liquidGlass);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    await tester.tap(find.byType(SwitchListTile));
    expect(gateway.writes, 0);
  });
  testWidgets('Active Focus cannot change stay policy', (tester) async {
    final gateway = _SettingsGateway();
    await _open(tester, gateway, AppTheme.liquidGlass, focusLocked: true);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
  });
  testWidgets('Failed policy save retains truth and can retry', (tester) async {
    final gateway = _SettingsGateway(fail: true);
    await _open(tester, gateway, AppTheme.liquidGlass);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(gateway.stay, isFalse);
    expect(find.text('Could not save. Reload and try again.'), findsOneWidget);
    gateway.fail = false;
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(gateway.stay, isTrue);
  });
}
