import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_life_graph/composition/optimization_providers.dart';
import 'package:my_life_graph/composition/skillset_providers.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/insights/domain/entities/correlation.dart';
import 'package:my_life_graph/features/insights/domain/entities/insight.dart';
import 'package:my_life_graph/features/insights/domain/repositories/insights_repository.dart';
import 'package:my_life_graph/features/insights/presentation/pages/insights_page.dart';
import 'package:my_life_graph/features/insights/presentation/providers/insights_providers.dart';
import 'package:my_life_graph/features/optimization/domain/entities/skillset_profile.dart';

void main() {
  testWidgets(
    'Compare ignores out-of-order window responses across tab switches',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1280, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _WindowRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSurfaceCapabilitiesProvider.overrideWithValue(
              const AppSurfaceCapabilities(
                isLocalDemo: true,
                canUseSyncedHabits: false,
              ),
            ),
            skillsetPreferenceScopeProvider.overrideWith((_) => 'guest'),
            skillsetProfileProvider.overrideWith(
              (_) async => SkillsetProfile(
                userName: 'Synthetic',
                overallScore: 0,
                primaryArchetype: '',
                scores: const [],
                updatedAt: DateTime(2026, 9, 25),
              ),
            ),
            insightsRepositoryProvider.overrideWithValue(repository),
            personalPatternsProvider.overrideWith((_) async => null),
            sleepRecommendationProvider.overrideWith((_) async => null),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: InsightsPage()),
          ),
        ),
      );
      await tester.pump();
      repository.complete(14);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(InsightsPage)),
      );

      await tester.tap(find.text('30d'));
      await tester.pump();
      expect(repository.pending.containsKey(30), isTrue);
      await tester.tap(find.text('90d'));
      await tester.pump();
      expect(repository.pending.containsKey(90), isTrue);
      await tester.tap(find.text('Top patterns').first);
      await tester.pump();
      repository.complete(90);
      await tester.pumpAndSettle();
      expect(
        container.read(correlationReportProvider).requireValue.windowDays,
        90,
      );
      repository.complete(30);
      await tester.pumpAndSettle();
      expect(
        container.read(correlationReportProvider).requireValue.windowDays,
        90,
      );
      expect(container.read(insightsWindowDaysProvider), 90);

      await tester.tap(find.text('Compare').first);
      await tester.pumpAndSettle();
      final selected = tester.widget<SegmentedButton<int>>(
        find.byType(SegmentedButton<int>),
      );
      expect(selected.selected, {90});
      expect(tester.takeException(), isNull);
    },
  );
}

class _WindowRepository implements InsightsRepository {
  final pending = <int, Completer<List<CorrelationDataPoint>>>{};
  @override
  Future<List<Insight>> getInsights() async => const [];
  @override
  Future<List<CorrelationDataPoint>> getCorrelationDataPoints({
    required int windowDays,
  }) => (pending[windowDays] = Completer<List<CorrelationDataPoint>>()).future;

  void complete(int days) => pending[days]!.complete([
    for (var i = 0; i < days; i++)
      CorrelationDataPoint(
        date: DateTime(2026, 9, 25).subtract(Duration(days: i)),
        values: {
          'sleep_hours': 6 + (i % 4) / 2,
          'focus_minutes': 30 + (i % 4) * 10,
          'energy_level': 5 + (i % 4).toDouble(),
        },
      ),
  ]);
}
