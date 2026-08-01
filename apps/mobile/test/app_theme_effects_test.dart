import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/theme/app_theme_effects.dart';
import 'package:my_life_graph/core/theme/app_visual_tokens.dart';
import 'package:my_life_graph/core/widgets/app_surface.dart';

void main() {
  test('Dark and Light keep every Observatory effect disabled', () {
    for (final theme in [AppTheme.dark, AppTheme.light]) {
      final effects = theme.extension<AppThemeEffects>()!;
      expect(effects.primaryControlIdleGlowColor, Colors.transparent);
      expect(effects.controlPressedScale, 1);
      expect(effects.interactiveSurfaceHoverLift, 0);
      expect(effects.navigationSignalColor, Colors.transparent);
      expect(effects.backdropMotion, same(AppBackdropMotion.disabled));
      expect(effects.surfaceMaterial, same(AppSurfaceMaterial.disabled));

      for (final style in _buttonStyles(theme)) {
        expect(style.foregroundBuilder, isNull);
        expect(style.shadowColor, isNull);
      }
      expect(
        theme.filledButtonTheme.style!.elevation!.resolve({}),
        0,
      );
      expect(
        theme.filledButtonTheme.style!.elevation!.resolve({
          WidgetState.hovered,
        }),
        0,
      );
    }
  });

  test('Space exposes exact Observatory tokens and surface glows', () {
    final theme = AppTheme.space;
    final tokens = theme.extension<AppVisualTokens>()!;
    final effects = theme.extension<AppThemeEffects>()!;

    expect(
      effects.primaryControlIdleGlowColor,
      tokens.brand.withValues(alpha: 0.26),
    );
    expect(effects.controlPressedScale, 0.96);
    expect(effects.interactiveSurfaceHoverLift, 1);
    expect(effects.navigationSignalColor, tokens.brand);
    final material = effects.surfaceMaterial;
    expect(material.enabled, isTrue);
    expect(material.hudFrameEnabled, isTrue);
    expect(material.plainOpacity, 0.48);
    expect(material.subtleOpacity, 0.52);
    expect(material.raisedOpacity, 0.58);
    expect(material.interactiveOpacity, 0.52);
    expect(material.interactiveHoverOpacity, 0.58);
    expect(material.interactivePressedOpacity, 0.60);
    expect(material.denseOpacity, 0.60);
    expect(material.semanticOpacity, 0.70);
    expect(material.overlayOpacity, 0.82);
    expect(material.navigationOpacity, 0.52);
    expect(material.navigationBlurSigma, 8);

    final hover = effects
        .interactionGlow(
          hovered: true,
          pressed: false,
          focused: false,
        )!
        .single;
    expect(hover.color, tokens.brand.withValues(alpha: 0.34));
    expect(hover.blurRadius, 24);

    final focus = effects
        .interactionGlow(
          hovered: false,
          pressed: false,
          focused: true,
        )!
        .single;
    expect(focus.color, tokens.focus.withValues(alpha: 0.38));
    expect(focus.blurRadius, 24);

    final press = effects
        .interactionGlow(
          hovered: true,
          pressed: true,
          focused: true,
        )!
        .single;
    expect(press.color, tokens.focus.withValues(alpha: 0.42));
    expect(press.blurRadius, 28);
  });

  test('Space filled button resolves idle hover focus press and disabled', () {
    final theme = AppTheme.space;
    final tokens = theme.extension<AppVisualTokens>()!;
    final effects = theme.extension<AppThemeEffects>()!;
    final style = theme.filledButtonTheme.style!;

    expect(style.elevation!.resolve({}), 2);
    expect(style.elevation!.resolve({WidgetState.hovered}), 6);
    expect(style.elevation!.resolve({WidgetState.focused}), 2);
    expect(style.elevation!.resolve({WidgetState.pressed}), 1);
    expect(style.elevation!.resolve({WidgetState.disabled}), 0);

    expect(
      style.shadowColor!.resolve({}),
      effects.primaryControlIdleGlowColor,
    );
    expect(
      style.shadowColor!.resolve({WidgetState.hovered}),
      tokens.brand.withValues(alpha: 0.55),
    );
    expect(
      style.shadowColor!.resolve({WidgetState.focused}),
      tokens.focus.withValues(alpha: 0.48),
    );
    expect(
      style.shadowColor!.resolve({WidgetState.pressed}),
      tokens.focus.withValues(alpha: 0.36),
    );
    expect(
      style.shadowColor!.resolve({WidgetState.disabled}),
      Colors.transparent,
    );

    expect(style.side!.resolve({})!.width, 1);
    expect(style.side!.resolve({WidgetState.focused})!.width, 2);
    expect(
      style.side!.resolve({WidgetState.focused})!.color,
      tokens.focus,
    );
    expect(
      style.side!.resolve({WidgetState.disabled})!.style,
      BorderStyle.none,
    );
    expect(
      style.overlayColor!.resolve({WidgetState.pressed}),
      tokens.brand.withValues(alpha: 0.30),
    );
  });

  test('Space secondary controls switch cyan hover to violet press', () {
    final theme = AppTheme.space;
    final tokens = theme.extension<AppVisualTokens>()!;
    final outlined = theme.outlinedButtonTheme.style!;
    final icon = theme.iconButtonTheme.style!;
    final text = theme.textButtonTheme.style!;

    expect(
      outlined.side!.resolve({WidgetState.hovered})!.color,
      tokens.brand,
    );
    expect(
      outlined.side!.resolve({WidgetState.pressed})!.color,
      tokens.focus,
    );
    expect(
      outlined.shadowColor!.resolve({WidgetState.hovered}),
      tokens.brand.withValues(alpha: 0.34),
    );
    expect(
      outlined.shadowColor!.resolve({WidgetState.pressed}),
      tokens.focus.withValues(alpha: 0.38),
    );
    expect(outlined.side!.resolve({WidgetState.focused})!.width, 2);
    expect(
      outlined.shadowColor!.resolve({WidgetState.focused}),
      tokens.focus.withValues(alpha: 0.36),
    );

    expect(icon.side!.resolve({WidgetState.hovered})!.color, tokens.brand);
    expect(icon.side!.resolve({WidgetState.pressed})!.color, tokens.focus);
    expect(
      icon.shadowColor!.resolve({WidgetState.hovered}),
      tokens.brand.withValues(alpha: 0.30),
    );
    expect(
      icon.shadowColor!.resolve({WidgetState.pressed}),
      tokens.focus.withValues(alpha: 0.36),
    );
    expect(icon.side!.resolve({WidgetState.focused})!.width, 2);
    expect(
      icon.shadowColor!.resolve({WidgetState.focused}),
      tokens.focus.withValues(alpha: 0.32),
    );

    expect(text.shadowColor, isNull);
    expect(text.elevation, isNull);
    expect(text.side!.resolve({WidgetState.focused})!.width, 2);
    expect(
      text.overlayColor!.resolve({WidgetState.hovered}),
      tokens.brand.withValues(alpha: 0.10),
    );
    expect(
      text.overlayColor!.resolve({WidgetState.focused}),
      tokens.focus.withValues(alpha: 0.22),
    );
    expect(
      text.overlayColor!.resolve({WidgetState.pressed}),
      tokens.focus.withValues(alpha: 0.18),
    );

    for (final style in [outlined, icon]) {
      expect(style.elevation!.resolve({WidgetState.disabled}), 0);
      expect(
        style.shadowColor!.resolve({WidgetState.disabled}),
        Colors.transparent,
      );
    }
  });

  testWidgets(
      'all four Space controls compress only enabled press and respect reduced motion',
      (tester) async {
    late BuildContext context;
    Future<void> pump({required bool reducedMotion}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.space,
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reducedMotion),
            child: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
    }

    await pump(reducedMotion: false);
    for (final style in _buttonStyles(AppTheme.space)) {
      final builder = style.foregroundBuilder!;
      expect(_scale(builder(context, {}, const Text('Idle'))).scale, 1);
      expect(
        _scale(
          builder(context, {WidgetState.hovered}, const Text('Hovered')),
        ).scale,
        1,
      );
      expect(
        _scale(
          builder(context, {WidgetState.focused}, const Text('Focused')),
        ).scale,
        1,
      );
      final pressed = _scale(
        builder(context, {WidgetState.pressed}, const Text('Pressed')),
      );
      expect(pressed.scale, 0.96);
      expect(pressed.duration, const Duration(milliseconds: 120));
      expect(
        _scale(
          builder(
            context,
            {WidgetState.disabled, WidgetState.pressed},
            const Text('Disabled'),
          ),
        ).scale,
        1,
      );
    }

    await pump(reducedMotion: true);
    for (final style in _buttonStyles(AppTheme.space)) {
      final pressed = _scale(
        style.foregroundBuilder!(
          context,
          {WidgetState.pressed},
          const Text('Pressed'),
        ),
      );
      expect(pressed.scale, 0.96);
      expect(pressed.duration, Duration.zero);
    }
  });

  testWidgets('interactive Space surface lifts one pixel and resets on press',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.space,
        home: const Scaffold(
          body: Center(
            child: AppSurface(
              variant: AppSurfaceVariant.interactive,
              onTap: _noop,
              child: Text('Hover card'),
            ),
          ),
        ),
      ),
    );

    Matrix4? transform() => tester
        .widget<AnimatedContainer>(
          find.byKey(const ValueKey('app-surface-visual')),
        )
        .transform;

    expect(transform()!.getTranslation().y, 0);
    final detector = tester.widget<FocusableActionDetector>(
      find.byType(FocusableActionDetector),
    );
    detector.onShowHoverHighlight!(true);
    await tester.pump(const Duration(milliseconds: 180));
    expect(transform()!.getTranslation().y, -1);

    final press = await tester.startGesture(
      tester.getCenter(find.text('Hover card')),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(transform()!.getTranslation().y, 0);
    await press.up();

    for (final theme in [AppTheme.dark, AppTheme.light]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: AppSurface(
              variant: AppSurfaceVariant.interactive,
              onTap: _noop,
              child: Text('Flat card'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedContainer>(
              find.byKey(const ValueKey('app-surface-visual')),
            )
            .transform,
        isNull,
      );
    }
  });

  testWidgets('Space cards resolve clear materials and HUD without blur',
      (tester) async {
    final tokens = AppTheme.space.extension<AppVisualTokens>()!;

    Future<BoxDecoration> pumpSurface(AppSurfaceVariant variant) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.space,
          home: Scaffold(
            body: Center(
              child: AppSurface(
                variant: variant,
                onTap: variant == AppSurfaceVariant.interactive ? _noop : null,
                child: const Text('Material card'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .widget<AnimatedContainer>(
            find.byKey(const ValueKey('app-surface-visual')),
          )
          .decoration! as BoxDecoration;
    }

    expect(
      (await pumpSurface(AppSurfaceVariant.plain)).color,
      tokens.surface.withValues(alpha: 0.48),
    );
    expect(find.byKey(const ValueKey('app-surface-hud-frame')), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);

    expect(
      (await pumpSurface(AppSurfaceVariant.subtle)).color,
      tokens.surfaceSubtle.withValues(alpha: 0.52),
    );
    expect(find.byKey(const ValueKey('app-surface-hud-frame')), findsOneWidget);

    expect(
      (await pumpSurface(AppSurfaceVariant.raised)).color,
      tokens.surfaceRaised.withValues(alpha: 0.58),
    );
    expect(find.byKey(const ValueKey('app-surface-hud-frame')), findsOneWidget);

    expect(
      (await pumpSurface(AppSurfaceVariant.warning)).color,
      tokens.attentionSurface.withValues(alpha: 0.70),
    );
    expect(find.byKey(const ValueKey('app-surface-hud-frame')), findsNothing);

    expect(
      (await pumpSurface(AppSurfaceVariant.danger)).color,
      tokens.dangerSurface.withValues(alpha: 0.70),
    );
    expect(find.byKey(const ValueKey('app-surface-hud-frame')), findsNothing);
  });

  testWidgets('interactive Space material changes density with pointer state',
      (tester) async {
    final tokens = AppTheme.space.extension<AppVisualTokens>()!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.space,
        home: const Scaffold(
          body: Center(
            child: AppSurface(
              variant: AppSurfaceVariant.interactive,
              onTap: _noop,
              child: Text('Stateful glass'),
            ),
          ),
        ),
      ),
    );

    Color? background() => (tester
            .widget<AnimatedContainer>(
              find.byKey(const ValueKey('app-surface-visual')),
            )
            .decoration as BoxDecoration?)
        ?.color;

    expect(background(), tokens.surfaceSubtle.withValues(alpha: 0.52));
    final detector = tester.widget<FocusableActionDetector>(
      find.byType(FocusableActionDetector),
    );
    detector.onShowHoverHighlight!(true);
    await tester.pump(const Duration(milliseconds: 180));
    expect(background(), tokens.surfaceRaised.withValues(alpha: 0.58));

    final press = await tester.startGesture(
      tester.getCenter(find.text('Stateful glass')),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(background(), tokens.surfaceRaised.withValues(alpha: 0.60));
    await press.up();
  });

  testWidgets('high contrast restores opaque blur-free Space surfaces',
      (tester) async {
    final theme = AppTheme.resolve(AppThemeId.space, highContrast: true);
    final tokens = theme.extension<AppVisualTokens>()!;
    final material = theme.extension<AppThemeEffects>()!.surfaceMaterial;
    expect(material, same(AppSurfaceMaterial.disabled));
    expect(theme.colorScheme.surfaceContainerLow, tokens.surface);
    expect(theme.colorScheme.surfaceContainer, tokens.surfaceSubtle);
    expect(theme.inputDecorationTheme.fillColor, tokens.surface);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: AppSurface(
            variant: AppSurfaceVariant.subtle,
            child: Text('Opaque card'),
          ),
        ),
      ),
    );
    final decoration = tester
        .widget<AnimatedContainer>(
          find.byKey(const ValueKey('app-surface-visual')),
        )
        .decoration! as BoxDecoration;
    expect(decoration.color, tokens.surfaceSubtle);
    expect(find.byKey(const ValueKey('app-surface-hud-frame')), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });
}

List<ButtonStyle> _buttonStyles(ThemeData theme) => [
      theme.filledButtonTheme.style!,
      theme.outlinedButtonTheme.style!,
      theme.textButtonTheme.style!,
      theme.iconButtonTheme.style!,
    ];

AnimatedScale _scale(Widget widget) => widget as AnimatedScale;

void _noop() {}
