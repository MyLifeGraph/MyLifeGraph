import 'package:flutter/material.dart';

/// A pull may close only if this pointer started at the top of every active list.
/// Nested scroll hand-offs cannot turn an existing scrolling gesture into Close.
class BlockingEditorDismissGuard extends StatefulWidget {
  const BlockingEditorDismissGuard({
    required this.enabled,
    required this.atTop,
    required this.child,
    super.key,
  });
  final bool enabled;
  final bool Function() atTop;
  final Widget child;

  @override
  State<BlockingEditorDismissGuard> createState() => _BlockingEditorDismissGuardState();
}

class _BlockingEditorDismissGuardState extends State<BlockingEditorDismissGuard> {
  int? _pointer;
  bool _armed = false;
  double _distance = 0;

  void _start(PointerDownEvent event) {
    if (_pointer != null) {
      _armed = false;
      return;
    }
    _pointer = event.pointer;
    _armed = widget.enabled && widget.atTop();
    _distance = 0;
  }

  void _end(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    _armed = false;
  }

  bool _observe(ScrollNotification event) {
    if (event.metrics.axis != Axis.vertical) return false;
    if (event is ScrollUpdateNotification && event.dragDetails != null &&
        event.metrics.pixels > event.metrics.minScrollExtent + .5) {
      _armed = false;
    }
    final delta = event is OverscrollNotification && event.overscroll < 0
        ? event.dragDetails?.delta.dy
        : event is ScrollUpdateNotification &&
            event.metrics.pixels <= event.metrics.minScrollExtent + .5
        ? event.dragDetails?.delta.dy : null;
    if (_armed && delta != null) {
      if (delta < 0) _armed = false;
      _distance += delta;
      if (_distance >= 100) {
        _armed = false;
        if (widget.enabled) Navigator.of(context).maybePop();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _start,
    onPointerUp: _end,
    onPointerCancel: _end,
    child: NotificationListener<ScrollNotification>(
      onNotification: _observe,
      child: widget.child,
    ),
  );
}
