import 'package:flutter/material.dart';

import 'support/blocking_navigation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/focus_protection/application/blocking_gateway.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';

import 'blocking_plans_test.dart' show snapshot;
import 'support/ui_catalog_capture.dart';

enum _State { unlocked, nfc, choice }

class _Gateway extends BlockingGateway {
  _Gateway(this.state);
  final _State state;
  final calls = <String>[];

  @override
  Future<BlockingSnapshot> command(
    String name, [
    Map<String, Object>? args,
  ]) async {
    calls.add(name);
    return BlockingSnapshot({
      ...snapshot(locked: state != _State.unlocked),
      'strict': {
        'enabled': true,
        'waitSeconds': 180,
        'nfc': state == _State.nfc,
      },
      'releaseRemainingMs': state == _State.unlocked ? 900000 : 0,
      'unlockStarted': state == _State.nfc,
      'nfcAvailable': true,
      'nfcEnrolled': true,
    });
  }
}

Future<void> _open(
  WidgetTester tester,
  _Gateway gateway,
  ThemeData theme, {
  double width = 390,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
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
        debugShowCheckedModeBanner: false,
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: const Scaffold(body: BlockingPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Discipline'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text(switch (gateway.state) {
      _State.unlocked => 'Configure',
      _State.nfc => 'Unlocking for 15m…',
      _State.choice => 'Unblock',
    }),
    150,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  if (gateway.state == _State.choice) {
    await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
    await tester.pumpAndSettle();
  }
}

void _roundControl(WidgetTester tester, Finder finder) {
  final button = tester.widget<ButtonStyleButton>(finder);
  final shape = button.style!.shape!.resolve({})!;
  expect(shape, isA<StadiumBorder>());
  expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
}

void _checkGeometry(WidgetTester tester, _State state, {bool normal = true}) {
  if (state == _State.unlocked) {
    final primary = find.widgetWithText(FilledButton, 'Lock now');
    final secondary = find.widgetWithText(OutlinedButton, 'Configure');
    expect(primary, findsOneWidget);
    expect(secondary, findsOneWidget);
    expect(
      tester.getTopLeft(secondary).dy - tester.getBottomLeft(primary).dy,
      12,
    );
    expect(tester.getSize(primary).width, tester.getSize(secondary).width);
    _roundControl(tester, primary);
    _roundControl(tester, secondary);
    if (normal) {
      expect(tester.getSize(primary).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(secondary).height, greaterThanOrEqualTo(48));
    }
  } else if (state == _State.nfc) {
    final timer = find.text('3:00');
    final scan = find.widgetWithText(OutlinedButton, 'Scan tag');
    final status = find.text('Unlocking for 15m…');
    expect(tester.getTopLeft(scan).dy - tester.getBottomLeft(timer).dy, 12);
    expect(tester.getTopLeft(status).dy - tester.getBottomLeft(scan).dy, 12);
    _roundControl(tester, scan);
  } else {
    final primary = find.widgetWithText(FilledButton, '15 minutes');
    final secondary = find.widgetWithText(
      OutlinedButton,
      'Turn off Discipline',
    );
    expect(
      tester.getTopLeft(secondary).dy - tester.getBottomLeft(primary).dy,
      12,
    );
    expect(tester.getSize(primary).width, tester.getSize(secondary).width);
    _roundControl(tester, primary);
    _roundControl(tester, secondary);
    if (normal) {
      expect(tester.getSize(primary).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(secondary).height, greaterThanOrEqualTo(48));
    }
  }
  expect(tester.takeException(), isNull);
}

void main() {
  final themes = {
    'Liquid Glass': AppTheme.liquidGlass,
    'Dark': AppTheme.dark,
    'Light': AppTheme.light,
    'Space': AppTheme.space,
  };
  for (final theme in themes.entries) {
    for (final state in _State.values) {
      for (final large in [false, true]) {
        testWidgets(
          'approved Strict buttons ${theme.key} $state ${large ? '320px/200%' : '390px/100%'}',
          (tester) async {
            final gateway = _Gateway(state);
            await _open(
              tester,
              gateway,
              theme.value,
              width: large ? 320 : 390,
              scale: large ? 2 : 1,
            );
            _checkGeometry(tester, state, normal: !large);
            expect(gateway.calls, isNot(contains('requestUnlock')));
            if (state == _State.unlocked) {
              await tester.ensureVisible(find.text('Configure'));
              await tester.pumpAndSettle();
              await tester.tap(find.text('Configure'));
              await enterUnlockMethod(tester);
              await tester.pumpAndSettle();
              expect(find.text('Charger connected'), findsOneWidget);
              tester.state<NavigatorState>(find.byType(Navigator).first).pop();
              await tester.pumpAndSettle();
              await tester.binding.handlePopRoute();
              await tester.pumpAndSettle();
              await tester.ensureVisible(find.text('Lock now'));
              await tester.pumpAndSettle();
              await tester.tap(find.text('Lock now'));
              await tester.pumpAndSettle();
              expect(
                gateway.calls.where((name) => name == 'relock'),
                hasLength(1),
              );
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  if (captureUiCatalog) {
    for (final state in _State.values) {
      testWidgets('approved button polish visual catalog $state', (
        tester,
      ) async {
        await loadCatalogFonts();
        await _open(tester, _Gateway(state), AppTheme.liquidGlass);
        await captureCatalog(tester, 'strict-${state.name}-implemented');
      });
    }
  }
}
