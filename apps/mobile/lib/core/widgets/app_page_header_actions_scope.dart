import 'package:flutter/widgets.dart';

/// Space available to an inline header menu without overlapping the title.
class AppPageHeaderActionsScope extends InheritedWidget {
  const AppPageHeaderActionsScope({
    required this.maxWidth,
    required super.child,
    super.key,
  });

  final double maxWidth;

  static double? maxWidthOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppPageHeaderActionsScope>()
      ?.maxWidth;

  @override
  bool updateShouldNotify(AppPageHeaderActionsScope oldWidget) =>
      maxWidth != oldWidget.maxWidth;
}
