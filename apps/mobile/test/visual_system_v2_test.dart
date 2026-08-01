import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_motion_tokens.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/theme/app_theme_effects.dart';
import 'package:my_life_graph/core/theme/app_visual_tokens.dart';
import 'package:my_life_graph/core/widgets/app_backdrop.dart';
import 'package:my_life_graph/core/widgets/app_brand_mark.dart';
import 'package:my_life_graph/core/widgets/app_surface.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('InstrumentSans')
      ..addFont(
        rootBundle.load('assets/fonts/InstrumentSans-Regular.ttf'),
      )
      ..addFont(
        rootBundle.load('assets/fonts/InstrumentSans-SemiBold.ttf'),
      )
      ..addFont(
        rootBundle.load('assets/fonts/InstrumentSans-Bold.ttf'),
      );
    await loader.load();
  });

  test('V2 themes expose the canonical visual and motion extensions', () {
    final expectations = {
      AppTheme.dark: const (
        background: Color(0xFF08110F),
        surface: Color(0xFF101A17),
        text: Color(0xFFF2F6F3),
        mint: Color(0xFF69E0BD),
      ),
      AppTheme.light: const (
        background: Color(0xFFF6F6F1),
        surface: Color(0xFFFFFFFF),
        text: Color(0xFF15201C),
        mint: Color(0xFF087A65),
      ),
      AppTheme.space: const (
        background: Color(0xFF070814),
        surface: Color(0xFF101329),
        text: Color(0xFFF6F3FF),
        mint: Color(0xFF67E8F9),
      ),
    };

    for (final entry in expectations.entries) {
      final tokens = entry.key.extension<AppVisualTokens>()!;
      expect(tokens.background, entry.value.background);
      expect(tokens.surface, entry.value.surface);
      expect(tokens.textPrimary, entry.value.text);
      expect(tokens.brand, entry.value.mint);
      expect(entry.key.textTheme.bodyLarge?.fontFamily, 'InstrumentSans');
      expect(entry.key.extension<AppMotionTokens>(), isNotNull);
      expect(entry.key.extension<AppThemeEffects>(), isNotNull);
    }
    expect(AppTheme.resolve(AppThemeId.dark), same(AppTheme.dark));
    expect(AppTheme.resolve(AppThemeId.light), same(AppTheme.light));
    expect(AppTheme.resolve(AppThemeId.space), same(AppTheme.space));

    final space = AppTheme.space.extension<AppVisualTokens>()!;
    expect(space.surfaceSubtle, const Color(0xFF171A38));
    expect(space.surfaceRaised, const Color(0xFF20244A));
    expect(space.surfaceInteractive, const Color(0xFF292E5C));
    expect(space.textSecondary, const Color(0xFFD4CFEA));
    expect(space.onBrand, const Color(0xFF07272C));
    expect(space.focus, const Color(0xFFC4B5FD));
    expect(space.outlineSoft, const Color(0xFF353B68));
    expect(space.info, const Color(0xFFA5B4FC));
    expect(space.infoSurface, const Color(0xFF1D254A));
    expect(space.attention, const Color(0xFFF6C76E));
    expect(space.attentionSurface, const Color(0xFF352A18));
    expect(space.danger, const Color(0xFFFF8E9E));
    expect(space.dangerSurface, const Color(0xFF3B1D2A));
    expect(space.success, const Color(0xFF7EE2B8));
    expect(space.successSurface, const Color(0xFF14342D));
    expect(space.dataBlue, const Color(0xFF6CB6FF));
    expect(space.dataViolet, const Color(0xFFC4A7FF));
    expect(space.dataCoral, const Color(0xFFFF9CA8));
    expect(
      AppTheme.space.colorScheme.primaryContainer,
      const Color(0xFF20224A),
    );
    expect(
      AppTheme.space.colorScheme.onPrimaryContainer,
      const Color(0xFFDCD4FF),
    );
  });

  test('Space alone enables the ripple, starfield, and interaction glow', () {
    for (final theme in [AppTheme.dark, AppTheme.light]) {
      final effects = theme.extension<AppThemeEffects>()!;
      expect(effects.starfieldEnabled, isFalse);
      expect(effects.interactionGlowEnabled, isFalse);
      expect(effects.surfaceMaterial, same(AppSurfaceMaterial.disabled));
      expect(effects.surfaceOutlineColor, Colors.transparent);
      expect(effects.backdropPortraitAsset, isNull);
      expect(effects.backdropLandscapeAsset, isNull);
      expect(effects.backdropScrimOpacity, 0);
      expect(theme.splashFactory, same(NoSplash.splashFactory));
      expect(
        (theme.cardTheme.shape! as RoundedRectangleBorder).side.style,
        BorderStyle.none,
      );
    }

    final effects = AppTheme.space.extension<AppThemeEffects>()!;
    expect(effects.starfieldEnabled, isTrue);
    expect(effects.interactionGlowEnabled, isTrue);
    expect(effects.starfieldCycle, const Duration(seconds: 24));
    expect(effects.maxVerticalStarDrift, 14);
    expect(effects.maxHorizontalStarDrift, 4);
    expect(effects.surfaceOutlineColor.a, greaterThan(0));
    expect(effects.surfaceHoverOutlineColor.a, greaterThan(0));
    expect(effects.raisedSurfaceGlowColor.a, greaterThan(0));
    expect(
      effects.backdropPortraitAsset,
      'assets/theme/space-deep-field-portrait.webp',
    );
    expect(
      effects.backdropLandscapeAsset,
      'assets/theme/space-deep-field-landscape.webp',
    );
    expect(effects.backdropScrimOpacity, 0.40);
    expect(effects.surfaceMaterial.enabled, isTrue);
    expect(AppTheme.space.splashFactory, same(InkRipple.splashFactory));
    expect(AppTheme.space.scaffoldBackgroundColor, Colors.transparent);
    expect(
      (AppTheme.space.cardTheme.shape! as RoundedRectangleBorder).side.color,
      effects.surfaceOutlineColor,
    );
  });

  testWidgets('reduced motion resolves non-essential durations to zero',
      (tester) async {
    late AppMotionTokens motion;
    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              capturedContext = context;
              motion = context.motionTokens;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(motion.selectionFor(capturedContext), Duration.zero);
    expect(motion.stateFor(capturedContext), Duration.zero);
    expect(motion.emphasisFor(capturedContext), Duration.zero);

    final reducedTheme = AppTheme.withoutAnimations(AppTheme.space);
    expect(reducedTheme.splashFactory, same(NoSplash.splashFactory));
    expect(
      reducedTheme.filledButtonTheme.style?.animationDuration,
      Duration.zero,
    );
    expect(
      reducedTheme.filledButtonTheme.style?.splashFactory,
      same(NoSplash.splashFactory),
    );
  });

  testWidgets('Space surfaces glow while Dark and Light feedback stays flat',
      (tester) async {
    Future<BoxBorder?> idleBorder(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Center(
              child: AppSurface(
                variant: AppSurfaceVariant.interactive,
                onTap: _noop,
                child: Text('Idle interactive surface'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final visual = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('app-surface-visual')),
      );
      return (visual.decoration! as BoxDecoration).border;
    }

    Future<List<BoxShadow>?> pressedShadows(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Center(
              child: AppSurface(
                variant: AppSurfaceVariant.interactive,
                onTap: _noop,
                child: Text('Interactive surface'),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Interactive surface')),
      );
      await tester.pump(const Duration(milliseconds: 120));
      final visual = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('app-surface-visual')),
      );
      final shadows = (visual.decoration! as BoxDecoration).boxShadow;
      await gesture.up();
      return shadows;
    }

    expect(await pressedShadows(AppTheme.dark), isNull);
    expect(await pressedShadows(AppTheme.light), isNull);
    expect(await pressedShadows(AppTheme.space), isNotEmpty);
    expect(await idleBorder(AppTheme.dark), isNull);
    expect(await idleBorder(AppTheme.light), isNull);
    expect(await idleBorder(AppTheme.space), isA<Border>());
  });

  for (final entry in {
    'dark': AppTheme.dark,
    'light': AppTheme.light,
    'space': AppTheme.space,
  }.entries) {
    for (final viewport in {
      'mobile': const Size(390, 844),
      'desktop': const Size(1280, 960),
    }.entries) {
      testWidgets(
        '${entry.key} ${viewport.key} component reference golden',
        (tester) async {
          tester.view.physicalSize = viewport.value;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: entry.value,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: entry.key == 'space'
                  ? const RepaintBoundary(
                      key: ValueKey('visual-reference'),
                      child: AppBackdrop(
                        child: _VisualReference(capture: false),
                      ),
                    )
                  : const _VisualReference(),
            ),
          );
          if (entry.key == 'space') {
            final imageFinder =
                find.byKey(const ValueKey('space-backdrop-image'));
            final backdrop = tester.widget<Image>(imageFinder);
            await tester.runAsync(
              () => precacheImage(
                backdrop.image,
                tester.element(imageFinder),
              ),
            );
            await tester.pump();
          }
          await tester.pumpAndSettle();

          await expectLater(
            find.byKey(const ValueKey('visual-reference')),
            matchesGoldenFile(
              'goldens/visual-system-${entry.key}-${viewport.key}.png',
            ),
          );
        },
      );
    }
  }
}

class _VisualReference extends StatelessWidget {
  const _VisualReference({this.capture = true});

  final bool capture;

  @override
  Widget build(BuildContext context) {
    final content = ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const AppBrandMark(size: 34),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MyLifeGraph',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            'Calm personal OS',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'A clear day, at your pace.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Quiet surfaces, explicit states, and one visible next step.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: const [
                      AppStatusPill(label: 'Current'),
                      AppStatusPill(
                        label: 'Synced',
                        tone: AppStatusTone.info,
                      ),
                      AppStatusPill(
                        label: 'On track',
                        tone: AppStatusTone.success,
                      ),
                      AppStatusPill(
                        label: 'Needs review',
                        tone: AppStatusTone.attention,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const AppSurface(
                    variant: AppSurfaceVariant.subtle,
                    child: Row(
                      children: [
                        Expanded(
                          child: AppMetric(
                            value: '3/5',
                            label: 'Today completed',
                          ),
                        ),
                        Expanded(
                          child: AppMetric(
                            value: '09:30',
                            label: 'Next focus',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const AppStatePanel(
                    title: 'Availability may be incomplete',
                    message:
                        'Review your weekly schedule before confirming a plan.',
                    tone: AppStatusTone.attention,
                  ),
                  const SizedBox(height: 12),
                  const AppStatePanel(
                    title: 'Your draft is still here',
                    message:
                        'Reload saved data or retry the same request unchanged.',
                    tone: AppStatusTone.danger,
                  ),
                  const SizedBox(height: 16),
                  const TextField(
                    decoration: InputDecoration(
                      labelText: 'Plan title',
                      hintText: 'e.g. Read chapter 4',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton(
                        onPressed: _noop,
                        child: const Text('Confirm plan'),
                      ),
                      OutlinedButton(
                        onPressed: _noop,
                        child: const Text('Review'),
                      ),
                      const FilledButton(
                        onPressed: null,
                        child: Text('Unavailable'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      body: capture
          ? RepaintBoundary(
              key: const ValueKey('visual-reference'),
              child: content,
            )
          : content,
    );
  }

  static void _noop() {}
}

void _noop() {}
