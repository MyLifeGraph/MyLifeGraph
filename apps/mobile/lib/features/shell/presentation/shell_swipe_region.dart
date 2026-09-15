import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Directional recognizers let nested scrollables win their own gestures.
/// Deliberate touch drags only: no wheel scrolling, mouse selection or taps.
class ShellSwipeRegion extends StatefulWidget {
  const ShellSwipeRegion({
    required this.child,
    this.onHorizontalSwipe,
    this.onSwipeUp,
    super.key,
  });

  final Widget child;
  final ValueChanged<bool>? onHorizontalSwipe;
  final VoidCallback? onSwipeUp;

  @override
  State<ShellSwipeRegion> createState() => _ShellSwipeRegionState();
}

class _ShellSwipeRegionState extends State<ShellSwipeRegion> {
  Offset? _start;
  Offset _delta = Offset.zero;
  final _elapsed = Stopwatch();

  void _down(DragDownDetails details) {
    _start = details.globalPosition;
    _delta = Offset.zero;
    _elapsed..reset()..start();
  }

  void _update(DragUpdateDetails details) {
    if (_start != null) _delta = details.globalPosition - _start!;
  }

  void _end(bool horizontal) {
    final delta = _delta;
    final deliberate = _start != null && _elapsed.elapsedMilliseconds <= 800;
    _cancel();
    if (!deliberate) return;
    if (horizontal && delta.dx.abs() >= 96 &&
        delta.dx.abs() > delta.dy.abs() * 2.5) {
      widget.onHorizontalSwipe?.call(delta.dx < 0);
    } else if (!horizontal && delta.dy <= -64 &&
        delta.dy.abs() > delta.dx.abs() * 2.5) {
      widget.onSwipeUp?.call();
    }
  }

  void _cancel() {
    _start = null;
    _elapsed.stop();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus},
    onHorizontalDragDown: widget.onHorizontalSwipe == null ? null : _down,
    onHorizontalDragUpdate: widget.onHorizontalSwipe == null ? null : _update,
    onHorizontalDragEnd: widget.onHorizontalSwipe == null ? null : (_) => _end(true),
    onHorizontalDragCancel: widget.onHorizontalSwipe == null ? null : _cancel,
    onVerticalDragDown: widget.onSwipeUp == null ? null : _down,
    onVerticalDragUpdate: widget.onSwipeUp == null ? null : _update,
    onVerticalDragEnd: widget.onSwipeUp == null ? null : (_) => _end(false),
    onVerticalDragCancel: widget.onSwipeUp == null ? null : _cancel,
    child: widget.child,
  );
}
