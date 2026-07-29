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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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
    expect(
      tester
          .widget<SegmentedButton<int>>(
            find.byType(SegmentedButton<int>),
          )
          .selected,
      {25},
    );
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

  testWidgets('start duration choices stack at 320 pixels and 200% text',
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
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const Scaffold(
            body: FocusSessionPage(initialPlannedMinutes: 45),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Start a focus block'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Start a focus block'), findsOneWidget);
    final choices = find.byWidgetPredicate(
      (widget) => widget is SegmentedButton,
      description: 'duration segmented button',
    );
    expect(choices, findsOneWidget);
    final firstChoice = find.descendant(
      of: choices,
      matching: find.text('25 min'),
    );
    final secondChoice = find.descendant(
      of: choices,
      matching: find.text('45 min'),
    );
    expect(firstChoice, findsOneWidget);
    expect(secondChoice, findsOneWidget);
    expect(
      tester.getTopLeft(secondChoice).dy,
      greaterThan(tester.getTopLeft(firstChoice).dy),
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

  testWidgets('planned duration wins over setup and recent-session defaults',
      (tester) async {
    final source = _StudyFocusSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          focusSessionPageDataSourceProvider.overrideWithValue(source),
          focusStudySettingsDataSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: FocusSessionPage(
              initialPlannedMinutes: 60,
              initialRecoveryMinutes: 15,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SegmentedButton<int>>(
            find.byType(SegmentedButton<int>),
          )
          .selected,
      {60},
    );
    expect(find.text('60 min focus + 15 min recovery'), findsOneWidget);
  });

  testWidgets(
      'study default beats recent duration and checklist stays ephemeral',
      (tester) async {
    final source = _StudyFocusSource();
    final snapshotRefresh = _CountingSnapshotRefresh();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          focusSessionPageDataSourceProvider.overrideWithValue(source),
          focusStudySettingsDataSourceProvider.overrideWithValue(source),
          snapshotRefreshServiceProvider.overrideWithValue(snapshotRefresh),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FocusSessionPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SegmentedButton<int>>(
            find.byType(SegmentedButton<int>),
          )
          .selected,
      {45},
    );
    expect(find.text('45 min focus + 10 min recovery'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Start focus session'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Start focus session'));
    await tester.pumpAndSettle();

    expect(find.text('Prepare to focus'), findsOneWidget);
    expect(find.text('Water'), findsOneWidget);
    expect(find.text('Study materials'), findsOneWidget);
    expect(source.startCalls, 0);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('focus-preparation-start')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Ready').first);
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('focus-preparation-start')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Not needed today').last);
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('focus-preparation-start')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(
      find.byKey(const ValueKey('focus-preparation-start')),
    );
    await tester.pumpAndSettle();

    expect(source.startCalls, 1);
    expect(source.lastDraft?.plannedMinutes, 45);
    expect(source.lastDraft?.recoveryMinutes, 10);
    expect(snapshotRefresh.focusCalls, 1);
    expect(find.text('Focus active'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable Study Setup blocks start until retry succeeds',
      (tester) async {
    final source = _FailOnceStudySettingsSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          focusSessionPageDataSourceProvider.overrideWithValue(source),
          snapshotRefreshServiceProvider.overrideWithValue(
            _CountingSnapshotRefresh(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FocusSessionPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Saved Study Setup could not be loaded.'),
      findsOneWidget,
    );
    expect(find.text('No finished sessions yet.'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Start focus session'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Retry Study Setup'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Saved Study Setup could not be loaded.'),
      findsNothing,
    );
    expect(
      tester
          .widget<SegmentedButton<int>>(
            find.byType(SegmentedButton<int>),
          )
          .selected,
      {45},
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Start focus session'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('explicit unavailable-Setup fallback is session-only and safe',
      (tester) async {
    final source = _UnavailableStudySettingsSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          focusSessionPageDataSourceProvider.overrideWithValue(source),
          snapshotRefreshServiceProvider.overrideWithValue(
            _CountingSnapshotRefresh(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FocusSessionPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue without saved Study Setup'));
    await tester.pumpAndSettle();
    expect(find.text('Saved Study Setup is unavailable'), findsNothing);
    expect(
      tester
          .widget<SegmentedButton<int>>(
            find.byType(SegmentedButton<int>),
          )
          .selected,
      {30},
    );
    expect(find.textContaining('recovery'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Start focus session'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Start focus session'));
    await tester.pumpAndSettle();

    expect(source.startCalls, 1);
    expect(source.lastDraft?.plannedMinutes, 30);
    expect(source.lastDraft?.recoveryMinutes, 0);
    expect(find.text('Prepare to focus'), findsNothing);
    expect(find.text('Focus active'), findsOneWidget);
  });

  testWidgets('skip remaining starts without persisting ritual choices',
      (tester) async {
    final source = _StudyFocusSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          focusSessionPageDataSourceProvider.overrideWithValue(source),
          focusStudySettingsDataSourceProvider.overrideWithValue(source),
          snapshotRefreshServiceProvider.overrideWithValue(
            _CountingSnapshotRefresh(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FocusSessionPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Start focus session'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Start focus session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ready').first);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('focus-skip-preparation')),
    );
    await tester.pumpAndSettle();

    expect(source.startCalls, 1);
    expect(source.lastDraft?.plannedMinutes, 45);
    expect(source.lastDraft?.recoveryMinutes, 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved local recovery countdown restores and can be skipped',
      (tester) async {
    final source = _RecoveryFocusSource();
    final endsAt = DateTime.now().add(const Duration(minutes: 10));
    SharedPreferences.setMockInitialValues({
      'focus-recovery-countdown-v1':
          'completed-with-recovery|${endsAt.toUtc().toIso8601String()}',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          focusSessionPageDataSourceProvider.overrideWithValue(source),
          focusStudySettingsDataSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FocusSessionPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recovery break'), findsOneWidget);
    expect(
      find.textContaining('does not add progress or preparation time'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('skip-recovery')));
    await tester.pumpAndSettle();

    expect(find.text('Recovery break'), findsNothing);
    expect(find.text('Start a focus block'), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<int>>(
            find.byType(SegmentedButton<int>),
          )
          .selected,
      {30},
    );
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('focus-recovery-countdown-v1'),
      isNull,
    );
  });

  testWidgets(
      'finish is durable and recovery starts before the reflection prompt',
      (tester) async {
    final source = _TerminalPromptFocusSource(recoveryMinutes: 10);
    final snapshotRefresh = _BlockingSnapshotRefresh();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          focusSessionPageDataSourceProvider.overrideWithValue(source),
          snapshotRefreshServiceProvider.overrideWithValue(snapshotRefresh),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FocusSessionPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Focus active'), findsOneWidget);

    await tester.tap(find.text('Finish focus session'));
    await tester.pumpAndSettle();

    expect(source.finishCalls, 1);
    expect(
      find.byKey(const ValueKey('focus-reflection-sheet')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Recovery continues while you reflect'),
      findsOneWidget,
    );
    expect(find.text('Recovery break'), findsOneWidget);
    expect(snapshotRefresh.focusCalls, 1);

    await tester.tap(find.byKey(const ValueKey('focus-quality-rating-4')));
    await tester.tap(find.byKey(const ValueKey('useful-progress-rating-5')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('save-focus-reflection')),
    );
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -180),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-focus-reflection')));
    await tester.pumpAndSettle();

    expect(source.savedDraft?.focusQuality, 4);
    expect(source.savedDraft?.usefulProgress, 5);
    expect(find.byKey(const ValueKey('focus-reflection-sheet')), findsNothing);
    expect(find.text('Recovery break'), findsOneWidget);
    expect(source.finishCalls, 1);
  });

  testWidgets('abandon prompts after confirmation and can be skipped',
      (tester) async {
    final source = _TerminalPromptFocusSource(recoveryMinutes: 0);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          focusSessionPageDataSourceProvider.overrideWithValue(source),
          snapshotRefreshServiceProvider.overrideWithValue(
            _CountingSnapshotRefresh(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FocusSessionPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Abandon'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abandon session'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(source.abandonCalls, 1);
    expect(
      find.byKey(const ValueKey('focus-reflection-sheet')),
      findsOneWidget,
    );
    expect(
      find.text('What got in the way? Optional, choose up to two'),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('skip-focus-reflection')),
    );
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -180),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('skip-focus-reflection')));
    await tester.pumpAndSettle();
    expect(find.text('Start a focus block'), findsOneWidget);
    expect(source.savedDraft, isNull);
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

  @override
  Future<StudyFocusSettings?> fetchStudyFocusSettings() async => null;
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

  @override
  Future<StudyFocusSettings?> fetchStudyFocusSettings() async => null;
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
  Future<StudyFocusSettings?> fetchStudyFocusSettings() async => null;

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

class _StudyFocusSource extends FocusSessionSupabaseDataSource {
  _StudyFocusSource()
      : super(
          SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  FocusSession? active;
  int startCalls = 0;
  FocusStartDraft? lastDraft;

  @override
  Future<FocusSession?> fetchActiveSession() async => active;

  @override
  Future<List<FocusSession>> fetchRecentSessions({int limit = 10}) async {
    final start = DateTime.utc(2026, 7, 12, 9);
    return [
      FocusSession(
        id: 'recent-completed',
        status: FocusSessionStatus.completed,
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 30)),
        plannedMinutes: 30,
        actualMinutes: 30,
        updatedAt: start.add(const Duration(minutes: 30)),
      ),
    ];
  }

  @override
  Future<List<FocusTargetOption>> fetchAvailableTargets() async => const [];

  @override
  Future<StudyFocusSettings?> fetchStudyFocusSettings() async {
    return StudyFocusSettings(
      focusMinutes: 45,
      recoveryMinutes: 10,
      setupRevision: 3,
      preparationItems: const [
        FocusPreparationItem(
          key: '4abc0000-0000-4000-8000-000000000001',
          label: 'Water',
          active: true,
        ),
        FocusPreparationItem(
          key: '5abc0000-0000-4000-8000-000000000002',
          label: 'Study materials',
          active: true,
        ),
      ],
    );
  }

  @override
  Future<FocusSession> startSession({
    required String sessionId,
    required FocusStartDraft draft,
  }) async {
    startCalls += 1;
    lastDraft = draft;
    final now = DateTime.now();
    active = FocusSession(
      id: sessionId,
      status: FocusSessionStatus.active,
      startedAt: now,
      plannedMinutes: draft.plannedMinutes,
      recoveryMinutes: draft.recoveryMinutes,
      label: draft.label,
      updatedAt: now,
    );
    return active!;
  }
}

class _FailOnceStudySettingsSource extends _StudyFocusSource {
  int studyLoads = 0;

  @override
  Future<StudyFocusSettings?> fetchStudyFocusSettings() {
    studyLoads += 1;
    if (studyLoads == 1) {
      throw StateError('Study Setup read failed');
    }
    return super.fetchStudyFocusSettings();
  }
}

class _UnavailableStudySettingsSource extends _StudyFocusSource {
  @override
  Future<StudyFocusSettings?> fetchStudyFocusSettings() {
    throw StateError('Study Setup read failed');
  }
}

class _RecoveryFocusSource extends FocusSessionSupabaseDataSource {
  _RecoveryFocusSource()
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
  Future<List<FocusSession>> fetchRecentSessions({int limit = 10}) async {
    final endedAt = DateTime.now().subtract(const Duration(minutes: 1));
    final startedAt = endedAt.subtract(const Duration(minutes: 29));
    return [
      FocusSession(
        id: 'completed-with-recovery',
        status: FocusSessionStatus.completed,
        startedAt: startedAt,
        endedAt: endedAt,
        plannedMinutes: 30,
        recoveryMinutes: 10,
        actualMinutes: 29,
        updatedAt: endedAt,
      ),
    ];
  }

  @override
  Future<List<FocusTargetOption>> fetchAvailableTargets() async => const [];

  @override
  Future<StudyFocusSettings?> fetchStudyFocusSettings() async => null;
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

class _BlockingSnapshotRefresh extends _CountingSnapshotRefresh {
  final Completer<void> _completer = Completer<void>();

  @override
  Future<void> refreshDailyAfterFocusChange({
    required String targetDate,
  }) {
    focusCalls += 1;
    return _completer.future;
  }
}

class _TerminalPromptFocusSource extends FocusSessionSupabaseDataSource {
  _TerminalPromptFocusSource({required this.recoveryMinutes})
      : super(
          SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        ) {
    final now = DateTime.now().subtract(const Duration(minutes: 25));
    _active = FocusSession(
      id: 'prompt-session',
      status: FocusSessionStatus.active,
      startedAt: now,
      plannedMinutes: 25,
      recoveryMinutes: recoveryMinutes,
      updatedAt: now,
    );
  }

  final int recoveryMinutes;
  FocusSession? _active;
  FocusSession? _terminal;
  FocusReflection? _reflection;
  int finishCalls = 0;
  int abandonCalls = 0;
  FocusReflectionDraft? savedDraft;

  @override
  Future<FocusSession?> fetchActiveSession() async => _active;

  @override
  Future<List<FocusSession>> fetchRecentSessions({int limit = 10}) async =>
      [if (_terminal != null) _terminal!];

  @override
  Future<List<FocusTargetOption>> fetchAvailableTargets() async => const [];

  @override
  Future<Map<String, FocusReflection>> fetchReflectionsForSessions(
    Iterable<FocusSession> sessions,
  ) async =>
      _reflection == null
          ? const {}
          : {_reflection!.focusSessionId: _reflection!};

  @override
  Future<bool> fetchFocusReflectionPromptEnabled() async => true;

  @override
  Future<FocusSession> finishSession(String sessionId) async {
    finishCalls += 1;
    return _end(FocusSessionStatus.completed);
  }

  @override
  Future<FocusSession> abandonSession(String sessionId) async {
    abandonCalls += 1;
    return _end(FocusSessionStatus.abandoned);
  }

  FocusSession _end(FocusSessionStatus status) {
    final active = _active!;
    final endedAt = active.startedAt.add(const Duration(minutes: 25));
    _terminal = FocusSession(
      id: active.id,
      status: status,
      startedAt: active.startedAt,
      endedAt: endedAt,
      plannedMinutes: active.plannedMinutes,
      recoveryMinutes: active.recoveryMinutes,
      actualMinutes: 25,
      label: active.label,
      updatedAt: endedAt,
    );
    _active = null;
    return _terminal!;
  }

  @override
  Future<FocusReflection> saveReflection({
    required FocusSession session,
    required FocusReflectionDraft draft,
    FocusReflection? existing,
  }) async {
    savedDraft = draft;
    final now = DateTime.now();
    _reflection = FocusReflection(
      focusSessionId: session.id,
      focusQuality: draft.focusQuality,
      usefulProgress: draft.usefulProgress,
      obstacles: draft.obstacles,
      createdAt: now,
      updatedAt: now,
    );
    return _reflection!;
  }

  @override
  Future<void> deleteReflection(FocusReflection reflection) async {
    _reflection = null;
  }
}
