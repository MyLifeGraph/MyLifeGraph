import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/navigation/app_routes.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/shell/presentation/main_shell.dart';

void main() {
  testWidgets('deep work selects the keyboard-operable quick action control',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final router = _router();
    addTearDown(router.dispose);

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
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('main-shell-add-signal')),
      ),
      matchesSemantics(
        label: 'Quick actions',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('main-nav-planner'))),
      matchesSemantics(
        label: 'Planner',
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
        hasTapAction: true,
      ),
    );

    final addSignalControl =
        find.byKey(const ValueKey('main-shell-add-signal-control'));
    await _tabUntilFocused(tester, addSignalControl);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Quick action destination'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('bottom destinations are keyboard focusable and selectable',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final router = _router(initialLocation: AppRoutes.dashboard);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final plannerControl = find.byKey(
      const ValueKey('main-nav-planner-control'),
    );
    await _tabUntilFocused(tester, plannerControl);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(find.text('Planner destination'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('main-nav-planner'))),
      matchesSemantics(
        label: 'Planner',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('light add icon uses the contrasting on-primary color',
      (tester) async {
    final router = _router(initialLocation: AppRoutes.dashboard);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final iconFinder = find.byKey(
      const ValueKey('main-shell-add-signal-icon'),
    );
    final icon = tester.widget<Icon>(iconFinder);
    final colors = Theme.of(tester.element(iconFinder)).colorScheme;

    expect(icon.color, colors.onPrimary);
    expect(
      _contrastRatio(colors.onPrimary, colors.primary),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('wide layouts expose a persistent desktop navigation',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    final router = _router(initialLocation: AppRoutes.dashboard);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MyLifeGraph'), findsOneWidget);
    expect(
      tester.getCenter(find.text('Home destination')).dx,
      greaterThan(236),
    );
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('main-shell-add-signal')),
      ),
      matchesSemantics(
        label: 'Quick actions',
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
        hasTapAction: true,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('main-nav-insights-control')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Insights destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final textScale in [1.5, 2.0]) {
    testWidgets(
        'compact bottom navigation respects ${textScale}x text and remains selectable',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final router = _router(initialLocation: AppRoutes.dashboard);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSurfaceCapabilitiesProvider.overrideWithValue(
              const AppSurfaceCapabilities(
                isLocalDemo: false,
                canUseSyncedHabits: true,
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      const labels = [
        'today',
        'insights',
        'quick-actions',
        'planner',
        'settings',
      ];
      for (final label in labels) {
        final labelFinder = find.byKey(ValueKey('main-nav-label-$label'));
        expect(labelFinder, findsOneWidget);
        _expectFullyRenderedLabel(tester, labelFinder);
        expect(
          find.ancestor(of: labelFinder, matching: find.byType(FittedBox)),
          findsNothing,
        );
      }
      expect(
        tester.getSemantics(find.byKey(const ValueKey('main-nav-settings'))),
        matchesSemantics(
          label: 'Settings',
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      expect(tester.takeException(), isNull);

      final settingsLabel = find.byKey(
        const ValueKey('main-nav-label-settings'),
      );
      await tester.tap(settingsLabel);
      await tester.pumpAndSettle();

      expect(find.text('Settings destination'), findsOneWidget);
      expect(settingsLabel, findsOneWidget);
      _expectFullyRenderedLabel(tester, settingsLabel);
      expect(
        find.ancestor(of: settingsLabel, matching: find.byType(FittedBox)),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('main-nav-label-today')),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('main-nav-settings'))),
        matchesSemantics(
          label: 'Settings',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      expect(find.bySemanticsLabel('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets('calendar integration selects Settings in shell semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final router = _router(initialLocation: AppRoutes.calendarIntegration);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseCalendarIntegration: true,
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Calendar destination'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('main-nav-settings'))),
      matchesSemantics(
        label: 'Settings',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('main-nav-today'))),
      matchesSemantics(
        label: 'Today',
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('legacy Inbox route selects Settings, not Planner',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final router = _router(initialLocation: AppRoutes.alerts);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inbox destination'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('main-nav-settings'))),
      matchesSemantics(
        label: 'Settings',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('main-nav-planner'))),
      matchesSemantics(
        label: 'Planner',
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });
}

double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground.computeLuminance()
      : background.computeLuminance();
  final darker = foreground.computeLuminance() > background.computeLuminance()
      ? background.computeLuminance()
      : foreground.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}

void _expectFullyRenderedLabel(WidgetTester tester, Finder labelFinder) {
  final widget = tester.widget<Text>(labelFinder);
  final context = tester.element(labelFinder);
  final renderBox = tester.renderObject<RenderBox>(labelFinder);
  final effectiveStyle = DefaultTextStyle.of(context).style.merge(widget.style);
  final painter = TextPainter(
    text: TextSpan(text: widget.data, style: effectiveStyle),
    textDirection: Directionality.of(context),
    textScaler: widget.textScaler ?? MediaQuery.textScalerOf(context),
    maxLines: widget.maxLines,
  )..layout(maxWidth: renderBox.size.width);

  expect(widget.overflow, isNot(TextOverflow.ellipsis));
  expect(
    painter.didExceedMaxLines,
    isFalse,
    reason: '${widget.data} did not fit ${renderBox.size.width}px',
  );
}

Future<void> _tabUntilFocused(WidgetTester tester, Finder control) async {
  for (var attempt = 0; attempt < 12; attempt += 1) {
    if (_containsPrimaryFocus(tester, control)) {
      return;
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(_containsPrimaryFocus(tester, control), isTrue);
}

bool _containsPrimaryFocus(WidgetTester tester, Finder control) {
  final focusedContext = FocusManager.instance.primaryFocus?.context;
  if (focusedContext is! Element) {
    return false;
  }
  final target = tester.element(control);
  if (identical(focusedContext, target)) {
    return true;
  }
  var containsFocus = false;
  focusedContext.visitAncestorElements((ancestor) {
    if (identical(ancestor, target)) {
      containsFocus = true;
      return false;
    }
    return true;
  });
  return containsFocus;
}

GoRouter _router({String initialLocation = AppRoutes.deepWork}) {
  Widget shell(String path, String label) => MainShell(
        currentPath: path,
        child: Center(child: Text(label)),
      );

  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.deepWork,
        builder: (_, __) => shell(AppRoutes.deepWork, 'Focus destination'),
      ),
      GoRoute(
        path: AppRoutes.quickAction,
        builder: (_, __) =>
            shell(AppRoutes.quickAction, 'Quick action destination'),
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (_, __) => shell(AppRoutes.dashboard, 'Home destination'),
      ),
      GoRoute(
        path: AppRoutes.insights,
        builder: (_, __) => shell(AppRoutes.insights, 'Insights destination'),
      ),
      GoRoute(
        path: AppRoutes.planner,
        builder: (_, __) => shell(AppRoutes.planner, 'Planner destination'),
      ),
      GoRoute(
        path: AppRoutes.alerts,
        builder: (_, __) => shell(AppRoutes.alerts, 'Inbox destination'),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, __) => shell(AppRoutes.settings, 'Settings destination'),
      ),
      GoRoute(
        path: AppRoutes.calendarIntegration,
        builder: (_, __) =>
            shell(AppRoutes.calendarIntegration, 'Calendar destination'),
      ),
    ],
  );
}
