import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/capabilities/app_surface_capabilities.dart';
import '../../../core/navigation/app_routes.dart';
import '../../notifications/domain/entities/notification_action_target.dart';
import '../../notifications/presentation/providers/notifications_providers.dart';

class MainShell extends ConsumerWidget {
  const MainShell({
    required this.currentPath,
    required this.child,
    super.key,
  });

  final String currentPath;
  final Widget child;

  static const _routes = [
    AppRoutes.dashboard,
    AppRoutes.insights,
    AppRoutes.quickAction,
    AppRoutes.alerts,
    AppRoutes.settings,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    ref.listen(inAppNotificationDeliveryProvider, (previous, next) {
      if (previous?.sequence == next.sequence || next.notification == null) {
        return;
      }
      final notification = next.notification!;
      unawaited(ref.read(notificationsProvider.notifier).load());
      final target = NotificationActionTargetResolver(
        canUseSyncedHabits: capabilities.canUseSyncedHabits,
        canUseFocusSessions: capabilities.canUseSyncedExecution,
        canUseWeeklyReview: capabilities.canUseWeeklyReview,
      ).resolve(notification.actionUrl);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              key: ValueKey('in-app-notification-${notification.id}'),
              duration: const Duration(seconds: 8),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(notification.body),
                  const SizedBox(height: 4),
                  const Text(
                    'In-app · deterministic · no LLM',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
              action: target == null
                  ? null
                  : SnackBarAction(
                      label: 'Open',
                      onPressed: () => context.go(target.location),
                    ),
            ),
          );
      });
    });
    final effectivePath = switch (currentPath) {
      final path when path.startsWith(AppRoutes.habitCompletion) =>
        AppRoutes.quickAction,
      final path when path.startsWith(AppRoutes.habitManagement) =>
        AppRoutes.quickAction,
      final path when path.startsWith(AppRoutes.quickMoodCheckIn) =>
        AppRoutes.quickAction,
      final path when path.startsWith(AppRoutes.dailyCheckIn) =>
        AppRoutes.quickAction,
      final path when path.startsWith(AppRoutes.weeklyReview) =>
        AppRoutes.dashboard,
      final path when path.startsWith(AppRoutes.deepWork) =>
        AppRoutes.quickAction,
      final path when path.startsWith(AppRoutes.calendarIntegration) =>
        AppRoutes.settings,
      final path when path.startsWith(AppRoutes.notificationSettings) =>
        AppRoutes.settings,
      final path when path.startsWith(AppRoutes.coach) => AppRoutes.settings,
      _ => currentPath,
    };
    final currentIndex = _routes.indexWhere(
      (route) => effectivePath.startsWith(route),
    );
    final selectedIndex = currentIndex == -1 ? 0 : currentIndex;

    return Scaffold(
      extendBody: true,
      body: capabilities.isLocalDemo
          ? Column(
              children: [
                const SafeArea(
                  bottom: false,
                  child: _LocalDemoBanner(),
                ),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: child,
                  ),
                ),
              ],
            )
          : child,
      floatingActionButton: _QuickActionButton(
        isSelected: selectedIndex == 2,
        onTap: () => context.go(AppRoutes.quickAction),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _FloatingBottomNav(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => context.go(_routes[index]),
      ),
    );
  }
}

class _FloatingBottomNav extends StatelessWidget {
  const _FloatingBottomNav({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final background = isLight
        ? Colors.white.withValues(alpha: 0.9)
        : const Color(0xFF102025).withValues(alpha: 0.92);
    final border = isLight ? const Color(0xFFD4E1DF) : const Color(0xFF2A424A);

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scaledLabelSize = MediaQuery.textScalerOf(context).scale(12);
          final compact = constraints.maxWidth < 360 || scaledLabelSize > 16;
          final itemHeight = compact ? 56.0 : 60.0;
          int itemFlex(bool selected) => compact
              ? selected
                  ? 4
                  : 3
              : 1;
          final selectedColor =
              isLight ? const Color(0xFF063D35) : Colors.white;
          final idleColor =
              isLight ? const Color(0xFF607078) : const Color(0xFFA8B5BE);

          return Padding(
            padding:
                EdgeInsets.fromLTRB(compact ? 8 : 14, 0, compact ? 8 : 14, 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: border, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: isLight ? 0.12 : 0.16),
                    blurRadius: 24,
                    spreadRadius: -10,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 0 : 10,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _FloatingNavItem(
                          icon: Icons.home_outlined,
                          selectedIcon: Icons.home,
                          label: 'Home',
                          isSelected: selectedIndex == 0,
                          showLabel: !compact,
                          flex: itemFlex(selectedIndex == 0),
                          height: itemHeight,
                          onTap: () => onDestinationSelected(0),
                        ),
                        _FloatingNavItem(
                          icon: Icons.auto_graph_outlined,
                          selectedIcon: Icons.auto_graph,
                          label: 'Insights',
                          isSelected: selectedIndex == 1,
                          showLabel: !compact,
                          flex: itemFlex(selectedIndex == 1),
                          height: itemHeight,
                          onTap: () => onDestinationSelected(1),
                        ),
                        Expanded(
                          flex: compact ? 6 : 1,
                          child: SizedBox(height: itemHeight),
                        ),
                        _FloatingNavItem(
                          icon: Icons.notifications_outlined,
                          selectedIcon: Icons.notifications,
                          label: 'Inbox',
                          isSelected: selectedIndex == 3,
                          showLabel: !compact,
                          flex: itemFlex(selectedIndex == 3),
                          height: itemHeight,
                          onTap: () => onDestinationSelected(3),
                        ),
                        _FloatingNavItem(
                          icon: Icons.settings_outlined,
                          selectedIcon: Icons.settings,
                          label: 'Settings',
                          isSelected: selectedIndex == 4,
                          showLabel: !compact,
                          flex: itemFlex(selectedIndex == 4),
                          height: itemHeight,
                          onTap: () => onDestinationSelected(4),
                        ),
                      ],
                    ),
                    if (compact) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        alignment: WrapAlignment.spaceEvenly,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _CompactNavLabel(
                            label: 'Home',
                            isSelected: selectedIndex == 0,
                            selectedColor: selectedColor,
                            idleColor: idleColor,
                            onTap: () => onDestinationSelected(0),
                          ),
                          _CompactNavLabel(
                            label: 'Insights',
                            isSelected: selectedIndex == 1,
                            selectedColor: selectedColor,
                            idleColor: idleColor,
                            onTap: () => onDestinationSelected(1),
                          ),
                          _CompactNavLabel(
                            label: 'Add signal',
                            isSelected: selectedIndex == 2,
                            selectedColor: selectedColor,
                            idleColor: idleColor,
                            onTap: () => onDestinationSelected(2),
                          ),
                          _CompactNavLabel(
                            label: 'Inbox',
                            isSelected: selectedIndex == 3,
                            selectedColor: selectedColor,
                            idleColor: idleColor,
                            onTap: () => onDestinationSelected(3),
                          ),
                          _CompactNavLabel(
                            label: 'Settings',
                            isSelected: selectedIndex == 4,
                            selectedColor: selectedColor,
                            idleColor: idleColor,
                            onTap: () => onDestinationSelected(4),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CompactNavLabel extends StatelessWidget {
  const _CompactNavLabel({
    required this.label,
    required this.isSelected,
    required this.selectedColor,
    required this.idleColor,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final Color selectedColor;
  final Color idleColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final normalizedLabel = label.toLowerCase().replaceAll(' ', '-');
    return ExcludeSemantics(
      child: GestureDetector(
        key: ValueKey('main-nav-label-$normalizedLabel-control'),
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            label,
            key: ValueKey('main-nav-label-$normalizedLabel'),
            maxLines: 1,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: isSelected ? selectedColor : idleColor,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                ),
          ),
        ),
      ),
    );
  }
}

class _LocalDemoBanner extends StatelessWidget {
  const _LocalDemoBanner();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      height: 28,
      color: colors.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 14,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            'Local demo',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _FloatingNavItem extends StatelessWidget {
  const _FloatingNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.showLabel,
    required this.flex,
    required this.height,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final bool showLabel;
  final int flex;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final selectedColor = Theme.of(context).brightness == Brightness.light
        ? const Color(0xFF063D35)
        : Colors.white;
    final idleColor = Theme.of(context).brightness == Brightness.light
        ? const Color(0xFF607078)
        : const Color(0xFFA8B5BE);

    return Expanded(
      flex: flex,
      child: Semantics(
        key: ValueKey('main-nav-${label.toLowerCase()}'),
        container: true,
        button: true,
        selected: isSelected,
        label: label,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('main-nav-${label.toLowerCase()}-control'),
                borderRadius: BorderRadius.circular(22),
                onTap: onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: height,
                  padding: EdgeInsets.symmetric(
                    horizontal: showLabel ? 6 : 0,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? primary.withValues(alpha: 0.22)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isSelected ? selectedIcon : icon,
                        color: isSelected ? selectedColor : idleColor,
                      ),
                      if (showLabel) ...[
                        const SizedBox(height: 4),
                        Text(
                          key: ValueKey(
                            'main-nav-label-${label.toLowerCase()}',
                          ),
                          label,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                color: isSelected ? selectedColor : idleColor,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
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
}

class _QuickActionButton extends StatefulWidget {
  const _QuickActionButton({
    required this.isSelected,
    required this.onTap,
  });

  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_QuickActionButton> createState() => _QuickActionButtonState();
}

class _QuickActionButtonState extends State<_QuickActionButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final primary = Theme.of(context).colorScheme.primary;
    final glowColor = isLight
        ? const Color(0xFF16C6A8).withValues(alpha: 0.16)
        : primary.withValues(alpha: 0.2);
    final haloColor = isLight
        ? const Color(0xFFB6F3E6).withValues(alpha: 0.24)
        : primary.withValues(alpha: 0.08);

    return Tooltip(
      message: 'Add signal',
      excludeFromSemantics: true,
      child: Semantics(
        key: const ValueKey('main-shell-add-signal'),
        container: true,
        button: true,
        selected: widget.isSelected,
        label: 'Add signal',
        onTap: widget.onTap,
        child: ExcludeSemantics(
          child: Material(
            color: Colors.transparent,
            child: InkResponse(
              key: const ValueKey('main-shell-add-signal-control'),
              onTap: widget.onTap,
              onHighlightChanged: (value) {
                if (_isPressed != value) {
                  setState(() => _isPressed = value);
                }
              },
              customBorder: const CircleBorder(),
              radius: 46,
              child: Container(
                width: 92,
                height: 92,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: haloColor,
                      blurRadius: 22,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: glowColor,
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 90),
                  scale: _isPressed ? 0.94 : 1,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 90),
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isPressed
                          ? Color.lerp(
                              primary,
                              Colors.black,
                              isLight ? 0.08 : 0.16,
                            )
                          : primary,
                      border: Border.all(
                        color: isLight
                            ? Colors.white.withValues(alpha: 0.72)
                            : Colors.black.withValues(alpha: 0.22),
                        width: 1.4,
                      ),
                    ),
                    child: Icon(
                      Icons.add,
                      key: const ValueKey('main-shell-add-signal-icon'),
                      color: Theme.of(context).colorScheme.onPrimary,
                      size: 34,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
