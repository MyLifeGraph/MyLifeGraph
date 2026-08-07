import 'package:flutter/material.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/widgets/app_card.dart';

typedef TodayInfoHeaderBuilder = Widget Function(
  BuildContext context,
  Widget infoButton,
);

const _todayInfoControlSize = 24.0;
const _todayInfoIconSize = 20.0;
const _todayInfoVerticalLayoutPadding = 10.0;

/// Feature-local, non-persisted disclosure for explanatory Today copy.
///
/// The description is absent from both the widget and semantics trees while
/// closed. Its control remains independent from any surrounding accordion.
class TodayInfoDisclosure extends StatefulWidget {
  const TodayInfoDisclosure({
    super.key,
    required this.topic,
    required this.description,
    required this.headerBuilder,
    this.descriptionStyle,
  });

  final String topic;
  final String description;
  final TodayInfoHeaderBuilder headerBuilder;
  final TextStyle? descriptionStyle;

  @override
  State<TodayInfoDisclosure> createState() => _TodayInfoDisclosureState();
}

class _TodayInfoDisclosureState extends State<TodayInfoDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final motion = context.motionTokens;
    final duration = motion.stateFor(context);
    final actionLabel =
        '${_expanded ? 'Hide' : 'Show'} information about ${widget.topic}';
    final inheritedIconButtonStyle = IconButtonTheme.of(context).style;
    final compactInfoButtonStyle =
        (inheritedIconButtonStyle ?? const ButtonStyle()).copyWith(
      minimumSize: const WidgetStatePropertyAll(
        Size.square(_todayInfoControlSize),
      ),
      fixedSize: const WidgetStatePropertyAll(
        Size.square(_todayInfoControlSize),
      ),
      maximumSize: const WidgetStatePropertyAll(
        Size.square(_todayInfoControlSize),
      ),
      iconSize: const WidgetStatePropertyAll(_todayInfoIconSize),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final infoButton = Padding(
      key: ValueKey('today-info-layout-${widget.topic}'),
      padding: const EdgeInsets.symmetric(
        vertical: _todayInfoVerticalLayoutPadding,
      ),
      child: SizedBox.square(
        key: ValueKey('today-info-control-${widget.topic}'),
        dimension: _todayInfoControlSize,
        child: IconButtonTheme(
          data: IconButtonThemeData(style: compactInfoButtonStyle),
          child: Semantics(
            button: true,
            expanded: _expanded,
            label: actionLabel,
            onTap: _toggle,
            child: ExcludeSemantics(
              child: IconButton(
                tooltip: actionLabel,
                color: Theme.of(context).colorScheme.primary,
                onPressed: _toggle,
                icon: const Icon(
                  AppIcons.infoOutline,
                  size: _todayInfoIconSize,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.headerBuilder(context, infoButton),
        ExcludeSemantics(
          excluding: !_expanded,
          child: AnimatedSwitcher(
            duration: duration,
            reverseDuration: duration,
            switchInCurve: motion.curve,
            switchOutCurve: motion.curve,
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: motion.curve,
                reverseCurve: motion.curve,
              );
              return SizeTransition(
                sizeFactor: curved,
                alignment: AlignmentDirectional.topStart,
                child: FadeTransition(opacity: curved, child: child),
              );
            },
            child: _expanded
                ? Padding(
                    key: ValueKey('today-info-description-${widget.topic}'),
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      widget.description,
                      style: widget.descriptionStyle ??
                          Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : SizedBox(
                    key: ValueKey(
                      'today-info-description-closed-${widget.topic}',
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _toggle() => setState(() => _expanded = !_expanded);
}

/// Presentation primitives shared only by the independently owned Dashboard
/// sections.
class DashboardSectionTitle extends StatelessWidget {
  const DashboardSectionTitle({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final copy = TodayInfoDisclosure(
      topic: title,
      description: subtitle,
      headerBuilder: (context, infoButton) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          infoButton,
        ],
      ),
    );
    if (trailing == null) return copy;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 520 ||
            MediaQuery.textScalerOf(context).scale(16) >= 24;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              copy,
              const SizedBox(height: AppSpacing.sm),
              trailing!,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: copy),
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
        );
      },
    );
  }
}

class DashboardStatusPill extends StatelessWidget {
  const DashboardStatusPill({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class DashboardInlineMessage extends StatelessWidget {
  const DashboardInlineMessage({
    super.key,
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(message)),
      ],
    );
  }
}

class DashboardSectionErrorCard extends StatelessWidget {
  const DashboardSectionErrorCard({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(
            AppIcons.cloudOffOutlined,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(AppIcons.refresh),
              label: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

class DashboardEmptySectionCard extends StatelessWidget {
  const DashboardEmptySectionCard({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class DashboardInlineExpansionCard extends StatelessWidget {
  const DashboardInlineExpansionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            child: ListTile(
              title: TodayInfoDisclosure(
                topic: title,
                description: subtitle,
                headerBuilder: (context, infoButton) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Text(title),
                      ),
                    ),
                    infoButton,
                  ],
                ),
              ),
              trailing:
                  Icon(expanded ? AppIcons.expandLess : AppIcons.expandMore),
              onTap: onToggle,
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: child,
            ),
          ],
        ],
      ),
    );
  }
}
