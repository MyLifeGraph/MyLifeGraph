import 'dart:math' as math;

import 'package:flutter/material.dart';

@immutable
class AppBackdropMotion {
  const AppBackdropMotion({
    required this.enabled,
    required this.cycle,
    required this.fixedPhase,
    required this.maxHorizontalDrift,
    required this.maxVerticalDrift,
    required this.baseScale,
    required this.scaleAmplitude,
  })  : assert(
          fixedPhase >= 0 && fixedPhase <= 1,
          'fixedPhase must be between zero and one.',
        ),
        assert(
          maxHorizontalDrift >= 0 && maxVerticalDrift >= 0,
          'Backdrop drift bounds cannot be negative.',
        ),
        assert(
          scaleAmplitude >= 0 && baseScale - scaleAmplitude > 0,
          'Backdrop scale must remain positive for the complete cycle.',
        );

  static const disabled = AppBackdropMotion(
    enabled: false,
    cycle: Duration.zero,
    fixedPhase: 0.37,
    maxHorizontalDrift: 0,
    maxVerticalDrift: 0,
    baseScale: 1,
    scaleAmplitude: 0,
  );

  final bool enabled;
  final Duration cycle;
  final double fixedPhase;
  final double maxHorizontalDrift;
  final double maxVerticalDrift;
  final double baseScale;
  final double scaleAmplitude;

  AppBackdropMotionFrame frameAt(double phase) {
    var normalizedPhase = phase % 1;
    if (normalizedPhase < 0) normalizedPhase += 1;
    final angle = normalizedPhase * 2 * math.pi;
    final cosine = _withoutTrigonometricNoise(math.cos(angle));
    final sine = _withoutTrigonometricNoise(math.sin(angle));
    return AppBackdropMotionFrame(
      offset: Offset(
        cosine * maxHorizontalDrift,
        sine * maxVerticalDrift,
      ),
      scale: baseScale + cosine * scaleAmplitude,
    );
  }

  static double _withoutTrigonometricNoise(double value) =>
      value.abs() < 0.000000000001 ? 0 : value;
}

@immutable
class AppBackdropMotionFrame {
  const AppBackdropMotionFrame({
    required this.offset,
    required this.scale,
  });

  final Offset offset;
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is AppBackdropMotionFrame &&
      other.offset == offset &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(offset, scale);
}

@immutable
class AppSurfaceMaterial {
  const AppSurfaceMaterial({
    required this.enabled,
    required this.hudFrameEnabled,
    required this.plainOpacity,
    required this.subtleOpacity,
    required this.raisedOpacity,
    required this.interactiveOpacity,
    required this.interactiveHoverOpacity,
    required this.interactivePressedOpacity,
    required this.denseOpacity,
    required this.semanticOpacity,
    required this.overlayOpacity,
    required this.navigationOpacity,
    required this.navigationBlurSigma,
  })  : assert(plainOpacity >= 0 && plainOpacity <= 1),
        assert(subtleOpacity >= 0 && subtleOpacity <= 1),
        assert(raisedOpacity >= 0 && raisedOpacity <= 1),
        assert(interactiveOpacity >= 0 && interactiveOpacity <= 1),
        assert(
          interactiveHoverOpacity >= 0 && interactiveHoverOpacity <= 1,
        ),
        assert(
          interactivePressedOpacity >= 0 && interactivePressedOpacity <= 1,
        ),
        assert(denseOpacity >= 0 && denseOpacity <= 1),
        assert(semanticOpacity >= 0 && semanticOpacity <= 1),
        assert(overlayOpacity >= 0 && overlayOpacity <= 1),
        assert(navigationOpacity >= 0 && navigationOpacity <= 1),
        assert(navigationBlurSigma >= 0);

  static const disabled = AppSurfaceMaterial(
    enabled: false,
    hudFrameEnabled: false,
    plainOpacity: 1,
    subtleOpacity: 1,
    raisedOpacity: 1,
    interactiveOpacity: 1,
    interactiveHoverOpacity: 1,
    interactivePressedOpacity: 1,
    denseOpacity: 1,
    semanticOpacity: 1,
    overlayOpacity: 1,
    navigationOpacity: 1,
    navigationBlurSigma: 0,
  );

  final bool enabled;
  final bool hudFrameEnabled;
  final double plainOpacity;
  final double subtleOpacity;
  final double raisedOpacity;
  final double interactiveOpacity;
  final double interactiveHoverOpacity;
  final double interactivePressedOpacity;
  final double denseOpacity;
  final double semanticOpacity;
  final double overlayOpacity;
  final double navigationOpacity;
  final double navigationBlurSigma;

  Color plain(Color color) => _resolve(color, plainOpacity);

  Color subtle(Color color) => _resolve(color, subtleOpacity);

  Color raised(Color color) => _resolve(color, raisedOpacity);

  Color interactive(
    Color color, {
    required bool hovered,
    required bool pressed,
  }) {
    final opacity = pressed
        ? interactivePressedOpacity
        : hovered
            ? interactiveHoverOpacity
            : interactiveOpacity;
    return _resolve(color, opacity);
  }

  Color dense(Color color) => _resolve(color, denseOpacity);

  Color semantic(Color color) => _resolve(color, semanticOpacity);

  Color overlay(Color color) => _resolve(color, overlayOpacity);

  Color navigation(Color color) => _resolve(color, navigationOpacity);

  Color _resolve(Color color, double opacity) =>
      color.withValues(alpha: opacity);

  AppSurfaceMaterial lerp(AppSurfaceMaterial other, double t) {
    double value(double from, double to) => from + (to - from) * t;
    return AppSurfaceMaterial(
      enabled: t < 0.5 ? enabled : other.enabled,
      hudFrameEnabled: t < 0.5 ? hudFrameEnabled : other.hudFrameEnabled,
      plainOpacity: value(plainOpacity, other.plainOpacity),
      subtleOpacity: value(subtleOpacity, other.subtleOpacity),
      raisedOpacity: value(raisedOpacity, other.raisedOpacity),
      interactiveOpacity: value(interactiveOpacity, other.interactiveOpacity),
      interactiveHoverOpacity:
          value(interactiveHoverOpacity, other.interactiveHoverOpacity),
      interactivePressedOpacity:
          value(interactivePressedOpacity, other.interactivePressedOpacity),
      denseOpacity: value(denseOpacity, other.denseOpacity),
      semanticOpacity: value(semanticOpacity, other.semanticOpacity),
      overlayOpacity: value(overlayOpacity, other.overlayOpacity),
      navigationOpacity: value(navigationOpacity, other.navigationOpacity),
      navigationBlurSigma:
          value(navigationBlurSigma, other.navigationBlurSigma),
    );
  }
}

@immutable
class AppThemeEffects extends ThemeExtension<AppThemeEffects> {
  const AppThemeEffects({
    required this.starfieldEnabled,
    required this.interactionGlowEnabled,
    required this.backdropPortraitAsset,
    required this.backdropLandscapeAsset,
    required this.backdropScrimOpacity,
    required this.splashFactory,
    required this.splashColor,
    required this.highlightColor,
    required this.focusColor,
    required this.hoverColor,
    required this.focusOverlay,
    required this.pressedOverlay,
    required this.hoverOverlay,
    required this.surfacePressedOverlay,
    required this.quickActionPressedColor,
    required this.interactionGlowColor,
    required this.primaryControlIdleGlowColor,
    required this.controlPressedScale,
    required this.interactiveSurfaceHoverLift,
    required this.navigationSignalColor,
    required this.surfaceOutlineColor,
    required this.surfaceHoverOutlineColor,
    required this.raisedSurfaceGlowColor,
    required this.accentSurfaceOpacity,
    required this.starCyan,
    required this.starViolet,
    required this.starNeutral,
    this.starfieldCycle = const Duration(seconds: 24),
    this.starfieldFixedPhase = 0.37,
    this.maxVerticalStarDrift = 14,
    this.maxHorizontalStarDrift = 4,
    this.backdropMotion = AppBackdropMotion.disabled,
    this.surfaceMaterial = AppSurfaceMaterial.disabled,
  })  : assert(
          backdropScrimOpacity >= 0 && backdropScrimOpacity <= 1,
          'backdropScrimOpacity must be between zero and one.',
        ),
        assert(
          controlPressedScale > 0 && controlPressedScale <= 1,
          'controlPressedScale must be greater than zero and at most one.',
        ),
        assert(
          interactiveSurfaceHoverLift >= 0,
          'interactiveSurfaceHoverLift cannot be negative.',
        );

  final bool starfieldEnabled;
  final bool interactionGlowEnabled;
  final String? backdropPortraitAsset;
  final String? backdropLandscapeAsset;
  final double backdropScrimOpacity;
  final InteractiveInkFeatureFactory splashFactory;
  final Color splashColor;
  final Color highlightColor;
  final Color focusColor;
  final Color hoverColor;
  final Color focusOverlay;
  final Color pressedOverlay;
  final Color hoverOverlay;
  final Color surfacePressedOverlay;
  final Color quickActionPressedColor;
  final Color interactionGlowColor;
  final Color primaryControlIdleGlowColor;
  final double controlPressedScale;
  final double interactiveSurfaceHoverLift;
  final Color navigationSignalColor;
  final Color surfaceOutlineColor;
  final Color surfaceHoverOutlineColor;
  final Color raisedSurfaceGlowColor;
  final double accentSurfaceOpacity;
  final Color starCyan;
  final Color starViolet;
  final Color starNeutral;
  final Duration starfieldCycle;
  final double starfieldFixedPhase;
  final double maxVerticalStarDrift;
  final double maxHorizontalStarDrift;
  final AppBackdropMotion backdropMotion;
  final AppSurfaceMaterial surfaceMaterial;

  factory AppThemeEffects.fallback(ThemeData theme) {
    final colors = theme.colorScheme;
    return AppThemeEffects(
      starfieldEnabled: false,
      interactionGlowEnabled: false,
      backdropPortraitAsset: null,
      backdropLandscapeAsset: null,
      backdropScrimOpacity: 0,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      focusColor: theme.focusColor,
      hoverColor: theme.hoverColor,
      focusOverlay: colors.primary.withValues(alpha: 0.20),
      pressedOverlay: colors.primary.withValues(alpha: 0.14),
      hoverOverlay: colors.primary.withValues(alpha: 0.08),
      surfacePressedOverlay: colors.primary.withValues(alpha: 0.12),
      quickActionPressedColor: Color.lerp(colors.primary, Colors.black, 0.12)!,
      interactionGlowColor: colors.primary,
      primaryControlIdleGlowColor: Colors.transparent,
      controlPressedScale: 1,
      interactiveSurfaceHoverLift: 0,
      navigationSignalColor: Colors.transparent,
      surfaceOutlineColor: Colors.transparent,
      surfaceHoverOutlineColor: Colors.transparent,
      raisedSurfaceGlowColor: Colors.transparent,
      accentSurfaceOpacity: theme.brightness == Brightness.dark ? 0.14 : 0.09,
      starCyan: colors.primary,
      starViolet: colors.secondary,
      starNeutral: colors.onSurface,
    );
  }

  String? backdropAssetFor(Size size) {
    if (size.height > size.width) {
      return backdropPortraitAsset ?? backdropLandscapeAsset;
    }
    return backdropLandscapeAsset ?? backdropPortraitAsset;
  }

  Color? controlOverlay(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) return null;
    if (interactionGlowEnabled) {
      if (states.contains(WidgetState.pressed)) return pressedOverlay;
      if (states.contains(WidgetState.focused)) return focusOverlay;
      if (states.contains(WidgetState.hovered)) return hoverOverlay;
      return null;
    }
    if (states.contains(WidgetState.focused)) return focusOverlay;
    if (states.contains(WidgetState.pressed)) return pressedOverlay;
    if (states.contains(WidgetState.hovered)) return hoverOverlay;
    return null;
  }

  Color? filledControlOverlay(
    Set<WidgetState> states,
    Color standardForeground,
  ) {
    if (states.contains(WidgetState.disabled)) return null;
    if (interactionGlowEnabled) {
      if (states.contains(WidgetState.pressed)) {
        return interactionGlowColor.withValues(alpha: 0.30);
      }
      return controlOverlay(states);
    }
    if (states.contains(WidgetState.focused)) {
      return standardForeground.withValues(alpha: 0.20);
    }
    if (states.contains(WidgetState.pressed)) {
      return standardForeground.withValues(alpha: 0.14);
    }
    if (states.contains(WidgetState.hovered)) {
      return standardForeground.withValues(alpha: 0.08);
    }
    return null;
  }

  List<BoxShadow>? interactionGlow({
    required bool hovered,
    required bool pressed,
    required bool focused,
  }) {
    if (!interactionGlowEnabled || !(hovered || pressed || focused)) {
      return null;
    }
    final color = pressed || focused ? focusOverlay : interactionGlowColor;
    return [
      BoxShadow(
        color: color.withValues(
          alpha: pressed
              ? 0.42
              : focused
                  ? 0.38
                  : 0.34,
        ),
        blurRadius: pressed ? 28 : 24,
        spreadRadius: pressed ? -4 : -5,
      ),
    ];
  }

  @override
  AppThemeEffects copyWith({
    bool? starfieldEnabled,
    bool? interactionGlowEnabled,
    String? backdropPortraitAsset,
    String? backdropLandscapeAsset,
    double? backdropScrimOpacity,
    InteractiveInkFeatureFactory? splashFactory,
    Color? splashColor,
    Color? highlightColor,
    Color? focusColor,
    Color? hoverColor,
    Color? focusOverlay,
    Color? pressedOverlay,
    Color? hoverOverlay,
    Color? surfacePressedOverlay,
    Color? quickActionPressedColor,
    Color? interactionGlowColor,
    Color? primaryControlIdleGlowColor,
    double? controlPressedScale,
    double? interactiveSurfaceHoverLift,
    Color? navigationSignalColor,
    Color? surfaceOutlineColor,
    Color? surfaceHoverOutlineColor,
    Color? raisedSurfaceGlowColor,
    double? accentSurfaceOpacity,
    Color? starCyan,
    Color? starViolet,
    Color? starNeutral,
    Duration? starfieldCycle,
    double? starfieldFixedPhase,
    double? maxVerticalStarDrift,
    double? maxHorizontalStarDrift,
    AppBackdropMotion? backdropMotion,
    AppSurfaceMaterial? surfaceMaterial,
  }) {
    return AppThemeEffects(
      starfieldEnabled: starfieldEnabled ?? this.starfieldEnabled,
      interactionGlowEnabled:
          interactionGlowEnabled ?? this.interactionGlowEnabled,
      backdropPortraitAsset:
          backdropPortraitAsset ?? this.backdropPortraitAsset,
      backdropLandscapeAsset:
          backdropLandscapeAsset ?? this.backdropLandscapeAsset,
      backdropScrimOpacity: backdropScrimOpacity ?? this.backdropScrimOpacity,
      splashFactory: splashFactory ?? this.splashFactory,
      splashColor: splashColor ?? this.splashColor,
      highlightColor: highlightColor ?? this.highlightColor,
      focusColor: focusColor ?? this.focusColor,
      hoverColor: hoverColor ?? this.hoverColor,
      focusOverlay: focusOverlay ?? this.focusOverlay,
      pressedOverlay: pressedOverlay ?? this.pressedOverlay,
      hoverOverlay: hoverOverlay ?? this.hoverOverlay,
      surfacePressedOverlay:
          surfacePressedOverlay ?? this.surfacePressedOverlay,
      quickActionPressedColor:
          quickActionPressedColor ?? this.quickActionPressedColor,
      interactionGlowColor: interactionGlowColor ?? this.interactionGlowColor,
      primaryControlIdleGlowColor:
          primaryControlIdleGlowColor ?? this.primaryControlIdleGlowColor,
      controlPressedScale: controlPressedScale ?? this.controlPressedScale,
      interactiveSurfaceHoverLift:
          interactiveSurfaceHoverLift ?? this.interactiveSurfaceHoverLift,
      navigationSignalColor:
          navigationSignalColor ?? this.navigationSignalColor,
      surfaceOutlineColor: surfaceOutlineColor ?? this.surfaceOutlineColor,
      surfaceHoverOutlineColor:
          surfaceHoverOutlineColor ?? this.surfaceHoverOutlineColor,
      raisedSurfaceGlowColor:
          raisedSurfaceGlowColor ?? this.raisedSurfaceGlowColor,
      accentSurfaceOpacity: accentSurfaceOpacity ?? this.accentSurfaceOpacity,
      starCyan: starCyan ?? this.starCyan,
      starViolet: starViolet ?? this.starViolet,
      starNeutral: starNeutral ?? this.starNeutral,
      starfieldCycle: starfieldCycle ?? this.starfieldCycle,
      starfieldFixedPhase: starfieldFixedPhase ?? this.starfieldFixedPhase,
      maxVerticalStarDrift: maxVerticalStarDrift ?? this.maxVerticalStarDrift,
      maxHorizontalStarDrift:
          maxHorizontalStarDrift ?? this.maxHorizontalStarDrift,
      backdropMotion: backdropMotion ?? this.backdropMotion,
      surfaceMaterial: surfaceMaterial ?? this.surfaceMaterial,
    );
  }

  @override
  AppThemeEffects lerp(AppThemeEffects? other, double t) {
    if (other == null) return this;
    return AppThemeEffects(
      starfieldEnabled: t < 0.5 ? starfieldEnabled : other.starfieldEnabled,
      interactionGlowEnabled:
          t < 0.5 ? interactionGlowEnabled : other.interactionGlowEnabled,
      backdropPortraitAsset:
          t < 0.5 ? backdropPortraitAsset : other.backdropPortraitAsset,
      backdropLandscapeAsset:
          t < 0.5 ? backdropLandscapeAsset : other.backdropLandscapeAsset,
      backdropScrimOpacity: backdropScrimOpacity +
          (other.backdropScrimOpacity - backdropScrimOpacity) * t,
      splashFactory: t < 0.5 ? splashFactory : other.splashFactory,
      splashColor: Color.lerp(splashColor, other.splashColor, t)!,
      highlightColor: Color.lerp(highlightColor, other.highlightColor, t)!,
      focusColor: Color.lerp(focusColor, other.focusColor, t)!,
      hoverColor: Color.lerp(hoverColor, other.hoverColor, t)!,
      focusOverlay: Color.lerp(focusOverlay, other.focusOverlay, t)!,
      pressedOverlay: Color.lerp(pressedOverlay, other.pressedOverlay, t)!,
      hoverOverlay: Color.lerp(hoverOverlay, other.hoverOverlay, t)!,
      surfacePressedOverlay: Color.lerp(
        surfacePressedOverlay,
        other.surfacePressedOverlay,
        t,
      )!,
      quickActionPressedColor: Color.lerp(
        quickActionPressedColor,
        other.quickActionPressedColor,
        t,
      )!,
      interactionGlowColor: Color.lerp(
        interactionGlowColor,
        other.interactionGlowColor,
        t,
      )!,
      primaryControlIdleGlowColor: Color.lerp(
        primaryControlIdleGlowColor,
        other.primaryControlIdleGlowColor,
        t,
      )!,
      controlPressedScale: controlPressedScale +
          (other.controlPressedScale - controlPressedScale) * t,
      interactiveSurfaceHoverLift: interactiveSurfaceHoverLift +
          (other.interactiveSurfaceHoverLift - interactiveSurfaceHoverLift) * t,
      navigationSignalColor: Color.lerp(
        navigationSignalColor,
        other.navigationSignalColor,
        t,
      )!,
      surfaceOutlineColor: Color.lerp(
        surfaceOutlineColor,
        other.surfaceOutlineColor,
        t,
      )!,
      surfaceHoverOutlineColor: Color.lerp(
        surfaceHoverOutlineColor,
        other.surfaceHoverOutlineColor,
        t,
      )!,
      raisedSurfaceGlowColor: Color.lerp(
        raisedSurfaceGlowColor,
        other.raisedSurfaceGlowColor,
        t,
      )!,
      accentSurfaceOpacity:
          t < 0.5 ? accentSurfaceOpacity : other.accentSurfaceOpacity,
      starCyan: Color.lerp(starCyan, other.starCyan, t)!,
      starViolet: Color.lerp(starViolet, other.starViolet, t)!,
      starNeutral: Color.lerp(starNeutral, other.starNeutral, t)!,
      starfieldCycle: t < 0.5 ? starfieldCycle : other.starfieldCycle,
      starfieldFixedPhase:
          t < 0.5 ? starfieldFixedPhase : other.starfieldFixedPhase,
      maxVerticalStarDrift:
          t < 0.5 ? maxVerticalStarDrift : other.maxVerticalStarDrift,
      maxHorizontalStarDrift:
          t < 0.5 ? maxHorizontalStarDrift : other.maxHorizontalStarDrift,
      backdropMotion: t < 0.5 ? backdropMotion : other.backdropMotion,
      surfaceMaterial: surfaceMaterial.lerp(other.surfaceMaterial, t),
    );
  }
}

extension AppThemeEffectsContext on BuildContext {
  AppThemeEffects get themeEffects {
    final theme = Theme.of(this);
    return theme.extension<AppThemeEffects>() ??
        AppThemeEffects.fallback(theme);
  }
}
