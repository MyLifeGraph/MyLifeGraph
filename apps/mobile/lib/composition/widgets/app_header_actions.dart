import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_radii.dart';
import '../../core/feedback/app_haptics.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/navigation/root_tab_pager.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_motion_tokens.dart';
import '../../core/theme/app_visual_tokens.dart';
import '../../core/widgets/app_surface.dart';
import '../../core/widgets/app_page_header_actions_scope.dart';
import '../../features/coach/application/coach_turn_notice.dart';
import '../../features/coach/presentation/providers/coach_providers.dart';
import '../../core/capabilities/app_surface_capabilities.dart';
import '../../features/focus_protection/application/focus_protection_gateway.dart';

class AppHeaderActions extends ConsumerStatefulWidget {
  const AppHeaderActions({
    this.pageActions = const <Widget>[],
    this.settingsSelected = false,
    super.key,
  });

  final List<Widget> pageActions;
  final bool settingsSelected;

  /// Custom page actions call this before their guarded callback. Pointer and
  /// keyboard activation are also handled by the shared menu.
  static void dismissForAction(BuildContext context) => context
      .getInheritedWidgetOfExactType<_HeaderActionActivation>()
      ?.dismiss();

  @override
  ConsumerState<AppHeaderActions> createState() => _AppHeaderActionsState();
}

class _AppHeaderActionsState extends ConsumerState<AppHeaderActions>
    with SingleTickerProviderStateMixin {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _tapGroup = Object();
  final _menuBounds = GlobalKey();
  final _overflowButton = GlobalKey();
  final _overflowFocus = FocusNode();
  Offset? _menuPointerStart;
  late final _animation = AnimationController(vsync: this);
  late final _reveal = CurvedAnimation(
    parent: _animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointer);
    _animation.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && !_expanded) _portal.hide();
    });
  }

  void _onGlobalPointer(PointerEvent event) {
    if (!_expanded || event is! PointerScrollEvent) return;
    final box = _menuBounds.currentContext?.findRenderObject();
    if (box is! RenderBox ||
        !(Offset.zero & box.size).contains(box.globalToLocal(event.position))) {
      _close();
    }
  }

  void _toggle() {
    AppHaptics.selection(context);
    if (_expanded) {
      _close();
    } else {
      setState(() => _expanded = true);
      _portal.show();
      _animation.forward();
    }
  }

  void _close() {
    if (!_expanded) return;
    setState(() => _expanded = false);
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 0;
      _portal.hide();
    } else {
      _animation.reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animation.duration = context.motionTokens.emphasisFor(context);
    // Subscribe while closed too; opening via setState does not re-run this hook.
    final routeCurrent = ModalRoute.of(context)?.isCurrent != false;
    final tabVisible = RootTabVisibility.of(context);
    if (_expanded && (!routeCurrent || !tabVisible)) {
      // Route/visibility notifications can arrive during the build phase.
      // Close the overlay only after that frame, not while it is building.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_expanded) return;
        if (ModalRoute.of(context)?.isCurrent == false ||
            !RootTabVisibility.of(context)) {
          setState(() => _expanded = false);
          _animation.value = 0;
          _portal.hide();
        }
      });
    }
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
    _reveal.dispose();
    _animation.dispose();
    _overflowFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notice = ref.watch(coachTurnNoticeProvider);
    final mediaWidth = MediaQuery.sizeOf(context).width;
    final screenWidth = mediaWidth > 0
        ? mediaWidth
        : View.of(context).physicalSize.width /
              View.of(context).devicePixelRatio;
    final menuWidth =
        (AppPageHeaderActionsScope.maxWidthOf(context) ?? screenWidth - 32)
            .clamp(48.0, double.infinity);
    final actions = Row(
      key: const ValueKey('global-header-actions'),
      mainAxisSize: MainAxisSize.min,
      children: [
        ...widget.pageActions.map(
          (action) => ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: action is IconButton
                ? _dismissibleIconButton(action)
                : action,
          ),
        ),
        if (notice != null)
          _CoachNoticeButton(
            notice: notice,
            onPressed: () {
              _close();
              _showCoachNotice(context, notice);
            },
          ),
        if (!widget.settingsSelected) ...[
          IconButton(
            key: const ValueKey('global-header-inbox'),
            tooltip: 'Inbox',
            onPressed: GoRouter.maybeOf(context) == null
                ? null
                : () {
                    _close();
                    context.push(AppRoutes.alerts);
                  },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            icon: const Icon(AppIcons.inboxOutlined),
          ),
          if (ref.watch(focusProtectionPlatformSupportedProvider) &&
              ref
                  .watch(appSurfaceCapabilitiesProvider)
                  .canUseDeviceFocusProtection)
            IconButton(
              key: const ValueKey('global-header-blocking'),
              tooltip: 'App blocking',
              onPressed: GoRouter.maybeOf(context) == null
                  ? null
                  : () {
                      _close();
                      context.push(AppRoutes.focusProtection);
                    },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: const Icon(AppIcons.shieldOutlined),
            ),
          _SettingsButton(selected: false, onActivate: _close),
        ],
      ],
    );
    if (widget.settingsSelected &&
        notice == null &&
        widget.pageActions.isEmpty) {
      return actions;
    }
    return PopScope(
      canPop: !_expanded,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _close();
      },
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                targetAnchor: Alignment.topRight,
                followerAnchor: Alignment.topRight,
                offset: Offset.zero,
                child: FadeTransition(
                  opacity: _reveal,
                  child: SizeTransition(
                    sizeFactor: _reveal,
                    axis: Axis.horizontal,
                    alignment: Alignment.centerRight,
                    child: IgnorePointer(
                      ignoring: !_expanded,
                      child: ExcludeSemantics(
                        excluding: !_expanded,
                        child: ConstrainedBox(
                          key: _menuBounds,
                          constraints: BoxConstraints(maxWidth: menuWidth),
                          child: FocusScope(
                            autofocus: true,
                            child: Focus(
                              autofocus: true,
                              onKeyEvent: (_, event) {
                                if (event is KeyDownEvent &&
                                    event.logicalKey ==
                                        LogicalKeyboardKey.escape) {
                                  _close();
                                  return KeyEventResult.handled;
                                }
                                if (!_overflowFocus.hasFocus &&
                                    ((event is KeyDownEvent &&
                                            event.logicalKey ==
                                                LogicalKeyboardKey.enter) ||
                                        (event is KeyUpEvent &&
                                            event.logicalKey ==
                                                LogicalKeyboardKey.space))) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) _close();
                                  });
                                }
                                return KeyEventResult.ignored;
                              },
                              child: TapRegion(
                                groupId: _tapGroup,
                                child: Material(
                                  color: Theme.of(context).colorScheme.surface,
                                  shape: const StadiumBorder(),
                                  child: Listener(
                                    // Reverse after activation without replacing a
                                    // caller's callback or disabling its existing guard.
                                    onPointerDown: (event) =>
                                        _menuPointerStart = event.position,
                                    onPointerCancel: (_) =>
                                        _menuPointerStart = null,
                                    onPointerUp: (event) {
                                      final start = _menuPointerStart;
                                      _menuPointerStart = null;
                                      final overflowBox = _overflowButton
                                          .currentContext
                                          ?.findRenderObject();
                                      final tappedOverflow =
                                          overflowBox is RenderBox &&
                                          (Offset.zero & overflowBox.size)
                                              .contains(
                                                overflowBox.globalToLocal(
                                                  event.position,
                                                ),
                                              );
                                      if (start != null &&
                                          !tappedOverflow &&
                                          (start - event.position).distance <
                                              kTouchSlop) {
                                        _close();
                                      }
                                    },
                                    child: _surface(
                                      context,
                                      _HeaderIconsViewport(
                                        controlKey: _overflowButton,
                                        controlFocus: _overflowFocus,
                                        child: _HeaderActionActivation(
                                          dismiss: _close,
                                          child: actions,
                                        ),
                                      ),
                                      key: const ValueKey('header-action-menu'),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        child: CompositedTransformTarget(
          link: _link,
          child: TapRegion(
            groupId: _tapGroup,
            onTapOutside: (_) => _close(),
            child: ExcludeSemantics(
              excluding: _expanded,
              child: _surface(
                context,
                Semantics(
                  expanded: _expanded,
                  child: IconButton(
                    key: const ValueKey('header-island-toggle'),
                    tooltip: _expanded ? 'Close actions' : 'Page actions',
                    onPressed: _toggle,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedSwitcher(
                          duration: context.motionTokens.selectionFor(context),
                          child: Icon(
                            _expanded ? AppIcons.close : AppIcons.menu,
                            key: ValueKey(_expanded),
                          ),
                        ),
                        if (notice != null)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Semantics(
                              label: notice.semanticsLabel,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.error,
                                  shape: BoxShape.circle,
                                ),
                                child: const SizedBox.square(dimension: 7),
                              ),
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
      ),
    );
  }

  // Page actions use standard IconButtons. Wrap their callback rather than
  // replacing semantics: Flutter must retain focus, tooltip and disabled state.
  Widget _dismissibleIconButton(IconButton action) => IconButton(
    key: action.key,
    iconSize: action.iconSize,
    visualDensity: action.visualDensity,
    padding: action.padding,
    alignment: action.alignment,
    splashRadius: action.splashRadius,
    color: action.color,
    focusColor: action.focusColor,
    hoverColor: action.hoverColor,
    highlightColor: action.highlightColor,
    splashColor: action.splashColor,
    disabledColor: action.disabledColor,
    onPressed: action.onPressed == null
        ? null
        : () {
            _close();
            action.onPressed!();
          },
    onHover: action.onHover,
    onLongPress: action.onLongPress,
    mouseCursor: action.mouseCursor,
    focusNode: action.focusNode,
    autofocus: action.autofocus,
    tooltip: action.tooltip,
    enableFeedback: action.enableFeedback,
    constraints: action.constraints,
    style: action.style,
    isSelected: action.isSelected,
    selectedIcon: action.selectedIcon,
    statesController: action.statesController,
    icon: action.icon,
  );

  Widget _surface(BuildContext context, Widget child, {Key? key}) => AppSurface(
    key: key ?? const ValueKey('header-action-island'),
    variant: AppSurfaceVariant.raised,
    radius: AppRadii.pill,
    padding: const EdgeInsets.all(2),
    child: IconButtonTheme(
      data: IconButtonThemeData(
        style: (IconButtonTheme.of(context).style ?? const ButtonStyle())
            .copyWith(
              visualDensity: VisualDensity.standard,
              minimumSize: const WidgetStatePropertyAll(Size.square(44)),
              fixedSize: const WidgetStatePropertyAll(Size.square(44)),
              backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
              // One shared glass surface, not a tiny glass tile per icon.
              backgroundBuilder: (context, states, child) =>
                  child ?? const SizedBox.shrink(),
              shape: const WidgetStatePropertyAll(CircleBorder()),
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? BorderSide(color: context.visualTokens.focus, width: 2)
                    : BorderSide.none,
              ),
            ),
      ),
      child: child,
    ),
  );
}

class _HeaderIconsViewport extends StatefulWidget {
  const _HeaderIconsViewport({
    required this.controlKey,
    required this.controlFocus,
    required this.child,
  });

  final GlobalKey controlKey;
  final FocusNode controlFocus;
  final Widget child;

  @override
  State<_HeaderIconsViewport> createState() => _HeaderIconsViewportState();
}

class _HeaderIconsViewportState extends State<_HeaderIconsViewport> {
  final _scroll = ScrollController();
  bool _overflow = false;
  bool _atEnd = false;
  bool _metricsQueued = false;
  double _availableWidth = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_queueMetrics);
  }

  void _queueMetrics() {
    if (_metricsQueued) return;
    _metricsQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _metricsQueued = false;
      if (!mounted ||
          !_scroll.hasClients ||
          !_scroll.position.hasContentDimensions) {
        return;
      }
      final position = _scroll.position;
      // Compare the complete icon width with the full available space, NOT the
      // viewport reduced by the arrow. Otherwise resize could retain it forever.
      final overflow =
          position.maxScrollExtent + position.viewportDimension >
          _availableWidth + .5;
      final atEnd = position.pixels >= position.maxScrollExtent - .5;
      if (overflow != _overflow || atEnd != _atEnd) {
        setState(() {
          _overflow = overflow;
          _atEnd = atEnd;
        });
      }
    });
  }

  void _showMore() {
    if (!_scroll.hasClients) return;
    final target = _atEnd ? 0.0 : _scroll.position.maxScrollExtent;
    final duration = context.motionTokens.stateFor(context);
    if (duration == Duration.zero) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target, duration: duration, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _availableWidth = constraints.maxWidth;
      _queueMetrics();
      final showControl = _overflow && constraints.maxWidth >= 88;
      final icons = NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _queueMetrics();
          return false;
        },
        child: SingleChildScrollView(
          key: const ValueKey('header-island-icons-scroll'),
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
      );
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            fit: FlexFit.loose,
            child: Stack(
              alignment: Alignment.centerRight,
              children: [
                icons,
                // At exceptionally narrow widths, preserve the icon hit target;
                // an inert edge hint accompanies the existing swipe interaction.
                if (_overflow && !showControl)
                  const IgnorePointer(
                    child: ExcludeSemantics(
                      child: Icon(AppIcons.chevronRight, size: 12),
                    ),
                  ),
              ],
            ),
          ),
          if (showControl)
            SizedBox.square(
              key: widget.controlKey,
              dimension: 44,
              child: IconButton(
                key: const ValueKey('header-island-overflow'),
                focusNode: widget.controlFocus,
                tooltip: _atEnd ? 'First actions' : 'More actions',
                padding: EdgeInsets.zero,
                onPressed: _showMore,
                icon: Icon(
                  _atEnd ? AppIcons.chevronLeft : AppIcons.chevronRight,
                  size: 16,
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _HeaderActionActivation extends InheritedWidget {
  const _HeaderActionActivation({required this.dismiss, required super.child});

  final VoidCallback dismiss;

  @override
  bool updateShouldNotify(_HeaderActionActivation oldWidget) => false;
}

class _CoachNoticeButton extends StatelessWidget {
  const _CoachNoticeButton({required this.notice, required this.onPressed});

  final CoachTurnNotice notice;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        key: const ValueKey('global-header-coach-notice'),
        tooltip: notice.semanticsLabel,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(AppIcons.psychologyOutlined),
            Positioned(
              right: -7,
              top: -7,
              child: ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(
                    dimension: 18,
                    child: Center(
                      child: Text(
                        '!',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onError,
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
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.selected, required this.onActivate});

  final bool selected;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    final tooltip = selected ? 'Settings, current page' : 'Settings';
    final button = IconButton(
      key: const ValueKey('global-header-settings'),
      tooltip: tooltip,
      onPressed: selected
          ? () {}
          : router == null
          ? null
          : () {
              onActivate();
              context.push(AppRoutes.settings);
            },
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      style: selected
          ? IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            )
          : null,
      icon: Icon(selected ? AppIcons.settings : AppIcons.settingsOutlined),
    );
    if (!selected) return button;
    return Semantics(selected: true, child: button);
  }
}

void _showCoachNotice(BuildContext context, CoachTurnNotice notice) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: ValueKey('coach-turn-notice-${notice.requestId}'),
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        duration: const Duration(minutes: 5),
        content: Text(notice.message),
      ),
    );
}
