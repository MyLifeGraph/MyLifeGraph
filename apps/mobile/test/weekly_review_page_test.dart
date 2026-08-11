import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/composition/weekly_review_providers.dart';
import 'package:my_life_graph/features/weekly_review/domain/weekly_review.dart';
import 'package:my_life_graph/features/weekly_review/domain/weekly_review_repository.dart';
import 'package:my_life_graph/features/weekly_review/presentation/pages/weekly_review_page.dart';

import 'support/weekly_review_fixtures.dart';

void main() {
  testWidgets(
    'current review shows facts but never renders historical proposals',
    (tester) async {
      final repository = _FakeWeeklyReviewRepository(_feed());
      expect(repository.feed.review?.proposals, hasLength(1));

      await _pumpPage(tester, repository: repository);

      expect(find.text('Weekly review'), findsOneWidget);
      expect(find.text('Last week in context'), findsOneWidget);
      expect(find.text('Weekly facts'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Skipped'), findsOneWidget);
      expect(find.text('Missed'), findsOneWidget);
      expect(find.text('Carried'), findsOneWidget);
      expect(find.text('Recovery days'), findsOneWidget);
      expect(find.textContaining('3 habit outcomes'), findsOneWidget);
      expect(find.textContaining('1 changed definitions'), findsOneWidget);
      expect(find.text('Walk after lunch'), findsNothing);
      expect(find.textContaining('smaller target'), findsNothing);
      expect(find.textContaining('Apply'), findsNothing);
      expect(find.textContaining('summarizes saved activity'), findsNothing);
      await tester.tap(
        find.byKey(
          const ValueKey(
            'weekly-review-info-control-How this review is created',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('summarizes saved activity'), findsOneWidget);
      expect(repository.generateCalls, isEmpty);
    },
  );

  testWidgets('missing generation and stale refresh require explicit taps',
      (tester) async {
    final missingRepository = _FakeWeeklyReviewRepository(
      _feed(freshness: 'missing', includeReview: false),
      generatedFeed: _feed(),
    );
    await _pumpPage(tester, repository: missingRepository);

    expect(missingRepository.generateCalls, isEmpty);
    await tester.tap(find.text('Create weekly review'));
    await tester.pumpAndSettle();
    expect(missingRepository.generateCalls, [('2026-W28', false)]);
    expect(find.text('Up to date'), findsOneWidget);

    final staleRepository = _FakeWeeklyReviewRepository(
      _feed(freshness: 'stale'),
      generatedFeed: _feed(),
    );
    await _pumpPage(tester, repository: staleRepository);

    expect(find.text('Needs update'), findsOneWidget);
    expect(
      find.textContaining('Update it to see the current weekly facts'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Update weekly review'));
    await tester.tap(find.text('Update weekly review'));
    await tester.pumpAndSettle();
    expect(staleRepository.generateCalls, [('2026-W28', true)]);
    expect(find.textContaining('Apply'), findsNothing);
  });

  testWidgets('not-ready and read-error states remain explicit',
      (tester) async {
    await _pumpPage(
      tester,
      repository: _FakeWeeklyReviewRepository(
        _feed(freshness: 'not_ready', includeReview: false),
      ),
    );
    expect(find.text('Weekly review not ready'), findsOneWidget);
    expect(find.text('Create weekly review'), findsNothing);

    await _pumpPage(
      tester,
      repository: _FakeWeeklyReviewRepository(_feed(), readFails: true),
    );
    expect(find.text('Weekly review unavailable'), findsOneWidget);
    expect(find.textContaining('could not be loaded'), findsOneWidget);
  });

  testWidgets('guest mode never presents demo facts as a personal review',
      (tester) async {
    await _pumpPage(
      tester,
      repository: _FakeWeeklyReviewRepository(WeeklyReviewFeed.localDemo()),
    );

    expect(find.text('Weekly review unavailable'), findsOneWidget);
    expect(find.textContaining('available after you sign in'), findsOneWidget);
    expect(find.text('Weekly facts'), findsNothing);
    expect(find.textContaining('Apply'), findsNothing);
  });

  testWidgets(
      'current review remains usable at 320 pixels and 200 percent text',
      (tester) async {
    await _pumpPage(
      tester,
      repository: _FakeWeeklyReviewRepository(_feed()),
      size: const Size(320, 760),
      textScaler: const TextScaler.linear(2),
    );

    expect(find.text('Last week in context'), findsOneWidget);
    expect(find.text('Up to date'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Weekly facts'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Weekly facts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeWeeklyReviewRepository repository,
  Size size = const Size(1200, 1400),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final router = GoRouter(
    initialLocation: '/weekly-review',
    routes: [
      GoRoute(
        path: '/weekly-review',
        builder: (_, __) => const Scaffold(body: WeeklyReviewPage()),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        weeklyReviewRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

WeeklyReviewFeed _feed({
  String freshness = 'current',
  bool includeReview = true,
}) =>
    WeeklyReviewFeed.fromJson(
      weeklyReviewResponseJson(
        freshness: freshness,
        includeReview: includeReview,
      ),
    );

class _FakeWeeklyReviewRepository implements WeeklyReviewRepository {
  _FakeWeeklyReviewRepository(
    this.feed, {
    this.generatedFeed,
    this.readFails = false,
  });

  WeeklyReviewFeed feed;
  final WeeklyReviewFeed? generatedFeed;
  final bool readFails;
  final List<(String, bool)> generateCalls = [];

  @override
  Future<WeeklyReviewFeed> getLatest() async {
    if (readFails) throw StateError('read failed');
    return feed;
  }

  @override
  Future<WeeklyReviewFeed> generate({
    required String periodKey,
    required bool force,
  }) async {
    generateCalls.add((periodKey, force));
    feed = generatedFeed ?? feed;
    return feed;
  }
}
