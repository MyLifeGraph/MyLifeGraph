import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:my_life_graph/composition/habit_action_providers.dart';
import 'package:my_life_graph/features/auth/application/profile_local_date_source.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
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
          profileLocalDateSourceProvider.overrideWithValue(_deviceDateSource),
          habitCompletionPageDataSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(home: Scaffold(body: HabitCompletionPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load today\'s habits.'), findsOneWidget);
    expect(
      find.textContaining('Your saved habits were not changed'),
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
          profileLocalDateSourceProvider.overrideWithValue(_deviceDateSource),
          habitManagementPageDataSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(home: Scaffold(body: HabitManagementPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load habits.'), findsOneWidget);
    expect(
      find.textContaining('Your saved habits were not changed'),
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
    final profileDate = SessionProfileLocalDateSource(
      session: AppSession.authenticated(_authenticatedProfile),
      currentInstant: () => DateTime.utc(2026, 7, 22, 6, 30),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          profileLocalDateSourceProvider.overrideWithValue(profileDate),
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
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(AppIcons.refresh),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
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
    expect(
      source.targetDates.map(habitDateKey),
      everyElement('2026-07-21'),
    );
    expect(
      snapshotRefresh.habitTargetDates,
      ['2026-07-21', '2026-07-21'],
    );
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
          profileLocalDateSourceProvider.overrideWithValue(_deviceDateSource),
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
          profileLocalDateSourceProvider.overrideWithValue(_deviceDateSource),
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
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(AppIcons.refresh),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
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

  testWidgets('habit routes stay usable at 320 px and 200 percent text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Widget app({required Widget home, required Override sourceOverride}) {
      return ProviderScope(
        key: UniqueKey(),
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          profileLocalDateSourceProvider.overrideWithValue(_deviceDateSource),
          sourceOverride,
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: Scaffold(body: home),
        ),
      );
    }

    await tester.pumpWidget(
      app(
        home: const HabitCompletionPage(),
        sourceOverride: habitCompletionPageDataSourceProvider
            .overrideWithValue(_ConcurrentCompletionSource()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Today\'s habits'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      app(
        home: const HabitManagementPage(),
        sourceOverride: habitManagementPageDataSourceProvider
            .overrideWithValue(_PendingLifecycleSource()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Habit management'), findsOneWidget);
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

const _deviceDateSource = SessionProfileLocalDateSource(session: null);

const _authenticatedProfile = AppProfile(
  id: '10000000-0000-4000-8000-000000000001',
  email: 'student@example.com',
  name: 'Student',
  timezone: 'America/Los_Angeles',
  role: AppRole.user,
  onboardingDone: true,
  authProvider: 'email',
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
  final List<DateTime> targetDates = [];
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
  }) {
    targetDates.add(targetDate);
    return switch (habitId) {
      'first' => firstWrite.future,
      'second' => secondWrite.future,
      _ => Future.error(StateError('unexpected habit')),
    };
  }
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
  Future<void> refreshDailyAfterUserSignal({String? targetDate}) async {
    if (targetDate != null) habitTargetDates.add(targetDate);
  }
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
