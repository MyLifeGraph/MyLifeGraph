import 'package:flutter/material.dart';

import 'app_icons.dart';
import 'app_visual_tokens.dart';

enum AppCategory {
  task,
  setup,
  habit,
  preparation,
  calendar,
  focus,
  fixedCommitment,
}

class AppCategoryVisual {
  const AppCategoryVisual({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;
}

extension AppCategoryVisuals on AppCategory {
  AppCategoryVisual visual(BuildContext context) {
    final tokens = context.visualTokens;
    return switch (this) {
      AppCategory.task => AppCategoryVisual(
          label: 'Task',
          icon: AppIcons.taskOutlined,
          foreground: tokens.brand,
          background: tokens.brand.withValues(alpha: 0.14),
        ),
      AppCategory.setup => AppCategoryVisual(
          label: 'Setup commitment',
          icon: AppIcons.eventRepeatOutlined,
          foreground: tokens.brand,
          background: tokens.brand.withValues(alpha: 0.14),
        ),
      AppCategory.habit => AppCategoryVisual(
          label: 'Habit',
          icon: AppIcons.repeatOutlined,
          foreground: tokens.info,
          background: tokens.infoSurface,
        ),
      AppCategory.preparation => AppCategoryVisual(
          label: 'Preparation',
          icon: AppIcons.schoolOutlined,
          foreground: tokens.info,
          background: tokens.infoSurface,
        ),
      AppCategory.calendar => AppCategoryVisual(
          label: 'Calendar',
          icon: AppIcons.calendarMonthOutlined,
          foreground: tokens.attention,
          background: tokens.attentionSurface,
        ),
      AppCategory.focus => AppCategoryVisual(
          label: 'Focus',
          icon: AppIcons.timerOutlined,
          foreground: tokens.dataViolet,
          background: tokens.dataViolet.withValues(alpha: 0.16),
        ),
      AppCategory.fixedCommitment => AppCategoryVisual(
          label: 'Fixed commitment',
          icon: AppIcons.eventBusyOutlined,
          foreground: tokens.danger,
          background: tokens.dangerSurface,
        ),
    };
  }
}
