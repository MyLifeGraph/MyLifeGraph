import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/capabilities/app_surface_capabilities.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_motion_tokens.dart';
import '../../../core/theme/app_theme_effects.dart';
import '../../../core/theme/app_visual_tokens.dart';
import '../../../core/widgets/app_brand_mark.dart';
import '../../../composition/notifications_providers.dart';
import '../../notifications/domain/entities/notification_action_target.dart';
import 'shell_destination_descriptor.dart';

class MainShell extends ConsumerWidget {
  const MainShell({
    required this.currentPath,
    required this.child,
    super.key,
  });

  final String currentPath;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    ref.listen(inAppNotificationDeliveryProvider, (previous, next) {
      if (previous?.sequence == next.sequence || next.notification == null) {
        return;
      }
      final notification = next.notification!;
      ref.invalidate(notificationsProvider);
      final target = NotificationActionTargetResolver(
        canUseSyncedHabits: capabilities.canUseSyncedHabits,
        canUseFocusSessions: capabilities.canUseSyncedExecution,
        canUseWeeklyReview: capabilities.canUseWeeklyReview,
      ).resolve(notification.actionUrl);
      final router = GoRouter.of(context);
      final messenger = ScaffoldMessenger.of(context);
      void openTarget() {
        if (target == null) return;
        messenger.hideCurrentSnackBar();
        router.go(target.location);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final viewportWidth = MediaQuery.sizeOf(context).width;
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              key: ValueKey('in-app-notification-${notification.id}'),
              duration: const Duration(seconds: 8),
              width: viewportWidth >= 640 ? 560 : null,
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              content: _InAppNotificationBannerContent(
                notificationId: notification.id,
                title: notification.title,
                body: notification.body,
                onOpen: target == null ? null : openTarget,
              ),
              action: target == null
                  ? null
                  : SnackBarAction(
                      label: target.openLabel,
                      onPressed: openTarget,
                    ),
            ),
          );
      });
    });
    final selectedDestination = shellDestinationForPath(currentPath);
    final visibleDestinations = visibleShellDestinations(
      canShowCoach: capabilities.canShowCoachSurface,
    ).toList(growable: false);
    final quickActionDestination = shellDestinations.firstWhere(
      (destination) => destination.emphasized,
    );

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
                  destinations: visibleDestinations,
                  selectedDestination: selectedDestination,
                  onDestinationSelected: (destination) =>
                      context.go(destination.path),
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
            destination: quickActionDestination,
            isSelected: selectedDestination == quickActionDestination,
            onTap: () => context.go(quickActionDestination.path),
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
          bottomNavigationBar: _FloatingBottomNav(
            destinations: visibleDestinations,
            selectedDestination: selectedDestination,
            onDestinationSelected: (destination) =>
                context.go(destination.path),
          ),
        );
      },
    );
  }
}

class _InAppNotificationBannerContent extends StatelessWidget {
  const _InAppNotificationBannerContent({
    required this.notificationId,
    required this.title,
    required this.body,
    required this.onOpen,
  });

  final String notificationId;
  final String title;
  final String body;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final snackTextStyle = Theme.of(context).snackBarTheme.contentTextStyle ??
        Theme.of(context).textTheme.bodyMedium;
    final tokens = context.visualTokens;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: tokens.brand.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Icon(
            AppIcons.notificationsActiveOutlined,
            size: 20,
            color: tokens.brand,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: snackTextStyle?.copyWith(
                  fontSize: 16,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: snackTextStyle?.copyWith(
                  fontSize: 13,
                  height: 1.35,
                  color: snackTextStyle.color?.withValues(alpha: 0.78),
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Icon(AppIcons.checkCircle, size: 13, color: tokens.brand),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Rule-based reminder',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: snackTextStyle?.copyWith(
                        fontSize: 12,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: tokens.brand,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    if (onOpen == null) return content;
    return Semantics(
      button: true,
      label: 'Open notification $title',
      child: InkWell(
        key: ValueKey('in-app-notification-content-$notificationId'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: content,
        ),
      ),
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

class _NavigationMaterial extends StatelessWidget {
  const _NavigationMaterial({
    required this.borderRadius,
    required this.child,
    required this.materialKey,
  });

  final BorderRadius borderRadius;
  final Widget child;
  final Key materialKey;

  @override
  Widget build(BuildContext context) {
    final tokens = context.visualTokens;
    final surfaceMaterial = context.themeEffects.surfaceMaterial;
    final background = surfaceMaterial.navigation(tokens.surface);
    final foreground = ColoredBox(
      color: background,
      child: RepaintBoundary(child: child),
    );
    if (surfaceMaterial.navigationBlurSigma <= 0) {
      return KeyedSubtree(key: materialKey, child: foreground);
    }
    return ClipRRect(
      key: materialKey,
      borderRadius: borderRadius,
      child: BackdropFilter(
        key: const ValueKey('space-navigation-backdrop-filter'),
        filter: ui.ImageFilter.blur(
          sigmaX: surfaceMaterial.navigationBlurSigma,
          sigmaY: surfaceMaterial.navigationBlurSigma,
        ),
        child: foreground,
      ),
    );
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.destinations,
    required this.selectedDestination,
    required this.onDestinationSelected,
  });

  final List<ShellDestinationDescriptor> destinations;
  final ShellDestinationDescriptor? selectedDestination;
  final ValueChanged<ShellDestinationDescriptor> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    double spacingBefore(int index) {
      final destination = destinations[index];
      final previous = destinations[index - 1];
      return destination.emphasized || previous.emphasized
          ? AppSpacing.md
          : AppSpacing.xs;
    }

    return _NavigationMaterial(
      materialKey: const ValueKey('desktop-navigation-material'),
      borderRadius: BorderRadius.zero,
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
                        for (var index = 0;
                            index < destinations.length;
                            index++) ...[
                          if (index > 0) SizedBox(height: spacingBefore(index)),
                          _DesktopNavItem(
                            destination: destinations[index],
                            isSelected:
                                selectedDestination == destinations[index],
                            onTap: () =>
                                onDestinationSelected(destinations[index]),
                          ),
                        ],
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
    final tokens = context.visualTokens;
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
          child: AppBrandMark(
            color: colors.onPrimaryContainer,
            size: 26,
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
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: tokens.textPrimary,
                    ),
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

class _DesktopNavItem extends StatefulWidget {
  const _DesktopNavItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final ShellDestinationDescriptor destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_DesktopNavItem> createState() => _DesktopNavItemState();
}

class _DesktopNavItemState extends State<_DesktopNavItem> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final effects = context.themeEffects;
    final label = widget.destination.label;
    final emphasized = widget.destination.emphasized;
    final normalizedLabel = label.toLowerCase().replaceAll(' ', '-');
    final semanticKey = emphasized
        ? const ValueKey('main-shell-add-signal')
        : ValueKey('main-nav-${label.toLowerCase()}');
    final controlKey = emphasized
        ? const ValueKey('main-shell-add-signal-control')
        : ValueKey('main-nav-${label.toLowerCase()}-control');
    final background = emphasized
        ? colors.primary
        : widget.isSelected
            ? colors.primaryContainer
            : Colors.transparent;
    final foreground = emphasized
        ? colors.onPrimary
        : widget.isSelected
            ? colors.onPrimaryContainer
            : colors.onSurfaceVariant;
    final interactionShadows = effects.interactionGlow(
      hovered: _hovered,
      pressed: _pressed,
      focused: _focused,
    );
    final shadows = <BoxShadow>[
      if (emphasized &&
          !_hovered &&
          !_pressed &&
          !_focused &&
          effects.primaryControlIdleGlowColor.a > 0)
        BoxShadow(
          color: effects.primaryControlIdleGlowColor,
          blurRadius: 24,
          spreadRadius: -4,
        ),
      ...?interactionShadows,
    ];

    return Semantics(
      key: semanticKey,
      container: true,
      button: true,
      selected: widget.isSelected,
      label: label,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          key: ValueKey('main-nav-$normalizedLabel-glow'),
          duration: context.motionTokens.selectionFor(context),
          curve: context.motionTokens.curve,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            boxShadow: shadows.isEmpty ? null : shadows,
          ),
          child: Material(
            color: background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              side: BorderSide(
                color: emphasized
                    ? colors.primary
                    : widget.isSelected
                        ? colors.primaryContainer
                        : Colors.transparent,
              ),
            ),
            child: InkWell(
              key: controlKey,
              onTap: widget.onTap,
              onHover: (value) => setState(() => _hovered = value),
              onFocusChange: (value) => setState(() => _focused = value),
              onHighlightChanged: (value) => setState(() => _pressed = value),
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    child: Row(
                      children: [
                        _NavigationIconScale(
                          enabled: effects.navigationSignalColor.a > 0,
                          selected: widget.isSelected,
                          child: Icon(
                            widget.isSelected
                                ? widget.destination.desktopSelectedIcon
                                : widget.destination.icon,
                            key: emphasized
                                ? const ValueKey(
                                    'main-shell-add-signal-icon',
                                  )
                                : null,
                            color: foreground,
                            size: 22,
                          ),
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
                  if (effects.navigationSignalColor.a > 0)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _NavigationSelectionSignal(
                          key: ValueKey(
                            'desktop-navigation-signal-$normalizedLabel',
                          ),
                          selected: widget.isSelected,
                          color: effects.navigationSignalColor,
                          axis: Axis.vertical,
                        ),
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

class _NavigationIconScale extends StatelessWidget {
  const _NavigationIconScale({
    required this.enabled,
    required this.selected,
    required this.child,
  });

  final bool enabled;
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return AnimatedScale(
      duration: context.motionTokens.stateFor(context),
      curve: context.motionTokens.curve,
      scale: selected ? 1 : 0.97,
      child: child,
    );
  }
}

class _NavigationSelectionSignal extends StatelessWidget {
  const _NavigationSelectionSignal({
    required this.selected,
    required this.color,
    required this.axis,
    super.key,
  });

  final bool selected;
  final Color color;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: context.motionTokens.stateFor(context),
      curve: context.motionTokens.curve,
      opacity: selected ? 1 : 0,
      child: Container(
        width: axis == Axis.vertical ? 3 : 24,
        height: axis == Axis.vertical ? 28 : 3,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.55),
              blurRadius: 10,
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingBottomNav extends StatelessWidget {
  const _FloatingBottomNav({
    required this.destinations,
    required this.selectedDestination,
    required this.onDestinationSelected,
  });

  final List<ShellDestinationDescriptor> destinations;
  final ShellDestinationDescriptor? selectedDestination;
  final ValueChanged<ShellDestinationDescriptor> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;
    final effects = context.themeEffects;
    final emphasizedIndex = destinations.indexWhere(
      (destination) => destination.emphasized,
    );
    assert(emphasizedIndex >= 0, 'The shell requires one emphasized action.');
    final leadingDestinations =
        destinations.take(emphasizedIndex).toList(growable: false);
    final trailingDestinations =
        destinations.skip(emphasizedIndex + 1).toList(growable: false);

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
                borderRadius: BorderRadius.circular(AppRadii.xl),
                border: effects.surfaceOutlineColor.a > 0
                    ? Border.all(color: effects.surfaceOutlineColor)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: tokens.shadow,
                    blurRadius: 28,
                    spreadRadius: -16,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: _NavigationMaterial(
                materialKey: const ValueKey('mobile-navigation-material'),
                borderRadius: BorderRadius.circular(AppRadii.xl),
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
                          for (final destination in leadingDestinations)
                            _FloatingNavItem(
                              destination: destination,
                              isSelected: selectedDestination == destination,
                              showLabel: !compact,
                              flex: itemFlex(
                                selectedDestination == destination,
                              ),
                              height: itemHeight,
                              onTap: () => onDestinationSelected(destination),
                            ),
                          Expanded(
                            flex: compact ? 6 : 1,
                            child: SizedBox(height: itemHeight),
                          ),
                          if (trailingDestinations.length == 1)
                            Expanded(
                              flex: itemFlex(false),
                              child: SizedBox(height: itemHeight),
                            ),
                          for (final destination in trailingDestinations)
                            _FloatingNavItem(
                              destination: destination,
                              isSelected: selectedDestination == destination,
                              showLabel: !compact,
                              flex: itemFlex(
                                selectedDestination == destination,
                              ),
                              height: itemHeight,
                              onTap: () => onDestinationSelected(destination),
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
                            for (final destination in destinations)
                              _CompactNavLabel(
                                destination: destination,
                                isSelected: selectedDestination == destination,
                                selectedColor: selectedColor,
                                idleColor: idleColor,
                                onTap: () => onDestinationSelected(destination),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CompactNavLabel extends StatefulWidget {
  const _CompactNavLabel({
    required this.destination,
    required this.isSelected,
    required this.selectedColor,
    required this.idleColor,
    required this.onTap,
  });

  final ShellDestinationDescriptor destination;
  final bool isSelected;
  final Color selectedColor;
  final Color idleColor;
  final VoidCallback onTap;

  @override
  State<_CompactNavLabel> createState() => _CompactNavLabelState();
}

class _CompactNavLabelState extends State<_CompactNavLabel> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final effects = context.themeEffects;
    final label = widget.destination.label;
    final normalizedLabel = label.toLowerCase().replaceAll(' ', '-');
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: context.motionTokens.selectionFor(context),
        curve: context.motionTokens.curve,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          boxShadow: effects.interactionGlow(
            hovered: _hovered,
            pressed: _pressed,
            focused: _focused,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('main-nav-label-$normalizedLabel-control'),
            excludeFromSemantics: true,
            canRequestFocus: false,
            onTap: widget.onTap,
            onHover: (value) => setState(() => _hovered = value),
            onFocusChange: (value) => setState(() => _focused = value),
            onHighlightChanged: (value) => setState(() => _pressed = value),
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                label,
                key: ValueKey('main-nav-label-$normalizedLabel'),
                maxLines: 2,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: widget.isSelected
                          ? widget.selectedColor
                          : widget.idleColor,
                      fontWeight:
                          widget.isSelected ? FontWeight.w800 : FontWeight.w600,
                    ),
              ),
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
            AppIcons.cloudOffOutlined,
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

class _FloatingNavItem extends StatefulWidget {
  const _FloatingNavItem({
    required this.destination,
    required this.isSelected,
    required this.showLabel,
    required this.flex,
    required this.height,
    required this.onTap,
  });

  final ShellDestinationDescriptor destination;
  final bool isSelected;
  final bool showLabel;
  final int flex;
  final double height;
  final VoidCallback onTap;

  @override
  State<_FloatingNavItem> createState() => _FloatingNavItemState();
}

class _FloatingNavItemState extends State<_FloatingNavItem> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final effects = context.themeEffects;
    final selectedColor = colors.onPrimaryContainer;
    final idleColor = colors.onSurfaceVariant;
    final label = widget.destination.label;
    final normalizedLabel = label.toLowerCase().replaceAll(' ', '-');

    return Expanded(
      flex: widget.flex,
      child: Semantics(
        key: ValueKey('main-nav-${label.toLowerCase()}'),
        container: true,
        button: true,
        selected: widget.isSelected,
        label: label,
        onTap: widget.onTap,
        child: ExcludeSemantics(
          child: Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('main-nav-${label.toLowerCase()}-control'),
                borderRadius: BorderRadius.circular(AppRadii.md),
                onTap: widget.onTap,
                onHover: (value) => setState(() => _hovered = value),
                onFocusChange: (value) => setState(() => _focused = value),
                onHighlightChanged: (value) => setState(() => _pressed = value),
                child: AnimatedContainer(
                  key: ValueKey(
                    'main-nav-${label.toLowerCase().replaceAll(' ', '-')}-glow',
                  ),
                  duration: context.motionTokens.stateFor(context),
                  curve: context.motionTokens.curve,
                  height: widget.height,
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.showLabel ? 6 : 0,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? colors.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    boxShadow: effects.interactionGlow(
                      hovered: _hovered,
                      pressed: _pressed,
                      focused: _focused,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _NavigationIconScale(
                            enabled: effects.navigationSignalColor.a > 0,
                            selected: widget.isSelected,
                            child: Icon(
                              widget.isSelected
                                  ? widget.destination.mobileSelectedIcon
                                  : widget.destination.icon,
                              color:
                                  widget.isSelected ? selectedColor : idleColor,
                            ),
                          ),
                          if (widget.showLabel) ...[
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
                                    color: widget.isSelected
                                        ? selectedColor
                                        : idleColor,
                                    fontWeight: widget.isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                            ),
                          ],
                        ],
                      ),
                      if (effects.navigationSignalColor.a > 0)
                        Positioned(
                          top: 0,
                          child: _NavigationSelectionSignal(
                            key: ValueKey(
                              'mobile-navigation-signal-$normalizedLabel',
                            ),
                            selected: widget.isSelected,
                            color: effects.navigationSignalColor,
                            axis: Axis.horizontal,
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
    );
  }
}

class _QuickActionButton extends StatefulWidget {
  const _QuickActionButton({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final ShellDestinationDescriptor destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_QuickActionButton> createState() => _QuickActionButtonState();
}

class _QuickActionButtonState extends State<_QuickActionButton> {
  bool _isPressed = false;
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final primary = colors.primary;
    final tokens = context.visualTokens;
    final motion = context.motionTokens;
    final effects = context.themeEffects;

    return Tooltip(
      message: widget.destination.label,
      excludeFromSemantics: true,
      child: Semantics(
        key: const ValueKey('main-shell-add-signal'),
        container: true,
        button: true,
        selected: widget.isSelected,
        label: widget.destination.label,
        onTap: widget.onTap,
        child: ExcludeSemantics(
          child: Material(
            color: Colors.transparent,
            child: InkResponse(
              key: const ValueKey('main-shell-add-signal-control'),
              onTap: widget.onTap,
              onHover: (value) => setState(() => _isHovered = value),
              onFocusChange: (value) => setState(() => _isFocused = value),
              onHighlightChanged: (value) {
                if (_isPressed != value) {
                  setState(() => _isPressed = value);
                }
              },
              customBorder: const CircleBorder(),
              radius: 38,
              child: Container(
                key: const ValueKey('main-shell-add-signal-glow'),
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: tokens.shadow,
                      blurRadius: 16,
                      spreadRadius: -4,
                      offset: const Offset(0, 8),
                    ),
                    if (!_isHovered &&
                        !_isPressed &&
                        !_isFocused &&
                        effects.primaryControlIdleGlowColor.a > 0)
                      BoxShadow(
                        color: effects.primaryControlIdleGlowColor,
                        blurRadius: 24,
                        spreadRadius: -4,
                      ),
                    ...?effects.interactionGlow(
                      hovered: _isHovered,
                      pressed: _isPressed,
                      focused: _isFocused,
                    ),
                  ],
                ),
                child: AnimatedScale(
                  duration: motion.selectionFor(context),
                  curve: motion.curve,
                  scale: _isPressed ? 0.94 : 1,
                  child: AnimatedContainer(
                    duration: motion.selectionFor(context),
                    curve: motion.curve,
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isPressed
                          ? effects.quickActionPressedColor
                          : primary,
                      border: Border.all(
                        color: colors.surface,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      widget.destination.mobileSelectedIcon,
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
