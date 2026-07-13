import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/briefings/domain/daily_briefing.dart';
import 'package:my_life_graph/features/briefings/presentation/providers/briefing_providers.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:my_life_graph/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:my_life_graph/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:my_life_graph/features/optimization/application/optimization_service.dart';
import 'package:my_life_graph/features/optimization/domain/entities/recommendation.dart';
import 'package:my_life_graph/features/optimization/domain/entities/recommendation_feed.dart';
import 'package:my_life_graph/features/optimization/domain/entities/skillset_profile.dart';
import 'package:my_life_graph/features/optimization/domain/repositories/optimization_repository.dart';
import 'package:my_life_graph/features/optimization/presentation/providers/optimization_providers.dart';
import 'package:my_life_graph/features/snapshots/application/snapshot_refresh_service.dart';
import 'package:my_life_graph/features/snapshots/data/snapshot_api_data_source.dart';
import 'package:my_life_graph/features/snapshots/presentation/providers/snapshot_providers.dart';

void main() {
  testWidgets('shows exact saved signals and no proxy metrics', (tester) async {
    final snapshot = DashboardSnapshot(
      origin: DashboardOrigin.localDemo,
      loadedAt: DateTime.now(),
      latestCheckIn: DashboardCheckIn(
        entryDate: DateTime.now(),
        mood: 2,
        energy: 9,
        sleepHours: 5.5,
        stress: 8,
      ),
      checkInStreakDays: 1,
      todayPlan: const [],
      scheduleDays: const [],
    );

    await _pumpDashboard(
      tester,
      snapshot: Future.value(snapshot),
      feed: Future.value(
        RecommendationFeed.demo(const [
          Recommendation(
            id: 'demo-rec',
            title: 'Demo next action',
            reason: 'Demo reason',
            actionLabel: 'Protect ten focused minutes',
            category: RecommendationCategory.focus,
            confidence: 0.7,
          ),
        ]),
      ),
    );

    expect(find.text('Latest check-in'), findsOneWidget);
    expect(find.text('2/10'), findsOneWidget);
    expect(find.text('9/10'), findsOneWidget);
    expect(find.text('5.5 h'), findsOneWidget);
    expect(find.text('8/10'), findsOneWidget);
    expect(find.text('Demo recommendations'), findsOneWidget);
    expect(find.text('Demo next action'), findsOneWidget);
    expect(find.text("Today's wellness score"), findsNothing);
    expect(find.text('Hydration'), findsNothing);
    expect(find.text('Activity score'), findsNothing);
  });

  testWidgets('real recommendation error is not replaced with demo items',
      (tester) async {
    final snapshot = DashboardSnapshot.empty(
      origin: DashboardOrigin.account,
      loadedAt: DateTime.now(),
    );

    await _pumpDashboard(
      tester,
      snapshot: Future.value(snapshot),
      feed: _failingFeed(),
    );

    expect(find.text('Recommendations unavailable'), findsOneWidget);
    expect(
      find.text('Your account data was not replaced with demo content.'),
      findsOneWidget,
    );
    expect(find.text('Demo recommendations'), findsNothing);
  });

  testWidgets('dashboard load error is distinct from an empty snapshot',
      (tester) async {
    await _pumpDashboard(
      tester,
      snapshot: _failingSnapshot(),
      feed: Future.value(RecommendationFeed.demo(const [])),
    );

    expect(find.text('Dashboard unavailable'), findsOneWidget);
    expect(find.text('Latest check-in'), findsNothing);
  });

  testWidgets('failed refresh retains the existing real recommendation',
      (tester) async {
    final snapshot = DashboardSnapshot.empty(
      origin: DashboardOrigin.account,
      loadedAt: DateTime.now(),
    );
    final feed = RecommendationFeed(
      items: const [
        Recommendation(
          id: 'real-existing',
          title: 'Keep this real recommendation',
          reason: 'Persisted backend evidence.',
          actionLabel: 'Review the next step',
          category: RecommendationCategory.planning,
          confidence: 0.8,
        ),
      ],
      provenance: RecommendationProvenance.authenticatedBackend,
      freshness: RecommendationFreshness.current,
      needsGeneration: false,
      generatedAt: DateTime.utc(2026, 7, 10),
      periodKey: '2026-W28',
    );

    await _pumpDashboard(
      tester,
      snapshot: Future.value(snapshot),
      feed: Future.value(feed),
      optimizationService: OptimizationService(
        _FailingRefreshOptimizationRepository(),
      ),
      snapshotRefreshService: _NoopSnapshotRefreshService(),
    );

    await tester.tap(find.text('Refresh recommendations'));
    await tester.pumpAndSettle();

    expect(find.text('Keep this real recommendation'), findsOneWidget);
    expect(
      find.text('Refresh failed. Existing recommendations were kept.'),
      findsOneWidget,
    );
    expect(find.text('Recommendations checked.'), findsNothing);
  });

  testWidgets('weekly review entry is account-only', (tester) async {
    await _pumpDashboard(
      tester,
      snapshot: Future.value(
        DashboardSnapshot.empty(
          origin: DashboardOrigin.localDemo,
          loadedAt: DateTime.now(),
        ),
      ),
      feed: Future.value(RecommendationFeed.demo(const [])),
    );
    expect(find.text('Review your week'), findsNothing);

    await _pumpDashboard(
      tester,
      snapshot: Future.value(
        DashboardSnapshot.empty(
          origin: DashboardOrigin.account,
          loadedAt: DateTime.now(),
        ),
      ),
      feed: Future.value(RecommendationFeed.demo(const [])),
      capabilities: const AppSurfaceCapabilities(
        isLocalDemo: false,
        canUseSyncedHabits: true,
        canUseSyncedExecution: true,
        canUseWeeklyReview: true,
      ),
    );
    expect(find.text('Review your week'), findsOneWidget);
  });
}

Future<RecommendationFeed> _failingFeed() async {
  await Future<void>.delayed(Duration.zero);
  throw Exception('backend unavailable');
}

Future<DashboardSnapshot> _failingSnapshot() async {
  await Future<void>.delayed(Duration.zero);
  throw Exception('database unavailable');
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required Future<DashboardSnapshot> snapshot,
  required Future<RecommendationFeed> feed,
  OptimizationService? optimizationService,
  SnapshotRefreshService? snapshotRefreshService,
  AppSurfaceCapabilities capabilities = const AppSurfaceCapabilities(
    isLocalDemo: true,
    canUseSyncedHabits: false,
  ),
}) async {
  tester.view.physicalSize = const Size(1200, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSurfaceCapabilitiesProvider.overrideWithValue(
          capabilities,
        ),
        dashboardSnapshotProvider.overrideWith((ref) => snapshot),
        todayBriefingProvider.overrideWith(
          (ref) => Future.value(
            BriefingFeed.localDemo(now: DateTime(2026, 7, 12)),
          ),
        ),
        recommendationFeedProvider.overrideWith((ref) => feed),
        if (optimizationService != null)
          optimizationServiceProvider.overrideWithValue(optimizationService),
        if (snapshotRefreshService != null)
          snapshotRefreshServiceProvider.overrideWithValue(
            snapshotRefreshService,
          ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: DashboardPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FailingRefreshOptimizationRepository implements OptimizationRepository {
  @override
  Future<SkillsetProfile> getSkillsetProfile() {
    throw UnsupportedError('Not used in this test.');
  }

  @override
  Future<RecommendationFeed> getRecommendations() {
    throw UnsupportedError('The feed provider is overridden in this test.');
  }

  @override
  Future<RecommendationFeed> refreshRecommendations() {
    throw StateError('Refresh failed.');
  }
}

class _NoopSnapshotRefreshService extends SnapshotRefreshService {
  _NoopSnapshotRefreshService()
      : super(
          config: const AppConfig(
            environment: 'test',
            supabaseUrl: '',
            supabaseAnonKey: '',
            aiServiceBaseUrl: 'http://localhost:8000',
            useMockData: false,
          ),
          apiDataSource: SnapshotApiDataSource(ApiClient(Dio())),
          accessTokenProvider: () => null,
          allowRemoteRefresh: false,
        );

  @override
  Future<void> refreshDailyAfterUserSignal({String? targetDate}) async {}
}
