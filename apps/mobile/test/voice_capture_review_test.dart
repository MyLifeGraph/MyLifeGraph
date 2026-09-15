import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/composition/capture_draft_providers.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import 'package:my_life_graph/composition/projection_refresh_providers.dart';
import 'package:my_life_graph/composition/quick_check_in_providers.dart';
import 'package:my_life_graph/composition/skillset_providers.dart';
import 'package:my_life_graph/features/auth/application/profile_local_date_source.dart';
import 'package:my_life_graph/features/quick_action/domain/capture_draft_proposal.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/morning_calibration_page.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/quick_mood_check_in_page.dart';
import 'package:my_life_graph/features/quick_action/presentation/widgets/daily_capture_controls.dart';

CaptureDraftProposal _proposal(String branch, Map<String, Object?> fields) =>
    CaptureDraftProposal.fromJson({
      'contract_version': dailyCaptureDraftVersion,
      'request_id': '5c281fae-9a65-4a04-bca9-3e01f5f0ca7c',
      'owner_id': 'owner-one',
      'entry_date': '2026-09-14',
      'timezone': 'Europe/Berlin',
      'branch': branch,
      'fields': fields,
      'evidence': {
        for (final entry in fields.entries)
          if (entry.value != null) entry.key: 'Explicit ${entry.value}',
      },
    }, ownerId: 'owner-one');

void main() {
  testWidgets(
    'voice load retry keeps edits when the saved branch is unchanged',
    (tester) async {
      final proposal = _proposal('morning', {'current_energy': 8});
      final saved =
          _proposal('morning', {
            'sleep_start': '23:00',
            'wake_time': '07:00',
            'sleep_quality': 7,
            'current_energy': 4,
          }).applyToMorning(
            MorningCalibrationDraft.empty(
              DateTime(2026, 9, 14),
            ).copyWith(sleepTargetMinutes: 480),
            allowSkillset: true,
          );
      final store = _Store(
        initial: DailyCaptureEntry(entryDate: saved.entryDate, morning: saved),
        failEveningOnce: true,
      );
      await _pump(tester, store, proposal);
      tester
          .widget<CaptureSleepTargetControl>(
            find.byType(CaptureSleepTargetControl),
          )
          .onChanged(600);
      await tester.pumpAndSettle();
      await _tap(tester, 'Retry load');
      expect(
        tester
            .widget<CaptureSleepTargetControl>(
              find.byType(CaptureSleepTargetControl),
            )
            .value,
        600,
      );
      await _tap(tester, 'Next');
      await _tap(tester, 'Save');
      expect(store.morningWrites.single.sleepTargetMinutes, 600);
      expect(store.morningWrites.single.energy, 8);
    },
  );
  testWidgets('account change during review prevents saving a foreign draft', (
    tester,
  ) async {
    final store = _Store();
    final ownerState = StateProvider<String?>((_) => 'owner-one');
    await _pump(
      tester,
      store,
      _proposal('morning', {
        'sleep_start': '23:00',
        'wake_time': '07:00',
        'sleep_quality': 7,
        'current_energy': 8,
      }),
      ownerState: ownerState,
    );
    await _tap(tester, 'Next');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MorningCalibrationPage)),
    );
    container.read(ownerState.notifier).state = 'owner-two';
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save'),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.textContaining('different account, day or timezone'),
      findsOneWidget,
    );
    expect(store.morningWrites, isEmpty);
    expect(find.byType(CaptureRatingControl), findsNothing);
  });

  testWidgets('account change hides the previous Evening reflection text', (
    tester,
  ) async {
    final store = _Store();
    final ownerState = StateProvider<String?>((_) => 'owner-one');
    await _pump(
      tester,
      store,
      _proposal('evening', {
        'mood': 7,
        'energy': 8,
        'stress_intensity': 3,
        'planned_sleep_time': '23:00',
        'sleep_target_minutes': 480,
        'reflection_note': 'Private owner-one reflection',
      }),
      ownerState: ownerState,
    );
    await _tap(tester, 'Next');
    await _tap(tester, 'Next');
    expect(find.text('Private owner-one reflection'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(QuickMoodCheckInPage)),
    );
    container.read(ownerState.notifier).state = 'owner-two';
    await tester.pumpAndSettle();
    expect(find.text('Private owner-one reflection'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.textContaining('different account, day or timezone'),
      findsOneWidget,
    );
    expect(store.eveningWrites, isEmpty);
  });

  testWidgets(
    'failed current-branch read applies voice only after successful retry',
    (tester) async {
      final store = _Store(failLoadOnce: true);
      await _pump(
        tester,
        store,
        _proposal('morning', {
          'sleep_start': '23:00',
          'wake_time': '07:00',
          'sleep_quality': 7,
          'current_energy': 8,
        }),
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
            .onPressed,
        isNull,
      );
      expect(store.morningWrites, isEmpty);
      await _tap(tester, 'Retry load');
      await _tap(tester, 'Next');
      await _tap(tester, 'Save');
      expect(store.morningWrites.single.energy, 8);
      expect(store.loads, 2);
    },
  );
  testWidgets(
    'Morning speech stays unsaved until explicit full form confirmation',
    (tester) async {
      final store = _Store();
      await _pump(
        tester,
        store,
        _proposal('morning', {
          'sleep_start': '23:00',
          'wake_time': '07:00',
          'sleep_quality': 7,
          'current_energy': 8,
          'motivation': 2,
        }),
      );
      expect(store.morningWrites, isEmpty);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('morning-sleep-duration')))
            .data,
        '8 h',
      );
      await _tap(tester, 'Next');
      expect(find.text('Study motivation (optional)'), findsOneWidget);
      expect(store.morningWrites, isEmpty);
      await _tap(tester, 'Save');
      expect(store.morningWrites.single.energy, 8);
      expect(store.morningWrites.single.sleepQuality, 7);
      expect(store.morningWrites.single.skillset?.values['motivation'], 2);
      expect(store.morningWrites.single.isComplete, isTrue);
    },
  );

  testWidgets('Morning speech missing rating requires manual completion', (
    tester,
  ) async {
    final store = _Store();
    await _pump(
      tester,
      store,
      _proposal('morning', {
        'sleep_start': '23:00',
        'wake_time': '07:00',
        'current_energy': 8,
      }),
    );
    await _tap(tester, 'Next');
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save'),
          )
          .onPressed,
      isNull,
    );
    final quality = tester
        .widgetList<CaptureRatingControl>(find.byType(CaptureRatingControl))
        .first;
    quality.onChanged(6);
    await tester.pumpAndSettle();
    await _tap(tester, 'Save');
    expect(store.morningWrites.single.sleepQuality, 6);
  });

  testWidgets(
    'Evening preserves stored note and asks for missing stress context',
    (tester) async {
      final saved = EveningShutdownDraft.empty(DateTime(2026, 9, 14)).copyWith(
        mood: 4,
        energy: 5,
        stress: 3,
        plannedSleepTime: '23:00',
        reflectionNote: 'Existing note',
      );
      final store = _Store(
        initial: DailyCaptureEntry(entryDate: saved.entryDate, evening: saved),
      );
      await _pump(
        tester,
        store,
        _proposal('evening', {'stress_intensity': 8, 'sport': 0}),
      );
      expect(find.textContaining('Saving updates today'), findsOneWidget);
      expect(store.eveningWrites, isEmpty);
      await _tap(tester, 'Next');
      await _tap(tester, 'Next');
      expect(find.text('Sport today'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Existing note'), findsOneWidget);
      final source = tester.widget<CaptureChoiceControl<StressSource>>(
        find.byType(CaptureChoiceControl<StressSource>),
      );
      source.onChanged(StressSource.workload);
      await tester.pumpAndSettle();
      final control = tester
          .widget<CaptureChoiceControl<StressControllability>>(
            find.byType(CaptureChoiceControl<StressControllability>),
          );
      control.onChanged(StressControllability.partlyControllable);
      await tester.pumpAndSettle();
      await _tap(tester, 'Save');
      expect(store.eveningWrites.single.reflectionNote, 'Existing note');
      expect(store.eveningWrites.single.mood, 4);
      expect(store.eveningWrites.single.skillset?.values['sport'], 0);
      expect(store.eveningWrites.single.captureId, saved.captureId);
    },
  );

  for (final branch in ['morning', 'evening']) {
    testWidgets(
      '$branch foreign account draft is blocked before loading or writing',
      (tester) async {
        final store = _Store();
        await _pump(tester, store, _proposal(branch, {}), owner: 'other');
        expect(
          find.textContaining('different account, day or timezone'),
          findsOneWidget,
        );
        expect(store.loads, 0);
        expect(store.morningWrites, isEmpty);
        expect(store.eveningWrites, isEmpty);
      },
    );
  }
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  _Store store,
  CaptureDraftProposal proposal, {
  String owner = 'owner-one',
  StateProvider<String?>? ownerState,
}) async {
  tester.view
    ..physicalSize = const Size(1200, 1500)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/review',
    routes: [
      GoRoute(
        path: '/review',
        builder: (_, __) => proposal.branch == 'morning'
            ? MorningCalibrationPage(proposal: proposal)
            : QuickMoodCheckInPage(proposal: proposal),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const Scaffold(body: Text('Done')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (ownerState == null)
          captureDraftOwnerProvider.overrideWithValue(owner)
        else
          captureDraftOwnerProvider.overrideWith(
            (ref) => ref.watch(ownerState),
          ),
        currentInstantProvider.overrideWithValue(
          () => DateTime(2026, 9, 14, 9),
        ),
        profileLocalDateSourceProvider.overrideWithValue(_Dates()),
        quickCheckInStoreProvider.overrideWithValue(store),
        optionalSkillsetCaptureProvider.overrideWithValue(false),
        projectionRefreshCoordinatorProvider.overrideWithValue(
          ProjectionRefreshCoordinator(
            refreshDailySnapshot: (_) async {},
            invalidateProjection: (_) {},
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

class _Dates implements ProfileLocalDateSource {
  @override
  String get timezoneName => 'Europe/Berlin';
  @override
  DateTime today() => DateTime(2026, 9, 14);
  @override
  String todayKey() => '2026-09-14';
  @override
  DateTime dateAt(DateTime instant) => today();
  @override
  String dateKeyAt(DateTime instant) => todayKey();
}

class _Store implements QuickCheckInStore {
  _Store({
    this.initial,
    this.failLoadOnce = false,
    this.failEveningOnce = false,
  });
  final DailyCaptureEntry? initial;
  final bool failLoadOnce;
  final bool failEveningOnce;
  var eveningLoads = 0;
  final morningWrites = <MorningCalibrationDraft>[];
  final eveningWrites = <EveningShutdownDraft>[];
  var loads = 0;
  @override
  QuickCheckInSaveTarget get target => QuickCheckInSaveTarget.guest;
  @override
  Future<DailyCaptureEntry?> loadToday(DateTime today) async {
    loads++;
    if (failLoadOnce && loads == 1) throw StateError('read failed');
    return initial;
  }

  @override
  Future<EveningShutdownDraft?> loadLatestEvening() async {
    eveningLoads++;
    if (failEveningOnce && eveningLoads == 1) throw StateError('read failed');
    return null;
  }

  @override
  Future<void> saveMorning(MorningCalibrationDraft draft) async {
    draft.validate();
    morningWrites.add(draft);
  }

  @override
  Future<void> saveEvening(EveningShutdownDraft draft) async {
    draft.validate();
    eveningWrites.add(draft);
  }
}
