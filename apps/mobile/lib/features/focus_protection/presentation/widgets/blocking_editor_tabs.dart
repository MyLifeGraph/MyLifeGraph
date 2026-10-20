import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/constants/app_radii.dart';

/// Compact, theme-owned sections. Large text can scroll rather than truncate.
class BlockingEditorTabs extends StatelessWidget {
  const BlockingEditorTabs({
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.icons,
    super.key,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int>? onChanged;
  final List<IconData>? icons;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final theme = Theme.of(context);
      final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: math.max(bounds.maxWidth, 300 * scale),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: Semantics(
                        selected: i == selected,
                        button: true,
                        child: Material(
                          color: i == selected
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          child: InkWell(
                            key: ValueKey('blocking-editor-tab-$i'),
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                            onTap: onChanged == null
                                ? null
                                : () => onChanged!(i),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (icons != null) ...[
                                      Icon(
                                        icons![i],
                                        size: 20,
                                        color: i == selected
                                            ? theme.colorScheme.onPrimary
                                            : theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 4),
                                    ],
                                    Text(
                                      labels[i],
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: i == selected
                                                ? theme.colorScheme.onPrimary
                                                : theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
