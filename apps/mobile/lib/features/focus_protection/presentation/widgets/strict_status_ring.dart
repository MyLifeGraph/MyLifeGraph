import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_liquid_glass.dart';

/// Status ornament, not unlock progress. The real timer stays separately labelled.
class StrictStatusRing extends StatefulWidget {
  const StrictStatusRing({required this.locked, super.key});

  final bool locked;

  @override
  State<StrictStatusRing> createState() => _StrictStatusRingState();
}

class _StrictStatusRingState extends State<StrictStatusRing>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(StrictStatusRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncMotion();
  }

  void _syncMotion() {
    final animate =
        widget.locked &&
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !_rotation.isAnimating) {
      _rotation.repeat();
    } else if (!animate) {
      _rotation.stop();
      if (MediaQuery.disableAnimationsOf(context)) _rotation.value = 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 136,
      child: ExcludeSemantics(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: RotationTransition(
                  key: const ValueKey('strict-ring-rotation'),
                  turns: _rotation,
                  child: CustomPaint(
                    painter: _RingPainter(
                      active: widget.locked,
                      highlight: colors.primary,
                      rim: colors.onSurface.withValues(alpha: .12),
                      track: colors.surfaceContainerHighest,
                    ),
                  ),
                ),
              ),
            ),
            Icon(
              widget.locked ? AppIcons.lockOutline : AppIcons.lockResetOutlined,
              size: 48,
              color: widget.locked ? colors.primary : colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.active,
    required this.highlight,
    required this.rim,
    required this.track,
  });

  final bool active;
  final Color highlight, rim, track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 7;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    if (active) {
      paint.shader = AppLiquidGlass.strictRingShader(bounds, highlight);
    } else {
      paint.color = track;
    }
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(
      center,
      radius + 4.5,
      Paint()
        ..color = rim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      active != oldDelegate.active ||
      highlight != oldDelegate.highlight ||
      rim != oldDelegate.rim ||
      track != oldDelegate.track;
}
