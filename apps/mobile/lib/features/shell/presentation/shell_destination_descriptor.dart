import 'package:flutter/material.dart';

import '../../../core/navigation/app_routes.dart';
import '../../../core/theme/app_icons.dart';

/// Presentation metadata shared by every responsive form of the app shell.
class ShellDestinationDescriptor {
  const ShellDestinationDescriptor({
    required this.path,
    required this.label,
    required this.icon,
    required this.desktopSelectedIcon,
    required this.mobileSelectedIcon,
    required this.activePathPrefixes,
    this.emphasized = false,
    this.requiresCoachCapability = false,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData desktopSelectedIcon;
  final IconData mobileSelectedIcon;
  final List<String> activePathPrefixes;
  final bool emphasized;
  final bool requiresCoachCapability;

  bool matches(String candidatePath) => activePathPrefixes.any(
        (prefix) =>
            candidatePath == prefix || candidatePath.startsWith('$prefix/'),
      );

  bool isVisible({required bool canShowCoach}) =>
      !requiresCoachCapability || canShowCoach;
}

const shellDestinations = <ShellDestinationDescriptor>[
  ShellDestinationDescriptor(
    path: AppRoutes.dashboard,
    label: 'Today',
    icon: AppIcons.homeOutlined,
    desktopSelectedIcon: AppIcons.homeRounded,
    mobileSelectedIcon: AppIcons.home,
    activePathPrefixes: [
      AppRoutes.dashboard,
      AppRoutes.weeklyReview,
    ],
  ),
  ShellDestinationDescriptor(
    path: AppRoutes.insights,
    label: 'Insights',
    icon: AppIcons.autoGraphOutlined,
    desktopSelectedIcon: AppIcons.autoGraphRounded,
    mobileSelectedIcon: AppIcons.autoGraph,
    activePathPrefixes: [AppRoutes.insights],
  ),
  ShellDestinationDescriptor(
    path: AppRoutes.quickAction,
    label: 'Quick actions',
    icon: AppIcons.add,
    desktopSelectedIcon: AppIcons.add,
    mobileSelectedIcon: AppIcons.add,
    activePathPrefixes: [
      AppRoutes.quickAction,
      AppRoutes.habitCompletion,
      AppRoutes.quickMoodCheckIn,
      AppRoutes.dailyCheckIn,
      AppRoutes.deepWork,
    ],
    emphasized: true,
  ),
  ShellDestinationDescriptor(
    path: AppRoutes.planner,
    label: 'Planner',
    icon: AppIcons.calendarViewWeekOutlined,
    desktopSelectedIcon: AppIcons.calendarViewWeekRounded,
    mobileSelectedIcon: AppIcons.calendarViewWeek,
    activePathPrefixes: [
      AppRoutes.planner,
      AppRoutes.habitManagement,
      AppRoutes.preparationPlans,
    ],
  ),
  ShellDestinationDescriptor(
    path: AppRoutes.coach,
    label: 'Coach',
    icon: AppIcons.forumOutlined,
    desktopSelectedIcon: AppIcons.forum,
    mobileSelectedIcon: AppIcons.forum,
    activePathPrefixes: [AppRoutes.coach],
    requiresCoachCapability: true,
  ),
];

ShellDestinationDescriptor? shellDestinationForPath(String path) {
  for (final destination in shellDestinations) {
    if (destination.matches(path)) return destination;
  }
  return null;
}

Iterable<ShellDestinationDescriptor> visibleShellDestinations({
  required bool canShowCoach,
}) =>
    shellDestinations.where(
      (destination) => destination.isVisible(canShowCoach: canShowCoach),
    );
