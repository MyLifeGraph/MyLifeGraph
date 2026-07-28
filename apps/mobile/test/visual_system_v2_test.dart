import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_motion_tokens.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/theme/app_visual_tokens.dart';
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
    };

    for (final entry in expectations.entries) {
      final tokens = entry.key.extension<AppVisualTokens>()!;
      expect(tokens.background, entry.value.background);
      expect(tokens.surface, entry.value.surface);
      expect(tokens.textPrimary, entry.value.text);
      expect(tokens.brand, entry.value.mint);
      expect(entry.key.textTheme.bodyLarge?.fontFamily, 'InstrumentSans');
      expect(entry.key.extension<AppMotionTokens>(), isNotNull);
    }
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
  });

  for (final entry in {
    'dark': AppTheme.dark,
    'light': AppTheme.light,
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
              home: const _VisualReference(),
            ),
          );
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
  const _VisualReference();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RepaintBoundary(
        key: const ValueKey('visual-reference'),
        child: ColoredBox(
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
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
        ),
      ),
    );
  }

  static void _noop() {}
}
