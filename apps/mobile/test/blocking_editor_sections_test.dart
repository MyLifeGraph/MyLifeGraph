import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:my_life_graph/core/widgets/app_backdrop.dart';
import 'package:my_life_graph/features/focus_protection/domain/blocking_plan.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';
import 'package:my_life_graph/features/focus_protection/presentation/widgets/blocking_custom_editor.dart';
import 'package:my_life_graph/features/focus_protection/presentation/widgets/blocking_screen_preview.dart';
import 'package:my_life_graph/features/focus_protection/presentation/widgets/blocking_target_list.dart';
import 'support/ui_catalog_capture.dart';

const _plan = BlockingPlan(
  id: 'study',
  name: 'Study',
  icon: 'study',
  apps: {'instagram', 'youtube'},
  sites: {'instagram.com'},
  focus: true,
  windows: [
    BlockingWindow(days: {1, 2, 3, 4, 5}, start: 540, end: 1080),
  ],
  budget: 45,
);
const _catalog = <Map>[
  {'packageName': 'instagram', 'label': 'Instagram'},
  {'packageName': 'youtube', 'label': 'YouTube'},
  {'packageName': 'calculator', 'label': 'Calculator'},
  {'packageName': 'game', 'label': 'Puzzle', 'category': 'Games'},
  {'packageName': 'notes', 'label': 'Notes'},
];
Future<void> _open(
  WidgetTester t,
  Widget editor, {
  ThemeData? theme,
  bool large = false,
  bool keyboard = false,
  bool animations = false,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(large ? 320 : 390, 844);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? AppTheme.liquidGlass,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(large ? 2 : 1),
          disableAnimations: !animations,
          viewInsets: EdgeInsets.only(bottom: keyboard ? 300 : 0),
        ),
        child: AppBackdrop(child: Scaffold(body: child!)),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              enableDrag: false,
              showDragHandle: false,
              builder: (_) => editor,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  await t.tap(find.text('Open'));
  await t.pumpAndSettle();
}

Future<void> _tab(WidgetTester t, int index) async {
  final f = find.byKey(ValueKey('blocking-editor-tab-$index'));
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> _show(WidgetTester t, Finder f) async {
  final scroll = t
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('blocking-custom-scroll')),
          matching: find.byType(Scrollable),
        ),
      )
      .position;
  while (f.evaluate().isEmpty && scroll.pixels < scroll.maxScrollExtent) {
    scroll.jumpTo((scroll.pixels + 160).clamp(0, scroll.maxScrollExtent));
    await t.pumpAndSettle();
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Customize horizontal text editing does not change sections', (t) async {
    await _open(t, BlockingCustomEditor(custom: const {}, iconBuilder: blockingIcon,
      onSave: (_) async => true, error: () => null), animations: true);
    final title = find.widgetWithText(TextField, 'Title');
    await t.enterText(title, 'Keep this title');
    await t.pumpAndSettle();
    final rect = t.getRect(find.byKey(const ValueKey('blocking-custom-scroll')));
    await t.dragFrom(Offset(rect.left + 4, rect.top + 24), const Offset(-280, 0));
    await t.pumpAndSettle();
    expect(find.ancestor(of: find.byKey(const ValueKey('blocking-editor-tab-0')),
      matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.selected == true)), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Keep this title'), findsOneWidget);
  });
  testWidgets('Customize top-only dismissal preserves scrolling and never saves', (t) async {
    var saves = 0;
    await _open(t, BlockingCustomEditor(custom: const {}, iconBuilder: blockingIcon,
      onSave: (_) async { saves++; return true; }, error: () => null), large: true, keyboard: true);
    await _tab(t, 1);
    final list = find.byKey(const ValueKey('blocking-custom-scroll'));
    final controller = t.widget<ListView>(list).controller!;
    final rect = t.getRect(list);
    final gesture = await t.startGesture(Offset(rect.left + 4, rect.center.dy));
    await gesture.moveBy(const Offset(0, -120));
    await t.pump();
    await gesture.moveBy(const Offset(0, 500));
    await t.pump();
    await gesture.up();
    await t.pumpAndSettle();
    expect(find.byType(BlockingCustomEditor), findsOneWidget);
    controller.jumpTo(120);
    await t.pumpAndSettle();
    await t.drag(list, const Offset(0, 1000));
    await t.pumpAndSettle();
    expect(find.byType(BlockingCustomEditor), findsOneWidget);
    expect(controller.position.pixels, closeTo(0, 1));
    await t.drag(list, const Offset(0, 220));
    await t.pumpAndSettle();
    expect(find.byType(BlockingCustomEditor), findsNothing);
    expect(saves, 0);
  });
  for (final custom in [false, true]) {
    testWidgets('editor sections retain independent scroll offsets; custom=$custom', (t) async {
      await _open(t, custom
        ? BlockingCustomEditor(custom: const {}, iconBuilder: blockingIcon,
            onSave: (_) async => true, error: () => null)
        : const BlockingPlanEditor(plan: _plan, catalog: _catalog,
            usageGranted: true, websiteAllowed: true), large: true, keyboard: true);
      await _tab(t, custom ? 1 : 0);
      final list = find.byKey(ValueKey(custom ? 'blocking-custom-scroll' : 'blocking-editor-scroll'));
      final controller = t.widget<ListView>(list).controller!;
      controller.jumpTo(100);
      await t.pumpAndSettle();
      final offset = controller.offset;
      await _tab(t, 2);
      await _tab(t, custom ? 1 : 0);
      expect(t.widget<ListView>(list).controller!.offset, closeTo(offset, 1));
      expect(t.takeException(), isNull);
    });
  }
  for (final customize in [false, true]) {
    testWidgets('editor sections swipe in both directions; customize=$customize', (t) async {
      await _open(t, customize
          ? BlockingCustomEditor(custom: const {}, iconBuilder: blockingIcon,
              onSave: (_) async => true, error: () => null)
          : const BlockingPlanEditor(plan: _plan, catalog: _catalog,
              usageGranted: true, websiteAllowed: true), animations: true);
      final area = find.byKey(ValueKey(customize ? 'blocking-custom-scroll' : 'blocking-editor-scroll'));
      var rect = t.getRect(area);
      await t.dragFrom(Offset(rect.left + 4, rect.top + 24), const Offset(-280, 0));
      await t.pumpAndSettle();
      final selected = find.ancestor(
        of: find.byKey(const ValueKey('blocking-editor-tab-1')),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.selected == true));
      expect(selected, findsOneWidget);
      rect = t.getRect(area);
      await t.dragFrom(Offset(rect.right - 4, rect.top + 24), const Offset(280, 0));
      await t.pumpAndSettle();
      expect(find.ancestor(of: find.byKey(const ValueKey('blocking-editor-tab-0')),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.selected == true)), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'plan sections retain all rule values, icon and current selections',
    (t) async {
      BlockingPlan? saved;
      await _open(
        t,
        BlockingPlanEditor(
          plan: _plan,
          catalog: _catalog,
          usageGranted: true,
          websiteAllowed: true,
          onSave: (p) async => saved = p,
        ),
      );
      for (final (index, icon) in [AppIcons.tuneOutlined, AppIcons.squaresFour, AppIcons.publicOutlined].indexed) {
        expect(find.descendant(
          of: find.byKey(ValueKey('blocking-editor-tab-$index')),
          matching: find.byIcon(icon),
        ), findsOneWidget);
      }
      await t.tap(find.byTooltip('Plan icon'));
      await t.pumpAndSettle();
      for (final icon in [
        'shield',
        'work',
        'games',
        'social',
        'sleep',
        'study',
      ]) {
        expect(find.byTooltip(icon), findsOneWidget);
      }
      await t.tap(find.byTooltip('work'));
      await t.pumpAndSettle();
      await _tab(t, 1);
      await t.tap(find.byKey(const ValueKey('blocking-app-calculator')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<BlockingTargetList>(find.byType(BlockingTargetList))
            .orderedIds
            .take(3),
        ['instagram', 'youtube', 'calculator'],
      );
      await t.tap(find.byKey(const ValueKey('blocking-app-instagram')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<BlockingTargetList>(find.byType(BlockingTargetList))
            .orderedIds,
        ['youtube', 'calculator', 'instagram', 'game', 'notes'],
      );
      await _tab(t, 2);
      await t.tap(find.byKey(const ValueKey('blocking-site-reddit.com')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<BlockingTargetList>(find.byType(BlockingTargetList))
            .orderedIds
            .take(2),
        ['instagram.com', 'reddit.com'],
      );
      await t.tap(find.widgetWithText(FilterChip, 'Video'));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('blocking-site-reddit.com')),
        findsOneWidget,
      );
      await t.tap(find.widgetWithText(FilledButton, 'Save'));
      await t.pumpAndSettle();
      expect(saved!.apps, {'youtube', 'calculator'});
      expect(saved!.sites, {'instagram.com', 'reddit.com'});
      expect(saved!.icon, 'work');
      expect(saved!.focus, _plan.focus);
      expect(saved!.budget, _plan.budget);
      expect(
        saved!.windows.map((w) => w.toMap()),
        _plan.windows.map((w) => w.toMap()),
      );
      expect(t.takeException(), isNull);
    },
  );
  for (final theme in [
    AppTheme.liquidGlass,
    AppTheme.dark,
    AppTheme.light,
    AppTheme.space,
  ]) {
    testWidgets(
      'Customize preserves draft across sections with large text/keyboard ${theme.brightness}/${theme.scaffoldBackgroundColor}',
      (t) async {
        Map<String, Object>? saved;
        await _open(
          t,
          BlockingCustomEditor(
            custom: const {'futureKey': 'retained'},
            iconBuilder: blockingIcon,
            error: () => null,
            onSave: (p) async {
              saved = p;
              return true;
            },
          ),
          theme: theme,
          large: true,
          keyboard: true,
        );
        expect(
          find.widgetWithText(FilledButton, 'Save').hitTestable(),
          findsOneWidget,
        );
        await t.enterText(find.widgetWithText(TextField, 'Title'), 'Your goal');
        await _tab(t, 1);
        await _show(t, find.byTooltip('study'));
        await t.tap(find.byTooltip('study'));
        await _show(t, find.byTooltip('mint'));
        await t.tap(find.byTooltip('mint'));
        await _tab(t, 2);
        await _show(t, find.byType(DropdownButtonFormField<int>));
        final field = t.widget<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>),
        );
        expect(field.initialValue, 0);
        final options = t
            .widget<DropdownButton<int>>(
              find.descendant(
                of: find.byType(DropdownButtonFormField<int>),
                matching: find.byType(DropdownButton<int>),
              ),
            )
            .items!
            .map((v) => v.value)
            .toList();
        expect(options, [0, 1, 3, 5, 10, 15, 20, 60, 180, 300, 600, 900]);
        await _tab(t, 0);
        expect(
          t
              .widget<TextField>(find.widgetWithText(TextField, 'Title'))
              .controller!
              .text,
          'Your goal',
        );
        await t.tap(find.byTooltip('Expand preview'));
        await t.pumpAndSettle();
        final preview = t.widget<BlockingScreenPreview>(
          find.byType(BlockingScreenPreview),
        );
        expect(preview.custom['icon'], 'study');
        expect(preview.custom['accent'], 'mint');
        await t.tap(find.byTooltip('Close preview'));
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(FilledButton, 'Save'));
        await t.pumpAndSettle();
        expect(saved!['futureKey'], 'retained');
        expect(saved!['title'], 'Your goal');
        expect(t.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
  if (captureUiCatalog) {
    testWidgets(
      'actual section screenshots',
      (t) async {
        await loadCatalogFonts();
        await _open(
          t,
          const BlockingPlanEditor(
            plan: _plan,
            catalog: _catalog,
            usageGranted: true,
            websiteAllowed: true,
          ),
        );
        await captureCatalog(t, 'after-plan-rules');
        await t.tap(find.byTooltip('Plan icon'));
        await t.pumpAndSettle();
        await captureCatalog(t, 'after-plan-icons');
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        await _tab(t, 1);
        await captureCatalog(t, 'after-plan-apps');
        await _tab(t, 2);
        await captureCatalog(t, 'after-plan-websites');
        await t.pumpWidget(const SizedBox());
        await _open(
          t,
          BlockingCustomEditor(
            custom: const {},
            iconBuilder: blockingIcon,
            onSave: (_) async => true,
            error: () => null,
          ),
        );
        await captureCatalog(t, 'after-custom-content');
        await _tab(t, 1);
        await captureCatalog(t, 'after-custom-style');
        await _tab(t, 2);
        await captureCatalog(t, 'after-custom-delay');
        await t.tap(find.byTooltip('Expand preview'));
        await t.pumpAndSettle();
        await captureCatalog(t, 'after-custom-expanded-preview');
        expect(t.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}
