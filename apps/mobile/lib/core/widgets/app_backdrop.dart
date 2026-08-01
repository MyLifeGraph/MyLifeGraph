import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme_effects.dart';
import '../theme/app_visual_tokens.dart';

class AppBackdrop extends StatefulWidget {
  const AppBackdrop({required this.child, super.key});

  final Widget child;

  @override
  State<AppBackdrop> createState() => _AppBackdropState();
}

class _AppBackdropState extends State<AppBackdrop>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _starController;
  late final AnimationController _backdropController;
  bool _appIsActive = true;
  bool _reduceMotion = false;
  AppThemeEffects? _effects;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _appIsActive =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _starController = AnimationController(vsync: this);
    _backdropController = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _effects = context.themeEffects;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncAnimations();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsActive = state == AppLifecycleState.resumed;
    _syncAnimations();
  }

  void _syncAnimations() {
    final effects = _effects;
    final animationAllowed = !_reduceMotion && _appIsActive;
    _syncController(
      _starController,
      shouldAnimate:
          effects != null && effects.starfieldEnabled && animationAllowed,
      period: effects?.starfieldCycle ?? Duration.zero,
    );
    _syncController(
      _backdropController,
      shouldAnimate:
          effects != null && effects.backdropMotion.enabled && animationAllowed,
      period: effects?.backdropMotion.cycle ?? Duration.zero,
    );
  }

  void _syncController(
    AnimationController controller, {
    required bool shouldAnimate,
    required Duration period,
  }) {
    if (shouldAnimate) {
      if (!controller.isAnimating || controller.duration != period) {
        controller.repeat(period: period);
      }
    } else if (controller.isAnimating) {
      controller.stop(canceled: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _starController.dispose();
    _backdropController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.visualTokens;
    final effects = context.themeEffects;
    final backdropAsset = effects.backdropAssetFor(MediaQuery.sizeOf(context));
    return ColoredBox(
      key: const ValueKey('app-backdrop'),
      color: tokens.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backdropAsset != null)
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SpaceBackdropMotionTransform(
                        key: const ValueKey('space-backdrop-motion'),
                        phase: _backdropController,
                        fixed: _reduceMotion,
                        motion: effects.backdropMotion,
                        child: RepaintBoundary(
                          key: const ValueKey(
                            'space-backdrop-image-repaint-boundary',
                          ),
                          child: Image.asset(
                            backdropAsset,
                            key: const ValueKey('space-backdrop-image'),
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            filterQuality: FilterQuality.medium,
                            gaplessPlayback: true,
                            excludeFromSemantics: true,
                            errorBuilder: (_, __, ___) => const SizedBox.expand(
                              key: ValueKey('space-backdrop-fallback'),
                            ),
                          ),
                        ),
                      ),
                      ColoredBox(
                        key: const ValueKey('space-backdrop-scrim'),
                        color: tokens.background.withValues(
                          alpha: effects.backdropScrimOpacity,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (effects.starfieldEnabled)
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const ValueKey('space-star-field'),
                      painter: SpaceStarFieldPainter(
                        phase: _starController,
                        fixed: _reduceMotion,
                        effects: effects,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(child: widget.child),
        ],
      ),
    );
  }
}

class SpaceBackdropMotionTransform extends StatelessWidget {
  const SpaceBackdropMotionTransform({
    required this.phase,
    required this.fixed,
    required this.motion,
    required this.child,
    super.key,
  });

  final Animation<double> phase;
  final bool fixed;
  final AppBackdropMotion motion;
  final Widget child;

  double get currentPhase => fixed ? motion.fixedPhase : phase.value;

  AppBackdropMotionFrame get currentFrame => motion.frameAt(currentPhase);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: phase,
      child: child,
      builder: (context, child) {
        final frame = currentFrame;
        return Transform.translate(
          key: const ValueKey('space-backdrop-translation'),
          offset: frame.offset,
          child: Transform.scale(
            key: const ValueKey('space-backdrop-scale'),
            alignment: Alignment.center,
            scale: frame.scale,
            child: child,
          ),
        );
      },
    );
  }
}

@immutable
class SpaceStarSpec {
  const SpaceStarSpec({
    required this.position,
    required this.radius,
    required this.minimumOpacity,
    required this.maximumOpacity,
    required this.motionPhase,
    required this.twinklePhase,
    required this.driftScale,
    required this.colorIndex,
    required this.sparkle,
  });

  final Offset position;
  final double radius;
  final double minimumOpacity;
  final double maximumOpacity;
  final double motionPhase;
  final double twinklePhase;
  final double driftScale;
  final int colorIndex;
  final bool sparkle;

  @override
  bool operator ==(Object other) =>
      other is SpaceStarSpec &&
      other.position == position &&
      other.radius == radius &&
      other.minimumOpacity == minimumOpacity &&
      other.maximumOpacity == maximumOpacity &&
      other.motionPhase == motionPhase &&
      other.twinklePhase == twinklePhase &&
      other.driftScale == driftScale &&
      other.colorIndex == colorIndex &&
      other.sparkle == sparkle;

  @override
  int get hashCode => Object.hash(
        position,
        radius,
        minimumOpacity,
        maximumOpacity,
        motionPhase,
        twinklePhase,
        driftScale,
        colorIndex,
        sparkle,
      );
}

class SpaceStarFieldPainter extends CustomPainter {
  SpaceStarFieldPainter({
    required this.phase,
    required this.fixed,
    required this.effects,
  }) : super(repaint: fixed ? null : phase);

  static const _seed = 0x4D4C47;
  static const _minimumStars = 36;
  static const _maximumStars = 96;
  static const _areaPerStar = 9000.0;
  static final List<SpaceStarSpec> _stars = _createStars();

  final Animation<double> phase;
  final bool fixed;
  final AppThemeEffects effects;

  double get currentPhase => fixed ? effects.starfieldFixedPhase : phase.value;

  static int starCountFor(Size size) {
    return (size.width * size.height / _areaPerStar)
        .round()
        .clamp(_minimumStars, _maximumStars);
  }

  static List<SpaceStarSpec> starsFor(Size size) =>
      List<SpaceStarSpec>.unmodifiable(_stars.take(starCountFor(size)));

  static List<SpaceStarSpec> _createStars() {
    final random = math.Random(_seed);
    return List<SpaceStarSpec>.generate(
      _maximumStars,
      (index) {
        final minimumOpacity = 0.10 + random.nextDouble() * 0.08;
        final maximumOpacity = math.max(
          minimumOpacity,
          0.18 + random.nextDouble() * 0.10,
        );
        return SpaceStarSpec(
          position: Offset(random.nextDouble(), random.nextDouble()),
          radius: 0.6 + random.nextDouble(),
          minimumOpacity: minimumOpacity,
          maximumOpacity: maximumOpacity,
          motionPhase: random.nextDouble(),
          twinklePhase: random.nextDouble(),
          driftScale: 0.45 + random.nextDouble() * 0.55,
          colorIndex: random.nextInt(3),
          sparkle: index % 13 == 3,
        );
      },
      growable: false,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      effects.starCyan,
      effects.starViolet,
      effects.starNeutral,
    ];
    final paint = Paint();
    final animationPhase = currentPhase;
    for (final star in _stars.take(starCountFor(size))) {
      final twinkle =
          (math.sin((animationPhase * 2 + star.twinklePhase) * math.pi * 2) +
                  1) /
              2;
      final opacity = star.minimumOpacity +
          (star.maximumOpacity - star.minimumOpacity) * twinkle;
      final center = _starCenter(star, size, animationPhase);
      paint.color = colors[star.colorIndex].withValues(alpha: opacity);
      canvas.drawCircle(center, star.radius, paint);
      if (star.sparkle) {
        final sparklePaint = Paint()
          ..color = colors[star.colorIndex].withValues(alpha: opacity * 0.52)
          ..strokeWidth = 0.55
          ..strokeCap = StrokeCap.round;
        final reach = star.radius * 2.35;
        canvas.drawLine(
          center - Offset(reach, 0),
          center + Offset(reach, 0),
          sparklePaint,
        );
        canvas.drawLine(
          center - Offset(0, reach),
          center + Offset(0, reach),
          sparklePaint,
        );
      }
    }
  }

  Offset _starCenter(
    SpaceStarSpec star,
    Size size,
    double animationPhase,
  ) {
    final motionAngle = (animationPhase + star.motionPhase) * math.pi * 2;
    return Offset(
      star.position.dx * size.width +
          math.cos(motionAngle) *
              effects.maxHorizontalStarDrift *
              star.driftScale,
      star.position.dy * size.height +
          math.sin(motionAngle) *
              effects.maxVerticalStarDrift *
              star.driftScale,
    );
  }

  @override
  bool shouldRepaint(covariant SpaceStarFieldPainter oldDelegate) {
    return fixed != oldDelegate.fixed ||
        effects != oldDelegate.effects ||
        phase != oldDelegate.phase;
  }
}
