import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/quick_mood_check_in_page.dart';
import 'package:my_life_graph/features/quick_action/presentation/providers/quick_check_in_providers.dart';
import 'package:my_life_graph/features/snapshots/application/snapshot_refresh_service.dart';
import 'package:my_life_graph/features/snapshots/data/snapshot_api_data_source.dart';
import 'package:my_life_graph/features/snapshots/presentation/providers/snapshot_providers.dart';

void main() {
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
    expect(first.mainFriction, MainFriction.emotionalLoad);
    expect(first.tomorrowPriority, 'Protect the exact priority');
    expect(first.reflectionNote, 'Exact retry reflection');
    expect(first.specificBlocker, 'Exact retry blocker');
    expect(first.makeTomorrowGentler, isTrue);
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
      makeTomorrowGentler: false,
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
    expect(
      _textFieldWithLabel('Reflection (optional)'),
      findsOneWidget,
    );
    await _tapVisible(tester, find.text('Save evening check-in'));
    await tester.pumpAndSettle();

    final written = store.eveningAttempts.single.toMetadataJson();
    expect(written, isNot(contains('reflection_note')));
    expect(written, isNot(contains('specific_blocker')));
    expect(written, isNot(contains('gentle_tomorrow')));
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
}

Future<void> _pumpEveningPage(
  WidgetTester tester,
  QuickCheckInStore store, {
  SnapshotRefreshService? snapshotRefresh,
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
        quickCheckInStoreProvider.overrideWithValue(store),
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

  await _tapVisible(
    tester,
    find.bySemanticsLabel('main friction emotional_load'),
  );
  await _tapVisible(
    tester,
    find.bySemanticsLabel('stress source private_emotional'),
  );
  await _tapVisible(
    tester,
    find.bySemanticsLabel('stress influence hardly_controllable'),
  );

  await tester.enterText(
    _textFieldWithLabel('Possible priority tomorrow (optional)'),
    'Protect the exact priority',
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
    await _tapVisible(
      tester,
      find.bySemanticsLabel('make tomorrow gentler'),
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
  bool makeTomorrowGentler = true,
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
    mainFriction: MainFriction.emotionalLoad,
    tomorrowPriority: 'Protect the exact priority',
    reflectionNote: reflectionNote,
    specificBlocker: specificBlocker,
    makeTomorrowGentler: makeTomorrowGentler,
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
  Future<void> saveEvening(EveningShutdownDraft draft) async {
    eveningAttempts.add(draft.normalized());
  }

  @override
  Future<void> saveMorning(MorningCalibrationDraft draft) async {}
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
