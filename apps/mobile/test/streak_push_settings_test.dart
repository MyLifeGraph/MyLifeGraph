import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/push_providers.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/notifications/application/push_controller.dart';
import 'package:my_life_graph/features/notifications/presentation/pages/push_settings_page.dart';
import 'push_test.dart' as fixtures;

void main() {
  for (final supported in [false, true]) {
    testWidgets(
      'streak switch is migration gated and uses existing settings at 320px: $supported',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = fixtures.Api();
        if (supported) api.current['settings']['streak'] = false;
        final platform = fixtures.Platform();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pushProvider.overrideWith(
                (ref) => PushController(
                  api,
                  platform,
                  () => 'access',
                  'owner',
                  'session',
                  android: false,
                ),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.liquidGlass,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: const PushSettingsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final streak = find.widgetWithText(
          CheckboxListTile,
          'Streak reminders',
        );
        expect(streak, supported ? findsOneWidget : findsNothing);
        if (supported) {
          await tester.ensureVisible(streak);
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(of: streak, matching: find.byType(Checkbox)),
          );
          await tester.pumpAndSettle();
          expect(tester.widget<CheckboxListTile>(streak).value, isTrue);
          await tester.ensureVisible(find.text('Save'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          expect(api.writes.single['streak'], isTrue);
          expect(api.writes.single['enabled'], isFalse);
          expect(platform.calls, isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
