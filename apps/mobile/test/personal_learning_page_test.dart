import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/projection_refresh_providers.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/features/learning/domain/learning_preferences.dart';
import 'package:my_life_graph/features/learning/domain/learning_repository.dart';
import 'package:my_life_graph/features/learning/presentation/pages/personal_learning_page.dart';
import 'package:my_life_graph/features/learning/presentation/providers/learning_providers.dart';

void main() {
  testWidgets('analysis disables learned planning and saves the full state',
      (tester) async {
    final repository = _LearningRepository(
      preferences: LearningPreferences(
        revision: 2,
        focusReflectionPromptEnabled: true,
        personalPatternAnalysisEnabled: true,
        learnedFocusPlanningEnabled: true,
        updatedAt: DateTime.utc(2026, 7, 26, 8),
      ),
    );
    await _pumpPage(tester, repository: repository, pilotEnabled: true);

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(
              const ValueKey('learned-focus-planning-setting'),
            ),
          )
          .value,
      isTrue,
    );
    await tester.tap(
      find.byKey(const ValueKey('personal-pattern-analysis-setting')),
    );
    await tester.pump();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(
              const ValueKey('learned-focus-planning-setting'),
            ),
          )
          .value,
      isFalse,
    );

    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('personal-learning-save')),
    );
    await tester.pumpAndSettle();
    expect(repository.updates, hasLength(1));
    final update = repository.updates.single;
    expect(update.expectedRevision, 2);
    expect(update.focusReflectionPromptEnabled, isTrue);
    expect(update.personalPatternAnalysisEnabled, isFalse);
    expect(update.learnedFocusPlanningEnabled, isFalse);
  });

  testWidgets('learned planning stays unavailable outside the pilot',
      (tester) async {
    final repository = _LearningRepository();
    await _pumpPage(tester, repository: repository, pilotEnabled: false);

    final tile = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('learned-focus-planning-setting')),
    );
    expect(tile.value, isFalse);
    expect(tile.onChanged, isNull);
    expect(
      find.text(
        'This optional Planner pilot is not enabled in this build.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('clear uses confirmation and preserves finished sessions copy',
      (tester) async {
    final repository = _LearningRepository();
    final invalidations = <ProductProjection>[];
    await _pumpPage(
      tester,
      repository: repository,
      pilotEnabled: true,
      invalidations: invalidations,
    );

    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('clear-focus-reflection-history')),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('keeps finished Focus sessions'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('confirm-clear-focus-reflections')),
    );
    await tester.pumpAndSettle();

    expect(repository.clearRequests, hasLength(1));
    expect(repository.clearRequests.single.expectedRevision, 0);
    expect(
      find.byKey(const ValueKey('focus-reflections-cleared-result')),
      findsOneWidget,
    );
    expect(find.text('3 reflections cleared.'), findsOneWidget);
    expect(invalidations, [ProductProjection.todayFullWeek]);
  });

  testWidgets('exact clear retry invalidates Full week after confirmed success',
      (tester) async {
    final repository = _LearningRepository(unknownClearAttempts: 1);
    final invalidations = <ProductProjection>[];
    await _pumpPage(
      tester,
      repository: repository,
      pilotEnabled: true,
      invalidations: invalidations,
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('clear-focus-reflection-history')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-clear-focus-reflections')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Retry unchanged'), findsOneWidget);
    expect(invalidations, isEmpty);
    expect(repository.clearRequests, hasLength(1));

    await tester.tap(find.text('Retry unchanged'));
    await tester.pumpAndSettle();

    expect(repository.clearRequests, hasLength(2));
    expect(
      repository.clearRequests[1].requestId,
      repository.clearRequests[0].requestId,
    );
    expect(invalidations, [ProductProjection.todayFullWeek]);
    expect(find.text('3 reflections cleared.'), findsOneWidget);
    expect(find.text('Focus reflection history cleared.'), findsOneWidget);
  });

  testWidgets('page fits 320 pixels at 200 percent text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _LearningRepository();
    await _pumpPage(
      tester,
      repository: repository,
      pilotEnabled: true,
      textScale: 2,
    );
    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(find.text('Analyze my study patterns'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _LearningRepository repository,
  required bool pilotEnabled,
  double textScale = 1,
  List<ProductProjection>? invalidations,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig(
            environment: 'test',
            supabaseUrl: 'http://localhost:54321',
            supabaseAnonKey: 'anon',
            aiServiceBaseUrl: 'http://localhost:8000',
            useMockData: false,
            learnedFocusPlanningPilotEnabled: pilotEnabled,
          ),
        ),
        learningRepositoryProvider.overrideWithValue(repository),
        if (invalidations != null)
          projectionRefreshCoordinatorProvider.overrideWithValue(
            ProjectionRefreshCoordinator(
              refreshDailySnapshot: (_) async {},
              invalidateProjection: invalidations.add,
            ),
          ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const Scaffold(body: PersonalLearningPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _LearningRepository implements LearningRepository {
  _LearningRepository({
    LearningPreferences? preferences,
    this.unknownClearAttempts = 0,
  }) : _preferences = preferences ??
            const LearningPreferences(
              revision: 0,
              focusReflectionPromptEnabled: true,
              personalPatternAnalysisEnabled: true,
              learnedFocusPlanningEnabled: false,
              updatedAt: null,
            );

  LearningPreferences _preferences;
  final int unknownClearAttempts;
  final List<LearningPreferencesUpdate> updates = [];
  final List<FocusReflectionHistoryClearRequest> clearRequests = [];

  @override
  Future<LearningPreferences> getPreferences() async => _preferences;

  @override
  Future<LearningPreferences> updatePreferences(
    LearningPreferencesUpdate request,
  ) async {
    updates.add(request);
    _preferences = LearningPreferences(
      revision: request.expectedRevision + 1,
      focusReflectionPromptEnabled: request.focusReflectionPromptEnabled,
      personalPatternAnalysisEnabled: request.personalPatternAnalysisEnabled,
      learnedFocusPlanningEnabled: request.learnedFocusPlanningEnabled,
      updatedAt: DateTime.utc(2026, 7, 26, 9),
    );
    return _preferences;
  }

  @override
  Future<FocusReflectionHistoryClearResult> clearFocusReflections(
    FocusReflectionHistoryClearRequest request,
  ) async {
    clearRequests.add(request);
    if (clearRequests.length <= unknownClearAttempts) {
      throw const LearningOutcomeUnknownException(
        'Focus reflection clear outcome is unknown.',
      );
    }
    return FocusReflectionHistoryClearResult(
      revision: request.expectedRevision,
      deletedCount: 3,
      clearedAt: DateTime.utc(2026, 7, 26, 9),
      replayed: false,
    );
  }
}
