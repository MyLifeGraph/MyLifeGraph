import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_info_disclosure.dart';
import '../../../../core/widgets/app_surface.dart';

typedef TodayInfoHeaderBuilder = Widget Function(
  BuildContext context,
  Widget infoButton,
);

/// Thin Today adapter over the shared, non-persisted information disclosure.
///
/// The description is absent from both the widget and semantics trees while
/// closed. Its control remains independent from any surrounding accordion.
class TodayInfoDisclosure extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return AppInfoDisclosure(
      topic: topic,
      description: description,
      descriptionStyle: descriptionStyle,
      layout: AppInfoDisclosureLayout.compact,
      keyPrefix: 'today-info',
      headerBuilder: headerBuilder,
    );
  }
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
    this.tone = AppStatusTone.neutral,
  });

  final IconData icon;
  final String label;
  final AppStatusTone tone;

  @override
  Widget build(BuildContext context) => AppStatusPill(
        label: label,
        icon: icon,
        tone: tone,
      );
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
