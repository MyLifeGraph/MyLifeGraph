import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';
import 'package:my_life_graph/composition/quick_capture_providers.dart';
import 'package:my_life_graph/composition/widgets/capture_dictation_input.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/core/navigation/app_routes.dart';
import 'package:my_life_graph/core/network/api_failure.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/auth/application/profile_local_date_source.dart';
import 'package:my_life_graph/features/quick_action/domain/capture_draft_proposal.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_capture_api.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/ultra_quick_check_in_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('German guide changes hints only and stays visible while recording', (tester) async {
    final api = _Api();
    await _pump(tester, api, width: 320);
    await tester.tap(find.byKey(const Key('capture-language-toggle')));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.hintText, contains('Schlafqualität: … / 10'));
    expect(field.controller!.text, isEmpty);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Evening'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).decoration!.hintText,
        contains('Stimmung: … / 10'));
    await tester.enterText(find.byType(TextField), 'Meine eigenen Worte');
    tester.widget<CaptureDictationInput>(find.byType(CaptureDictationInput)).onBusyChanged(true);
    await tester.pumpAndSettle();
    expect(find.textContaining('Soziale Kontakte (optional)'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const Key('capture-language-toggle'))).onPressed, isNull);
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
  for (final mode in ['Morning', 'Evening']) {
    testWidgets('$mode guide hides on typing and stays during dictation', (
      tester,
    ) async {
      final api = _Api();
      await _pump(tester, api, width: 390);
      await tester.tap(find.widgetWithText(ChoiceChip, mode));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      final guide = field.decoration!.hintText!;
      expect(
        guide,
        contains(mode == 'Morning' ? 'Sleep quality: … / 10' : 'Mood: … / 10'),
      );
      expect(field.controller!.text, isEmpty);
      await tester.enterText(find.byType(TextField), 'My own words');
      await tester.pumpAndSettle();
      expect(find.text(guide).hitTestable(), findsNothing);
      tester
          .widget<CaptureDictationInput>(find.byType(CaptureDictationInput))
          .onBusyChanged(true);
      await tester.pump();
      expect(find.text(guide), findsOneWidget);
      expect(find.text('Speaking guide'), findsOneWidget);
      tester
          .widget<CaptureDictationInput>(find.byType(CaptureDictationInput))
          .onText('more words');
      tester
          .widget<CaptureDictationInput>(find.byType(CaptureDictationInput))
          .onBusyChanged(false);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'My own words more words',
      );
      expect(api.calls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('guest makes no calls and has no cloud capture action', (
    tester,
  ) async {
    final api = _Api();
    await _pump(tester, api, owner: null);
    expect(
      find.text('Sign in to use voice check-ins and cloud notes.'),
      findsOneWidget,
    );
    expect(find.text('Save note'), findsNothing);
    expect(api.calls, isEmpty);
  });

  testWidgets(
    'note is saved only explicitly and exact retry retains its identity',
    (tester) async {
      final api = _Api()..failSave = true;
      await _pump(tester, api);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Quick note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A useful thought');
      await tester.pump();
      expect(api.calls, isEmpty);
      await tester.ensureVisible(find.text('Save note'));
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(find.text('A useful thought'), findsOneWidget);
      expect(
        find.text('Note not confirmed. Your text is kept; try again.'),
        findsOneWidget,
      );
      api.failSave = false;
      await tester.ensureVisible(find.text('Save note'));
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(api.calls, hasLength(2));
      expect(api.calls[0], api.calls[1]);
      expect(find.text('Note saved.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'note exact retry keeps the original timezone after profile changes',
    (tester) async {
      final api = _Api()..failSave = true;
      final date = _Date();
      await _pump(tester, api, date: date);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Quick note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A useful thought');
      await tester.pump();
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      final original = api.calls.single;
      expect(original, contains('|Europe/Berlin|'));
      date.zone = 'America/New_York';
      api.failSave = false;
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(api.calls, [original, original]);
      expect(find.text('Note saved.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'A new thought');
      await tester.pump();
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(api.calls.last, contains('|America/New_York|A new thought'));
      expect(api.calls.last.split('|').first, isNot(original.split('|').first));
    },
  );

  testWidgets(
    'conflicted note keeps text and identity until explicitly edited',
    (tester) async {
      final api = _Api()
        ..saveError = const AppException(
          'Conflict',
          cause: ApiFailure(kind: ApiFailureKind.response, statusCode: 409),
        );
      final date = _Date();
      await _pump(tester, api, date: date);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Quick note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Unconfirmed note');
      await tester.pump();
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      final original = api.calls.single;
      expect(
        find.textContaining('Check saved notes before editing'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Unconfirmed note',
      );
      date.zone = 'America/New_York';
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(api.calls, [original, original]);
      await tester.enterText(
        find.byType(TextField),
        'Reviewed unconfirmed note',
      );
      await tester.pump();
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(
        api.calls.last,
        contains('|America/New_York|Reviewed unconfirmed note'),
      );
      expect(api.calls.last.split('|').first, isNot(original.split('|').first));
    },
  );

  testWidgets(
    'confirmed proposal opens review and Back preserves the transcript',
    (tester) async {
      CaptureDraftProposal? reviewed;
      final api = _Api()
        ..proposal = (id, branch, text) async => _proposal(id, branch);
      await _pump(tester, api, onReview: (value) => reviewed = value);
      await tester.enterText(find.byType(TextField), 'Energy 7');
      await tester.pump();
      expect(api.calls, isEmpty);
      await tester.tap(find.text('Review fields'));
      await tester.pumpAndSettle();
      expect(find.text('Review form'), findsOneWidget);
      expect(reviewed?.fields, {'current_energy': 7});
      expect(reviewed?.evidence, {'current_energy': 'Energy 7'});
      expect(api.calls, ['draft:${reviewed!.requestId}']);
      await tester.tap(find.text('Back to transcript'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Energy 7',
      );
      await tester.tap(find.text('Review fields'));
      await tester.pumpAndSettle();
      expect(api.calls, hasLength(2));
      expect(api.calls[0], isNot(api.calls[1]));
    },
  );

  for (final mismatch in ['owner', 'day', 'timezone', 'request', 'evidence']) {
    testWidgets('rejects a proposal with mismatched $mismatch', (tester) async {
      final api = _Api()
        ..proposal = (id, branch, text) async {
          final response = _proposal(id, branch);
          switch (mismatch) {
            case 'owner':
              response['owner_id'] = 'owner-b';
            case 'day':
              response['entry_date'] = '2026-09-13';
            case 'timezone':
              response['timezone'] = 'America/New_York';
            case 'request':
              response['request_id'] = 'another-request';
            case 'evidence':
              response['evidence'] = {'current_energy': 'Energy 9'};
          }
          return response;
        };
      await _pump(tester, api);
      await tester.enterText(find.byType(TextField), 'Energy 7');
      await tester.pump();
      await tester.tap(find.text('Review fields'));
      await tester.pumpAndSettle();
      expect(find.text('Review form'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Energy 7',
      );
      expect(
        find.textContaining('Could not prepare your check-in.'),
        findsOneWidget,
      );
    });
  }

  for (final change in ['day', 'timezone']) {
    testWidgets('new $change rebinds a failed draft only on explicit retry', (
      tester,
    ) async {
      final date = _Date();
      final api = _Api();
      await _pump(tester, api, date: date);
      await tester.enterText(find.byType(TextField), 'Energy 7');
      await tester.pump();
      await tester.tap(find.text('Review fields'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review fields'));
      await tester.pumpAndSettle();
      expect(api.calls[0], api.calls[1]);
      if (change == 'day') {
        date.day = '2026-09-15';
      } else {
        date.zone = 'America/New_York';
      }
      await tester.pump();
      expect(api.calls, hasLength(2));
      await tester.tap(find.text('Review fields'));
      await tester.pumpAndSettle();
      expect(api.calls, hasLength(3));
      expect(api.calls[2], isNot(api.calls[1]));
    });
  }

  testWidgets('request limit is visible and retains text and retry identity', (
    tester,
  ) async {
    final api = _Api()
      ..proposal = (_, __, ___) async => throw const AppException(
        'Unavailable',
        cause: ApiFailure(kind: ApiFailureKind.response, statusCode: 429),
      );
    await _pump(tester, api);
    await tester.enterText(find.byType(TextField), 'Energy 7');
    await tester.pump();
    await tester.tap(find.text('Review fields'));
    await tester.pumpAndSettle();
    expect(find.textContaining('busy or at its request limit'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Energy 7',
    );
    await tester.tap(find.text('Review fields'));
    await tester.pumpAndSettle();
    expect(api.calls[0], api.calls[1]);
  });

  testWidgets('saved notes cannot start a competing read during note save', (
    tester,
  ) async {
    final pending = Completer<QuickNote>();
    final api = _Api()..pending = pending;
    await _pump(tester, api);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Quick note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'New note');
    await tester.pump();
    await tester.tap(find.text('Save note'));
    await tester.pump();
    expect(
      tester.widget<ExpansionTile>(find.byType(ExpansionTile)).enabled,
      isFalse,
    );
    await tester.tap(find.text('Saved notes'));
    await tester.pump();
    expect(api.noteReads, 0);
    pending.complete(
      const QuickNote(
        id: 'new-note',
        text: 'New note',
        entryDate: '2026-09-14',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Note saved.'), findsOneWidget);
    expect(
      tester.widget<ExpansionTile>(find.byType(ExpansionTile)).enabled,
      isTrue,
    );
  });

  testWidgets(
    'account change clears unsaved text and ignores late save result',
    (tester) async {
      final pending = Completer<QuickNote>();
      final api = _Api()..pending = pending;
      final owner = StateProvider<String?>((ref) => 'owner-a');
      final container = await _pump(tester, api, ownerProvider: owner);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Quick note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Private thought');
      await tester.pump();
      await tester.ensureVisible(find.text('Save note'));
      await tester.tap(find.text('Save note'));
      await tester.pump();
      expect(api.calls, hasLength(1));
      container.read(owner.notifier).state = 'owner-b';
      await tester.pump();
      pending.complete(
        const QuickNote(
          id: 'id',
          text: 'Private thought',
          entryDate: '2026-09-14',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private thought'), findsNothing);
      expect(find.text('Note saved.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'compact capture at 320px and text scale $scale has no overflow',
      (tester) async {
        await _pump(tester, _Api(), width: 320, scale: scale);
        final chipTops = tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .map((chip) => tester.getTopLeft(find.byWidget(chip)).dy)
            .toSet();
        expect(chipTops, hasLength(1));
        for (final label in ['Morning', 'Evening', 'Quick note']) {
          final bounds = tester.getRect(
            find.ancestor(
              of: find.text(label),
              matching: find.byType(ChoiceChip),
            ),
          );
          final textBounds = tester.getRect(find.text(label));
          expect(bounds.contains(textBounds.topLeft), isTrue);
          expect(
            bounds.contains(textBounds.bottomRight - const Offset(0.1, 0.1)),
            isTrue,
          );
        }
        await tester.tap(find.widgetWithText(ChoiceChip, 'Evening'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Quick note'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Saved notes').hitTestable(),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Saved notes'));
        await tester.pumpAndSettle();
        expect(find.text('No saved notes yet.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Api api, {
  String? owner = 'owner-a',
  StateProvider<String?>? ownerProvider,
  double width = 700,
  double scale = 1,
  _Date? date,
  ValueChanged<CaptureDraftProposal>? onReview,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      quickCaptureProfileIdProvider.overrideWith(
        (ref) => ownerProvider == null ? owner : ref.watch(ownerProvider),
      ),
      quickCaptureApiProvider.overrideWithValue(api),
      profileLocalDateSourceProvider.overrideWithValue(date ?? _Date()),
      appSurfaceCapabilitiesProvider.overrideWithValue(
        const AppSurfaceCapabilities(
          isLocalDemo: false,
          canUseSyncedHabits: true,
          canUseSyncedExecution: true,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const UltraQuickCheckInPage()),
      for (final path in [
        AppRoutes.morningCalibration,
        AppRoutes.quickMoodCheckIn,
      ])
        GoRoute(
          path: path,
          builder: (context, state) {
            onReview?.call(state.extra! as CaptureDraftProposal);
            return Scaffold(
              body: Column(
                children: [
                  const Text('Review form'),
                  TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('Back to transcript'),
                  ),
                ],
              ),
            );
          },
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

class _Date implements ProfileLocalDateSource {
  String day = '2026-09-14';
  String zone = 'Europe/Berlin';
  @override
  String get timezoneName => zone;
  @override
  DateTime dateAt(DateTime instant) => DateTime.parse(day);
  @override
  String dateKeyAt(DateTime instant) => day;
  @override
  DateTime today() => dateAt(DateTime.now());
  @override
  String todayKey() => day;
}

Map<String, dynamic> _proposal(String id, String branch) => {
  'contract_version': dailyCaptureDraftVersion,
  'owner_id': 'owner-a',
  'request_id': id,
  'entry_date': '2026-09-14',
  'timezone': 'Europe/Berlin',
  'branch': branch,
  'fields': {'current_energy': 7},
  'evidence': {'current_energy': 'Energy 7'},
};

class _Api implements QuickCaptureApi {
  final calls = <String>[];
  bool failSave = false;
  Object? saveError;
  Completer<QuickNote>? pending;
  Future<Map<String, dynamic>> Function(String, String, String)? proposal;
  int noteReads = 0;
  @override
  Future<QuickNote> saveNote({
    required String noteId,
    required String timezone,
    required String text,
  }) async {
    calls.add('$noteId|$timezone|$text');
    if (saveError != null) throw saveError!;
    if (failSave) throw StateError('Unavailable');
    return pending?.future ??
        Future.value(
          QuickNote(id: noteId, text: text, entryDate: '2026-09-14'),
        );
  }

  @override
  Future<QuickNotesPage> notes({String? before}) async {
    noteReads++;
    return const QuickNotesPage([], null);
  }

  @override
  Future<void> deleteNote(String noteId) async {
    calls.add('delete:$noteId');
  }

  @override
  Future<Map<String, dynamic>> propose({
    required String requestId,
    required String branch,
    required String transcript,
  }) async {
    calls.add('draft:$requestId');
    if (proposal != null) return proposal!(requestId, branch, transcript);
    throw StateError('Not used');
  }
}
