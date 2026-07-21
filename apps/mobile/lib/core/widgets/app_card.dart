import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: child,
    );
    final shape = Theme.of(context).cardTheme.shape;

    return Card(
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              customBorder: shape,
              child: content,
            ),
    );
  }
}
