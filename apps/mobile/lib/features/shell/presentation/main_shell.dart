import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/capabilities/app_surface_capabilities.dart';
import '../../../core/navigation/app_routes.dart';

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
    final effectivePath = switch (currentPath) {
      final path when path.startsWith(AppRoutes.habitCompletion) =>
        AppRoutes.quickAction,
      final path when path.startsWith(AppRoutes.habitManagement) =>
        AppRoutes.quickAction,
      final path when path.startsWith(AppRoutes.quickMoodCheckIn) =>
        AppRoutes.quickAction,
      final path when path.startsWith(AppRoutes.dailyCheckIn) =>
        AppRoutes.quickAction,
      final path when path.startsWith(AppRoutes.deepWork) => AppRoutes.alerts,
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                _FloatingNavItem(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home,
                  label: 'Home',
                  isSelected: selectedIndex == 0,
                  onTap: () => onDestinationSelected(0),
                ),
                _FloatingNavItem(
                  icon: Icons.auto_graph_outlined,
                  selectedIcon: Icons.auto_graph,
                  label: 'Insights',
                  isSelected: selectedIndex == 1,
                  onTap: () => onDestinationSelected(1),
                ),
                const Expanded(child: SizedBox(height: 60)),
                _FloatingNavItem(
                  icon: Icons.notifications_outlined,
                  selectedIcon: Icons.notifications,
                  label: 'Alerts',
                  isSelected: selectedIndex == 3,
                  onTap: () => onDestinationSelected(3),
                ),
                _FloatingNavItem(
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings,
                  label: 'Settings',
                  isSelected: selectedIndex == 4,
                  onTap: () => onDestinationSelected(4),
                ),
              ],
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
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 6),
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
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: isSelected ? selectedColor : idleColor,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatefulWidget {
  const _QuickActionButton({required this.onTap});

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
      child: Semantics(
        button: true,
        label: 'Add signal',
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          behavior: HitTestBehavior.opaque,
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
                      ? Color.lerp(primary, Colors.black, isLight ? 0.08 : 0.16)
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
                  color: isLight ? const Color(0xFF063D35) : Colors.black,
                  size: 34,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
