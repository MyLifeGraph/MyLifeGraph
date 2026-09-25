import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_liquid_glass.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/theme/app_theme_effects.dart';
import 'package:my_life_graph/core/theme/app_visual_tokens.dart';
import 'package:my_life_graph/core/widgets/app_backdrop.dart';
import 'package:my_life_graph/core/widgets/app_surface.dart';
import 'package:my_life_graph/core/widgets/app_page.dart';

void main() {
  testWidgets(
    'nested supporting glass has one rim, without hiding semantic edges',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.liquidGlass,
          home: const Scaffold(
            body: AppSurface(
              child: Column(
                children: [
                  AppSurface(
                    variant: AppSurfaceVariant.subtle,
                    child: Text('Details'),
                  ),
                  AppSurface(
                    variant: AppSurfaceVariant.warning,
                    child: Text('Needs attention'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('liquid-glass-surface-rim')),
        findsOneWidget,
      );
      final warning = find
          .ancestor(
            of: find.text('Needs attention'),
            matching: find.byType(AnimatedContainer),
          )
          .first;
      expect(
        (tester.widget<AnimatedContainer>(warning).decoration as BoxDecoration)
            .border,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'glass keeps dark content and localized light instead of a white wash',
    () {
      final tokens = AppVisualTokens.liquidGlass;
      for (final surface in [
        tokens.surface,
        tokens.surfaceSubtle,
        tokens.surfaceRaised,
        tokens.surfaceInteractive,
        tokens.attentionSurface,
      ]) {
        expect(surface.computeLuminance(), lessThan(0.04));
      }
      final lighting = const AppLiquidGlass().sheen;
      expect(lighting.colors[2].a, lessThan(0.005));
      expect(lighting.colors.first.a, greaterThan(lighting.colors[2].a));
      expect(lighting.colors.last.a, greaterThan(lighting.colors[2].a));
      expect(tokens.brand.computeLuminance(), lessThan(0.55));
      expect(tokens.attention, isNot(tokens.success));
      expect(tokens.attention, isNot(tokens.danger));
    },
  );

  testWidgets(
    'glass pages cover the previous route without changing geometry',
    (tester) async {
      for (final theme in [AppTheme.dark, AppTheme.liquidGlass]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: AppPage(title: 'Planner', children: []),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final finder = find.byKey(
          const ValueKey('liquid-glass-page-background'),
        );
        if (theme == AppTheme.dark) {
          expect(finder, findsNothing);
        } else {
          final paint =
              tester.widget<DecoratedBox>(finder).decoration as BoxDecoration;
          expect(paint.gradient!.colors.every((color) => color.a == 1), isTrue);
          expect(find.byType(LiquidGlassLightAccents), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
  test(
    'glass is opt-in, static and high contrast disables optical effects',
    () {
      for (final theme in [AppTheme.dark, AppTheme.light, AppTheme.space]) {
        expect(theme.extension<AppLiquidGlass>(), isNull);
      }
      final glass = AppTheme.resolve(AppThemeId.liquidGlass);
      final effects = glass.extension<AppThemeEffects>()!;
      expect(glass.extension<AppLiquidGlass>(), isNotNull);
      expect(effects.starfieldEnabled, isFalse);
      expect(effects.backdropMotion.enabled, isFalse);
      expect(effects.surfaceMaterial.hudFrameEnabled, isFalse);
      expect(effects.surfaceMaterial.navigationBlurSigma, 8);
      expect(glass.dialogTheme.shape, isA<LiquidGlassBorder>());
      expect(glass.bottomSheetTheme.shape, isA<LiquidGlassBorder>());
      expect(glass.popupMenuTheme.shape, isA<LiquidGlassBorder>());
      expect(glass.datePickerTheme.shape, isA<LiquidGlassBorder>());
      expect(glass.timePickerTheme.shape, isA<LiquidGlassBorder>());
      final accessible = AppTheme.resolve(
        AppThemeId.liquidGlass,
        highContrast: true,
      );
      expect(accessible.extension<AppLiquidGlass>(), isNull);
      expect(
        accessible.extension<AppThemeEffects>()!.surfaceMaterial.enabled,
        isFalse,
      );
      expect(
        accessible
            .extension<AppThemeEffects>()!
            .surfaceMaterial
            .navigationBlurSigma,
        0,
      );
      expect(accessible.dialogTheme.backgroundColor!.a, 1);
    },
  );

  test('glass lighting preserves semantic tint and readable text', () {
    final tokens = AppVisualTokens.liquidGlass;
    final material = AppTheme.liquidGlass
        .extension<AppThemeEffects>()!
        .surfaceMaterial;
    final backgrounds = [
      for (final base in AppLiquidGlass.backdrop.colors)
        for (final cool in AppLiquidGlass.coolLight.colors)
          for (final soft in AppLiquidGlass.softLight.colors)
            Color.alphaBlend(soft, Color.alphaBlend(cool, base)),
    ];
    for (final backdrop in backgrounds) {
      expect(
        (tokens.textSecondary.computeLuminance() + 0.05) /
            (backdrop.computeLuminance() + 0.05),
        greaterThanOrEqualTo(4.5),
        reason: 'Unframed text must remain readable over both light pools',
      );
    }
    expect(material.plainOpacity, lessThan(0.65));
    expect(material.overlayOpacity, greaterThanOrEqualTo(0.95));
    for (final tint in [
      material.plain(tokens.surface),
      material.subtle(tokens.surfaceSubtle),
      material.raised(tokens.surfaceRaised),
      material.semantic(tokens.attentionSurface),
      material.semantic(tokens.dangerSurface),
    ]) {
      for (final lit in const AppLiquidGlass().surfaceGradient(tint).colors) {
        expect(lit.a, greaterThanOrEqualTo(tint.a));
        for (final backdrop in backgrounds) {
          final background = Color.alphaBlend(lit, backdrop).computeLuminance();
          for (final text in [tokens.textPrimary, tokens.textSecondary]) {
            final ratio =
                (text.computeLuminance() + 0.05) / (background + 0.05);
            expect(ratio, greaterThanOrEqualTo(4.5));
          }
        }
      }
    }
  });

  testWidgets(
    'glass changes paint but not surface layout, even with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<Rect> render(ThemeData theme) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(2),
              ),
              child: AppBackdrop(child: child!),
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    const AppSurface(
                      child: Text('Your next focus', key: ValueKey('label')),
                    ),
                    AppSurface(
                      variant: AppSurfaceVariant.interactive,
                      onTap: () {},
                      child: const Text('Open Planner'),
                    ),
                    const AppSurface(
                      variant: AppSurfaceVariant.warning,
                      child: Text('Needs attention'),
                    ),
                    const TextField(
                      decoration: InputDecoration(labelText: 'Plan title'),
                    ),
                    FilledButton(onPressed: () {}, child: const Text('Save')),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(BackdropFilter), findsNothing);
        return tester.getRect(find.byKey(const ValueKey('label')));
      }

      final original = await render(AppTheme.dark);
      final glass = await render(AppTheme.liquidGlass);
      expect(glass, original);
      expect(
        find.byKey(const ValueKey('liquid-glass-backdrop')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('liquid-glass-surface-rim')),
        findsNWidgets(2),
      );
    },
  );
}
