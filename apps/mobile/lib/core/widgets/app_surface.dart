import 'package:flutter/material.dart';

import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../theme/app_motion_tokens.dart';
import '../theme/app_theme_effects.dart';
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
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.visualTokens;
    final motion = context.motionTokens;
    final effects = context.themeEffects;
    final surfaceMaterial = effects.surfaceMaterial;
    final interactive =
        widget.onTap != null || widget.variant == AppSurfaceVariant.interactive;
    final background = switch (widget.variant) {
      AppSurfaceVariant.plain => surfaceMaterial.plain(tokens.surface),
      AppSurfaceVariant.subtle => surfaceMaterial.subtle(tokens.surfaceSubtle),
      AppSurfaceVariant.raised => surfaceMaterial.raised(tokens.surfaceRaised),
      AppSurfaceVariant.interactive => surfaceMaterial.interactive(
          _hovered || _pressed ? tokens.surfaceRaised : tokens.surfaceSubtle,
          hovered: _hovered,
          pressed: _pressed,
        ),
      AppSurfaceVariant.accent when surfaceMaterial.enabled => Color.alphaBlend(
          tokens.brand.withValues(alpha: 0.10),
          surfaceMaterial.subtle(tokens.surfaceSubtle),
        ),
      AppSurfaceVariant.accent => tokens.brand.withValues(
          alpha: effects.accentSurfaceOpacity,
        ),
      AppSurfaceVariant.warning =>
        surfaceMaterial.semantic(tokens.attentionSurface),
      AppSurfaceVariant.danger =>
        surfaceMaterial.semantic(tokens.dangerSurface),
    };
    final hasAmbientOutline = effects.surfaceOutlineColor.a > 0 &&
        widget.variant != AppSurfaceVariant.warning &&
        widget.variant != AppSurfaceVariant.danger;
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
                    : interactive && _hovered
                        ? effects.surfaceHoverOutlineColor
                        : effects.surfaceOutlineColor;

    final shadows = <BoxShadow>[
      if (widget.variant == AppSurfaceVariant.raised)
        BoxShadow(
          color: tokens.shadow,
          blurRadius: 24,
          spreadRadius: -16,
          offset: const Offset(0, 12),
        ),
      if (widget.variant == AppSurfaceVariant.raised &&
          effects.raisedSurfaceGlowColor.a > 0)
        BoxShadow(
          color: effects.raisedSurfaceGlowColor,
          blurRadius: 32,
          spreadRadius: -14,
          offset: const Offset(0, 8),
        ),
      ...?effects.interactionGlow(
        hovered: _hovered,
        pressed: _pressed,
        focused: _focused,
      ),
    ];
    final hoverLift = interactive && _hovered && !_pressed
        ? effects.interactiveSurfaceHoverLift
        : 0.0;
    final showsHudFrame = surfaceMaterial.hudFrameEnabled &&
        widget.variant != AppSurfaceVariant.accent &&
        widget.variant != AppSurfaceVariant.warning &&
        widget.variant != AppSurfaceVariant.danger;
    final content = AnimatedContainer(
      key: const ValueKey('app-surface-visual'),
      duration:
          _pressed ? motion.selectionFor(context) : motion.stateFor(context),
      curve: motion.curve,
      transform: effects.interactiveSurfaceHoverLift > 0
          ? Matrix4.translationValues(0, -hoverLift, 0)
          : null,
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(widget.radius),
        border: hasSemanticBorder || hasAmbientOutline
            ? Border.all(color: borderColor, width: _focused ? 2 : 1)
            : null,
        boxShadow: shadows.isEmpty ? null : shadows,
      ),
      child: Stack(
        children: [
          Padding(
            padding: widget.padding,
            child: Material(
              type: MaterialType.transparency,
              child: widget.child,
            ),
          ),
          if (showsHudFrame)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    key: const ValueKey('app-surface-hud-frame'),
                    painter: _AppSurfaceHudPainter(
                      radius: widget.radius,
                      emphasized: widget.variant == AppSurfaceVariant.raised ||
                          widget.variant == AppSurfaceVariant.interactive,
                      primaryColor: _pressed
                          ? tokens.focus.withValues(alpha: 0.78)
                          : tokens.brand.withValues(
                              alpha: _hovered ? 0.82 : 0.72,
                            ),
                      secondaryColor: tokens.dataViolet.withValues(alpha: 0.60),
                    ),
                  ),
                ),
              ),
            ),
        ],
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
            onHighlightChanged: (value) {
              if (_pressed != value) setState(() => _pressed = value);
            },
            borderRadius: BorderRadius.circular(widget.radius),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return effects.surfacePressedOverlay;
              }
              if (effects.interactionGlowEnabled &&
                  states.contains(WidgetState.focused)) {
                return effects.focusOverlay;
              }
              if (effects.interactionGlowEnabled &&
                  states.contains(WidgetState.hovered)) {
                return effects.hoverOverlay;
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

class _AppSurfaceHudPainter extends CustomPainter {
  const _AppSurfaceHudPainter({
    required this.radius,
    required this.emphasized,
    required this.primaryColor,
    required this.secondaryColor,
  });

  final double radius;
  final bool emphasized;
  final Color primaryColor;
  final Color secondaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final inset = emphasized ? 0.625 : 0.5;
    final primaryLength = emphasized ? 24.0 : 18.0;
    final secondaryLength = emphasized ? 16.0 : 12.0;
    final strokeWidth = emphasized ? 1.25 : 1.0;
    final primaryPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final secondaryPaint = Paint()
      ..color = secondaryColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final primaryPath = Path()
      ..moveTo(radius, inset)
      ..lineTo(radius + primaryLength, inset)
      ..moveTo(inset, radius)
      ..lineTo(inset, radius + primaryLength);
    final secondaryPath = Path()
      ..moveTo(size.width - radius - secondaryLength, size.height - inset)
      ..lineTo(size.width - radius, size.height - inset)
      ..moveTo(size.width - inset, size.height - radius - secondaryLength)
      ..lineTo(size.width - inset, size.height - radius);
    canvas
      ..drawPath(primaryPath, primaryPaint)
      ..drawPath(secondaryPath, secondaryPaint);
  }

  @override
  bool shouldRepaint(_AppSurfaceHudPainter oldDelegate) =>
      radius != oldDelegate.radius ||
      emphasized != oldDelegate.emphasized ||
      primaryColor != oldDelegate.primaryColor ||
      secondaryColor != oldDelegate.secondaryColor;
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
