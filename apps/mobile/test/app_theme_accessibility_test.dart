import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/theme/app_theme_effects.dart';
import 'package:my_life_graph/core/theme/app_visual_tokens.dart';

void main() {
  for (final entry in {
    'dark': AppTheme.dark,
    'light': AppTheme.light,
    'space': AppTheme.space,
  }.entries) {
    test('${entry.key} theme keeps keyboard focus visibly highlighted', () {
      final theme = entry.value;
      expect(theme.focusColor.a, greaterThan(0));

      final styles = [
        theme.filledButtonTheme.style,
        theme.iconButtonTheme.style,
        theme.textButtonTheme.style,
        theme.outlinedButtonTheme.style,
      ];
      for (final style in styles) {
        final focused = style?.overlayColor?.resolve({WidgetState.focused});
        expect(focused, isNotNull);
        expect(focused!.a, greaterThan(0));
      }

      final filledFocus = theme.filledButtonTheme.style?.overlayColor
          ?.resolve({WidgetState.focused});
      expect(
        Color.alphaBlend(filledFocus!, theme.colorScheme.primary),
        isNot(theme.colorScheme.primary),
      );
    });

    test('${entry.key} text and status roles meet normal-text contrast', () {
      final theme = entry.value;
      final scheme = theme.colorScheme;
      final tokens = theme.extension<AppVisualTokens>()!;
      for (final background in [
        tokens.background,
        tokens.surface,
        tokens.surfaceSubtle,
        tokens.surfaceRaised,
        tokens.surfaceInteractive,
      ]) {
        for (final foreground in [tokens.textPrimary, tokens.textSecondary]) {
          expect(
            _contrastRatio(foreground, background),
            greaterThanOrEqualTo(4.5),
            reason: '$foreground on $background',
          );
        }
      }
      for (final foreground in [
        scheme.primary,
        scheme.secondary,
        scheme.error,
      ]) {
        for (final background in [tokens.background, tokens.surface]) {
          expect(
            _contrastRatio(foreground, background),
            greaterThanOrEqualTo(4.5),
            reason: '$foreground on $background',
          );
        }
      }
      for (final pair in [
        (scheme.onPrimary, scheme.primary),
        (scheme.onSecondary, scheme.secondary),
        (scheme.onTertiary, scheme.tertiary),
        (scheme.onError, scheme.error),
        (tokens.info, tokens.infoSurface),
        (tokens.attention, tokens.attentionSurface),
        (tokens.danger, tokens.dangerSurface),
        (tokens.success, tokens.successSurface),
      ]) {
        expect(
          _contrastRatio(pair.$1, pair.$2),
          greaterThanOrEqualTo(4.5),
          reason: '${pair.$1} on ${pair.$2}',
        );
      }

      for (final background in [tokens.background, tokens.surface]) {
        expect(
          _contrastRatio(tokens.focus, background),
          greaterThanOrEqualTo(3),
          reason: 'focus ${tokens.focus} on $background',
        );
      }
    });

    test('${entry.key} enabled inputs retain a 3:1 visual boundary', () {
      final decoration = entry.value.inputDecorationTheme;
      final border = decoration.enabledBorder;

      expect(border, isA<OutlineInputBorder>());
      expect(decoration.fillColor, isNotNull);
      final background = decoration.fillColor!.a < 1
          ? Color.alphaBlend(
              decoration.fillColor!,
              Color.alphaBlend(
                const Color(0x66000000),
                Colors.white,
              ),
            )
          : decoration.fillColor!;
      expect(
        _contrastRatio(
          (border! as OutlineInputBorder).borderSide.color,
          background,
        ),
        greaterThanOrEqualTo(3),
      );
    });
  }

  test(
    'Space clear materials meet contrast against the all-white backdrop bound',
    () {
      final theme = AppTheme.space;
      final tokens = theme.extension<AppVisualTokens>()!;
      final effects = theme.extension<AppThemeEffects>()!;
      final material = effects.surfaceMaterial;
      final surfaces = <String, Color>{
        'plain': material.plain(tokens.surface),
        'subtle': material.subtle(tokens.surfaceSubtle),
        'raised': material.raised(tokens.surfaceRaised),
        'interactive': material.interactive(
          tokens.surfaceSubtle,
          hovered: false,
          pressed: false,
        ),
        'interactive hover': material.interactive(
          tokens.surfaceRaised,
          hovered: true,
          pressed: false,
        ),
        'interactive press': material.interactive(
          tokens.surfaceRaised,
          hovered: true,
          pressed: true,
        ),
        'dense': material.dense(tokens.surface),
        'navigation': material.navigation(tokens.surface),
      };
      for (final entry in surfaces.entries) {
        // Channel compositing is monotonic, so white is a conservative upper
        // luminance bound for every pixel in either Observatory backdrop.
        final maximumLuminance = _compositedSurfaceLuminance(
          surface: entry.value,
          backdropRed: 255,
          backdropGreen: 255,
          backdropBlue: 255,
          scrimOpacity: effects.backdropScrimOpacity,
        );
        for (final foreground in [
          tokens.textPrimary,
          tokens.textSecondary,
        ]) {
          expect(
            _contrastFromLuminance(
              foreground.computeLuminance(),
              maximumLuminance,
            ),
            greaterThanOrEqualTo(4.5),
            reason: '$foreground over ${entry.key} material',
          );
        }
        for (final foreground in [tokens.focus, tokens.brand]) {
          expect(
            _contrastFromLuminance(
              foreground.computeLuminance(),
              maximumLuminance,
            ),
            greaterThanOrEqualTo(3),
            reason: '$foreground boundary over ${entry.key} material',
          );
        }
      }

      for (final semanticSurface in [
        material.semantic(tokens.infoSurface),
        material.semantic(tokens.attentionSurface),
        material.semantic(tokens.dangerSurface),
        material.semantic(tokens.successSurface),
      ]) {
        final luminance = _compositedSurfaceLuminance(
          surface: semanticSurface,
          backdropRed: 255,
          backdropGreen: 255,
          backdropBlue: 255,
          scrimOpacity: effects.backdropScrimOpacity,
        );
        for (final foreground in [
          tokens.textPrimary,
          tokens.textSecondary,
        ]) {
          expect(
            _contrastFromLuminance(
              foreground.computeLuminance(),
              luminance,
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    },
  );
}

double _contrastRatio(Color a, Color b) {
  final luminanceA = a.computeLuminance();
  final luminanceB = b.computeLuminance();
  return (luminanceA > luminanceB ? luminanceA + 0.05 : luminanceB + 0.05) /
      (luminanceA > luminanceB ? luminanceB + 0.05 : luminanceA + 0.05);
}

double _compositedSurfaceLuminance({
  required Color surface,
  required int backdropRed,
  required int backdropGreen,
  required int backdropBlue,
  required double scrimOpacity,
}) {
  final visibleBackdrop = 1 - scrimOpacity;
  final surfaceAlpha = surface.a;
  final visibleSurfaceBackdrop = 1 - surfaceAlpha;
  return _relativeLuminance(
    surface.r * 255 * surfaceAlpha +
        backdropRed * visibleBackdrop * visibleSurfaceBackdrop,
    surface.g * 255 * surfaceAlpha +
        backdropGreen * visibleBackdrop * visibleSurfaceBackdrop,
    surface.b * 255 * surfaceAlpha +
        backdropBlue * visibleBackdrop * visibleSurfaceBackdrop,
  );
}

double _relativeLuminance(double red, double green, double blue) {
  double linearize(double channel) {
    final normalized = channel / 255;
    return normalized <= 0.04045
        ? normalized / 12.92
        : math.pow((normalized + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linearize(red) +
      0.7152 * linearize(green) +
      0.0722 * linearize(blue);
}

double _contrastFromLuminance(double first, double second) =>
    (first > second ? first + 0.05 : second + 0.05) /
    (first > second ? second + 0.05 : first + 0.05);
