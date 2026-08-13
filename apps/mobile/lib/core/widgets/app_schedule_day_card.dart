import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../theme/app_category_visuals.dart';
import '../theme/app_icons.dart';
import '../theme/app_visual_tokens.dart';
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

class _ScheduleItemRow extends StatefulWidget {
  const _ScheduleItemRow({required this.item, required this.onTap});

  final AppScheduleDayItem item;
  final VoidCallback onTap;

  @override
  State<_ScheduleItemRow> createState() => _ScheduleItemRowState();
}

class _ScheduleItemRowState extends State<_ScheduleItemRow> {
  final FocusNode _focusNode = FocusNode();
  bool _showFocusHighlight = false;

  @override
  void didUpdateWidget(_ScheduleItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.actionable && !widget.item.actionable) {
      _focusNode.unfocus();
      _showFocusHighlight = false;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final appearance = item.category.visual(context);
    final action = item.actionable ? _activate : null;
    final statusLabel = item.status == null ? null : _statusLabel(item.status!);
    final semanticsLabel = '${[
      item.title,
      item.detail,
      appearance.label,
      if (statusLabel != null) statusLabel,
    ].join('. ')}.';
    return Container(
      key: ValueKey('schedule-day-item-${item.id}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        key: ValueKey('schedule-day-item-material-${item.id}'),
        color: appearance.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          side: BorderSide(
            color: _showFocusHighlight
                ? context.visualTokens.focus
                : appearance.foreground.withValues(alpha: 0.34),
            width: _showFocusHighlight ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          key: ValueKey('schedule-day-item-semantics-${item.id}'),
          container: true,
          button: action != null,
          label: semanticsLabel,
          onTap: action,
          excludeSemantics: true,
          child: FocusableActionDetector(
            focusNode: _focusNode,
            enabled: action != null,
            descendantsAreFocusable: false,
            descendantsAreTraversable: false,
            includeFocusSemantics: false,
            mouseCursor:
                action == null ? MouseCursor.defer : SystemMouseCursors.click,
            onShowFocusHighlight: _handleFocusHighlight,
            actions: action == null
                ? null
                : <Type, Action<Intent>>{
                    ActivateIntent: CallbackAction<ActivateIntent>(
                      onInvoke: (_) {
                        _activate();
                        return null;
                      },
                    ),
                  },
            child: InkWell(
              onTap: action,
              canRequestFocus: false,
              excludeFromSemantics: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (item.status case final status?) ...[
                        _ScheduleStatusBox(
                          itemId: item.id,
                          status: status,
                          completedColor: appearance.foreground,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
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
        ),
      ),
    );
  }

  void _activate() {
    if (widget.item.actionable) widget.onTap();
  }

  void _handleFocusHighlight(bool value) {
    if (mounted && value != _showFocusHighlight) {
      setState(() => _showFocusHighlight = value);
    }
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
    final checkColor = status == AppScheduleItemStatus.fullyRated
        ? completedColor
        : colors.onSurfaceVariant;
    return ExcludeSemantics(
      key: ValueKey('schedule-status-$itemId'),
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
        child:
            checked ? Icon(AppIcons.check, size: 19, color: checkColor) : null,
      ),
    );
  }
}

String _statusLabel(AppScheduleItemStatus status) => switch (status) {
      AppScheduleItemStatus.notApplicable => 'Completion status not applicable',
      AppScheduleItemStatus.open => 'Not completed',
      AppScheduleItemStatus.completed => 'Completed',
      AppScheduleItemStatus.fullyRated => 'Completed and fully rated',
    };
