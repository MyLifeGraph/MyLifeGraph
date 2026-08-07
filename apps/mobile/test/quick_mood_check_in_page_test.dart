import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/auth/application/profile_local_date_source.dart';
import 'package:my_life_graph/composition/projection_refresh_providers.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import 'package:my_life_graph/features/focus/data/focus_session_supabase_data_source.dart';
import 'package:my_life_graph/features/focus/domain/focus_session.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/quick_mood_check_in_page.dart';
import 'package:my_life_graph/composition/quick_check_in_providers.dart';
import 'package:my_life_graph/features/quick_action/presentation/widgets/daily_capture_controls.dart';
import 'package:my_life_graph/features/snapshots/application/snapshot_refresh_service.dart';
import 'package:my_life_graph/features/snapshots/data/snapshot_api_data_source.dart';
import 'package:my_life_graph/features/snapshots/presentation/providers/snapshot_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('first Evening value shows eight hours but still requires a time',
      (tester) async {
    final store = _NoSleepPlanStore();
    await _pumpEveningPage(tester, store);

    await tester.tap(find.bySemanticsLabel('evening mood 7 of 10'));
    await tester.tap(find.bySemanticsLabel('evening energy 7 of 10'));
    await tester.tap(find.bySemanticsLabel('evening stress 3 of 10'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('8 h'), findsWidgets);
    expect(
      find.textContaining('becomes your current sleep plan'),
      findsOneWidget,
    );
    final next = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Next'),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('latest Evening sleep plan prefills the next save',
      (tester) async {
    await _pumpEveningPage(tester, _RecordingCaptureStore());

    await tester.tap(find.bySemanticsLabel('evening mood 7 of 10'));
    await tester.tap(find.bySemanticsLabel('evening energy 7 of 10'));
    await tester.tap(find.bySemanticsLabel('evening stress 3 of 10'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('23:00'), findsWidgets);
    expect(find.text('8 h'), findsWidgets);
    final next = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Next'),
    );
    expect(next.onPressed, isNotNull);
  });

  testWidgets('top back returns an Evening flow step before leaving the route',
      (tester) async {
    await _pumpEveningPage(tester, _RecordingCaptureStore());
    await tester.tap(find.bySemanticsLabel('evening mood 7 of 10'));
    await tester.tap(find.bySemanticsLabel('evening energy 7 of 10'));
    await tester.tap(find.bySemanticsLabel('evening stress 3 of 10'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Planned sleep time'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('capture-flow-back')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Close today in under a minute'), findsOneWidget);
    expect(find.text('Planned sleep time'), findsNothing);
    expect(find.text('7 / 10'), findsNWidgets(2));
  });

  testWidgets('authenticated evening failure retains exact draft for retry',
      (tester) async {
    final store = _FailOnceCaptureStore();
    final snapshotRefresh = _RecordingSnapshotRefreshService();
    await _pumpEveningPage(tester, store, snapshotRefresh: snapshotRefresh);

    await _completeEveningDraft(tester);
    await _tapVisible(tester, find.text('Save evening check-in'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Could not save. Your answers are still here. Try again.',
      ),
      findsWidgets,
    );
    expect(store.eveningAttempts, hasLength(1));
    final first = store.eveningAttempts.single;
    expect(first.mood, 2);
    expect(first.energy, 9);
    expect(first.stress, 8);
    expect(first.stressSource, StressSource.privateEmotional);
    expect(
      first.stressControllability,
      StressControllability.hardlyControllable,
    );
    expect(first.focusBand, isNull);
    expect(first.mainFriction, isNull);
    expect(first.additionalFrictions, isEmpty);
    expect(first.tomorrowPriority, isEmpty);
    expect(first.reflectionNote, 'Exact retry reflection');
    expect(first.specificBlocker, 'Exact retry blocker');
    expect(first.plannedSleepTime, '23:00');
    expect(first.sleepTargetMinutes, 480);
    expect(snapshotRefresh.targetDates, isEmpty);

    await _tapVisible(tester, find.text('Save evening check-in'));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard destination'), findsOneWidget);
    expect(store.eveningAttempts, hasLength(2));
    expect(store.eveningAttempts[1].captureId, first.captureId);
    expect(
      store.eveningAttempts[1].toMetadataJson(),
      first.toMetadataJson(),
    );
    expect(snapshotRefresh.targetDates, [first.entryDate]);
  });

  testWidgets('evening re-entry is prefilled and blank optionals stay blank',
      (tester) async {
    final saved = _eveningDraft(
      reflectionNote: '',
      specificBlocker: '',
    );
    final store = _RecordingCaptureStore(
      initial: DailyCaptureEntry(entryDate: saved.entryDate, evening: saved),
    );
    await _pumpEveningPage(tester, store);

    expect(
      find.text(
        'Today\'s evening check-in is loaded. Saving updates only these evening answers.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(
      _textFieldWithLabel('Possible priority tomorrow (optional)'),
      findsNothing,
    );
    expect(
      _textFieldWithLabel('Reflection (optional)'),
      findsOneWidget,
    );
    await _tapVisible(tester, find.text('Save evening check-in'));
    await tester.pumpAndSettle();

    final written = store.eveningAttempts.single.toMetadataJson();
    expect(written, isNot(contains('main_friction')));
    expect(written, isNot(contains('additional_frictions')));
    expect(written, isNot(contains('reflection_note')));
    expect(written, isNot(contains('specific_blocker')));
    expect(written, isNot(contains('gentle_tomorrow')));
    expect(written['tomorrow_priority'], 'Protect the exact priority');
  });

  testWidgets('evening omits friction choices but keeps stress and notes',
      (tester) async {
    final store = _RecordingCaptureStore();
    await _pumpEveningPage(tester, store);

    await _completeEveningDraft(tester, includeOptionals: false);

    expect(find.text('Make tomorrow gentler'), findsNothing);
    expect(find.textContaining('friction'), findsNothing);
    expect(find.text('What drove the pressure?'), findsOneWidget);
    expect(
      _textFieldWithLabel('Possible priority tomorrow (optional)'),
      findsNothing,
    );
    expect(_textFieldWithLabel('Specific blocker (optional)'), findsOneWidget);
    await _tapVisible(tester, find.text('Save evening check-in'));
    await tester.pumpAndSettle();

    final saved = store.eveningAttempts.single;
    expect(saved.mainFriction, isNull);
    expect(saved.additionalFrictions, isEmpty);
    expect(saved.stressSource, StressSource.privateEmotional);
    expect(saved.toMetadataJson(), isNot(contains('tomorrow_priority')));
  });

  testWidgets(
      'stress source info supports hover and tap without changing selection',
      (tester) async {
    var changed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CaptureChoiceControl<String>(
            value: null,
            choices: const [
              CaptureChoice(
                value: 'workload',
                label: 'Workload',
                semanticLabel: 'stress source workload',
                description: 'Deadlines, volume, meetings, or responsibility',
              ),
            ],
            onChanged: (_) => changed += 1,
          ),
        ),
      ),
    );

    final info = find.byKey(
      const ValueKey('capture-choice-info-Workload'),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(info));
    await mouse.moveTo(tester.getCenter(info));
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('Deadlines, volume, meetings, or responsibility'),
      findsOneWidget,
    );
    expect(changed, 0);

    await mouse.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();
    await tester.tap(info);
    await tester.pumpAndSettle();
    expect(
      find.text('Deadlines, volume, meetings, or responsibility'),
      findsOneWidget,
    );
    expect(changed, 0);
    expect(
      find.bySemanticsLabel(
        'More information about Workload: '
        'Deadlines, volume, meetings, or responsibility',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'influence choices stay equal and horizontal at narrow large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: CaptureChoiceControl<String>(
            value: null,
            equalWidthRow: true,
            choices: const [
              CaptureChoice(value: 'little', label: 'Little influence'),
              CaptureChoice(value: 'some', label: 'Some influence'),
              CaptureChoice(
                value: 'mostly',
                label: 'Mostly within my influence',
              ),
            ],
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final chips = find.byType(ChoiceChip);
    expect(chips, findsNWidgets(3));
    final rects = [
      for (var index = 0; index < 3; index++) tester.getRect(chips.at(index)),
    ];
    expect(rects[0].top, rects[1].top);
    expect(rects[1].top, rects[2].top);
    expect(rects[0].width, closeTo(rects[1].width, 0.01));
    expect(rects[1].width, closeTo(rects[2].width, 0.01));
    expect(rects[0].height, closeTo(rects[1].height, 0.01));
    expect(rects[1].height, closeTo(rects[2].height, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving state prevents a duplicate in-flight evening write',
      (tester) async {
    final store = _PendingCaptureStore();
    await _pumpEveningPage(tester, store);
    await _completeEveningDraft(tester, includeOptionals: false);

    await _tapVisible(tester, find.text('Save evening check-in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Saving...'));
    await tester.pump();

    expect(store.calls, 1);
    store.complete();
    await tester.pumpAndSettle();
    expect(find.text('Dashboard destination'), findsOneWidget);
  });

  testWidgets(
      'dismissed reflection sheet still invalidates Full week after save',
      (tester) async {
    final source = _PendingFocusReflectionSource();
    final projection = _RecordingProjectionRefresh();
    await _pumpEveningPage(
      tester,
      _RecordingCaptureStore(),
      focusSource: source,
      projectionRefresh: projection.coordinator,
      currentInstant: _reflectionNow,
    );
    await _openReflectionSheet(tester);

    await tester.tap(find.bySemanticsLabel('Focus quality 4 of 5'));
    await tester.tap(find.bySemanticsLabel('Useful progress 5 of 5'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-focus-reflection')));
    await tester.pump();
    expect(source.saveCalls, 1);

    final sheetContext =
        tester.element(find.byKey(const ValueKey('focus-reflection-sheet')));
    Navigator.of(sheetContext).pop();
    await tester.pumpAndSettle();
    source.completeSave();
    await tester.pump();
    await tester.pump();

    expect(projection.fullWeekInvalidations, 1);
    expect(find.text('Focus reflection saved.'), findsNothing);
  });

  testWidgets(
      'dismissed reflection sheet still invalidates Full week after delete',
      (tester) async {
    final source = _PendingFocusReflectionSource(withExisting: true);
    final projection = _RecordingProjectionRefresh();
    await _pumpEveningPage(
      tester,
      _RecordingCaptureStore(),
      focusSource: source,
      projectionRefresh: projection.coordinator,
      currentInstant: _reflectionNow,
    );
    await _openReflectionSheet(tester);

    await tester.tap(find.byKey(const ValueKey('delete-focus-reflection')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete reflection'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(source.deleteCalls, 1);

    final sheetContext =
        tester.element(find.byKey(const ValueKey('focus-reflection-sheet')));
    Navigator.of(sheetContext).pop();
    await tester.pumpAndSettle();
    source.completeDelete();
    await tester.pump();
    await tester.pump();

    expect(projection.fullWeekInvalidations, 1);
    expect(find.text('Focus reflection deleted.'), findsNothing);
  });

  testWidgets('reflection refresh failure does not turn save into an error',
      (tester) async {
    final source = _PendingFocusReflectionSource(immediateSave: true);
    final projection = _RecordingProjectionRefresh(throwOnFullWeek: true);
    await _pumpEveningPage(
      tester,
      _RecordingCaptureStore(),
      focusSource: source,
      projectionRefresh: projection.coordinator,
      currentInstant: _reflectionNow,
    );
    await _openReflectionSheet(tester);

    await tester.tap(find.bySemanticsLabel('Focus quality 4 of 5'));
    await tester.tap(find.bySemanticsLabel('Useful progress 5 of 5'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-focus-reflection')));
    await tester.pumpAndSettle();

    expect(source.saveCalls, 1);
    expect(projection.fullWeekInvalidations, 1);
    expect(find.text('Focus reflection saved.'), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-reflection-error')), findsNothing);
  });
}

final _reflectionNow = DateTime(2026, 8, 5, 18);

Future<void> _openReflectionSheet(WidgetTester tester) async {
  await _completeEveningDraft(tester, includeOptionals: false);
  await _tapVisible(
    tester,
    find.byKey(const ValueKey('evening-focus-reflections')),
  );
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey('focus-reflection-sheet')),
    findsOneWidget,
  );
}

Future<void> _pumpEveningPage(
  WidgetTester tester,
  QuickCheckInStore store, {
  SnapshotRefreshService? snapshotRefresh,
  FocusSessionSupabaseDataSource? focusSource,
  ProjectionRefreshCoordinator? projectionRefresh,
  DateTime? currentInstant,
}) async {
  final router = GoRouter(
    initialLocation: '/quick-mood-check-in',
    routes: [
      GoRoute(
        path: '/quick-mood-check-in',
        builder: (_, __) => const QuickMoodCheckInPage(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const Scaffold(body: Text('Dashboard destination')),
      ),
      GoRoute(
        path: '/quick-action',
        builder: (_, __) => const Scaffold(body: Text('Quick action')),
      ),
    ],
  );
  addTearDown(router.dispose);
  tester.view.physicalSize = const Size(1200, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileLocalDateSourceProvider.overrideWithValue(
          SessionProfileLocalDateSource(
            session: null,
            currentInstant:
                currentInstant == null ? DateTime.now : () => currentInstant,
          ),
        ),
        if (currentInstant != null)
          currentInstantProvider.overrideWithValue(() => currentInstant),
        quickCheckInStoreProvider.overrideWithValue(store),
        if (focusSource != null)
          eveningFocusReflectionSourceProvider.overrideWithValue(focusSource),
        if (projectionRefresh != null)
          projectionRefreshCoordinatorProvider.overrideWithValue(
            projectionRefresh,
          ),
        if (snapshotRefresh != null)
          snapshotRefreshServiceProvider.overrideWithValue(snapshotRefresh),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _completeEveningDraft(
  WidgetTester tester, {
  bool includeOptionals = true,
}) async {
  await tester.tap(find.bySemanticsLabel('evening mood 2 of 10'));
  await tester.pump();
  await tester.tap(find.bySemanticsLabel('evening energy 9 of 10'));
  await tester.pump();
  await tester.tap(find.bySemanticsLabel('evening stress 8 of 10'));
  await tester.pump();
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
  expect(find.text('Planned sleep time'), findsOneWidget);
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();

  await _tapVisible(
    tester,
    find.bySemanticsLabel('stress source private_emotional'),
  );
  await _tapVisible(
    tester,
    find.bySemanticsLabel('stress influence hardly_controllable'),
  );

  if (includeOptionals) {
    await tester.enterText(
      _textFieldWithLabel('Reflection (optional)'),
      'Exact retry reflection',
    );
    await tester.enterText(
      _textFieldWithLabel('Specific blocker (optional)'),
      'Exact retry blocker',
    );
  }
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

EveningShutdownDraft _eveningDraft({
  String reflectionNote = 'Saved reflection',
  String specificBlocker = 'Saved blocker',
}) {
  final now = DateTime.now();
  return EveningShutdownDraft(
    captureId: 'saved-evening',
    entryDate: dailyCaptureEntryDate(now),
    capturedAt: now,
    mood: 2,
    energy: 9,
    stress: 8,
    stressSource: StressSource.privateEmotional,
    stressControllability: StressControllability.hardlyControllable,
    focusBand: FocusBand.thirtyToSixtyMinutes,
    tomorrowPriority: 'Protect the exact priority',
    reflectionNote: reflectionNote,
    specificBlocker: specificBlocker,
    plannedSleepTime: '23:00',
    sleepTargetMinutes: 480,
    branchVersion: dailyCaptureV4,
  );
}

Finder _textFieldWithLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
      description: 'TextField with label $label',
    );

class _RecordingCaptureStore implements QuickCheckInStore {
  _RecordingCaptureStore({this.initial});

  final DailyCaptureEntry? initial;
  final List<EveningShutdownDraft> eveningAttempts = [];

  @override
  QuickCheckInSaveTarget get target => QuickCheckInSaveTarget.guest;

  @override
  Future<DailyCaptureEntry?> loadToday(DateTime today) async => initial;

  @override
  Future<EveningShutdownDraft?> loadLatestEvening() async =>
      initial?.evening ?? _eveningDraft();

  @override
  Future<void> saveEvening(EveningShutdownDraft draft) async {
    eveningAttempts.add(draft.normalized());
  }

  @override
  Future<void> saveMorning(MorningCalibrationDraft draft) async {}
}

class _NoSleepPlanStore extends _RecordingCaptureStore {
  @override
  Future<EveningShutdownDraft?> loadLatestEvening() async => null;
}

class _FailOnceCaptureStore extends _RecordingCaptureStore {
  @override
  QuickCheckInSaveTarget get target => QuickCheckInSaveTarget.supabase;

  @override
  Future<void> saveEvening(EveningShutdownDraft draft) async {
    await super.saveEvening(draft);
    if (eveningAttempts.length == 1) {
      throw StateError('planned failure');
    }
  }
}

class _PendingCaptureStore extends _RecordingCaptureStore {
  final _completer = Completer<void>();
  int calls = 0;

  @override
  Future<void> saveEvening(EveningShutdownDraft draft) {
    calls++;
    return _completer.future;
  }

  void complete() => _completer.complete();
}

class _RecordingSnapshotRefreshService extends SnapshotRefreshService {
  _RecordingSnapshotRefreshService()
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

  final List<String?> targetDates = [];

  @override
  Future<void> refreshDailyAfterUserSignal({String? targetDate}) async {
    targetDates.add(targetDate);
  }
}

class _PendingFocusReflectionSource extends FocusSessionSupabaseDataSource {
  _PendingFocusReflectionSource({
    this.withExisting = false,
    this.immediateSave = false,
  }) : super(
          SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final bool withExisting;
  final bool immediateSave;
  final Completer<FocusReflection> _saveCompleter = Completer();
  final Completer<void> _deleteCompleter = Completer();
  int saveCalls = 0;
  int deleteCalls = 0;

  FocusSession get session => FocusSession(
        id: '11111111-1111-4111-8111-111111111111',
        status: FocusSessionStatus.completed,
        startedAt: DateTime.utc(2026, 8, 5, 15),
        endedAt: DateTime.utc(2026, 8, 5, 15, 25),
        plannedMinutes: 25,
        actualMinutes: 25,
        label: 'Algorithms review',
        entryDate: '2026-08-05',
        updatedAt: DateTime.utc(2026, 8, 5, 15, 25),
      );

  FocusReflection get reflection => FocusReflection(
        focusSessionId: session.id,
        focusQuality: 4,
        usefulProgress: 5,
        obstacles: const [],
        createdAt: DateTime.utc(2026, 8, 5, 15, 30),
        updatedAt: DateTime.utc(2026, 8, 5, 15, 30),
      );

  @override
  Future<List<FocusSession>> fetchRecentSessions({int limit = 10}) async =>
      [session];

  @override
  Future<Map<String, FocusReflection>> fetchReflectionsForSessions(
    Iterable<FocusSession> sessions,
  ) async =>
      withExisting ? {session.id: reflection} : const {};

  @override
  Future<FocusReflection> saveReflection({
    required FocusSession session,
    required FocusReflectionDraft draft,
    FocusReflection? existing,
  }) {
    saveCalls += 1;
    return immediateSave ? Future.value(reflection) : _saveCompleter.future;
  }

  @override
  Future<void> deleteReflection(FocusReflection reflection) {
    deleteCalls += 1;
    return _deleteCompleter.future;
  }

  void completeSave() => _saveCompleter.complete(reflection);

  void completeDelete() => _deleteCompleter.complete();
}

class _RecordingProjectionRefresh {
  _RecordingProjectionRefresh({this.throwOnFullWeek = false});

  final bool throwOnFullWeek;
  int fullWeekInvalidations = 0;
  late final ProjectionRefreshCoordinator coordinator =
      ProjectionRefreshCoordinator(
    refreshDailySnapshot: (_) async {},
    invalidateProjection: (projection) {
      if (projection == ProductProjection.todayFullWeek) {
        fullWeekInvalidations += 1;
        if (throwOnFullWeek) throw StateError('refresh unavailable');
      }
    },
  );
}
