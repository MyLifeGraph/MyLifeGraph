import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';

void main() {
  for (final entry in {
    'dark': AppTheme.dark,
    'light': AppTheme.light,
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
  }

  test('light semantic colors meet normal-text contrast on app surfaces', () {
    final theme = AppTheme.light;
    final scheme = theme.colorScheme;
    final backgrounds = [
      theme.scaffoldBackgroundColor,
      scheme.surface,
    ];
    for (final foreground in [
      scheme.primary,
      scheme.secondary,
      scheme.error,
    ]) {
      for (final background in backgrounds) {
        expect(
          _contrastRatio(foreground, background),
          greaterThanOrEqualTo(4.5),
          reason: '$foreground on $background',
        );
      }
    }
    expect(
      _contrastRatio(scheme.onPrimary, scheme.primary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(scheme.onSecondary, scheme.secondary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(scheme.onError, scheme.error),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('light enabled input fields remain distinguishable from their fill', () {
    final decoration = AppTheme.light.inputDecorationTheme;
    final border = decoration.enabledBorder;

    expect(border, isA<OutlineInputBorder>());
    expect(decoration.fillColor, isNotNull);
    expect(
      _contrastRatio(
        (border! as OutlineInputBorder).borderSide.color,
        decoration.fillColor!,
      ),
      greaterThanOrEqualTo(3),
    );
  });
}

double _contrastRatio(Color a, Color b) {
  final luminanceA = a.computeLuminance();
  final luminanceB = b.computeLuminance();
  return (luminanceA > luminanceB ? luminanceA + 0.05 : luminanceB + 0.05) /
      (luminanceA > luminanceB ? luminanceB + 0.05 : luminanceA + 0.05);
}
