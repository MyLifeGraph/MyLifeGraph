import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/theme/app_theme_effects.dart';
import 'package:my_life_graph/core/widgets/app_backdrop.dart';

void main() {
  test('Space camera motion follows one exact closed bounded path', () {
    final motion = AppTheme.space.extension<AppThemeEffects>()!.backdropMotion;

    expect(motion.enabled, isTrue);
    expect(motion.cycle, const Duration(seconds: 48));
    expect(motion.fixedPhase, 0.37);
    expect(motion.maxHorizontalDrift, 6);
    expect(motion.maxVerticalDrift, 4);
    expect(motion.baseScale, 1.04);
    expect(motion.scaleAmplitude, 0.004);

    final phase0 = motion.frameAt(0);
    expect(phase0.offset, const Offset(6, 0));
    expect(phase0.scale, closeTo(1.044, 0.000000000001));

    final phaseQuarter = motion.frameAt(0.25);
    expect(phaseQuarter.offset, const Offset(0, 4));
    expect(phaseQuarter.scale, 1.04);

    final phaseHalf = motion.frameAt(0.5);
    expect(phaseHalf.offset, const Offset(-6, 0));
    expect(phaseHalf.scale, closeTo(1.036, 0.000000000001));

    expect(motion.frameAt(1), phase0);

    for (var index = 0; index <= 1000; index += 1) {
      final frame = motion.frameAt(index / 1000);
      expect(frame.offset.dx.abs(), lessThanOrEqualTo(6));
      expect(frame.offset.dy.abs(), lessThanOrEqualTo(4));
      expect(frame.scale, inInclusiveRange(1.036, 1.044));
    }
    expect((1.036 - 1) * 390 / 2, greaterThan(6));
  });

  test('Space star layout is deterministic and bounded by viewport area', () {
    const mobile = Size(390, 844);
    const desktop = Size(1280, 960);

    final first = SpaceStarFieldPainter.starsFor(mobile);
    final second = SpaceStarFieldPainter.starsFor(mobile);
    expect(first, second);
    expect(first, hasLength(37));
    expect(SpaceStarFieldPainter.starsFor(desktop), hasLength(96));
    expect(SpaceStarFieldPainter.starsFor(const Size(1, 1)), hasLength(36));
    for (final star in first) {
      expect(star.radius, inInclusiveRange(0.6, 1.6));
      expect(star.minimumOpacity, inInclusiveRange(0.10, 0.28));
      expect(star.maximumOpacity, inInclusiveRange(0.10, 0.28));
      expect(star.maximumOpacity, greaterThanOrEqualTo(star.minimumOpacity));
      expect(star.colorIndex, inInclusiveRange(0, 2));
    }
    expect(first.where((star) => star.sparkle), isNotEmpty);
  });

  testWidgets('Space selects a responsive local deep-field asset',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final entry in {
      const Size(390, 844): 'assets/theme/space-deep-field-portrait.webp',
      const Size(1280, 960): 'assets/theme/space-deep-field-landscape.webp',
    }.entries) {
      tester.view.physicalSize = entry.key;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.space,
          home: const AppBackdrop(child: SizedBox.expand()),
        ),
      );
      await tester.pump();

      final image = tester.widget<Image>(
        find.byKey(const ValueKey('space-backdrop-image')),
      );
      expect((image.image as AssetImage).assetName, entry.value);
      await tester.runAsync(
        () => precacheImage(
          image.image,
          tester.element(find.byKey(const ValueKey('space-backdrop-image'))),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('space-backdrop-scrim')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('space-backdrop-fallback')),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('space-backdrop-image-repaint-boundary'),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('space-backdrop-image')),
          matching: find.byKey(const ValueKey('space-backdrop-motion')),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('space-backdrop-scrim')),
          matching: find.byKey(const ValueKey('space-backdrop-motion')),
        ),
        findsNothing,
      );
    }
  });

  testWidgets('Space star and camera controllers use independent cycles',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.space,
        home: const AppBackdrop(child: SizedBox.expand()),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(seconds: 12));
    expect(_starPainter(tester).currentPhase, closeTo(0.5, 0.0001));
    expect(_backdropMotion(tester).currentPhase, closeTo(0.25, 0.0001));

    await tester.pump(const Duration(seconds: 12));
    expect(_starPainter(tester).currentPhase, closeTo(0, 0.0001));
    expect(_backdropMotion(tester).currentPhase, closeTo(0.5, 0.0001));
  });

  testWidgets('Space starfield and camera advance only while app is active',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.space,
        home: const AppBackdrop(child: SizedBox.expand()),
      ),
    );
    await tester.pump();
    final painter = _starPainter(tester);
    final backdrop = _backdropMotion(tester);
    final initialStar = painter.currentPhase;
    final initialBackdrop = backdrop.currentPhase;

    await tester.pump(const Duration(seconds: 1));
    expect(painter.currentPhase, isNot(initialStar));
    expect(backdrop.currentPhase, isNot(initialBackdrop));

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    await tester.pump();
    final pausedStar = painter.currentPhase;
    final pausedBackdrop = backdrop.currentPhase;
    await tester.pump(const Duration(seconds: 3));
    expect(painter.currentPhase, pausedStar);
    expect(backdrop.currentPhase, pausedBackdrop);

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(painter.currentPhase, isNot(pausedStar));
    expect(backdrop.currentPhase, isNot(pausedBackdrop));
  });

  testWidgets('reduced motion freezes Space at one deterministic phase',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.space,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const AppBackdrop(child: SizedBox.expand()),
      ),
    );
    await tester.pump();
    final painter = _starPainter(tester);
    final backdrop = _backdropMotion(tester);

    expect(painter.fixed, isTrue);
    expect(painter.currentPhase, 0.37);
    expect(backdrop.fixed, isTrue);
    expect(backdrop.currentPhase, 0.37);
    final fixedFrame = backdrop.currentFrame;
    await tester.pump(const Duration(seconds: 30));
    expect(painter.currentPhase, 0.37);
    expect(backdrop.currentPhase, 0.37);
    expect(backdrop.currentFrame, fixedFrame);
  });

  testWidgets('Dark and Light add no decorative backdrop layer',
      (tester) async {
    for (final theme in [AppTheme.dark, AppTheme.light]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const AppBackdrop(child: SizedBox.expand()),
        ),
      );
      expect(find.byKey(const ValueKey('space-star-field')), findsNothing);
      expect(find.byKey(const ValueKey('space-backdrop-image')), findsNothing);
      expect(find.byKey(const ValueKey('space-backdrop-motion')), findsNothing);
    }
  });
}

SpaceStarFieldPainter _starPainter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(const ValueKey('space-star-field')),
  );
  return paint.painter! as SpaceStarFieldPainter;
}

SpaceBackdropMotionTransform _backdropMotion(WidgetTester tester) =>
    tester.widget<SpaceBackdropMotionTransform>(
      find.byKey(const ValueKey('space-backdrop-motion')),
    );
