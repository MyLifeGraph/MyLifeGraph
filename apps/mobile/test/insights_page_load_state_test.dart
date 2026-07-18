import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/insights/domain/entities/correlation.dart';
import 'package:my_life_graph/features/insights/domain/entities/insight.dart';
import 'package:my_life_graph/features/insights/presentation/pages/insights_page.dart';
import 'package:my_life_graph/features/insights/presentation/providers/insights_providers.dart';
import 'package:my_life_graph/features/optimization/domain/entities/skillset_profile.dart';
import 'package:my_life_graph/features/optimization/presentation/providers/optimization_providers.dart';

void main() {
  test('planned load names the current mutable workload projection', () {
    final metric = correlationMetrics.singleWhere(
      (candidate) => candidate.id == 'planned_minutes',
    );

    expect(metric.label, 'Current planned workload');
  });

  testWidgets('keeps an account insight failure distinct from empty evidence',
      (tester) async {
    var insightLoads = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _demoSurfaceOverride(),
          insightsProvider.overrideWith((ref) async {
            insightLoads += 1;
            if (insightLoads == 1) {
              throw StateError('account read failed');
            }
            return const [];
          }),
          correlationReportProvider.overrideWith(
            (ref) async => const CorrelationReport(
              windowDays: 14,
              metrics: correlationMetrics,
              points: [],
              results: [],
            ),
          ),
          skillsetProfileProvider.overrideWith(
            (ref) async => _skillsetProfile(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: InsightsPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load account insights.'), findsOneWidget);
    expect(
      find.textContaining('No demo patterns were substituted'),
      findsOneWidget,
    );
    expect(find.text('ONE OBSERVATION'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load account insights.'), findsNothing);
    expect(find.text('ONE OBSERVATION'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Focused Builder · 82 / 100'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Focused Builder · 82 / 100'), findsOneWidget);
    expect(insightLoads, 2);
  });

  testWidgets('skillset failure stays visible and retries independently',
      (tester) async {
    var skillsetLoads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _demoSurfaceOverride(),
          insightsProvider.overrideWith((ref) async => const []),
          correlationReportProvider.overrideWith(
            (ref) async => const CorrelationReport(
              windowDays: 14,
              metrics: correlationMetrics,
              points: [],
              results: [],
            ),
          ),
          skillsetProfileProvider.overrideWith((ref) async {
            skillsetLoads += 1;
            if (skillsetLoads == 1) {
              throw StateError('skillset read failed');
            }
            return _skillsetProfile();
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: InsightsPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Example skill profile unavailable.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Example skill profile unavailable.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('optional demo card could not be loaded'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Retry example'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry example'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Focused Builder · 82 / 100'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Focused Builder · 82 / 100'), findsOneWidget);
    expect(skillsetLoads, 2);
  });

  testWidgets('missing demo skillset remains an honest example error',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _demoSurfaceOverride(),
          insightsProvider.overrideWith((ref) async => const []),
          correlationReportProvider.overrideWith(
            (ref) async => const CorrelationReport(
              windowDays: 14,
              metrics: correlationMetrics,
              points: [],
              results: [],
            ),
          ),
          skillsetProfileProvider.overrideWith(
            (ref) async => throw const SkillsetProfileUnavailableException(
              'no generated row',
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: InsightsPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Example skill profile unavailable.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Example skill profile unavailable.'), findsOneWidget);
    expect(
      find.text(
        'This optional demo card could not be loaded. Your real activity was not scored or replaced.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('EXAMPLE SKILL PROFILE'),
      findsOneWidget,
    );
    expect(find.text('Retry example'), findsOneWidget);
  });

  testWidgets('real account hides the unproduced skillset without loading it',
      (tester) async {
    var skillsetLoads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _realSurfaceOverride(),
          insightsProvider.overrideWith((ref) async => const []),
          correlationReportProvider.overrideWith(
            (ref) async => const CorrelationReport(
              windowDays: 14,
              metrics: correlationMetrics,
              points: [],
              results: [],
            ),
          ),
          skillsetProfileProvider.overrideWith((ref) async {
            skillsetLoads += 1;
            return _skillsetProfile();
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: InsightsPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EXAMPLE SKILL PROFILE'), findsNothing);
    expect(find.text('Focused Builder · 82 / 100'), findsNothing);
    expect(skillsetLoads, 0);
  });

  testWidgets('light theme derives panel and header contrast from its scheme',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _loadedOverrides(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: InsightsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final panel = tester.widget<Container>(
      find.byKey(const Key('insights-observation-panel')),
    );
    final decoration = panel.decoration! as BoxDecoration;
    final headerDescription = tester.widget<Text>(
      find.byKey(const Key('insights-header-description')),
    );
    final refreshButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Refresh correlations'),
    );

    expect(decoration.color, AppTheme.light.colorScheme.surfaceContainerLow);
    expect(
      (decoration.border! as Border).top.color,
      AppTheme.light.colorScheme.outlineVariant,
    );
    expect(
      headerDescription.style?.color,
      AppTheme.light.colorScheme.onSurfaceVariant,
    );
    expect(
      refreshButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      AppTheme.light.colorScheme.onPrimary,
    );
  });

  testWidgets('advanced exploration ends at 90 days and labels null confidence',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _loadedOverrides(
          insights: const [
            Insight(
              id: 'insight-without-confidence',
              title: 'Stored pattern',
              summary: 'A stored observation without a confidence value.',
              confidence: null,
              tags: ['recovery'],
            ),
          ],
        ),
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: InsightsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Advanced correlation exploration'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Advanced correlation exploration'));
    await tester.pumpAndSettle();

    final selector = tester.widget<SegmentedButton<int>>(
      find.byType(SegmentedButton<int>),
    );
    expect(
      selector.segments.map((segment) => segment.value),
      insightsWindowDayOptions,
    );
    expect(find.text('All'), findsNothing);
    expect(find.text('Confidence not stored'), findsOneWidget);
    expect(
      find.text('Stored insights and previous notes'),
      findsOneWidget,
    );
    expect(find.text('Stored insights and previous AI notes'), findsNothing);
  });

  testWidgets('matrix cells expose their metric pair, result, and selection',
      (tester) async {
    final semantics = tester.ensureSemantics();
    const report = CorrelationReport(
      windowDays: 14,
      metrics: [
        CorrelationMetric(
          id: 'sleep_hours',
          label: 'Sleep',
          unit: 'h',
          category: 'Recovery',
          higherIsPositive: true,
        ),
        CorrelationMetric(
          id: 'focus_minutes',
          label: 'Focus',
          unit: 'min',
          category: 'Work',
          higherIsPositive: true,
        ),
      ],
      points: [],
      results: [
        CorrelationResult(
          metricAId: 'sleep_hours',
          metricBId: 'focus_minutes',
          sampleSize: 14,
          coefficient: 0.42,
          summary: 'Stored deterministic result.',
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _demoSurfaceOverride(),
          insightsProvider.overrideWith((ref) async => const []),
          correlationReportProvider.overrideWith((ref) async => report),
          skillsetProfileProvider.overrideWith(
            (ref) async => _skillsetProfile(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: InsightsPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Advanced correlation exploration'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Advanced correlation exploration'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Correlation matrix'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    final cell = find.byKey(
      const ValueKey(
        'insights-matrix-cell-sleep_hours-focus_minutes',
      ),
    );
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(cell),
      matchesSemantics(
        label: 'Sleep and Focus correlation. 0.42. Moderate positive',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  for (final textScale in [1.5, 2.0]) {
    testWidgets(
      'mobile pattern title and nullable confidence wrap at ${textScale}x',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const insight = Insight(
          id: 'responsive-null-confidence',
          title: 'A deliberately long stored pattern title for a small screen',
          summary: 'A stored observation without a confidence value.',
          confidence: null,
          tags: ['recovery'],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
            home: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: InsightsPatternTile(
                  insight: insight,
                  isMobile: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final title = find.byKey(
          const ValueKey(
            'insight-pattern-title-responsive-null-confidence',
          ),
        );
        final confidence = find.byKey(
          const ValueKey(
            'insight-pattern-confidence-responsive-null-confidence',
          ),
        );

        expect(title, findsOneWidget);
        expect(confidence, findsOneWidget);
        expect(
          tester.getTopLeft(confidence).dy,
          greaterThanOrEqualTo(
            tester.getBottomLeft(title).dy,
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

List<Override> _loadedOverrides({List<Insight> insights = const []}) => [
      _demoSurfaceOverride(),
      insightsProvider.overrideWith((ref) async => insights),
      correlationReportProvider.overrideWith(
        (ref) async => const CorrelationReport(
          windowDays: 14,
          metrics: correlationMetrics,
          points: [],
          results: [],
        ),
      ),
      skillsetProfileProvider.overrideWith((ref) async => _skillsetProfile()),
    ];

Override _demoSurfaceOverride() =>
    appSurfaceCapabilitiesProvider.overrideWithValue(
      const AppSurfaceCapabilities(
        isLocalDemo: true,
        canUseSyncedHabits: false,
      ),
    );

Override _realSurfaceOverride() =>
    appSurfaceCapabilitiesProvider.overrideWithValue(
      const AppSurfaceCapabilities(
        isLocalDemo: false,
        canUseSyncedHabits: true,
        canUseSyncedExecution: true,
      ),
    );

SkillsetProfile _skillsetProfile() => SkillsetProfile(
      userName: 'Alex',
      overallScore: 82,
      primaryArchetype: 'Focused Builder',
      scores: const [
        SkillScore(name: 'Recovery', score: 74, signal: 'Stable sleep'),
      ],
      updatedAt: DateTime.utc(2026, 7, 13, 10),
    );
