import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_life_graph/composition/skillset_providers.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/insights/presentation/pages/insights_page.dart';
import 'package:my_life_graph/features/insights/presentation/providers/insights_providers.dart';

import 'checkin_correlations_test.dart' as checkin;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final pane in ['Compare', 'Top patterns']) {
    testWidgets(
      '$pane retains correlations and exposes retry when their real source refresh fails',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var patternReads = 0;
        final patterns = checkin.fixture(14);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appSurfaceCapabilitiesProvider.overrideWithValue(
                const AppSurfaceCapabilities(
                  isLocalDemo: false,
                  canUseSyncedHabits: true,
                  canUseSyncedExecution: true,
                ),
              ),
              skillsetPreferenceScopeProvider.overrideWith((_) => 'guest'),
              insightsProvider.overrideWith((_) async => const []),
              personalPatternsProvider.overrideWith((_) async {
                patternReads++;
                if (patternReads == 2) {
                  throw StateError(
                    'Controlled personal-pattern refresh failure',
                  );
                }
                return patterns;
              }),
              sleepRecommendationProvider.overrideWith((_) async => null),
              // Keep the production derived provider: overriding it would hide
              // lost upstream errors behind a different data flow.
            ],
            child: MaterialApp(
              theme: AppTheme.dark,
              home: const Scaffold(body: InsightsPage()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Advanced'));
        await tester.pumpAndSettle();
        if (pane == 'Top patterns') {
          await tester.tap(find.text('Top patterns').first);
          await tester.pumpAndSettle();
        }

        final container = ProviderScope.containerOf(
          tester.element(find.byType(InsightsPage)),
        );
        final before = container
            .read(correlationReportProvider)
            .requireValue
            .resultFor('sleep_hours', 'energy_level')!;
        expect(before.sampleSize, 14);
        expect(before.coefficient, closeTo(1, 1e-10));

        container.invalidate(personalPatternsProvider);
        await tester.pumpAndSettle();

        expect(patternReads, 2);
        expect(container.read(personalPatternsProvider).hasError, isTrue);
        final retained = container
            .read(correlationReportProvider)
            .requireValue
            .resultFor('sleep_hours', 'energy_level')!;
        expect(retained.sampleSize, before.sampleSize);
        expect(retained.coefficient, before.coefficient);
        expect(retained.isCheckInEvidence, before.isCheckInEvidence);
        expect(
          find.text('Could not load account insights.'),
          findsOneWidget,
          reason: 'Advanced must disclose the failure of its upstream read.',
        );
        final retry = find.widgetWithText(OutlinedButton, 'Retry');
        expect(retry, findsOneWidget);

        await tester.tap(find.text('Overview'));
        await tester.pumpAndSettle();
        expect(
          find.text('Could not load account insights.'),
          findsNothing,
          reason: 'Overview keeps its existing independent card error.',
        );
        await tester.tap(find.text('Advanced'));
        await tester.pumpAndSettle();
        expect(find.text('Could not load account insights.'), findsOneWidget);

        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await tester.pumpAndSettle();

        expect(patternReads, 3);
        expect(container.read(personalPatternsProvider).hasError, isFalse);
        expect(find.text('Could not load account insights.'), findsNothing);
        expect(find.text('Advanced'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
