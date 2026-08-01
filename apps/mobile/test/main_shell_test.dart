import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/navigation/app_routes.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/theme/app_theme_effects.dart';
import 'package:my_life_graph/core/theme/app_visual_tokens.dart';
import 'package:my_life_graph/features/shell/presentation/main_shell.dart';
import 'package:my_life_graph/features/shell/presentation/shell_destination_descriptor.dart';

void main() {
  group('shell destination descriptors', () {
    test('own one unique route and presentation definition per destination',
        () {
      expect(
        shellDestinations.map((destination) => destination.path),
        [
          AppRoutes.dashboard,
          AppRoutes.insights,
          AppRoutes.quickAction,
          AppRoutes.planner,
          AppRoutes.coach,
        ],
      );
      expect(
        shellDestinations.map((destination) => destination.label),
        ['Today', 'Insights', 'Quick actions', 'Planner', 'Coach'],
      );
      expect(
        shellDestinations.map((destination) => destination.path).toSet().length,
        shellDestinations.length,
      );
      expect(
        shellDestinations
            .where((destination) => destination.emphasized)
            .single
            .path,
        AppRoutes.quickAction,
      );
      for (final destination in shellDestinations) {
        expect(destination.activePathPrefixes, contains(destination.path));
      }
    });

    test('maps nested feature paths to the same responsive destination', () {
      const expectedPaths = <String, String>{
        AppRoutes.dashboard: AppRoutes.dashboard,
        AppRoutes.weeklyReview: AppRoutes.dashboard,
        AppRoutes.insights: AppRoutes.insights,
        AppRoutes.quickAction: AppRoutes.quickAction,
        AppRoutes.habitCompletion: AppRoutes.quickAction,
        AppRoutes.quickMoodCheckIn: AppRoutes.quickAction,
        AppRoutes.dailyCheckIn: AppRoutes.quickAction,
        AppRoutes.deepWork: AppRoutes.quickAction,
        AppRoutes.planner: AppRoutes.planner,
        AppRoutes.plannerReplan: AppRoutes.planner,
        AppRoutes.habitManagement: AppRoutes.planner,
        AppRoutes.preparationPlans: AppRoutes.planner,
        AppRoutes.coach: AppRoutes.coach,
      };
      for (final entry in expectedPaths.entries) {
        expect(
          shellDestinationForPath(entry.key)?.path,
          entry.value,
          reason: entry.key,
        );
      }

      for (final path in [
        AppRoutes.settings,
        AppRoutes.alerts,
        AppRoutes.notifications,
        AppRoutes.notificationSettings,
        AppRoutes.calendarIntegration,
        AppRoutes.morningCalibration,
      ]) {
        expect(shellDestinationForPath(path), isNull, reason: path);
      }
    });

    test('Coach is the only capability-gated destination', () {
      expect(
        visibleShellDestinations(canShowCoach: false)
            .map((destination) => destination.path),
        isNot(contains(AppRoutes.coach)),
      );
      expect(
        visibleShellDestinations(canShowCoach: true)
            .map((destination) => destination.path),
        contains(AppRoutes.coach),
      );
      expect(
        shellDestinations
            .where((destination) => destination.requiresCoachCapability)
            .single
            .path,
        AppRoutes.coach,
      );
    });
  });

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
              canShowCoachSurface: true,
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
              canShowCoachSurface: true,
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

  testWidgets('Space applies the shared glow to quick action and navigation',
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
              canShowCoachSurface: true,
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.space,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final idleQuickActionGlow = tester.widget<Container>(
      find.byKey(const ValueKey('main-shell-add-signal-glow')),
    );
    final idleQuickActionShadows =
        (idleQuickActionGlow.decoration! as BoxDecoration).boxShadow!;
    expect(idleQuickActionShadows, hasLength(2));
    expect(
      idleQuickActionShadows.last.color,
      AppTheme.space.extension<AppThemeEffects>()!.primaryControlIdleGlowColor,
    );
    final quickActionPress = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey('main-shell-add-signal-control')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      tester
          .widget<AnimatedScale>(
            find.descendant(
              of: find.byKey(
                const ValueKey('main-shell-add-signal-control'),
              ),
              matching: find.byType(AnimatedScale),
            ),
          )
          .scale,
      0.94,
    );
    await quickActionPress.cancel();
    await tester.pump(const Duration(milliseconds: 120));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();

    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey('main-shell-add-signal-control')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));
    final quickActionGlow = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(
              const ValueKey('main-shell-add-signal-control'),
            ),
            matching: find.byKey(
              const ValueKey('main-shell-add-signal-glow'),
            ),
          )
          .first,
    );
    expect(
      (quickActionGlow.decoration! as BoxDecoration).boxShadow,
      hasLength(2),
    );

    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey('main-nav-planner-control')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 180));
    final navigationGlow = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('main-nav-planner-glow')),
    );
    expect(
      (navigationGlow.decoration! as BoxDecoration).boxShadow,
      isNotEmpty,
    );
  });

  testWidgets(
      'Space shell renders one navigation blur and opaque themes render none',
      (tester) async {
    final router = _router(initialLocation: AppRoutes.dashboard);
    addTearDown(router.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    Future<void> pump(ThemeData theme, Size size) async {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSurfaceCapabilitiesProvider.overrideWithValue(
              const AppSurfaceCapabilities(
                isLocalDemo: false,
                canUseSyncedHabits: true,
                canShowCoachSurface: true,
              ),
            ),
          ],
          child: MaterialApp.router(
            theme: theme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(AppTheme.space, const Size(390, 844));
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      find.byKey(const ValueKey('space-navigation-backdrop-filter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-navigation-material')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-navigation-material')),
      findsNothing,
    );
    final mobileSurface = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byKey(const ValueKey('mobile-navigation-material')),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    final spaceTokens = AppTheme.space.extension<AppVisualTokens>()!;
    expect(
      mobileSurface.color,
      spaceTokens.surface.withValues(alpha: 0.52),
    );

    await pump(AppTheme.dark, const Size(390, 844));
    expect(find.byType(BackdropFilter), findsNothing);

    final highContrast = AppTheme.resolve(AppThemeId.space, highContrast: true);
    await pump(highContrast, const Size(390, 844));
    expect(find.byType(BackdropFilter), findsNothing);
    final opaqueMobileSurface = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byKey(const ValueKey('mobile-navigation-material')),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(opaqueMobileSurface.color, spaceTokens.surface);

    await pump(AppTheme.space, const Size(1280, 800));
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktop-navigation-material')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-navigation-material')),
      findsNothing,
    );
  });

  testWidgets(
      'Space mobile navigation signals selection without changing semantics',
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
              canShowCoachSurface: true,
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.space,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final todaySignal =
        find.byKey(const ValueKey('mobile-navigation-signal-today'));
    final plannerSignal =
        find.byKey(const ValueKey('mobile-navigation-signal-planner'));
    expect(tester.getSize(todaySignal), const Size(24, 3));
    expect(_signalOpacity(tester, todaySignal).opacity, 1);
    expect(_signalOpacity(tester, plannerSignal).opacity, 0);
    expect(
      _signalOpacity(tester, todaySignal).duration,
      const Duration(milliseconds: 180),
    );
    _expectSignalHalo(tester, todaySignal);
    expect(_navigationIconScale(tester, 'today').scale, 1);
    expect(_navigationIconScale(tester, 'planner').scale, 0.97);

    await tester.tap(
      find.byKey(const ValueKey('main-nav-planner-control')),
    );
    await tester.pumpAndSettle();

    expect(_signalOpacity(tester, todaySignal).opacity, 0);
    expect(_signalOpacity(tester, plannerSignal).opacity, 1);
    expect(_navigationIconScale(tester, 'today').scale, 0.97);
    expect(_navigationIconScale(tester, 'planner').scale, 1);
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

  testWidgets('Space desktop navigation uses a three by twenty-eight signal',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = _router(initialLocation: AppRoutes.dashboard);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canShowCoachSurface: true,
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.space,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final todaySignal =
        find.byKey(const ValueKey('desktop-navigation-signal-today'));
    final insightsSignal =
        find.byKey(const ValueKey('desktop-navigation-signal-insights'));
    expect(tester.getSize(todaySignal), const Size(3, 28));
    expect(_signalOpacity(tester, todaySignal).opacity, 1);
    expect(_signalOpacity(tester, insightsSignal).opacity, 0);
    _expectSignalHalo(tester, todaySignal);

    await tester.tap(
      find.byKey(const ValueKey('main-nav-insights-control')),
    );
    await tester.pumpAndSettle();
    expect(_signalOpacity(tester, todaySignal).opacity, 0);
    expect(_signalOpacity(tester, insightsSignal).opacity, 1);
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
              canShowCoachSurface: true,
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
    expect(find.byKey(const ValueKey('main-nav-coach')), findsOneWidget);
    expect(find.byKey(const ValueKey('main-nav-settings')), findsNothing);
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
                canShowCoachSurface: true,
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
        'coach',
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
        tester.getSemantics(find.byKey(const ValueKey('main-nav-coach'))),
        matchesSemantics(
          label: 'Coach',
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      expect(tester.takeException(), isNull);

      final coachLabel = find.byKey(
        const ValueKey('main-nav-label-coach'),
      );
      await tester.tap(coachLabel);
      await tester.pumpAndSettle();

      expect(find.text('Coach destination'), findsOneWidget);
      expect(coachLabel, findsOneWidget);
      _expectFullyRenderedLabel(tester, coachLabel);
      expect(
        find.ancestor(of: coachLabel, matching: find.byType(FittedBox)),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('main-nav-label-today')),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('main-nav-coach'))),
        matchesSemantics(
          label: 'Coach',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      expect(find.bySemanticsLabel('Coach'), findsOneWidget);
      expect(find.bySemanticsLabel('Settings'), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets('Coach gate hides the destination without restoring Settings',
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
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('main-nav-coach')), findsNothing);
    expect(find.byKey(const ValueKey('main-nav-settings')), findsNothing);
  });

  testWidgets('calendar integration leaves shell destinations unselected',
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
              canShowCoachSurface: true,
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Calendar destination'), findsOneWidget);
    expect(find.byKey(const ValueKey('main-nav-settings')), findsNothing);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('main-nav-coach'))),
      matchesSemantics(
        label: 'Coach',
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
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

  testWidgets('legacy Inbox route leaves Coach and Planner unselected',
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
              canShowCoachSurface: true,
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inbox destination'), findsOneWidget);
    expect(find.byKey(const ValueKey('main-nav-settings')), findsNothing);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('main-nav-coach'))),
      matchesSemantics(
        label: 'Coach',
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
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

AnimatedOpacity _signalOpacity(WidgetTester tester, Finder signal) =>
    tester.widget<AnimatedOpacity>(
      find.descendant(
        of: signal,
        matching: find.byType(AnimatedOpacity),
      ),
    );

AnimatedScale _navigationIconScale(WidgetTester tester, String label) =>
    tester.widget<AnimatedScale>(
      find
          .descendant(
            of: find.byKey(ValueKey('main-nav-$label-control')),
            matching: find.byType(AnimatedScale),
          )
          .first,
    );

void _expectSignalHalo(WidgetTester tester, Finder signal) {
  final container = tester.widget<Container>(
    find.descendant(of: signal, matching: find.byType(Container)),
  );
  final decoration = container.decoration! as BoxDecoration;
  final halo = decoration.boxShadow!.single;
  final signalColor =
      AppTheme.space.extension<AppThemeEffects>()!.navigationSignalColor;
  expect(decoration.color, signalColor);
  expect(halo.color, signalColor.withValues(alpha: 0.55));
  expect(halo.blurRadius, 10);
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
        path: AppRoutes.coach,
        builder: (_, __) => shell(AppRoutes.coach, 'Coach destination'),
      ),
      GoRoute(
        path: AppRoutes.calendarIntegration,
        builder: (_, __) =>
            shell(AppRoutes.calendarIntegration, 'Calendar destination'),
      ),
    ],
  );
}
