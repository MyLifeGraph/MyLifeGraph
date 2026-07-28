import 'package:flutter/material.dart';

import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../theme/app_motion_tokens.dart';
import '../theme/app_visual_tokens.dart';

enum AppSurfaceVariant {
  plain,
  subtle,
  raised,
  interactive,
  accent,
  warning,
  danger,
}

class AppSurface extends StatefulWidget {
  const AppSurface({
    required this.child,
    this.variant = AppSurfaceVariant.plain,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.semanticLabel,
    this.selected = false,
    this.radius = AppRadii.md,
    super.key,
  });

  final Widget child;
  final AppSurfaceVariant variant;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool selected;
  final double radius;

  @override
  State<AppSurface> createState() => _AppSurfaceState();
}

class _AppSurfaceState extends State<AppSurface> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.visualTokens;
    final motion = context.motionTokens;
    final interactive =
        widget.onTap != null || widget.variant == AppSurfaceVariant.interactive;
    final background = switch (widget.variant) {
      AppSurfaceVariant.plain => tokens.surface,
      AppSurfaceVariant.subtle => tokens.surfaceSubtle,
      AppSurfaceVariant.raised => tokens.surfaceRaised,
      AppSurfaceVariant.interactive when _hovered => tokens.surfaceInteractive,
      AppSurfaceVariant.interactive => tokens.surfaceSubtle,
      AppSurfaceVariant.accent => tokens.brand.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.14 : 0.09,
        ),
      AppSurfaceVariant.warning => tokens.attentionSurface,
      AppSurfaceVariant.danger => tokens.dangerSurface,
    };
    final hasSemanticBorder = widget.selected ||
        _focused ||
        widget.variant == AppSurfaceVariant.warning ||
        widget.variant == AppSurfaceVariant.danger;
    final borderColor = _focused
        ? tokens.focus
        : widget.selected
            ? tokens.brand
            : widget.variant == AppSurfaceVariant.warning
                ? tokens.attention
                : widget.variant == AppSurfaceVariant.danger
                    ? tokens.danger
                    : Colors.transparent;

    final content = AnimatedContainer(
      duration: motion.stateFor(context),
      curve: motion.curve,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(widget.radius),
        border: hasSemanticBorder
            ? Border.all(color: borderColor, width: _focused ? 2 : 1)
            : null,
        boxShadow: widget.variant == AppSurfaceVariant.raised
            ? [
                BoxShadow(
                  color: tokens.shadow,
                  blurRadius: 24,
                  spreadRadius: -16,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: widget.child,
      ),
    );

    if (!interactive) return content;
    return Semantics(
      button: widget.onTap != null,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        mouseCursor:
            widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(widget.radius),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return tokens.brand.withValues(alpha: 0.12);
              }
              return Colors.transparent;
            }),
            child: content,
          ),
        ),
      ),
    );
  }
}

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    required this.title,
    this.description,
    this.trailing,
    super.key,
  });

  final String title;
  final String? description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              if (description != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.md),
          trailing!,
        ],
      ],
    );
  }
}

enum AppStatusTone { neutral, info, success, attention, danger }

class AppStatusPill extends StatelessWidget {
  const AppStatusPill({
    required this.label,
    this.icon,
    this.tone = AppStatusTone.neutral,
    super.key,
  });

  final String label;
  final IconData? icon;
  final AppStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.visualTokens;
    final (foreground, background) = switch (tone) {
      AppStatusTone.neutral => (tokens.textSecondary, tokens.surfaceRaised),
      AppStatusTone.info => (tokens.info, tokens.infoSurface),
      AppStatusTone.success => (tokens.success, tokens.successSurface),
      AppStatusTone.attention => (tokens.attention, tokens.attentionSurface),
      AppStatusTone.danger => (tokens.danger, tokens.dangerSurface),
    };
    return Semantics(
      label: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 28),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppMetric extends StatelessWidget {
  const AppMetric({
    required this.value,
    required this.label,
    this.supportingText,
    super.key,
  });

  final String value;
  final String label;
  final String? supportingText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        if (supportingText != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            supportingText!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.title,
    required this.message,
    this.icon,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      variant: AppSurfaceVariant.subtle,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: context.visualTokens.textSecondary),
            const SizedBox(height: AppSpacing.md),
          ],
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}

class AppStatePanel extends StatelessWidget {
  const AppStatePanel({
    required this.title,
    required this.message,
    this.tone = AppStatusTone.neutral,
    this.icon,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final AppStatusTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final variant = switch (tone) {
      AppStatusTone.attention => AppSurfaceVariant.warning,
      AppStatusTone.danger => AppSurfaceVariant.danger,
      AppStatusTone.info || AppStatusTone.success => AppSurfaceVariant.accent,
      AppStatusTone.neutral => AppSurfaceVariant.subtle,
    };
    return AppSurface(
      variant: variant,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppIconBadge extends StatelessWidget {
  const AppIconBadge({
    required this.icon,
    this.tone = AppStatusTone.neutral,
    this.size = 40,
    this.iconSize = 20,
    super.key,
  });

  final IconData icon;
  final AppStatusTone tone;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final tokens = context.visualTokens;
    final (foreground, background) = switch (tone) {
      AppStatusTone.neutral => (tokens.textSecondary, tokens.surfaceRaised),
      AppStatusTone.info => (tokens.info, tokens.infoSurface),
      AppStatusTone.success => (tokens.success, tokens.successSurface),
      AppStatusTone.attention => (tokens.attention, tokens.attentionSurface),
      AppStatusTone.danger => (tokens.danger, tokens.dangerSurface),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Icon(icon, size: iconSize, color: foreground),
    );
  }
}
