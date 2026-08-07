import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../theme/app_category_visuals.dart';
import '../theme/app_icons.dart';
import 'app_card.dart';

enum AppScheduleItemStatus {
  notApplicable,
  open,
  completed,
  fullyRated,
}

class AppScheduleDayItem {
  const AppScheduleDayItem({
    required this.id,
    required this.title,
    required this.detail,
    required this.category,
    required this.actionable,
    this.icon,
    this.status,
    this.payload,
  });

  final String id;
  final String title;
  final String detail;
  final AppCategory category;
  final bool actionable;
  final IconData? icon;
  final AppScheduleItemStatus? status;
  final Object? payload;
}

class AppScheduleDayCard extends StatelessWidget {
  const AppScheduleDayCard({
    super.key,
    required this.localDate,
    required this.items,
    required this.emptyLabel,
    required this.onItemTap,
  });

  final DateTime localDate;
  final List<AppScheduleDayItem> items;
  final String emptyLabel;
  final ValueChanged<AppScheduleDayItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('EEEE, MMM d').format(localDate),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (items.isEmpty)
            Text(emptyLabel)
          else
            for (final item in items)
              _ScheduleItemRow(
                item: item,
                onTap: () => onItemTap(item),
              ),
        ],
      ),
    );
  }
}

class _ScheduleItemRow extends StatelessWidget {
  const _ScheduleItemRow({required this.item, required this.onTap});

  final AppScheduleDayItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final appearance = item.category.visual(context);
    final action = item.actionable ? onTap : null;
    return Container(
      key: ValueKey('schedule-day-item-${item.id}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: appearance.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          side: BorderSide(
            color: appearance.foreground.withValues(alpha: 0.34),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (item.status case final status?)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: Center(
                  child: _ScheduleStatusBox(
                    itemId: item.id,
                    status: status,
                    completedColor: appearance.foreground,
                  ),
                ),
              ),
            Expanded(
              child: Semantics(
                key: ValueKey('schedule-day-item-semantics-${item.id}'),
                container: true,
                button: action != null,
                label: '${item.title}. ${item.detail}. ${appearance.label}.',
                onTap: action,
                excludeSemantics: true,
                child: InkWell(
                  onTap: action,
                  excludeFromSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          item.icon ?? appearance.icon,
                          size: 22,
                          color: appearance.foreground,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: appearance.foreground),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                '${item.detail} · ${appearance.label}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: appearance.foreground),
                              ),
                            ],
                          ),
                        ),
                        if (action != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Icon(
                            AppIcons.chevronRight,
                            color: appearance.foreground,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleStatusBox extends StatelessWidget {
  const _ScheduleStatusBox({
    required this.itemId,
    required this.status,
    required this.completedColor,
  });

  final String itemId;
  final AppScheduleItemStatus status;
  final Color completedColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final checked = status == AppScheduleItemStatus.completed ||
        status == AppScheduleItemStatus.fullyRated;
    final label = switch (status) {
      AppScheduleItemStatus.notApplicable => 'Completion status not applicable',
      AppScheduleItemStatus.open => 'Not completed',
      AppScheduleItemStatus.completed => 'Completed',
      AppScheduleItemStatus.fullyRated => 'Completed and fully rated',
    };
    final checkColor = status == AppScheduleItemStatus.fullyRated
        ? completedColor
        : colors.onSurfaceVariant;
    return Semantics(
      key: ValueKey('schedule-status-$itemId'),
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: status == AppScheduleItemStatus.fullyRated
                ? completedColor.withValues(alpha: 0.13)
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: checked
              ? Icon(AppIcons.check, size: 19, color: checkColor)
              : null,
        ),
      ),
    );
  }
}
