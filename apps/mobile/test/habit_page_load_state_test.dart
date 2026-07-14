import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/features/quick_action/data/habit_completion_supabase_data_source.dart';
import 'package:my_life_graph/features/quick_action/domain/habit_v1.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/habit_completion_page.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/habit_management_page.dart';
import 'package:my_life_graph/features/snapshots/application/snapshot_refresh_service.dart';
import 'package:my_life_graph/features/snapshots/presentation/providers/snapshot_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('today habits keeps an initial read error distinct from empty',
      (tester) async {
    final source = _FailOnceActiveHabitSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          habitCompletionPageDataSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(home: Scaffold(body: HabitCompletionPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load today\'s habits.'), findsOneWidget);
    expect(
      find.textContaining('No empty habit state was assumed'),
      findsOneWidget,
    );
    expect(find.text('No active habit is scheduled for today.'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load today\'s habits.'), findsNothing);
    expect(
      find.text('No active habit is scheduled for today.'),
      findsOneWidget,
    );
    expect(source.loads, 2);
  });

  testWidgets(
      'habit management keeps an initial read error distinct from empty',
      (tester) async {
    final source = _FailOnceManagementHabitSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          habitManagementPageDataSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(home: Scaffold(body: HabitManagementPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load habits.'), findsOneWidget);
    expect(
      find.textContaining('No empty habit list was assumed'),
      findsOneWidget,
    );
    expect(find.text('No manual habits yet.'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load habits.'), findsNothing);
    expect(find.text('No manual habits yet.'), findsOneWidget);
    expect(source.loads, 2);
  });

  testWidgets(
      'today habit mutations disable refresh and latest completed load wins',
      (tester) async {
    final source = _ConcurrentCompletionSource();
    final snapshotRefresh = _RecordingSnapshotRefresh();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          habitCompletionPageDataSourceProvider.overrideWithValue(source),
          snapshotRefreshServiceProvider.overrideWithValue(snapshotRefresh),
        ],
        child: const MaterialApp(home: Scaffold(body: HabitCompletionPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Complete habit First habit'));
    await tester.pump();
    expect(
      tester.widget<IconButton>(find.byType(IconButton).first).onPressed,
      isNull,
    );
    await tester.tap(find.bySemanticsLabel('Complete habit Second habit'));
    await tester.pump();

    source.firstWrite.complete();
    await tester.pump();
    await tester.pump();
    expect(source.loads, 2);

    source.secondWrite.complete();
    await tester.pump();
    await tester.pump();
    expect(source.loads, 3);

    source.latestLoad.complete([_habit('latest', 'Latest response')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Latest response'), findsOneWidget);

    source.staleLoad.complete([_habit('stale', 'Stale response')]);
    await tester.pumpAndSettle();

    expect(find.text('Latest response'), findsOneWidget);
    expect(find.text('Stale response'), findsNothing);
    expect(snapshotRefresh.habitTargetDates, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('today habit commit refreshes its snapshot after page navigation',
      (tester) async {
    final source = _PendingCompletionSource();
    final snapshotRefresh = _RecordingSnapshotRefresh();
    final showPage = ValueNotifier(true);
    addTearDown(showPage.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          habitCompletionPageDataSourceProvider.overrideWithValue(source),
          snapshotRefreshServiceProvider.overrideWithValue(snapshotRefresh),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showPage,
              builder: (_, visible, __) => visible
                  ? const HabitCompletionPage()
                  : const Text('Different destination'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Complete habit Pending habit'));
    await tester.pump();
    showPage.value = false;
    await tester.pump();
    source.write.complete();
    await tester.pumpAndSettle();

    expect(find.text('Different destination'), findsOneWidget);
    expect(snapshotRefresh.habitTargetDates, hasLength(1));
    expect(source.loads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'habit lifecycle commit disables refresh and refreshes after navigation',
      (tester) async {
    final source = _PendingLifecycleSource();
    final snapshotRefresh = _RecordingSnapshotRefresh();
    final showPage = ValueNotifier(true);
    addTearDown(showPage.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          habitManagementPageDataSourceProvider.overrideWithValue(source),
          snapshotRefreshServiceProvider.overrideWithValue(snapshotRefresh),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showPage,
              builder: (_, visible, __) => visible
                  ? const HabitManagementPage()
                  : const Text('Different destination'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Habit actions for Lifecycle habit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(
      tester.widget<IconButton>(find.byType(IconButton).first).onPressed,
      isNull,
    );
    showPage.value = false;
    await tester.pump();
    source.write.complete(source.habit);
    await tester.pumpAndSettle();

    expect(find.text('Different destination'), findsOneWidget);
    expect(snapshotRefresh.habitTargetDates, hasLength(1));
    expect(source.loads, 1);
    expect(tester.takeException(), isNull);
  });
}

const _realConfig = AppConfig(
  environment: 'test',
  supabaseUrl: 'http://localhost:54321',
  supabaseAnonKey: 'test-anon-key',
  aiServiceBaseUrl: 'http://localhost:8000',
  useMockData: false,
);

class _FailOnceActiveHabitSource extends HabitCompletionSupabaseDataSource {
  _FailOnceActiveHabitSource()
      : super(
          SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  int loads = 0;

  @override
  Future<List<HabitV1>> fetchActiveHabits() async {
    loads += 1;
    if (loads == 1) {
      throw StateError('account read failed');
    }
    return const [];
  }
}

class _FailOnceManagementHabitSource extends HabitCompletionSupabaseDataSource {
  _FailOnceManagementHabitSource()
      : super(
          SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  int loads = 0;

  @override
  Future<List<HabitV1>> fetchHabits({
    bool activeOnly = false,
    bool excludeSetupManaged = false,
  }) async {
    loads += 1;
    if (loads == 1) {
      throw StateError('account read failed');
    }
    return const [];
  }
}

class _ConcurrentCompletionSource extends HabitCompletionSupabaseDataSource {
  _ConcurrentCompletionSource() : super(_testClient());

  final firstWrite = Completer<void>();
  final secondWrite = Completer<void>();
  final staleLoad = Completer<List<HabitV1>>();
  final latestLoad = Completer<List<HabitV1>>();
  int loads = 0;

  @override
  Future<List<HabitV1>> fetchActiveHabits() {
    loads += 1;
    return switch (loads) {
      1 => Future.value([
          _habit('first', 'First habit'),
          _habit('second', 'Second habit'),
        ]),
      2 => staleLoad.future,
      3 => latestLoad.future,
      _ => Future.value(const []),
    };
  }

  @override
  Future<void> setTodayOutcome({
    required String habitId,
    required HabitOutcome outcome,
    required DateTime targetDate,
    String? notes,
  }) =>
      switch (habitId) {
        'first' => firstWrite.future,
        'second' => secondWrite.future,
        _ => Future.error(StateError('unexpected habit')),
      };
}

class _PendingCompletionSource extends HabitCompletionSupabaseDataSource {
  _PendingCompletionSource() : super(_testClient());

  final write = Completer<void>();
  int loads = 0;

  @override
  Future<List<HabitV1>> fetchActiveHabits() async {
    loads += 1;
    return [_habit('pending', 'Pending habit')];
  }

  @override
  Future<void> setTodayOutcome({
    required String habitId,
    required HabitOutcome outcome,
    required DateTime targetDate,
    String? notes,
  }) =>
      write.future;
}

class _PendingLifecycleSource extends HabitCompletionSupabaseDataSource {
  _PendingLifecycleSource()
      : habit = _habit('lifecycle', 'Lifecycle habit'),
        super(_testClient());

  final HabitV1 habit;
  final write = Completer<HabitV1>();
  int loads = 0;

  @override
  Future<List<HabitV1>> fetchHabits({
    bool activeOnly = false,
    bool excludeSetupManaged = false,
  }) async {
    loads += 1;
    return [habit];
  }

  @override
  Future<HabitV1> setHabitLifecycle({
    required HabitV1 habit,
    required HabitLifecycle lifecycle,
  }) =>
      write.future;
}

class _RecordingSnapshotRefresh implements SnapshotRefreshService {
  final List<String> habitTargetDates = [];

  @override
  Future<void> refreshDailyAfterHabitChange({
    required String targetDate,
  }) async {
    habitTargetDates.add(targetDate);
  }

  @override
  Future<void> refreshDailyAfterFocusChange({
    required String targetDate,
  }) async {}

  @override
  Future<void> refreshDailyAfterTaskChange({
    required String targetDate,
  }) async {}

  @override
  Future<void> refreshDailyAfterUserSignal({String? targetDate}) async {}
}

HabitV1 _habit(String id, String title) {
  final now = DateTime.now();
  return HabitV1(
    id: id,
    title: title,
    cadence: HabitCadence.daily(),
    lifecycle: HabitLifecycle.active,
    createdAt: now.subtract(const Duration(days: 1)),
    updatedAt: now,
    isSetupManaged: false,
    metadata: const {},
  );
}

SupabaseClient _testClient() => SupabaseClient(
      'http://localhost:54321',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
