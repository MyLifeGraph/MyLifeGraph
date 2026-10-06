import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/widgets/app_backdrop.dart';
import 'package:my_life_graph/core/widgets/app_surface.dart';
import 'package:my_life_graph/features/focus_protection/domain/blocking_plan.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';

import 'support/ui_catalog_capture.dart';

const _catalog = <Map>[
  {'packageName': 'example.calculator', 'label': 'Calculator'},
  {'packageName': 'com.instagram.android', 'label': 'Instagram'},
  {'packageName': 'com.google.android.youtube', 'label': 'YouTube'},
  {'packageName': 'example.game', 'label': 'Puzzle', 'category': 'Games'},
  {'packageName': 'example.notes', 'label': 'Notes'},
];
const _plan = BlockingPlan(
  id: 'editor-polish',
  name: 'Study',
  focus: true,
  apps: {'example.notes', 'com.instagram.android'},
  sites: {'instagram.com', 'university.example'},
);

Finder get _outer => find
    .descendant(
      of: find.byKey(const ValueKey('blocking-editor-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;
Finder get _save => find.widgetWithText(FilledButton, 'Save');
Finder get _windows => find.byKey(const ValueKey('blocking-windows-toggle'));
Finder get _budget => find.byKey(const ValueKey('blocking-budget-toggle'));
Finder _app(String label) => find.widgetWithText(CheckboxListTile, label);
Finder _site(String domain) => find.byKey(ValueKey('blocking-site-$domain'));

Future<void> _open(
  WidgetTester tester, {
  BlockingPlan plan = _plan,
  ThemeData? theme,
  bool large = false,
  bool usageGranted = true,
  bool websiteAllowed = true,
  bool modal = false,
  Future<void> Function(BlockingPlan)? save,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(large ? 320 : 390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? AppTheme.liquidGlass,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(large ? 2 : 1),
          disableAnimations: true,
        ),
        child: AppBackdrop(child: child!),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final editor = BlockingPlanEditor(
              plan: plan,
              catalog: _catalog,
              usageGranted: usageGranted,
              websiteAllowed: websiteAllowed,
              onSave: save,
            );
            return modal
                ? TextButton(
                    onPressed: () => showModalBottomSheet<BlockingPlan>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => editor,
                    ),
                    child: const Text('Open editor'),
                  )
                : editor;
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (modal) {
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 170, scrollable: _outer);
  await tester.pumpAndSettle();
}

List<String> _visibleAppOrder(WidgetTester tester) => tester
    .widget<ListView>(find.byKey(const ValueKey('blocking-app-list')))
    .childrenDelegate
    .letAppLabels();

extension on SliverChildDelegate {
  List<String> letAppLabels() {
    final widgets = (this as SliverChildListDelegate).children;
    return [
      for (final tile in widgets.whereType<CheckboxListTile>())
        ((tile.title! as Tooltip).child as Text).data!,
    ];
  }
}

void main() {
  testWidgets(
    'closing a changed draft never saves; reopening restores original',
    (tester) async {
      var saves = 0;
      await _open(tester, modal: true, save: (_) async => saves++);
      await _reveal(tester, _windows);
      await tester.tap(_windows);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byTooltip('Close'), -170, scrollable: _outer);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(find.text('Open editor'), findsOneWidget);
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
    await _reveal(tester, _windows);
      expect(tester.widget<SwitchListTile>(_windows).value, isFalse);
      expect(_plan.windows, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('website category suggestions never implicitly select targets', (
    tester,
  ) async {
    BlockingPlan? submitted;
    await _open(tester, save: (p) async => submitted = p);
    final video = find.widgetWithText(FilterChip, 'Video');
    await _reveal(tester, video);
    await tester.tap(video);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(video).selected, isTrue);
    expect(
      tester.widget<CheckboxListTile>(_site('youtube.com')).value,
      isFalse,
    );
    expect(tester.widget<CheckboxListTile>(_site('twitch.tv')).value, isFalse);
    expect(
      tester.widget<CheckboxListTile>(_site('instagram.com')).value,
      isTrue,
    );
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(submitted!.sites, _plan.sites);
  });

  testWidgets(
    'opening selected apps first; toggling never reorders the draft',
    (tester) async {
      await _open(tester);
      await _reveal(tester, find.byKey(const ValueKey('blocking-app-list')));
      final opening = _visibleAppOrder(tester);
      expect(opening.take(2).toSet(), {'Instagram', 'Notes'});
      expect(opening.skip(2).toList(), ['Calculator', 'YouTube', 'Puzzle']);
      final selected = _app(opening.first);
      await tester.ensureVisible(selected);
      await tester.tap(selected);
      await tester.pumpAndSettle();
      expect(_visibleAppOrder(tester), opening);
      final tile = tester.widget<CheckboxListTile>(selected);
      expect(tile.value, isFalse);
      expect(tile.contentPadding, EdgeInsets.zero);
      expect(tile.checkboxScaleFactor, 1.25);
      expect(_save.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disabled rule toggles hide settings and exclude them on Save', (
    tester,
  ) async {
    BlockingPlan? submitted;
    await _open(
      tester,
      plan: const BlockingPlan(
        id: 'existing',
        name: 'Study',
        apps: {'example.notes'},
        focus: true,
        windows: [BlockingWindow()],
        budget: 45,
      ),
      save: (p) async => submitted = p,
    );
    expect(tester.widget<SwitchListTile>(_windows).value, isTrue);
    expect(tester.widget<SwitchListTile>(_budget).value, isTrue);
    expect(find.text('Block when any rule applies.'), findsNothing);
    await _reveal(tester, _windows);
    await tester.tap(_windows);
    await tester.pumpAndSettle();
    expect(find.text('Add time'), findsNothing);
    await _reveal(tester, _budget);
    await tester.tap(_budget);
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(submitted!.windows, isEmpty);
    expect(submitted!.budget, 0);
    expect(submitted!.focus, isTrue);
    expect(submitted!.apps, {'example.notes'});
  });

  testWidgets('rules begin compact; time and budget switches reveal controls', (
    tester,
  ) async {
    await _open(tester);
    expect(tester.widget<SwitchListTile>(_windows).value, isFalse);
    expect(tester.widget<SwitchListTile>(_budget).value, isFalse);
    expect(find.text('Add time'), findsNothing);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    await _reveal(tester, _windows);
    await tester.tap(_windows);
    await tester.pumpAndSettle();
    expect(find.text('Add time'), findsOneWidget);
    await _reveal(tester, _budget);
    await tester.tap(_budget);
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    final rules = find.ancestor(
      of: find.text('Rules'),
      matching: find.byType(AppSurface),
    );
    expect(
      find.descendant(of: rules, matching: find.text('Block now')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'revoked usage permits removing retained budget but no new budget',
    (tester) async {
      BlockingPlan? submitted;
      await _open(
        tester,
        usageGranted: false,
        plan: const BlockingPlan(
          id: 'retained',
          name: 'Study',
          apps: {'example.notes'},
          focus: true,
          budget: 45,
        ),
        save: (p) async => submitted = p,
      );
      final values = tester
          .widget<DropdownButton<int>>(
            find.descendant(
              of: find.byType(DropdownButtonFormField<int>),
              matching: find.byType(DropdownButton<int>),
            ),
          )
          .items!
          .map((item) => item.value!);
      expect(values.every((value) => value <= 45), isTrue);
      await _reveal(tester, _budget);
      await tester.tap(_budget);
      await tester.pumpAndSettle();
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(submitted!.budget, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await _open(tester, usageGranted: false);
      expect(tester.widget<SwitchListTile>(_budget).onChanged, isNull);
    },
  );

  testWidgets(
    'websites normalize/deduplicate and remain selectable list rows',
    (tester) async {
      BlockingPlan? submitted;
      await _open(tester, save: (p) async => submitted = p);
      await _reveal(tester, _site('instagram.com'));
      expect(
        tester.widget<CheckboxListTile>(_site('instagram.com')).value,
        isTrue,
      );
      expect(
        tester.widget<CheckboxListTile>(_site('instagram.com')).secondary,
        isA<SvgPicture>(),
      );
      expect(
        tester.widget<CheckboxListTile>(_site('university.example')).secondary,
        isA<Icon>(),
      );
      await tester.tap(_site('instagram.com'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(_site('instagram.com')).value,
        isFalse,
      );
      final domain = find.widgetWithText(TextField, 'Search or add domain');
      await _reveal(tester, domain);
      await tester.enterText(domain, 'https://NEW.example./path');
      await tester.tap(find.byTooltip('Add website'));
      await tester.pumpAndSettle();
      await tester.enterText(domain, 'new.example');
      await tester.tap(find.byTooltip('Add website'));
      await tester.pumpAndSettle();
      expect(_site('new.example'), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(_site('new.example')).value,
        isTrue,
      );
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(submitted!.sites, {'university.example', 'new.example'});
    },
  );

  testWidgets(
    'revoked website access permits only retained target reductions',
    (tester) async {
      BlockingPlan? submitted;
      await _open(
        tester,
        websiteAllowed: false,
        save: (p) async => submitted = p,
      );
      await _reveal(tester, _site('instagram.com'));
      expect(
        tester.widget<CheckboxListTile>(_site('instagram.com')).value,
        isTrue,
      );
      await tester.tap(_site('instagram.com'));
      await tester.pumpAndSettle();
      // Revoking website access must never prevent removing a saved target.
      expect(
        tester.widget<CheckboxListTile>(_site('instagram.com')).value,
        isFalse,
      );
      expect(find.byTooltip('Add website'), findsNothing);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(submitted!.sites, {'university.example'});
      expect(submitted!.apps, _plan.apps);
    },
  );

  final themes = {
    'glass': AppTheme.liquidGlass,
    'dark': AppTheme.dark,
    'light': AppTheme.light,
    'space': AppTheme.space,
  };
  for (final theme in themes.entries) {
    testWidgets('${theme.key}: compact editor retains actions at 320px/200%', (
      tester,
    ) async {
      await _open(tester, theme: theme.value, large: true);
      expect(_save.hitTestable(), findsOneWidget);
      await _reveal(tester, _windows);
      await tester.tap(_windows);
      await tester.pumpAndSettle();
      await _reveal(tester, _budget);
      await tester.tap(_budget);
      await tester.pumpAndSettle();
      await _reveal(
        tester,
        find.widgetWithText(TextField, 'Search or add domain'),
      );
      expect(_save.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  if (captureUiCatalog) {
    testWidgets('approved blocking editor real renderer catalog', (
      tester,
    ) async {
      await loadCatalogFonts();
      await _open(tester);
      await tester.ensureVisible(find.text('Rules'));
      await tester.pumpAndSettle();
      await captureCatalog(tester, 'blocking-editor-rules-off');
      await _reveal(tester, _windows);
      await tester.tap(_windows);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add time'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();
      await _reveal(tester, _budget);
      await tester.tap(_budget);
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('Rules'));
      await captureCatalog(tester, 'blocking-editor-rules-on');
      await _reveal(tester, find.byKey(const ValueKey('blocking-app-list')));
      await captureCatalog(tester, 'blocking-editor-apps-selected-first');
      await _reveal(tester, _site('instagram.com'));
      await captureCatalog(tester, 'blocking-editor-websites');
      expect(tester.takeException(), isNull);
    });
  }
}
