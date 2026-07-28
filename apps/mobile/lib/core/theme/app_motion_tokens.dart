import 'package:flutter/material.dart';

@immutable
class AppMotionTokens extends ThemeExtension<AppMotionTokens> {
  const AppMotionTokens({
    this.selection = const Duration(milliseconds: 120),
    this.state = const Duration(milliseconds: 180),
    this.emphasis = const Duration(milliseconds: 260),
    this.curve = Curves.easeOutCubic,
  });

  final Duration selection;
  final Duration state;
  final Duration emphasis;
  final Curve curve;

  Duration selectionFor(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : selection;

  Duration stateFor(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : state;

  Duration emphasisFor(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : emphasis;

  @override
  AppMotionTokens copyWith({
    Duration? selection,
    Duration? state,
    Duration? emphasis,
    Curve? curve,
  }) {
    return AppMotionTokens(
      selection: selection ?? this.selection,
      state: state ?? this.state,
      emphasis: emphasis ?? this.emphasis,
      curve: curve ?? this.curve,
    );
  }

  @override
  AppMotionTokens lerp(AppMotionTokens? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }
}

extension AppMotionTokensContext on BuildContext {
  AppMotionTokens get motionTokens =>
      Theme.of(this).extension<AppMotionTokens>() ?? const AppMotionTokens();
}
