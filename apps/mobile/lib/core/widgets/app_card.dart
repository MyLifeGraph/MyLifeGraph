import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';
import 'app_surface.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.variant = AppSurfaceVariant.subtle,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final AppSurfaceVariant variant;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      variant: onTap == null || variant != AppSurfaceVariant.subtle
          ? variant
          : AppSurfaceVariant.interactive,
      padding: padding,
      onTap: onTap,
      child: child,
    );
  }
}
