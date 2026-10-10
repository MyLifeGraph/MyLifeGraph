import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_radii.dart';
import '../../core/navigation/app_routes.dart';
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
    this.showOverflowControl = false,
    super.key,
  });

  final List<Widget> pageActions;
  final bool settingsSelected;
  final bool showOverflowControl;

  /// Compatibility seam for page callbacks; the always-open island has no menu
  /// to dismiss. Keep existing guarded action callbacks unchanged.
  static void dismissForAction(BuildContext context) {}

  @override
  ConsumerState<AppHeaderActions> createState() => _AppHeaderActionsState();
}

class _AppHeaderActionsState extends ConsumerState<AppHeaderActions> {
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
            .clamp(48.0, 180.0);
    final actions = Row(
      key: const ValueKey('global-header-actions'),
      mainAxisSize: MainAxisSize.min,
      children: [
        ...widget.pageActions.map(
          (action) => ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: action,
          ),
        ),
        if (notice != null)
          _CoachNoticeButton(
            notice: notice,
            onPressed: () {
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
                      context.push(AppRoutes.focusProtection);
                    },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: const Icon(AppIcons.shieldOutlined),
            ),
          _SettingsButton(selected: false, onActivate: () {}),
        ],
      ],
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: menuWidth),
      child: _surface(
        context,
        _HeaderIconsViewport(
          showOverflowControl: widget.showOverflowControl,
          child: actions,
        ),
      ),
    );
  }

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
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
    required this.child,
    required this.showOverflowControl,
  });
  final Widget child;
  final bool showOverflowControl;

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

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _availableWidth = constraints.maxWidth;
      _queueMetrics();
      final showControl =
          widget.showOverflowControl && _overflow && constraints.maxWidth >= 88;
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
                  IgnorePointer(
                    child: ExcludeSemantics(
                      child: Icon(
                        _atEnd ? AppIcons.chevronLeft : AppIcons.chevronRight,
                        size: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (showControl)
            SizedBox.square(
              dimension: 44,
              child: IconButton(
                key: const ValueKey('header-island-overflow'),
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
