import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_motion_tokens.dart';
import '../theme/app_visual_tokens.dart';

/// Read acknowledgement belongs only to the settled root destination, not to
/// a lazily mounted neighbouring preview. Non-pager routes are visible by default.
class RootTabVisibility extends InheritedWidget {
  const RootTabVisibility({
    required this.visible,
    required super.child,
    super.key,
  });

  final bool visible;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<RootTabVisibility>()
          ?.visible ??
      true;

  @override
  bool updateShouldNotify(RootTabVisibility oldWidget) =>
      visible != oldWidget.visible;
}

/// One route surface for the root tabs. Previews are real, lazily built pages;
/// navigation is committed only when the pager settles, not on pointer down.
class RootTabPager extends StatefulWidget {
  const RootTabPager({
    required this.index,
    required this.count,
    required this.pageBuilder,
    required this.onSettled,
    this.enabled = true,
    this.onMovementChanged,
    super.key,
  });

  final int index;
  final int count;
  final IndexedWidgetBuilder pageBuilder;
  final ValueChanged<int> onSettled;
  final bool enabled;
  final ValueChanged<bool>? onMovementChanged;

  @override
  State<RootTabPager> createState() => _RootTabPagerState();
}

class _RootTabPagerState extends State<RootTabPager> {
  late final _controller = PageController(
    initialPage: widget.index,
    keepPage: false,
  );
  bool _moving = false;
  int _origin = 0;
  Offset? _touchStart;
  Offset _touchDelta = Offset.zero;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _origin = widget.index;
    FocusManager.instance.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false) {
      _cancelled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_controller.hasClients ||
            ModalRoute.of(context)?.isCurrent != false) {
          return;
        }
        _controller.jumpToPage(widget.index);
      });
    }
  }

  @override
  void didUpdateWidget(covariant RootTabPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index && oldWidget.count == widget.count) {
      return;
    }
    final requested = widget.index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients || requested != widget.index) {
        return;
      }
      _origin = requested;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.jumpToPage(requested);
      } else {
        _controller.animateToPage(
          requested,
          duration: context.motionTokens.emphasisFor(context),
          curve: context.motionTokens.curve,
        );
      }
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final candidate = FocusManager.instance.primaryFocus?.context;
    final focusContext = candidate?.mounted == true ? candidate : null;
    var focusedEditor = focusContext?.widget is EditableText;
    try {
      focusedEditor =
          focusedEditor ||
          focusContext?.findAncestorWidgetOfExactType<EditableText>() != null;
    } on FlutterError catch (error) {
      // Focus repair happens after layout. A popped editor can still be mounted
      // but deactivated for this frame: hold navigation until focus is repaired.
      if (!error.message.contains('deactivated widget')) {
        rethrow;
      }
      focusedEditor = true;
    }
    final editing =
        MediaQuery.viewInsetsOf(context).bottom > 0 || focusedEditor;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0 ||
            notification.metrics.axis != Axis.horizontal) {
          return false;
        }
        if (notification is ScrollStartNotification) {
          _origin = widget.index;
          if (!_moving) {
            setState(() => _moving = true);
            widget.onMovementChanged?.call(true);
          }
        } else if (notification is ScrollEndNotification) {
          if (_moving) {
            setState(() => _moving = false);
            widget.onMovementChanged?.call(false);
          }
          // A pushed page owns navigation while this route is covered. A late
          // swipe must not change its history or leave a different page on Back.
          if (ModalRoute.of(context)?.isCurrent == false) {
            return false;
          }
          final settled = _controller.page!.round().clamp(0, widget.count - 1);
          if (settled != widget.index) widget.onSettled(settled);
        }
        return false;
      },
      child: Listener(
        onPointerDown: (event) {
          _touchStart = event.position;
          _touchDelta = Offset.zero;
          _cancelled = false;
        },
        onPointerMove: (event) {
          if (_touchStart != null) _touchDelta = event.position - _touchStart!;
        },
        onPointerCancel: (_) => _cancelled = true,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
            },
            scrollbars: false,
            overscroll: false,
          ),
          child: PageView.builder(
            key: const ValueKey('root-tab-pager'),
            controller: _controller,
            pageSnapping: false,
            physics: !widget.enabled || editing || reducedMotion
                ? const NeverScrollableScrollPhysics()
                : _RootSnapPhysics(
                    origin: () => _origin,
                    canAdvance: () =>
                        !_cancelled &&
                        _touchDelta.dx.abs() > _touchDelta.dy.abs() * 2.5,
                    parent: const ClampingScrollPhysics(),
                  ),
            itemCount: widget.count,
            itemBuilder: (context, index) => ColoredBox(
              // Cover neighbouring content during movement; retain the shared
              // Liquid Glass backdrop once stationary.
              color: _moving
                  ? context.visualTokens.background
                  : Colors.transparent,
              child: RootTabVisibility(
                visible: !_moving && index == widget.index,
                child: widget.pageBuilder(context, index),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RootSnapPhysics extends ScrollPhysics {
  const _RootSnapPhysics({
    required this.origin,
    required this.canAdvance,
    super.parent,
  });
  final int Function() origin;
  final bool Function() canAdvance;

  @override
  _RootSnapPhysics applyTo(ScrollPhysics? ancestor) => _RootSnapPhysics(
    origin: origin,
    canAdvance: canAdvance,
    parent: buildParent(ancestor),
  );

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final width = position.viewportDimension;
    if (width <= 0) return null;
    final start = origin();
    final distance = position.pixels - start * width;
    final threshold = (width * .22).clamp(48.0, 120.0);
    final flick =
        distance.abs() >= 32 &&
        velocity.abs() >= 650 &&
        velocity.sign == distance.sign;
    final advance = canAdvance() && (distance.abs() >= threshold || flick);
    final target = ((start + (advance ? distance.sign : 0)) * width).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final tolerance = toleranceFor(position);
    if ((target - position.pixels).abs() <= tolerance.distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}
