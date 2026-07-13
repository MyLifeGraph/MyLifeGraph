import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/features/quick_action/domain/habit_v1.dart';
import 'package:my_life_graph/features/weekly_review/application/weekly_review_proposal_applier.dart';
import 'package:my_life_graph/features/weekly_review/domain/weekly_review.dart';
import 'package:my_life_graph/features/weekly_review/domain/weekly_review_repository.dart';
import 'package:my_life_graph/features/weekly_review/presentation/pages/weekly_review_page.dart';
import 'package:my_life_graph/features/weekly_review/presentation/providers/weekly_review_providers.dart';

import 'support/weekly_review_fixtures.dart';

void main() {
  testWidgets('current review shows distinct facts without generating',
      (tester) async {
    final repository = _FakeWeeklyReviewRepository(_feed());
    await _pumpPage(tester, repository: repository);

    expect(find.text('Weekly review'), findsOneWidget);
    expect(find.text('Last week in context'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Skipped'), findsOneWidget);
    expect(find.text('Missed'), findsOneWidget);
    expect(find.text('Carried'), findsOneWidget);
    expect(find.text('Recovery days'), findsOneWidget);
    expect(find.textContaining('3 habit outcomes'), findsOneWidget);
    expect(find.textContaining('1 changed definitions'), findsOneWidget);
    expect(repository.generateCalls, isEmpty);
  });

  testWidgets('not-ready and error states never become generated content',
      (tester) async {
    await _pumpPage(
      tester,
      repository: _FakeWeeklyReviewRepository(
        _feed(freshness: 'not_ready', includeReview: false),
      ),
    );
    expect(find.text('Weekly review not ready'), findsOneWidget);
    expect(find.text('Generate weekly review'), findsNothing);

    await _pumpPage(
      tester,
      repository: _FakeWeeklyReviewRepository(_feed(), readFails: true),
    );
    expect(find.text('Weekly review unavailable'), findsOneWidget);
    expect(find.textContaining('not replaced'), findsOneWidget);
  });

  testWidgets('missing generation and stale refresh require explicit taps',
      (tester) async {
    final missingRepository = _FakeWeeklyReviewRepository(
      _feed(freshness: 'missing', includeReview: false),
      generatedFeed: _feed(),
    );
    await _pumpPage(tester, repository: missingRepository);

    expect(missingRepository.generateCalls, isEmpty);
    await tester.tap(find.text('Generate weekly review'));
    await tester.pumpAndSettle();
    expect(missingRepository.generateCalls, [('2026-W28', false)]);
    expect(find.text('Current'), findsOneWidget);

    final staleRepository = _FakeWeeklyReviewRepository(
      _feed(freshness: 'stale'),
      generatedFeed: _feed(),
    );
    await _pumpPage(tester, repository: staleRepository);
    final applyButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Apply change'),
    );
    expect(applyButton.onPressed, isNull);
    await tester.ensureVisible(find.text('Refresh weekly review'));
    await tester.tap(find.text('Refresh weekly review'));
    await tester.pumpAndSettle();
    expect(staleRepository.generateCalls, [('2026-W28', true)]);
  });

  testWidgets('manual change requires dialog and cancel performs zero writes',
      (tester) async {
    final gateway = _FakeHabitGateway(_habit());
    final repository = _FakeWeeklyReviewRepository(_feed());
    await _pumpPage(
      tester,
      repository: repository,
      applier: WeeklyReviewProposalApplier(
        habitGateway: gateway,
        loadLatestReview: repository.getLatest,
        refreshDailySnapshot: () async {},
      ),
    );

    await tester.ensureVisible(find.text('Apply change'));
    await tester.tap(find.text('Apply change'));
    await tester.pumpAndSettle();
    expect(find.text('Apply this habit change?'), findsOneWidget);
    await tester.tap(find.text('Keep current'));
    await tester.pumpAndSettle();
    expect(gateway.fetches, 0);
    expect(gateway.updates, 0);

    await tester.tap(find.text('Apply change'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Apply change').last,
    );
    await tester.pumpAndSettle();
    expect(gateway.fetches, 1);
    expect(gateway.updates, 1);
    expect(find.text('Habit change saved.'), findsOneWidget);
    expect(find.text('Change applied'), findsOneWidget);
  });

  testWidgets('source change before confirmation causes zero habit writes',
      (tester) async {
    final displayed = _feed();
    final changed = _feedWithFingerprint(
      _changedFingerprint,
      freshness: 'stale',
    );
    final gateway = _FakeHabitGateway(_habit());
    final repository = _FakeWeeklyReviewRepository(displayed);
    await _pumpPage(
      tester,
      repository: repository,
      applier: WeeklyReviewProposalApplier(
        habitGateway: gateway,
        loadLatestReview: repository.getLatest,
        refreshDailySnapshot: () async {},
      ),
    );
    repository.feed = changed;

    await tester.ensureVisible(find.text('Apply change'));
    await tester.tap(find.text('Apply change'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply change').last);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Weekly review changed before confirmation. Refresh before applying it.',
      ),
      findsOneWidget,
    );
    expect(gateway.fetches, 0);
    expect(gateway.updates, 0);
    expect(gateway.lifecycleUpdates, 0);
    expect(find.text('Stale'), findsOneWidget);
    final disabledApply = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Apply change'),
    );
    expect(disabledApply.onPressed, isNull);
  });

  testWidgets('keep records only a no-change UI state', (tester) async {
    final keepFeed = _feed(
      operation: 'keep',
      applicationMode: 'none',
      after: weeklyHabitState(weeklyTarget: 3),
    );
    final gateway = _FakeHabitGateway(_habit());
    final repository = _FakeWeeklyReviewRepository(keepFeed);
    await _pumpPage(
      tester,
      repository: repository,
      applier: WeeklyReviewProposalApplier(
        habitGateway: gateway,
        loadLatestReview: repository.getLatest,
        refreshDailySnapshot: () async {},
      ),
    );

    await tester.ensureVisible(find.text('Keep current'));
    await tester.tap(find.text('Keep current'));
    await tester.pumpAndSettle();

    expect(find.text('No change made'), findsOneWidget);
    expect(find.text('Change applied'), findsNothing);
    expect(gateway.fetches, 0);
    expect(gateway.updates, 0);
  });

  testWidgets('Setup-owned proposal deep-links without a habit write',
      (tester) async {
    final gateway = _FakeHabitGateway(_habit(isSetupManaged: true));
    final setupFeed = _feed(
      operation: 'pause',
      ownership: 'setup',
      applicationMode: 'settings_setup',
      before: weeklyHabitState(),
      after: weeklyHabitState(lifecycle: 'paused'),
    );
    final repository = _FakeWeeklyReviewRepository(setupFeed);
    await _pumpPage(
      tester,
      repository: repository,
      applier: WeeklyReviewProposalApplier(
        habitGateway: gateway,
        loadLatestReview: repository.getLatest,
        refreshDailySnapshot: () async {},
      ),
    );

    await tester.ensureVisible(find.text('Review in Setup'));
    await tester.tap(find.text('Review in Setup'));
    await tester.pumpAndSettle();

    expect(find.text('Setup destination'), findsOneWidget);
    expect(gateway.fetches, 0);
    expect(gateway.updates, 0);
    expect(gateway.lifecycleUpdates, 0);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeWeeklyReviewRepository repository,
  WeeklyReviewProposalApplier? applier,
}) async {
  tester.view.physicalSize = const Size(1200, 1400);
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
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const Scaffold(body: Text('Setup destination')),
      ),
      GoRoute(
        path: '/habits',
        builder: (_, __) => const Scaffold(body: Text('Habits destination')),
      ),
    ],
  );
  addTearDown(router.dispose);
  final effectiveApplier = applier ??
      WeeklyReviewProposalApplier(
        habitGateway: _FakeHabitGateway(_habit()),
        loadLatestReview: repository.getLatest,
        refreshDailySnapshot: () async {},
      );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        weeklyReviewRepositoryProvider.overrideWithValue(repository),
        weeklyReviewProposalApplierProvider.overrideWithValue(effectiveApplier),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

WeeklyReviewFeed _feed({
  String freshness = 'current',
  bool includeReview = true,
  String operation = 'shrink',
  String ownership = 'manual',
  String applicationMode = 'direct_habit',
  Map<String, dynamic>? before,
  Object? after = _defaultAfter,
}) =>
    WeeklyReviewFeed.fromJson(
      weeklyReviewResponseJson(
        freshness: freshness,
        includeReview: includeReview,
        operation: operation,
        ownership: ownership,
        applicationMode: applicationMode,
        before: before,
        after: identical(after, _defaultAfter)
            ? weeklyHabitState(weeklyTarget: 2)
            : after,
      ),
    );

WeeklyReviewFeed _feedWithFingerprint(
  String fingerprint, {
  String freshness = 'current',
}) {
  final json = jsonDecode(
    jsonEncode(weeklyReviewResponseJson(freshness: freshness)),
  ) as Map<String, dynamic>;
  ((json['review'] as Map<String, dynamic>)['provenance']
      as Map<String, dynamic>)['source_fingerprint'] = fingerprint;
  return WeeklyReviewFeed.fromJson(json);
}

HabitV1 _habit({bool isSetupManaged = false}) => HabitV1(
      id: '22222222-2222-4222-8222-222222222222',
      title: 'Walk after lunch',
      description: 'A short walk.',
      cadence: HabitCadence.weeklyTarget(3),
      lifecycle: HabitLifecycle.active,
      createdAt: DateTime.utc(2026, 7, 1),
      updatedAt: DateTime.utc(2026, 7, 12, 17, 30),
      isSetupManaged: isSetupManaged,
      metadata: {
        if (isSetupManaged) 'managed_by': 'setup',
      },
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

class _FakeHabitGateway implements WeeklyReviewHabitGateway {
  _FakeHabitGateway(this.habit);

  final HabitV1 habit;
  int fetches = 0;
  int updates = 0;
  int lifecycleUpdates = 0;

  @override
  Future<HabitV1> fetchOwnedHabit(String habitId) async {
    fetches++;
    return habit;
  }

  @override
  Future<HabitV1> updateHabit({
    required HabitV1 habit,
    required String title,
    String? description,
    required HabitCadence cadence,
  }) async {
    updates++;
    return habit;
  }

  @override
  Future<HabitV1> setHabitLifecycle({
    required HabitV1 habit,
    required HabitLifecycle lifecycle,
  }) async {
    lifecycleUpdates++;
    return habit;
  }
}

const Object _defaultAfter = Object();
const String _changedFingerprint =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
