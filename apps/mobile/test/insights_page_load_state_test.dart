import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/insights/domain/entities/correlation.dart';
import 'package:my_life_graph/features/insights/domain/entities/insight.dart';
import 'package:my_life_graph/features/insights/domain/entities/personal_patterns.dart';
import 'package:my_life_graph/features/insights/domain/entities/sleep_recommendation.dart';
import 'package:my_life_graph/features/insights/presentation/pages/insights_page.dart';
import 'package:my_life_graph/features/insights/presentation/providers/insights_providers.dart';
import 'package:my_life_graph/features/optimization/domain/entities/skillset_profile.dart';
import 'package:my_life_graph/composition/optimization_providers.dart';

const _fingerprint =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  test('advanced metrics omit unversioned plan and habit reconstructions', () {
    final ids = correlationMetrics.map((candidate) => candidate.id).toSet();

    expect(ids, isNot(contains('planned_minutes')));
    expect(ids, isNot(contains('habit_completion_rate')));
    expect(ids, containsAll(['focus_quality', 'useful_progress']));
  });

  test('daily metric labels and evidence timing stay explicit', () {
    final byId = {
      for (final metric in correlationMetrics) metric.id: metric,
    };

    expect(byId['sleep_hours']?.label, 'Previous-night sleep');
    expect(
      byId['sleep_hours']?.timing,
      CorrelationEvidenceTiming.previousNightOnLocalWakeDay,
    );
    expect(
      byId['sleep_quality']?.label,
      'Previous-night sleep quality',
    );
    expect(
      byId['sleep_target_deviation_minutes']?.label,
      'Sleep shortfall',
    );
    expect(byId['focus_minutes']?.label, 'Rated focus time');
    expect(byId['planned_focus_minutes']?.label, 'Planned focus time');
    expect(byId['focus_quality']?.label, 'Rated focus quality');
    expect(byId['useful_progress']?.label, 'Rated useful progress');
    expect(
      byId['focus_completion_rate']?.label,
      'Rated session completion',
    );
  });

  test('backend points aggregate in the profile-local response window', () {
    final patterns = _personalPatterns();

    final points = patterns.correlationDataPoints(windowDays: 14);

    expect(points, hasLength(1));
    expect(points.single.date, DateTime.utc(2026, 7, 25));
    expect(points.single.values['focus_minutes'], 65);
    expect(points.single.values['planned_focus_minutes'], 75);
    expect(points.single.values['focus_quality'], 3.5);
    expect(points.single.values['useful_progress'], 4.5);
    expect(points.single.values['sleep_target_deviation_minutes'], 15);
    expect(points.single.values, isNot(contains('planned_minutes')));
    expect(points.single.values, isNot(contains('habit_completion_rate')));
  });

  test('local demo sleep provider stops before its API dependency', () async {
    var apiDependencyReads = 0;
    final container = ProviderContainer(
      overrides: [
        _demoSurfaceOverride(),
        sleepRecommendationApiDataSourceProvider.overrideWith((ref) {
          apiDependencyReads += 1;
          throw StateError('The API dependency must remain untouched.');
        }),
      ],
    );
    addTearDown(container.dispose);

    final value = await container.read(sleepRecommendationProvider.future);

    expect(value, isNull);
    expect(apiDependencyReads, 0);
  });

  for (final status in [
    SleepRecommendationStatus.disabled,
    SleepRecommendationStatus.collecting,
    SleepRecommendationStatus.unstable,
    SleepRecommendationStatus.ready,
  ]) {
    testWidgets('sleep recommendation renders ${status.name} at 320px and 200%',
        (tester) async {
      tester.view
        ..physicalSize = const Size(320, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _realSurfaceOverride(),
            insightsProvider.overrideWith((ref) async => const []),
            correlationReportProvider.overrideWith(
              (ref) async => const CorrelationReport(
                windowDays: 14,
                metrics: [],
                points: [],
                results: [],
              ),
            ),
            personalPatternsProvider.overrideWith(
              (ref) async => _personalPatterns(),
            ),
            sleepRecommendationProvider.overrideWith(
              (ref) async => _sleepRecommendation(status),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
              ),
              child: child!,
            ),
            home: const Scaffold(body: InsightsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(Key('sleep-recommendation-${status.name}')),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(
        find.byKey(Key('sleep-recommendation-${status.name}')),
        findsOneWidget,
      );
      if (status == SleepRecommendationStatus.ready) {
        expect(find.text('Best-supported sleep window'), findsOneWidget);
        expect(find.text('Sleep start'), findsOneWidget);
        expect(find.text('Wake time'), findsOneWidget);
        expect(find.text('Following local day'), findsOneWidget);
        expect(find.text('Duration'), findsOneWidget);
        expect(
          find.byKey(const Key('sleep-recommendation-warning')),
          findsOneWidget,
        );
      } else {
        expect(find.text('No stable window yet'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('same-day sleep recommendation labels the wake day explicitly',
      (tester) async {
    tester.view
      ..physicalSize = const Size(320, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _realSurfaceOverride(),
          insightsProvider.overrideWith((ref) async => const []),
          correlationReportProvider.overrideWith(
            (ref) async => const CorrelationReport(
              windowDays: 14,
              metrics: [],
              points: [],
              results: [],
            ),
          ),
          personalPatternsProvider.overrideWith(
            (ref) async => _personalPatterns(),
          ),
          sleepRecommendationProvider.overrideWith(
            (ref) async => _sleepRecommendation(
              SleepRecommendationStatus.ready,
              wakeDayOffset: 0,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const Scaffold(body: InsightsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('sleep-recommendation-ready')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Same local day'), findsOneWidget);
    expect(find.text('Following local day'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sleep recommendation loading is readable at 320px and 200%',
      (tester) async {
    tester.view
      ..physicalSize = const Size(320, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<SleepRecommendation?>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _realSurfaceOverride(),
          insightsProvider.overrideWith((ref) async => const []),
          correlationReportProvider.overrideWith(
            (ref) async => const CorrelationReport(
              windowDays: 14,
              metrics: [],
              points: [],
              results: [],
            ),
          ),
          personalPatternsProvider.overrideWith(
            (ref) async => _personalPatterns(),
          ),
          sleepRecommendationProvider.overrideWith((ref) => pending.future),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const Scaffold(body: InsightsPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('sleep-recommendation-loading')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Loading sleep recommendation…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    pending.complete();
    await tester.pumpAndSettle();
  });

  for (final theme in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
    'space': AppTheme.space,
  }.entries) {
    testWidgets('ready sleep recommendation renders on desktop ${theme.key}',
        (tester) async {
      tester.view
        ..physicalSize = const Size(1280, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _realSurfaceOverride(),
            insightsProvider.overrideWith((ref) async => const []),
            correlationReportProvider.overrideWith(
              (ref) async => const CorrelationReport(
                windowDays: 14,
                metrics: [],
                points: [],
                results: [],
              ),
            ),
            personalPatternsProvider.overrideWith(
              (ref) async => _personalPatterns(),
            ),
            sleepRecommendationProvider.overrideWith(
              (ref) async => _sleepRecommendation(
                SleepRecommendationStatus.ready,
              ),
            ),
          ],
          child: MaterialApp(
            theme: theme.value,
            home: const Scaffold(body: InsightsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('sleep-recommendation-ready')),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Best-supported sleep window'), findsOneWidget);
      expect(find.text('Sleep start'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sleep recommendation failure stays inside its own card',
      (tester) async {
    tester.view
      ..physicalSize = const Size(320, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _realSurfaceOverride(),
          insightsProvider.overrideWith((ref) async => const []),
          correlationReportProvider.overrideWith(
            (ref) async => const CorrelationReport(
              windowDays: 14,
              metrics: [],
              points: [],
              results: [],
            ),
          ),
          personalPatternsProvider.overrideWith(
            (ref) async => _personalPatterns(),
          ),
          sleepRecommendationProvider.overrideWith(
            (ref) async => throw StateError('sleep unavailable'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.space,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const Scaffold(body: InsightsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('sleep-recommendation-error')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      find.text('Sleep evidence is temporarily unavailable.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('personal-study-pattern-panel')),
      findsOneWidget,
    );
    expect(find.text('Could not load account insights.'), findsNothing);
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
          personalPatternsProvider.overrideWith(
            (ref) async => _personalPatterns(),
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
          personalPatternsProvider.overrideWith(
            (ref) async => _personalPatterns(),
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
          personalPatternsProvider.overrideWith(
            (ref) async => _personalPatterns(),
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
    expect(find.text('PERSONAL STUDY PATTERN'), findsOneWidget);
    expect(find.text('ONE OBSERVATION'), findsNothing);
  });

  testWidgets('real account shows stable personal evidence and limitations',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _realSurfaceOverride(),
          insightsProvider.overrideWith((ref) async => const []),
          correlationReportProvider.overrideWith(
            (ref) async => const CorrelationReport(
              windowDays: 14,
              metrics: [],
              points: [],
              results: [],
            ),
          ),
          personalPatternsProvider.overrideWith(
            (ref) async => _personalPatterns(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: InsightsPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('personal-study-pattern-panel')),
      findsOneWidget,
    );
    expect(find.textContaining('stable baseline'), findsOneWidget);
    expect(find.text('Stable'), findsOneWidget);
    expect(find.text('20 rated sessions'), findsOneWidget);
    expect(find.text('ONE OBSERVATION'), findsNothing);

    await tester.ensureVisible(find.text('Evidence and limits'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Evidence and limits'));
    await tester.pumpAndSettle();
    expect(find.text('Focus timing'), findsOneWidget);
    expect(
      find.textContaining('observational associations'),
      findsOneWidget,
    );
  });

  testWidgets('disabled personal analysis still names its evidence context',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _realSurfaceOverride(),
          insightsProvider.overrideWith((ref) async => const []),
          correlationReportProvider.overrideWith(
            (ref) async => const CorrelationReport(
              windowDays: 14,
              metrics: [],
              points: [],
              results: [],
            ),
          ),
          personalPatternsProvider.overrideWith(
            (ref) async => _disabledPersonalPatterns(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: InsightsPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Disabled'), findsOneWidget);
    expect(find.text('0 rated sessions'), findsOneWidget);
    expect(find.text('0% coverage'), findsOneWidget);
    expect(find.text('90-day window'), findsOneWidget);
    expect(find.text('Europe/Berlin · 0 rated days'), findsOneWidget);
    expect(
      find.text('Pattern analysis is turned off in Personal learning.'),
      findsOneWidget,
    );
  });

  testWidgets('personal pattern failure stays inside its compact card',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _realSurfaceOverride(),
          insightsProvider.overrideWith((ref) async => const []),
          correlationReportProvider.overrideWith(
            (ref) async => const CorrelationReport(
              windowDays: 14,
              metrics: [],
              points: [],
              results: [],
            ),
          ),
          personalPatternsProvider.overrideWith(
            (ref) async => throw StateError('patterns unavailable'),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: InsightsPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Personal evidence is temporarily unavailable.'),
      findsOneWidget,
    );
    expect(find.text('Could not load account insights.'), findsNothing);
    expect(
      find.textContaining('No local estimate was substituted'),
      findsOneWidget,
    );
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

  testWidgets(
      'every correlation-window switch keeps exploration open and scroll stable',
      (tester) async {
    final requestedWindows = <int>[];
    final pendingWindows = <int>[];
    final pendingReports = <Completer<CorrelationReport>>[];
    var isInitialRequest = true;

    CorrelationReport reportFor({
      required int windowDays,
      required int sampleSize,
      required String summary,
    }) =>
        CorrelationReport(
          windowDays: windowDays,
          metrics: correlationMetrics,
          points: const [],
          results: [
            CorrelationResult(
              metricAId: 'sleep_hours',
              metricBId: 'useful_progress',
              sampleSize: sampleSize,
              coefficient: 0.42,
              summary: summary,
            ),
          ],
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _demoSurfaceOverride(),
          insightsProvider.overrideWith((ref) async => const []),
          correlationReportProvider.overrideWith((ref) {
            final windowDays = ref.watch(insightsWindowDaysProvider);
            requestedWindows.add(windowDays);
            if (isInitialRequest) {
              isInitialRequest = false;
              return Future.value(
                reportFor(
                  windowDays: windowDays,
                  sampleSize: 14,
                  summary: 'Fourteen-day chart data.',
                ),
              );
            }
            final pending = Completer<CorrelationReport>();
            pendingWindows.add(windowDays);
            pendingReports.add(pending);
            return pending.future;
          }),
          skillsetProfileProvider.overrideWith(
            (ref) async => _skillsetProfile(),
          ),
        ],
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
    await tester.scrollUntilVisible(
      find.text('90d'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final scrollOffsetBefore = scrollable.position.pixels;
    expect(scrollOffsetBefore, greaterThan(0));
    expect(find.text('Trend overlay'), findsOneWidget);
    expect(find.text('Fourteen-day chart data.'), findsOneWidget);

    var visibleSummary = 'Fourteen-day chart data.';
    Future<void> selectWindow(int windowDays) async {
      final pendingBefore = pendingReports.length;
      await tester.tap(find.text('${windowDays}d'));
      await tester.pump();

      expect(requestedWindows.last, windowDays);
      expect(pendingReports, hasLength(pendingBefore + 1));
      expect(pendingWindows.last, windowDays);
      expect(find.text('Trend overlay'), findsOneWidget);
      expect(find.text(visibleSummary), findsOneWidget);
      expect(
        scrollable.position.pixels,
        closeTo(scrollOffsetBefore, 0.01),
      );
      expect(
        tester
            .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
            .selected,
        {windowDays},
      );

      final nextSummary =
          'Window $windowDays chart data request ${pendingReports.length}.';
      pendingReports.last.complete(
        reportFor(
          windowDays: windowDays,
          sampleSize: 42,
          summary: nextSummary,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trend overlay'), findsOneWidget);
      expect(find.text(nextSummary), findsOneWidget);
      expect(
        scrollable.position.pixels,
        closeTo(scrollOffsetBefore, 0.01),
      );
      visibleSummary = nextSummary;
    }

    // Starting at 14d, this path exercises every directed switch between the
    // four available windows exactly once.
    for (final windowDays in [7, 30, 14, 90, 30, 7, 90, 14, 30, 90, 7, 14]) {
      await selectWindow(windowDays);
    }

    expect(tester.takeException(), isNull);
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

  testWidgets('overlapping matrix signals are neutral and not selectable',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: _loadedOverrides(),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: InsightsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openCorrelationMatrix(tester);

    final cell = find.byKey(
      const ValueKey(
        'insights-matrix-cell-sleep_hours-sleep_target_deviation_minutes',
      ),
    );
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(cell),
      matchesSemantics(
        label: 'Previous-night sleep and Sleep shortfall. '
            'Not compared · overlapping signals',
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
    expect(find.text('Not compared\n· overlapping signals'), findsWidgets);
    semantics.dispose();
  });

  testWidgets('desktop correlation matrix keeps long axis labels readable',
      (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 960)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _loadedOverrides(),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: InsightsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openCorrelationMatrix(tester);

    expect(
      find.textContaining(
        'Previous-night sleep is placed on the local wake and Focus day.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Focus values include rated sessions only.'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Each line is normalized relative to its own range.',
      ),
      findsOneWidget,
    );

    const columnKey = ValueKey(
      'insights-matrix-column-sleep_target_deviation_minutes',
    );
    const rowKey = ValueKey(
      'insights-matrix-row-sleep_target_deviation_minutes',
    );
    final column = find.byKey(columnKey);
    final row = find.byKey(rowKey);

    expect(tester.getSize(column).width, greaterThanOrEqualTo(88));
    expect(tester.getSize(row).width, greaterThanOrEqualTo(196));
    _expectMatrixLabelFits(tester, column, 'Sleep shortfall');
    _expectMatrixLabelFits(tester, row, 'Sleep shortfall');

    final rowLeftBefore = tester.getTopLeft(row).dx;
    final horizontalScroll = find.descendant(
      of: find.byKey(
        const ValueKey('insights-correlation-matrix-grid'),
      ),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.right,
      ),
    );
    await tester.drag(horizontalScroll, const Offset(-480, 0));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(row).dx, rowLeftBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets('matrix labels remain complete at 320px and 200 percent text',
      (tester) async {
    tester.view
      ..physicalSize = const Size(320, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _loadedOverrides(),
        child: MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const Scaffold(body: InsightsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openCorrelationMatrix(tester);

    const columnKey = ValueKey(
      'insights-matrix-column-sleep_target_deviation_minutes',
    );
    const rowKey = ValueKey(
      'insights-matrix-row-sleep_target_deviation_minutes',
    );
    _expectMatrixLabelFits(
      tester,
      find.byKey(columnKey),
      'Sleep shortfall',
    );
    _expectMatrixLabelFits(
      tester,
      find.byKey(rowKey),
      'Sleep shortfall',
    );
    expect(tester.takeException(), isNull);
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

Future<void> _openCorrelationMatrix(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Advanced correlation exploration'),
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.text('Advanced correlation exploration'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Advanced correlation exploration'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Correlation matrix'),
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void _expectMatrixLabelFits(
  WidgetTester tester,
  Finder container,
  String label,
) {
  final textFinder = find.descendant(
    of: container,
    matching: find.text(label),
  );
  final widget = tester.widget<Text>(textFinder);
  final context = tester.element(textFinder);
  final renderBox = tester.renderObject<RenderBox>(textFinder);
  final style = DefaultTextStyle.of(context).style.merge(widget.style);
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: Directionality.of(context),
    textScaler: widget.textScaler ?? MediaQuery.textScalerOf(context),
    maxLines: widget.maxLines,
  )..layout(maxWidth: renderBox.size.width);

  expect(widget.overflow, isNot(TextOverflow.ellipsis));
  expect(
    painter.didExceedMaxLines,
    isFalse,
    reason: '$label did not fit ${renderBox.size.width}px',
  );
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

SleepRecommendation _sleepRecommendation(
  SleepRecommendationStatus status, {
  int wakeDayOffset = 1,
}) {
  final statusCode = status.name;
  final ready = status == SleepRecommendationStatus.ready;
  final reason = switch (status) {
    SleepRecommendationStatus.disabled => 'analysis_disabled',
    SleepRecommendationStatus.collecting => 'insufficient_eligible_days',
    SleepRecommendationStatus.unstable => 'mixed_focus_outcomes',
    SleepRecommendationStatus.ready => 'ready',
  };
  return SleepRecommendation.fromJson({
    'contract_version': sleepRecommendationContractVersion,
    'status': statusCode,
    'reason': reason,
    'generated_at': '2026-07-30T12:00:00Z',
    'timezone': 'Europe/Berlin',
    'window': {
      'rolling_days': 90,
      'starts_at': '2026-05-01T12:00:00Z',
      'ends_at': '2026-07-30T12:00:00Z',
      'local_starts_on': '2026-05-01',
      'local_ends_on': '2026-07-30',
    },
    'sample': {
      'valid_nights': status == SleepRecommendationStatus.disabled ? 0 : 30,
      'eligible_focus_days': status == SleepRecommendationStatus.disabled
          ? 0
          : status == SleepRecommendationStatus.collecting
              ? 22
              : 30,
      'rated_sessions': status == SleepRecommendationStatus.disabled ? 0 : 34,
      'required_eligible_days': 30,
      'progress': status == SleepRecommendationStatus.disabled
          ? '0/30'
          : status == SleepRecommendationStatus.collecting
              ? '22/30'
              : '30/30',
    },
    'recommendation': ready
        ? {
            'bedtime': {
              'start_local_time': '22:45',
              'end_local_time': '23:15',
              'end_day_offset': 0,
              'width_minutes': 30,
            },
            'wake_time': {
              'start_local_time': '06:45',
              'end_local_time': '07:15',
              'end_day_offset': 0,
              'width_minutes': 30,
            },
            'duration': {
              'minimum_minutes': 465,
              'maximum_minutes': 495,
            },
            'wake_day_offset': wakeDayOffset,
            'raw_median_duration_minutes': 480,
            'median_confirmed_sleep_target_minutes': 510,
            'warning': 'below_confirmed_sleep_target',
            'evidence': {
              'candidate_days': 15,
              'comparison_days': 15,
              'morning_readiness_median_delta': 1.0,
              'sleep_quality_median_delta': 1.0,
              'morning_energy_median_delta': 1.0,
              'useful_progress_median_delta': 1.0,
              'focus_quality_median_delta': 0.0,
              'completion_rate_delta': 0.0,
              'consistent_in_both_halves': true,
            },
            'evidence_fingerprint': _fingerprint,
          }
        : null,
    'summary': ready
        ? 'This best-supported sleep window is associated with stronger mornings.'
        : status == SleepRecommendationStatus.disabled
            ? 'Sleep recommendation analysis is turned off.'
            : 'No stable window yet. Keep collecting comparable days.',
    'limitations': ready
        ? ['This is an observed association, not a causal claim.']
        : ['No recommendation is shown without stable evidence.'],
  });
}

PersonalPatterns _personalPatterns() => PersonalPatterns.fromJson({
      'contract_version': 'personal-patterns-v1',
      'status': 'stable',
      'generated_at': '2026-07-26T12:00:00Z',
      'timezone': 'Europe/Berlin',
      'window': {
        'rolling_days': 90,
        'starts_at': '2026-04-27T12:00:00Z',
        'ends_at': '2026-07-26T12:00:00Z',
        'local_starts_on': '2026-04-27',
        'local_ends_on': '2026-07-26',
      },
      'summary':
          'A stable baseline now covers 20 rated sessions. Morning sessions were associated with higher useful progress.',
      'sample': {
        'terminal_sessions': 20,
        'rated_sessions': 20,
        'rated_local_days': 20,
        'rating_coverage': 1.0,
        'first_rated_local_date': '2026-06-16',
        'last_rated_local_date': '2026-07-25',
      },
      'baseline': {
        'median_focus_quality': 4.0,
        'median_useful_progress': 4.0,
        'completion_rate': 0.9,
      },
      'patterns': [
        {
          'kind': 'focus_timing',
          'maturity': 'stable',
          'title': 'Focus timing',
          'summary':
              'Sessions starting 09:00–13:00 were associated with higher median useful progress.',
          'evidence': {
            'preferred_group': '09:00–13:00',
            'comparison_group': 'other daytime windows',
            'preferred_count': 10,
            'comparison_count': 10,
            'useful_progress_median_delta': 1.0,
            'focus_quality_median_delta': 0.0,
            'completion_rate_delta': 0.0,
            'details': [
              'Median useful progress 5.0 vs 4.0.',
              '10 preferred-window days and 10 comparison days.',
            ],
          },
        },
      ],
      'planner_preference': {
        'eligible': true,
        'reason': 'eligible',
        'window': '09-13',
        'window_label': '09:00–13:00',
        'evidence_count': 20,
        'evidence_starts_on': '2026-06-16',
        'evidence_ends_on': '2026-07-25',
        'evidence_fingerprint': _fingerprint,
      },
      'limitations': [
        'These are observational associations and do not show cause.',
        'Missing reflections are excluded rather than scored as zero.',
      ],
      'correlation_points': [
        {
          'local_date': '2026-07-25',
          'local_started_at': '2026-07-25T09:00:00+02:00',
          'focus_quality': 4,
          'useful_progress': 5,
          'planned_focus_minutes': 45,
          'actual_focus_minutes': 45,
          'completed': 1,
          'sleep_hours': 7.5,
          'sleep_target_deviation_minutes': -30,
          'sleep_quality': 7,
          'morning_energy': 6,
        },
        {
          'local_date': '2026-07-25',
          'local_started_at': '2026-07-25T14:00:00+02:00',
          'focus_quality': 3,
          'useful_progress': 4,
          'planned_focus_minutes': 30,
          'actual_focus_minutes': 20,
          'completed': 0,
          'sleep_hours': 7.5,
          'sleep_target_deviation_minutes': 15,
          'sleep_quality': 7,
          'morning_energy': 6,
        },
      ],
      'evidence_fingerprint': _fingerprint,
    });

PersonalPatterns _disabledPersonalPatterns() => PersonalPatterns(
      status: PersonalPatternsStatus.disabled,
      summary: 'Personal pattern analysis is off.',
      timezone: 'Europe/Berlin',
      window: PersonalPatternsWindow(
        startsAt: DateTime.utc(2026, 4, 27, 12),
        endsAt: DateTime.utc(2026, 7, 26, 12),
        localStartsOn: DateTime.utc(2026, 4, 27),
        localEndsOn: DateTime.utc(2026, 7, 26),
      ),
      sample: const PersonalPatternsSample(
        terminalSessions: 0,
        ratedSessions: 0,
        ratedLocalDays: 0,
        ratingCoverage: 0,
        firstRatedLocalDate: null,
        lastRatedLocalDate: null,
      ),
      baseline: null,
      patterns: const [],
      plannerPreference: const LearnedPlannerPreference(
        eligible: false,
        reason: 'analysis_disabled',
        window: null,
        windowLabel: null,
        evidenceCount: 0,
      ),
      limitations: const [
        'Pattern analysis is turned off in Personal learning.',
      ],
      correlationPoints: const [],
      evidenceFingerprint: null,
    );
