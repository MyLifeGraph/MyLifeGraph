import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/capabilities/app_surface_capabilities.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
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
                    'In-app · fixed text · not AI-written',
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
      final path when path.startsWith(AppRoutes.preparationPlans) =>
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

    final content = _ShellBody(
      isLocalDemo: capabilities.isLocalDemo,
      child: child,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1100;
        if (desktop) {
          return Scaffold(
            body: Row(
              children: [
                _DesktopNavigation(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) => context.go(_routes[index]),
                ),
                Expanded(child: content),
              ],
            ),
          );
        }

        return Scaffold(
          extendBody: true,
          body: content,
          floatingActionButton: _QuickActionButton(
            isSelected: selectedIndex == 2,
            onTap: () => context.go(AppRoutes.quickAction),
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
          bottomNavigationBar: _FloatingBottomNav(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) => context.go(_routes[index]),
          ),
        );
      },
    );
  }
}

class _ShellBody extends StatelessWidget {
  const _ShellBody({required this.isLocalDemo, required this.child});

  final bool isLocalDemo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isLocalDemo) return child;

    return Column(
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
    );
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: Container(
        width: 236,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: colors.outlineVariant),
          ),
        ),
        child: SafeArea(
          right: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _DesktopBrand(),
                const SizedBox(height: AppSpacing.xl),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DesktopNavItem(
                          icon: Icons.home_outlined,
                          selectedIcon: Icons.home_rounded,
                          label: 'Today',
                          isSelected: selectedIndex == 0,
                          onTap: () => onDestinationSelected(0),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        _DesktopNavItem(
                          icon: Icons.auto_graph_outlined,
                          selectedIcon: Icons.auto_graph_rounded,
                          label: 'Insights',
                          isSelected: selectedIndex == 1,
                          onTap: () => onDestinationSelected(1),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _DesktopNavItem(
                          icon: Icons.add,
                          selectedIcon: Icons.add,
                          label: 'Quick actions',
                          isSelected: selectedIndex == 2,
                          emphasized: true,
                          onTap: () => onDestinationSelected(2),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _DesktopNavItem(
                          icon: Icons.notifications_outlined,
                          selectedIcon: Icons.notifications_rounded,
                          label: 'Inbox',
                          isSelected: selectedIndex == 3,
                          onTap: () => onDestinationSelected(3),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        _DesktopNavItem(
                          icon: Icons.settings_outlined,
                          selectedIcon: Icons.settings_rounded,
                          label: 'Settings',
                          isSelected: selectedIndex == 4,
                          onTap: () => onDestinationSelected(4),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    'A clear next step, grounded in your day.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopBrand extends StatelessWidget {
  const _DesktopBrand();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.auto_awesome_rounded,
            color: colors.onPrimaryContainer,
            size: 22,
          ),
        ),
        const SizedBox(width: AppSpacing.sm + 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MyLifeGraph',
                maxLines: 1,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                'Daily coach',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopNavItem extends StatelessWidget {
  const _DesktopNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final normalizedLabel = label.toLowerCase().replaceAll(' ', '-');
    final semanticKey = emphasized
        ? const ValueKey('main-shell-add-signal')
        : ValueKey('main-nav-${label.toLowerCase()}');
    final controlKey = emphasized
        ? const ValueKey('main-shell-add-signal-control')
        : ValueKey('main-nav-${label.toLowerCase()}-control');
    final background = emphasized
        ? colors.primary
        : isSelected
            ? colors.primaryContainer
            : Colors.transparent;
    final foreground = emphasized
        ? colors.onPrimary
        : isSelected
            ? colors.onPrimaryContainer
            : colors.onSurfaceVariant;

    return Semantics(
      key: semanticKey,
      container: true,
      button: true,
      selected: isSelected,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            side: BorderSide(
              color: emphasized
                  ? colors.primary
                  : isSelected
                      ? colors.primaryContainer
                      : Colors.transparent,
            ),
          ),
          child: InkWell(
            key: controlKey,
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected ? selectedIcon : icon,
                    key: emphasized
                        ? const ValueKey('main-shell-add-signal-icon')
                        : null,
                    color: foreground,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: emphasized
                        ? RichText(
                            key: ValueKey(
                              'main-nav-label-$normalizedLabel',
                            ),
                            maxLines: 2,
                            textScaler: MediaQuery.textScalerOf(context),
                            text: TextSpan(
                              text: label,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(color: foreground),
                            ),
                          )
                        : Text(
                            label,
                            key: ValueKey(
                              'main-nav-label-$normalizedLabel',
                            ),
                            maxLines: 2,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(color: foreground),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scaledLabelSize = MediaQuery.textScalerOf(context).scale(12);
          final compact = constraints.maxWidth < 360 || scaledLabelSize > 16;
          final itemHeight = compact ? 52.0 : 56.0;
          int itemFlex(bool selected) => compact
              ? selected
                  ? 4
                  : 3
              : 1;
          final selectedColor = colors.onPrimaryContainer;
          final idleColor = colors.onSurfaceVariant;

          return Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 8 : 12,
              0,
              compact ? 8 : 12,
              8,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(AppRadii.xl),
                border: Border.all(color: colors.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 22,
                    spreadRadius: -8,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 0 : 10,
                  vertical: 7,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _FloatingNavItem(
                          icon: Icons.home_outlined,
                          selectedIcon: Icons.home,
                          label: 'Today',
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
                            label: 'Today',
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
                            label: 'Quick actions',
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
            maxLines: 2,
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
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant),
        ),
      ),
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
    final colors = Theme.of(context).colorScheme;
    final selectedColor = colors.onPrimaryContainer;
    final idleColor = colors.onSurfaceVariant;

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
                borderRadius: BorderRadius.circular(AppRadii.md),
                onTap: onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  height: height,
                  padding: EdgeInsets.symmetric(
                    horizontal: showLabel ? 6 : 0,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colors.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.md),
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
    final colors = Theme.of(context).colorScheme;
    final primary = colors.primary;

    return Tooltip(
      message: 'Quick actions',
      excludeFromSemantics: true,
      child: Semantics(
        key: const ValueKey('main-shell-add-signal'),
        container: true,
        button: true,
        selected: widget.isSelected,
        label: 'Quick actions',
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
              radius: 38,
              child: Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 16,
                      spreadRadius: -4,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 90),
                  scale: _isPressed ? 0.94 : 1,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 90),
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isPressed
                          ? Color.lerp(primary, Colors.black, 0.12)
                          : primary,
                      border: Border.all(
                        color: colors.surface,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.add,
                      key: const ValueKey('main-shell-add-signal-icon'),
                      color: colors.onPrimary,
                      size: 30,
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
