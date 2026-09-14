import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/insights/domain/entities/correlation.dart';
import 'package:my_life_graph/features/insights/domain/entities/skillset_display_preferences.dart';
import 'package:my_life_graph/features/insights/presentation/widgets/insights_skillset_card.dart';

const defaults = {
  'sleep',
  'sport',
  'energy',
  'social',
  'learning',
  'concentration',
};

CorrelationReport report(List<Map<String, double>> values) => CorrelationReport(
  windowDays: 14,
  metrics: correlationMetrics,
  points: [
    for (var i = 0; i < values.length; i++)
      CorrelationDataPoint(date: DateTime(2026, 9, i + 1), values: values[i]),
  ],
  results: const [],
);

Future<void> pumpCard(
  WidgetTester tester,
  CorrelationReport report, {
  double scale = 1,
  Set<String> selectedIds = defaults,
}) async {
  if (const bool.fromEnvironment('SKILLSET_PREVIEW')) {
    await (FontLoader('InstrumentSans')
          ..addFont(rootBundle.load('assets/fonts/InstrumentSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/InstrumentSans-SemiBold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/InstrumentSans-Bold.ttf')))
        .load();
    await (FontLoader('packages/phosphor_flutter/PhosphorRegular')..addFont(
          rootBundle.load('packages/phosphor_flutter/lib/fonts/Phosphor.ttf'),
        ))
        .load();
  }
  final selected = {...selectedIds};
  var chart = SkillsetChartView.radar;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => InsightsSkillsetCard(
              report: report,
              isDemo: false,
              selectedIds: selected,
              chartView: chart,
              onChartChanged: (value) => setState(() => chart = value),
              onToggle: (id) => setState(() {
                if (!selected.remove(id)) selected.add(id);
              }),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 1280.0]) {
    testWidgets('bar toggle keeps ratings and dimensions at $width', (
      tester,
    ) async {
      tester.view
        ..physicalSize = Size(width, 960)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpCard(
        tester,
        report([
          {'sleep_quality': 6, 'sport_activity': 0, 'energy_level': 4},
          {'sleep_quality': 8, 'sport_activity': 2, 'energy_level': 6},
        ]),
        scale: width == 320 ? 2 : 1,
      );
      final dynamic original = tester
          .widget<CustomPaint>(find.byKey(const Key('skillset-radar')))
          .painter;
      await tester.tap(find.byTooltip('Bar chart'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('skillset-radar')), findsNothing);
      expect(find.byKey(const Key('skillset-bars')), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('skillset-bar-sleep')),
            )
            .value,
        .7,
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('skillset-bar-sport')),
            )
            .value,
        .5,
      );
      expect(find.text('No data'), findsNWidgets(3));
      await tester.ensureVisible(find.byTooltip('Radar chart'));
      await tester.tap(find.byTooltip('Radar chart'));
      await tester.pumpAndSettle();
      final dynamic restored = tester
          .widget<CustomPaint>(find.byKey(const Key('skillset-radar')))
          .painter;
      expect(restored.values, original.values);
      expect(restored.labels, original.labels);
      expect(find.text('Dimensions (6)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('bars support one observed axis without scoring missing values', (
    tester,
  ) async {
    await pumpCard(
      tester,
      report([
        {'sport_activity': 0},
      ]),
    );
    expect(find.byKey(const Key('skillset-radar')), findsNothing);
    await tester.tap(find.byTooltip('Bar chart'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('skillset-bar-sport')),
          )
          .value,
      0,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('No data'), findsNWidgets(5));
  });
  testWidgets(
    'every supported dimension renders from its own source, including zero',
    (tester) async {
      await pumpCard(
        tester,
        report([
          {
            'sleep_quality': 7,
            'sport_activity': 0,
            'energy_level': 4,
            'social_activity': 1,
            'learning_completion_rate': 50,
            'focus_quality': 3,
            'stress_level': 2,
            'mood_score': 6,
            'useful_progress': 4,
            'study_motivation': 0,
            'regularity': 75,
          },
        ]),
        selectedIds: {
          ...defaults,
          'stress',
          'mood',
          'productivity',
          'motivation',
          'discipline',
        },
      );
      final dynamic radar = tester
          .widget<CustomPaint>(find.byKey(const Key('skillset-radar')))
          .painter;
      expect(radar.labels, hasLength(11));
      await tester.ensureVisible(find.text('Details'));
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sport · 0.0/2'), findsOneWidget);
      expect(find.textContaining('Motivation · 0.0/2'), findsOneWidget);
      expect(find.textContaining('Discipline · 75%'), findsOneWidget);
      expect(find.textContaining('Learning · 50%'), findsOneWidget);
      expect(find.textContaining('No data'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'Skillset uses real ratings without missing-value scores at $width',
      (tester) async {
        tester.view
          ..physicalSize = Size(width, 960)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpCard(
          tester,
          report([
            {
              'sleep_quality': 6,
              'energy_level': 4,
              'focus_quality': 2,
              'activity_level': 9,
            },
            {'sleep_quality': 8, 'energy_level': 8, 'focus_quality': 4},
            {
              'sleep_quality': double.nan,
              'energy_level': 99,
              'focus_quality': -1,
            },
          ]),
          scale: width == 320 ? 2 : 1,
        );
        expect(find.byKey(const Key('skillset-radar')), findsOneWidget);
        if (const bool.fromEnvironment('SKILLSET_PREVIEW')) {
          await expectLater(
            find.byType(Scaffold),
            matchesGoldenFile('../../../.tools/skillset-${width.toInt()}.png'),
          );
        }
        expect(find.textContaining('Sleep · 7.0/10 · 2 days'), findsNothing);
        final paint = tester.widget<CustomPaint>(
          find.byKey(const Key('skillset-radar')),
        );
        final dynamic radar = paint.painter;
        expect(radar.labels, ['Sleep', 'Energy', 'Focus']);
        await tester.ensureVisible(find.text('Details'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Details'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Sleep · 7.0/10 · 2 days'), findsOneWidget);
        expect(find.textContaining('Energy · 6.0/10 · 2 days'), findsOneWidget);
        expect(
          find.textContaining('Concentration · 3.0/5 · 2 days'),
          findsOneWidget,
        );
        expect(find.textContaining('Sport · No data'), findsOneWidget);
        expect(
          find.textContaining('Social activity · No data'),
          findsOneWidget,
        );
        expect(find.textContaining('Learning · No data'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Skillset empty state retains all dimensions; window belongs to the page',
    (tester) async {
      await pumpCard(tester, report([]));
      expect(find.byKey(const Key('skillset-radar')), findsNothing);
      expect(find.text('No ratings in this window yet.'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      await tester.tap(find.text('Dimensions (6)'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .map((tile) => (tile.title! as Text).data),
        [
          'Sleep',
          'Sport',
          'Energy',
          'Social activity',
          'Learning',
          'Concentration',
          'Stress',
          'Mood',
          'Productivity',
          'Motivation',
          'Discipline',
        ],
      );
      for (final id in defaults) {
        tester
            .widget<CheckboxListTile>(
              find.byKey(ValueKey('skillset-select-$id')),
            )
            .onChanged!(false);
        await tester.pumpAndSettle();
      }
      expect(find.text('Dimensions (0)'), findsOneWidget);
      expect(
        find.text('Choose dimensions to see your profile.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
