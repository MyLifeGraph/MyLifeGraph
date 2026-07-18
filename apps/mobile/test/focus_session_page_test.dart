import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/features/focus/data/focus_session_supabase_data_source.dart';
import 'package:my_life_graph/features/focus/domain/focus_session.dart';
import 'package:my_life_graph/features/focus/presentation/pages/focus_session_page.dart';
import 'package:my_life_graph/features/snapshots/application/snapshot_refresh_service.dart';
import 'package:my_life_graph/features/snapshots/presentation/providers/snapshot_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('initial focus read failure stays visible until retry succeeds',
      (tester) async {
    final source = _FailOnceFocusSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          focusSessionPageDataSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(home: Scaffold(body: FocusSessionPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load focus sessions.'), findsOneWidget);
    expect(
      find.textContaining('No empty focus state was assumed'),
      findsOneWidget,
    );
    expect(find.text('Start a focus block'), findsNothing);
    expect(find.text('No finished sessions yet.'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load focus sessions.'), findsNothing);
    expect(find.text('Start a focus block'), findsOneWidget);
    expect(find.text('No finished sessions yet.'), findsOneWidget);
    expect(source.activeLoads, 2);
  });

  testWidgets('active focus actions wrap at 320 pixels with larger text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          focusSessionPageDataSourceProvider.overrideWithValue(
            _ActiveFocusSource(),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.5),
            ),
            child: child!,
          ),
          home: const Scaffold(body: FocusSessionPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Focus active'), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-countdown')), findsOneWidget);
    expect(find.text('Planned time reached'), findsOneWidget);
    expect(find.byKey(const ValueKey('active-focus-actions')), findsOneWidget);
    expect(find.text('Abandon'), findsOneWidget);
    expect(find.text('Finish focus session'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Finish focus session')).dy,
      greaterThan(tester.getTopLeft(find.text('Abandon')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reload clears a selected target that is no longer available',
      (tester) async {
    final source = _TargetRemovedOnReloadFocusSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          focusSessionPageDataSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: FocusSessionPage(
              initialTargetKind: FocusTargetKind.task,
              initialTargetId: 'task-1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButtonFormField<String?>>(
            find.byType(DropdownButtonFormField<String?>),
          )
          .initialValue,
      'task:task-1',
    );

    await tester.tap(find.byTooltip('Refresh focus sessions'));
    await tester.pumpAndSettle();

    expect(source.targetLoads, 2);
    expect(
      tester
          .widget<DropdownButtonFormField<String?>>(
            find.byType(DropdownButtonFormField<String?>),
          )
          .initialValue,
      isNull,
    );
    expect(find.text('Independent focus block'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long focus targets fit at 320 pixels with larger text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          focusSessionPageDataSourceProvider.overrideWithValue(
            _LongTargetFocusSource(),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.5),
            ),
            child: child!,
          ),
          home: const Scaffold(
            body: FocusSessionPage(
              initialTargetKind: FocusTargetKind.task,
              initialTargetId: 'long-task',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selector = tester.widget<DropdownButton<String?>>(
      find.byType(DropdownButton<String?>),
    );
    expect(selector.isExpanded, isTrue);
    final targetLabel = tester.widget<Text>(
      find.textContaining('Task: A very long focus target').first,
    );
    expect(targetLabel.maxLines, 1);
    expect(targetLabel.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'leaving during a committed focus start has no disposed-ref error',
      (tester) async {
    final source = _PendingStartFocusSource();
    final snapshotRefresh = _CountingSnapshotRefresh();
    final showFocus = ValueNotifier(true);
    addTearDown(showFocus.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          focusSessionPageDataSourceProvider.overrideWithValue(source),
          snapshotRefreshServiceProvider.overrideWithValue(snapshotRefresh),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showFocus,
              builder: (_, visible, __) => visible
                  ? const FocusSessionPage()
                  : const Text('Different destination'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start focus session'));
    await tester.pump();
    showFocus.value = false;
    await tester.pump();
    expect(find.text('Different destination'), findsOneWidget);

    source.completeStart();
    await tester.pumpAndSettle();

    expect(snapshotRefresh.focusCalls, 1);
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

class _FailOnceFocusSource extends FocusSessionSupabaseDataSource {
  _FailOnceFocusSource()
      : super(
          SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  int activeLoads = 0;

  @override
  Future<FocusSession?> fetchActiveSession() async {
    activeLoads += 1;
    if (activeLoads == 1) {
      throw StateError('account read failed');
    }
    return null;
  }

  @override
  Future<List<FocusSession>> fetchRecentSessions({int limit = 10}) async {
    return const [];
  }

  @override
  Future<List<FocusTargetOption>> fetchAvailableTargets() async {
    return const [];
  }
}

class _ActiveFocusSource extends FocusSessionSupabaseDataSource {
  _ActiveFocusSource()
      : super(
          SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  static final _startedAt = DateTime.utc(2026, 7, 13, 8, 30);

  @override
  Future<FocusSession?> fetchActiveSession() async {
    return FocusSession(
      id: 'focus-active',
      status: FocusSessionStatus.active,
      startedAt: _startedAt,
      plannedMinutes: 50,
      label: 'Prepare the weekly review',
      updatedAt: _startedAt,
    );
  }

  @override
  Future<List<FocusSession>> fetchRecentSessions({int limit = 10}) async {
    return const [];
  }

  @override
  Future<List<FocusTargetOption>> fetchAvailableTargets() async {
    return const [];
  }
}

class _TargetRemovedOnReloadFocusSource extends FocusSessionSupabaseDataSource {
  _TargetRemovedOnReloadFocusSource()
      : super(
          SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  int targetLoads = 0;

  @override
  Future<FocusSession?> fetchActiveSession() async => null;

  @override
  Future<List<FocusSession>> fetchRecentSessions({int limit = 10}) async =>
      const [];

  @override
  Future<List<FocusTargetOption>> fetchAvailableTargets() async {
    targetLoads += 1;
    if (targetLoads > 1) {
      return const [];
    }
    return const [
      FocusTargetOption(
        kind: FocusTargetKind.task,
        id: 'task-1',
        title: 'Prepare the plan',
      ),
    ];
  }
}

class _LongTargetFocusSource extends FocusSessionSupabaseDataSource {
  _LongTargetFocusSource()
      : super(
          SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  @override
  Future<FocusSession?> fetchActiveSession() async => null;

  @override
  Future<List<FocusSession>> fetchRecentSessions({int limit = 10}) async =>
      const [];

  @override
  Future<List<FocusTargetOption>> fetchAvailableTargets() async => const [
        FocusTargetOption(
          kind: FocusTargetKind.task,
          id: 'long-task',
          title: 'A very long focus target that must remain inside the field',
        ),
      ];
}

class _PendingStartFocusSource extends FocusSessionSupabaseDataSource {
  _PendingStartFocusSource()
      : super(
          SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final _start = Completer<FocusSession>();

  @override
  Future<FocusSession?> fetchActiveSession() async => null;

  @override
  Future<List<FocusSession>> fetchRecentSessions({int limit = 10}) async =>
      const [];

  @override
  Future<List<FocusTargetOption>> fetchAvailableTargets() async => const [];

  @override
  Future<FocusSession> startSession({
    required String sessionId,
    required FocusStartDraft draft,
  }) =>
      _start.future;

  void completeStart() {
    final now = DateTime.utc(2026, 7, 13, 8, 30);
    _start.complete(
      FocusSession(
        id: 'focus-started',
        status: FocusSessionStatus.active,
        startedAt: now,
        plannedMinutes: 25,
        updatedAt: now,
      ),
    );
  }
}

class _CountingSnapshotRefresh implements SnapshotRefreshService {
  int focusCalls = 0;

  @override
  Future<void> refreshDailyAfterFocusChange({
    required String targetDate,
  }) async {
    focusCalls += 1;
  }

  @override
  Future<void> refreshDailyAfterHabitChange({
    required String targetDate,
  }) async {}

  @override
  Future<void> refreshDailyAfterTaskChange({
    required String targetDate,
  }) async {}

  @override
  Future<void> refreshDailyAfterUserSignal({String? targetDate}) async {}
}
