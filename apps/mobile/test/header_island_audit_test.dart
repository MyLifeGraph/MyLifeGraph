import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/composition/widgets/app_header_actions.dart';
import 'package:my_life_graph/composition/widgets/assistant_language_button.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/navigation/root_tab_pager.dart';
import 'package:my_life_graph/core/preferences/assistant_language.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/widgets/app_page.dart';
import 'package:my_life_graph/features/coach/application/coach_turn_notice.dart';
import 'package:my_life_graph/features/coach/presentation/providers/coach_providers.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_catalog_capture.dart';

const _toggleKey = ValueKey('header-island-toggle');
const _menuKey = ValueKey('header-action-menu');
const _actionKey = ValueKey('audited-page-action');

void main() {
  Future<void> pumpHeader(
    WidgetTester tester, {
    required VoidCallback action,
    FocusNode? actionFocus,
    ValueNotifier<bool>? visibility,
    Widget? pageAction,
  }) async {
    final page = Scaffold(
      body: AppPage(
        title: 'Planner',
        compactHeader: true,
        actions: [
          AppHeaderActions(
            pageActions: [
              pageAction ??
                  IconButton(
                    key: _actionKey,
                    tooltip: 'Reload',
                    focusNode: actionFocus,
                    onPressed: action,
                    icon: const Icon(Icons.refresh),
                  ),
            ],
          ),
        ],
        children: const [Text('Page body')],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: visibility == null
              ? page
              : ValueListenableBuilder<bool>(
                  valueListenable: visibility,
                  builder: (_, visible, child) =>
                      RootTabVisibility(visible: visible, child: child!),
                  child: page,
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_menuKey), findsOneWidget);
  }

  testWidgets('semantics activation of a page action dismisses the island', (
    tester,
  ) async {
    var calls = 0;
    await pumpHeader(tester, action: () => calls++);
    final node = tester.getSemantics(find.byKey(_actionKey));
    node.owner!.performAction(node.id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byKey(_menuKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
    testWidgets('keyboard ${key.keyLabel} page action dismisses the island', (
      tester,
    ) async {
      var calls = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await pumpHeader(tester, action: () => calls++, actionFocus: focus);
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(focus.hasPrimaryFocus, isTrue);
      final semantics = tester
          .getSemantics(find.byKey(_actionKey))
          .getSemanticsData();
      expect(semantics.flagsCollection.isFocused, ui.Tristate.isTrue);
      expect(semantics.hasAction(ui.SemanticsAction.focus), isTrue);
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byKey(_menuKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('screenreader language selection closes and persists once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpHeader(
      tester,
      action: () {},
      pageAction: const AssistantLanguageButton(scope: 'coach'),
    );
    final node = tester.getSemantics(
      find.byKey(const Key('coach-language-toggle')),
    );
    node.owner!.performAction(node.id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(find.byKey(_menuKey), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppHeaderActions)),
    );
    expect(container.read(assistantLanguageProvider('coach')).value, 'de');
    expect(
      (await SharedPreferences.getInstance()).getString(
        'assistant_language_v1:coach',
      ),
      'de',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'screenreader opens an unread Coach notice and closes the island',
    (tester) async {
      final notice = CoachTurnNoticeController(profileId: 'audit-profile')
        ..publish(
          profileId: 'audit-profile',
          requestId: 'audit-request',
          status: CoachTurnNoticeStatus.completed,
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [coachTurnNoticeProvider.overrideWith((_) => notice)],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(
              body: AppPage(
                title: 'Insights',
                actions: [AppHeaderActions()],
                children: [Text('Page body')],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();
      final node = tester.getSemantics(
        find.byKey(const ValueKey('global-header-coach-notice')),
      );
      expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
      node.owner!.performAction(node.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(find.byKey(_menuKey), findsNothing);
      expect(
        find.byKey(const ValueKey('coach-turn-notice-audit-request')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hiding a root page closes its island without a build exception',
    (tester) async {
      final visibility = ValueNotifier(true);
      addTearDown(visibility.dispose);
      await pumpHeader(tester, action: () {}, visibility: visibility);
      visibility.value = false;
      await tester.pumpAndSettle();
      expect(find.byKey(_menuKey), findsNothing);
      expect(tester.takeException(), isNull);
      visibility.value = true;
      await tester.pumpAndSettle();
      expect(find.byKey(_menuKey), findsNothing);
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();
      expect(find.byKey(_menuKey), findsOneWidget);
    },
  );

  testWidgets('disposing the header during reveal removes its overlay', (
    tester,
  ) async {
    await pumpHeader(tester, action: () {});
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(const MaterialApp(home: Text('Replacement')));
    await tester.pumpAndSettle();
    expect(find.byKey(_menuKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pushed page and system Back never restore an old open island', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: AppPage(
              title: 'Planner',
              compactHeader: true,
              actions: [AppHeaderActions()],
              children: [],
            ),
          ),
        ),
        GoRoute(
          path: '/details',
          builder: (_, _) => const Scaffold(body: Text('Details')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    for (var cycle = 0; cycle < 10; cycle++) {
      await tester.tap(find.byKey(_toggleKey));
      await tester.pump(const Duration(milliseconds: 35));
      router.push('/details');
      await tester.pumpAndSettle();
      expect(find.text('Details').hitTestable(), findsOneWidget);
      expect(find.byKey(_menuKey), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.text('Planner').hitTestable(), findsOneWidget);
      expect(find.byKey(_menuKey), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('reopening while closing retains one usable action', (
    tester,
  ) async {
    var calls = 0;
    await pumpHeader(tester, action: () => calls++);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 30));
    // Activate the real toggle directly because the exiting capsule still
    // paints above the anchor while it completes the reverse animation.
    tester.widget<IconButton>(find.byKey(_toggleKey)).onPressed!();
    await tester.pumpAndSettle();
    expect(find.byKey(_menuKey), findsOneWidget);
    await tester.tap(find.byKey(_actionKey));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byKey(_menuKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'direct heading preserves title with Android and unread actions at $width',
      (tester) async {
        // Real bundled font metrics are necessary to establish glyph overlap,
        // rather than measuring the artificial Ahem font of widget tests.
        await loadCatalogFonts();
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              focusProtectionPlatformSupportedProvider.overrideWithValue(true),
              appSurfaceCapabilitiesProvider.overrideWithValue(
                const AppSurfaceCapabilities(
                  isLocalDemo: false,
                  canUseSyncedHabits: true,
                  canUseDeviceFocusProtection: true,
                ),
              ),
              coachTurnNoticeProvider.overrideWith(
                (_) =>
                    CoachTurnNoticeController(profileId: 'audit-profile')
                      ..publish(
                        profileId: 'audit-profile',
                        requestId: 'audit-request',
                        status: CoachTurnNoticeStatus.completed,
                      ),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.dark,
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AppPageHeading(
                    title: Text(
                      'Insights',
                      style: AppTheme.dark.textTheme.headlineMedium,
                    ),
                    actions: const AppHeaderActions(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final title = tester.getRect(find.text('Insights'));
        final painter = TextPainter(
          text: TextSpan(
            text: 'Insights',
            style: AppTheme.dark.textTheme.headlineMedium,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final titleGlyphRight = title.left + painter.width;
        painter.dispose();
        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('global-header-blocking')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('global-header-coach-notice')),
          findsOneWidget,
        );
        final menu = tester.getRect(find.byKey(_menuKey));
        expect(
          menu.left,
          greaterThanOrEqualTo(titleGlyphRight + 8),
          reason: 'The loaded Insights title must remain outside its capsule.',
        );
        expect(tester.getRect(find.text('Insights')), title);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
