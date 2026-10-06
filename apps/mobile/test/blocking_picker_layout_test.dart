import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/widgets/app_backdrop.dart';
import 'package:my_life_graph/features/focus_protection/domain/blocking_plan.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';

import 'support/ui_catalog_capture.dart';

final _catalog = <Map>[
  {'packageName': 'com.instagram.android', 'label': 'Instagram'},
  {'packageName': 'com.google.android.youtube', 'label': 'YouTube'},
  {'packageName': 'example.game', 'label': 'Example game', 'category': 'Games'},
  for (var i = 0; i < 100; i++)
    {'packageName': 'example.app$i', 'label': 'App $i'},
];

Future<void> _pumpEditor(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  double keyboard = 0,
  bool modal = false,
  Future<void> Function(BlockingPlan)? save,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final editor = BlockingPlanEditor(
    plan: const BlockingPlan(
      id: 'test',
      name: 'Study',
      focus: true,
      apps: {'example.app99'},
      sites: {'example.com'},
    ),
    catalog: _catalog,
    usageGranted: true,
    websiteAllowed: true,
    onSave: save,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.liquidGlass,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          viewInsets: EdgeInsets.only(bottom: keyboard),
          padding: const EdgeInsets.only(bottom: 24),
        ),
        child: modal ? AppBackdrop(child: child!) : child!,
      ),
      home: Scaffold(
        body: modal
            ? Builder(
                builder: (context) => TextButton(
                  onPressed: () => showModalBottomSheet<BlockingPlan>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    enableDrag: false,
                    builder: (_) => editor,
                  ),
                  child: const Text('Open picker'),
                ),
              )
            : editor,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (modal) {
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
  }
}

Finder get _save => find.widgetWithText(FilledButton, 'Save');
Finder get _toggle => find.byKey(const ValueKey('blocking-footer-apps-toggle'));
Finder get _outer => find
    .descendant(
      of: find.byKey(const ValueKey('blocking-editor-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  for (final setting in [
    (390.0, 1.0, 0.0),
    (320.0, 2.0, 0.0),
    (320.0, 2.0, 300.0),
  ]) {
    testWidgets('Save and collapse reachable with 103 apps at $setting', (
      tester,
    ) async {
      await _pumpEditor(
        tester,
        width: setting.$1,
        scale: setting.$2,
        keyboard: setting.$3,
      );
      expect(_save.hitTestable(), findsOneWidget);
      expect(_toggle.hitTestable(), findsOneWidget);
      expect(
        tester.getBottomRight(_save).dy,
        lessThanOrEqualTo(844 - setting.$3 - 24),
      );
      await tester.drag(
        find.byKey(const ValueKey('blocking-editor-scroll')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      // Dragging can expand the sheet itself; Save remains pinned to it.
      expect(_save.hitTestable(), findsOneWidget);
      expect(_toggle.hitTestable(), findsOneWidget);
      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('blocking-app-list')), findsNothing);
      expect(_save.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('presets reflect full selection, collapse/search preserve it', (
    tester,
  ) async {
    BlockingPlan? submitted;
    await _pumpEditor(tester, save: (plan) async => submitted = plan);
    await tester.scrollUntilVisible(
      find.widgetWithText(FilterChip, 'Social media').first,
      250,
      scrollable: _outer,
    );
    final social = find.widgetWithText(FilterChip, 'Social media').first;
    final games = find.widgetWithText(FilterChip, 'Games');
    await tester.ensureVisible(social);
    await tester.pumpAndSettle();
    await tester.tap(social);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(social).selected, isTrue);
    expect(tester.widget<FilterChip>(games).selected, isFalse);
    await tester.tap(games);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(games).selected, isTrue);
    final instagram = find.widgetWithText(CheckboxListTile, 'Instagram');
    final checkbox = tester.widget<CheckboxListTile>(instagram);
    expect(checkbox.value, isTrue);
    expect(checkbox.checkboxScaleFactor, greaterThan(1));
    expect(checkbox.activeColor, AppTheme.liquidGlass.colorScheme.primary);
    expect(checkbox.checkColor, AppTheme.liquidGlass.colorScheme.onPrimary);
    await tester.tap(instagram);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(social).selected, isFalse);
    await tester.tap(social);
    await tester.pumpAndSettle();
    final appsTop = tester.getTopLeft(find.text('Apps · 4'));
    final footer = tester.getRect(
      find.byKey(const ValueKey('blocking-save-footer')),
    );
    await tester.drag(
      find.byKey(const ValueKey('blocking-app-list')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Apps · 4')), appsTop);
    expect(
      tester.getRect(find.byKey(const ValueKey('blocking-save-footer'))),
      footer,
    );
    await tester.tap(_toggle);
    await tester.pumpAndSettle();
    expect(find.text('Apps · 4'), findsOneWidget);
    await tester.tap(_toggle);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search apps'),
      'no matching app',
    );
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(submitted!.apps, {
      'example.app99',
      'com.instagram.android',
      'com.google.android.youtube',
      'example.game',
    });
    expect(submitted!.sites, {'example.com'});
  });

  testWidgets(
    'failure retains selection; pending save excludes keyboard edits',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await _pumpEditor(
        tester,
        save: (_) async {
          calls++;
          if (calls == 1) throw StateError('Try again');
          await pending.future;
        },
      );
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('1 apps · 1 sites'), findsOneWidget);
      await tester.tap(_save);
      await tester.pump();
      expect(
        tester.widget<ExcludeFocus>(find.byType(ExcludeFocus).first).excluding,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(calls, 2);
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  if (captureUiCatalog) {
    testWidgets('picker layout visual catalog', (tester) async {
      await loadCatalogFonts();
      await _pumpEditor(tester, modal: true);
      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilterChip, 'Social media').first.hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilterChip, 'Social media').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Apps · 3'));
      await tester.pumpAndSettle();
      await captureCatalog(tester, 'blocking-picker-expanded');
      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      await captureCatalog(tester, 'blocking-picker-collapsed');
    });
  }
}
