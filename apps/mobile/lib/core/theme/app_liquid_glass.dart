import 'package:flutter/material.dart';

/// Static optical depth, deliberately separate from Space's animated material.
/// No per-card blur, shaders requiring assets, timers, or layout changes.
@immutable
class AppLiquidGlass extends ThemeExtension<AppLiquidGlass> {
  const AppLiquidGlass({this.strength = 1});

  final double strength;

  // Soft, stationary pools of light show through tinted cards as they scroll.
  // The page still has an opaque base: no previous route can bleed through.
  static const coolLight = RadialGradient(
    center: Alignment(0.95, -0.30),
    radius: 0.85,
    colors: [Color(0x59536F91), Color(0x24536F91), Color(0x00536F91)],
    stops: [0, 0.42, 1],
  );
  static const softLight = RadialGradient(
    center: Alignment(-1.0, 0.75),
    radius: 0.75,
    colors: [Color(0x3075618A), Color(0x1475618A), Color(0x0075618A)],
    stops: [0, 0.38, 1],
  );

  static const backdrop = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1B2735),
      Color(0xFF0B1018),
      Color(0xFF080A0E),
      Color(0xFF171922),
    ],
    stops: [0, 0.28, 0.70, 1],
  );

  LinearGradient get sheen => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.fromRGBO(210, 231, 255, 0.065 * strength),
      Color.fromRGBO(184, 210, 239, 0.018 * strength),
      Color.fromRGBO(184, 210, 239, 0.002 * strength),
      Color.fromRGBO(179, 186, 219, 0.012 * strength),
      Color.fromRGBO(206, 220, 244, 0.042 * strength),
    ],
    stops: const [0, 0.14, 0.48, 0.84, 1],
  );

  LinearGradient get rim => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.fromRGBO(218, 237, 255, 0.32 * strength),
      Color.fromRGBO(187, 215, 240, 0.09 * strength),
      Color.fromRGBO(187, 215, 240, 0.025 * strength),
      Color.fromRGBO(203, 214, 247, 0.18 * strength),
      Color.fromRGBO(203, 214, 247, 0.06 * strength),
    ],
    stops: const [0, 0.20, 0.55, 0.90, 1],
  );

  LinearGradient surfaceGradient(Color tint) => LinearGradient(
    begin: sheen.begin,
    end: sheen.end,
    colors: [for (final light in sheen.colors) Color.alphaBlend(light, tint)],
    stops: sheen.stops,
  );

  @override
  AppLiquidGlass copyWith({double? strength}) =>
      AppLiquidGlass(strength: strength ?? this.strength);

  @override
  AppLiquidGlass lerp(AppLiquidGlass? other, double t) => other == null
      ? this
      : AppLiquidGlass(strength: strength + (other.strength - strength) * t);
}

/// Paint-only wrapper; no padding, hit targets, animation or blur layers.
class LiquidGlassLightAccents extends StatelessWidget {
  const LiquidGlassLightAccents({this.child, super.key});

  final Widget? child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(gradient: AppLiquidGlass.coolLight),
    child: DecoratedBox(
      decoration: const BoxDecoration(gradient: AppLiquidGlass.softLight),
      child: child,
    ),
  );
}

/// Shared Material overlays keep their original geometry and hit targets.
class LiquidGlassBorder extends RoundedRectangleBorder {
  const LiquidGlassBorder({
    required super.borderRadius,
    super.side = BorderSide.none,
  });

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    super.paint(canvas, rect, textDirection: textDirection);
    final shape = borderRadius
        .resolve(textDirection)
        .toRRect(rect)
        .deflate(0.5);
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = const AppLiquidGlass().rim.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  LiquidGlassBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => LiquidGlassBorder(
    side: side ?? this.side,
    borderRadius: borderRadius ?? this.borderRadius,
  );
}
