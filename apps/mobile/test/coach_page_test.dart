import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/widgets/app_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/coach_credentials_providers.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/coach/application/coach_credentials_controller.dart';
import 'package:my_life_graph/features/coach/data/coach_api_data_source.dart';
import 'package:my_life_graph/features/coach/data/coach_credential_store.dart';
import 'package:my_life_graph/features/coach/domain/coach.dart';
import 'package:my_life_graph/features/coach/domain/coach_repository.dart';
import 'package:my_life_graph/features/coach/presentation/pages/coach_page.dart';
import 'package:my_life_graph/features/coach/presentation/providers/coach_providers.dart';
import 'package:my_life_graph/features/coach/presentation/widgets/coach_dictation_button.dart';

import 'support/coach_fixtures.dart';

void main() {
  for (final keyboard in [true, false]) {
    testWidgets('Coach Enter sends once; hardware keyboard = $keyboard',
        (tester) async {
      final repository = _FakeCoachRepository();
      await _pumpPage(tester, repository);
      final input = find.byKey(const Key('coach-message-field'));
      await tester.enterText(input, 'Send this question');
      await tester.pump();
      if (keyboard) {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        await tester.testTextInput.receiveAction(TextInputAction.send);
      }
      await tester.pumpAndSettle();
      expect(repository.messages, ['Send this question']);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Coach Shift Enter does not send', (tester) async {
    final repository = _FakeCoachRepository();
    await _pumpPage(tester, repository);
    await tester.enterText(find.byKey(const Key('coach-message-field')), 'Draft');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(repository.messages, isEmpty);
    expect(tester.widget<TextField>(find.byKey(const Key('coach-message-field')))
        .controller!.text, contains('\n'));
    expect(tester.takeException(), isNull);
  });

  for (final sendNow in [false, true]) {
    testWidgets('dictation result preserves draft; direct send = $sendNow', (tester) async {
      final repository = _FakeCoachRepository();
      await _pumpPage(tester, repository);
      await tester.enterText(find.byKey(const Key('coach-message-field')), 'My question:');
      await tester.pump();
      final dictation = tester.widget<CoachDictationButton>(find.byType(CoachDictationButton));
      expect(dictation.canSendDirect, isTrue);
      dictation.onText('What should I focus on?', sendNow);
      await tester.pumpAndSettle();
      if (sendNow) {
        expect(repository.messages, ['My question: What should I focus on?']);
      } else {
        expect(repository.messages, isEmpty);
        expect(tester.widget<TextField>(find.byKey(const Key('coach-message-field')))
            .controller!.text, 'My question: What should I focus on?');
      }
      expect(tester.takeException(), isNull);
    });
  }
  setUpAll(() async {
    final loader = FontLoader('InstrumentSans')
      ..addFont(rootBundle.load('assets/fonts/InstrumentSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/InstrumentSans-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/InstrumentSans-Bold.ttf'));
    await loader.load();
    await (FontLoader('packages/phosphor_flutter/PhosphorRegular')
      ..addFont(rootBundle.load('packages/phosphor_flutter/lib/fonts/Phosphor.ttf'))).load();
  });
  for (final scale in [1.0, 2.0]) {
  testWidgets(
    'compact mobile Coach selects a provider in a dialog at $scale',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final credentials = CoachCredentialsController(
        store: PlatformCoachCredentialStore(web: true),
        api: CoachApiDataSource(ApiClient(Dio())),
        accessToken: () async => null,
      );
      await credentials.setProfile('profile-a');
      final repository = _FakeCoachRepository(
        capability: CoachCapabilities.fromJson(
          coachCapabilitiesJson(
            state: 'disabled',
            provider: 'disabled',
            providerMode: 'disabled',
            reasonCode: 'provider_not_selected',
          ),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coachRepositoryProvider.overrideWithValue(repository),
            coachCredentialsProvider.overrideWith((ref) => credentials),
          ],
          child: MaterialApp(theme: AppTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
            home: const Scaffold(body: RepaintBoundary(key: Key('coach-preview'), child: CoachPage()))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Coach unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'initial fixed layout');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Project Coach uses a temporary'), findsNothing);
      if (const bool.fromEnvironment('COACH_PREVIEW')) {
        await expectLater(find.byKey(const Key('coach-preview')),
            matchesGoldenFile('../../../.tools/coach-mobile-$scale.png'));
      }
      expect(credentials.state.provider, CoachProviderName.operatorCodexPilot);
      await tester.tap(find.byKey(const Key('coach-model-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('coach-provider-selection')));
      await tester.pumpAndSettle();
      expect(find.text('OpenAI (your key)').hitTestable(), findsOneWidget);
      expect(find.text('Gemini (your key)').hitTestable(), findsOneWidget);
      repository.capability = CoachCapabilities.fromJson(coachCapabilitiesJson());
      await tester.tap(find.text('Standard (provided)').hitTestable());
      await tester.pumpAndSettle();
      expect(credentials.state.provider, CoachProviderName.operatorCodexPilot);
      expect(tester.takeException(), isNull, reason: 'selected provider layout');
      expect(find.text('Coach unavailable'), findsNothing);
      expect(find.byKey(const Key('coach-provider-selection')), findsOneWidget);
      expect(find.textContaining('No automatic provider fallback'), findsNothing);
      await tester.tap(find.byTooltip('Show information about Coach modes'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No automatic provider fallback'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNWidgets(2));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(repository.capabilityCalls, 2);
      expect(repository.messages, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  }

  testWidgets('empty chat shows a quiet outlined invitation', (tester) async {
    await _pumpPage(tester, _FakeCoachRepository(historyTurns: []));
    expect(find.text('No saved Coach conversation yet.'), findsNothing);
    expect(find.byKey(const Key('coach-empty-chat')), findsOneWidget);
    expect(find.text('Ask your coach anything'), findsOneWidget);
    final frame = tester.getRect(find.byKey(const Key('app-page-body-outline')));
    final input = tester.getRect(find.byKey(const Key('coach-message-field')));
    final model = tester.getRect(find.byKey(const Key('coach-model-button')));
    final send = tester.getRect(find.byKey(const Key('coach-send-button')));
    expect(input.bottom, lessThanOrEqualTo(model.top));
    expect(input.width, greaterThan(model.width));
    expect(model.right, lessThan(send.left));
    expect(find.descendant(of: find.byType(AppPageHeading),
        matching: find.textContaining('left')), findsOneWidget);
    expect(frame.bottom, greaterThan(input.bottom));
    final invitation = tester.getRect(find.byKey(const Key('coach-empty-chat')));
    expect(frame.top, closeTo(invitation.top - 8, 0.1));
    expect(frame.top, lessThan(tester.getTopLeft(
        find.byKey(const Key('coach-empty-chat'))).dy));
    expect(find.text('For example: What patterns do you notice in my week?'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat opens at newest message; outline, provider and composer stay fixed',
      (tester) async {
    final repository = _FakeCoachRepository(historyTurns: [
      {
        'request_id': coachSecondRequestId,
        'message': 'Newer question',
        'response': coachResponseJson(requestId: coachSecondRequestId),
        'created_at': '2026-07-27T10:15:01Z',
      },
      {
        'request_id': coachRequestId,
        'message': 'Older question',
        'response': coachResponseJson(),
        'created_at': '2026-07-26T10:15:01Z',
      },
    ]);
    await _pumpPage(tester, repository);
    final chat = tester.widget<SingleChildScrollView>(find.byKey(const Key('coach-chat-scroll')));
    expect(chat.controller!.position.maxScrollExtent, greaterThan(0));
    expect(chat.controller!.offset, chat.controller!.position.maxScrollExtent);
    expect(find.byType(CustomScrollView), findsNothing);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final frame = tester.getRect(find.byKey(const Key('app-page-body-outline')));
    final provider = tester.getRect(find.byKey(const Key('coach-model-button')));
    expect(provider.top, greaterThan(frame.top));
    expect(tester.getTopLeft(find.text('Older question')).dy,
        lessThan(tester.getTopLeft(find.text('Newer question')).dy));
    final composer = tester.getRect(find.byKey(const Key('coach-message-field')));
    await tester.drag(find.byKey(const Key('coach-chat-scroll')), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(chat.controller!.offset, lessThan(chat.controller!.position.maxScrollExtent));
    expect(tester.getRect(find.byKey(const Key('app-page-body-outline'))), frame);
    expect(tester.getRect(find.byKey(const Key('coach-model-button'))), provider);
    expect(tester.getRect(find.byKey(const Key('coach-message-field'))), composer);
    await tester.enterText(find.byKey(const Key('coach-message-field')),
        'Newest question');
    await tester.pump();
    await tester.tap(find.byKey(const Key('coach-send-button')));
    await tester.pumpAndSettle();
    expect(find.descendant(
        of: find.byKey(const Key('coach-chat-timeline')),
        matching: find.text('Newest question')), findsOneWidget);
    expect(find.text('Older question'), findsOneWidget);
    expect(find.text('Newer question'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Newer question')).dy,
        lessThan(tester.getTopLeft(find.text('Newest question')).dy));
    expect(repository.messages, ['Newest question']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('free-question surface has no modes, starters, or memories', (
    tester,
  ) async {
    final repository = _FakeCoachRepository();
    await _pumpPage(tester, repository);

    expect(find.descendant(of: find.byType(AppPageHeading),
        matching: find.text('Coach')), findsOneWidget);
    expect(find.text('Coach unavailable'), findsNothing);
    expect(find.byKey(const Key('coach-model-button')), findsOneWidget);
    expect(find.byKey(const Key('coach-choose-provider')), findsNothing);
    expect(find.text('Ask Coach'), findsNothing);
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(find.byKey(const Key('coach-message-field')), findsOneWidget);
    expect(find.text('Conversation history'), findsNothing);
    expect(find.byKey(const Key('coach-chat-timeline')), findsOneWidget);
    for (final removed in [
      'Choose Coach context',
      'Today',
      'Patterns',
      'Focus',
      'Review',
      'Prompt starters',
      'Selected memories',
    ]) {
      expect(find.text(removed), findsNothing);
    }
  });

  testWidgets(
    'answer shows snapshot source coverage, SQL/Python trace, and provenance',
    (tester) async {
      final repository = _FakeCoachRepository();
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const Key('coach-message-field')),
        'How long are my Focus sessions?',
      );
      await _scrollTo(tester, find.byKey(const Key('coach-send-button')));
      await tester.tap(find.byKey(const Key('coach-send-button')));
      await tester.pumpAndSettle();

      expect(repository.messages, ['How long are my Focus sessions?']);
      await _scrollTo(
        tester,
        find.text('Your median Focus duration was 42 minutes.'),
      );
      expect(
        find.text('Your median Focus duration was 42 minutes.'),
        findsOneWidget,
      );
      expect(find.text('Uncertainty'), findsOneWidget);
      expect(find.textContaining('suggestion'), findsNothing);

      final details = find.text('Data and analysis details').last;
      await _scrollTo(tester, details);
      await tester.tap(details);
      await tester.pumpAndSettle();

      expect(find.text('Snapshot source coverage'), findsOneWidget);
      expect(find.text('Data used'), findsNothing);
      expect(find.text('Focus Sessions'), findsOneWidget);
      expect(find.textContaining('12 records in snapshot'), findsOneWidget);
      expect(
        find.text(
          'Counts and dates describe source coverage, not rows returned '
          'by one query.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Read-only SQL'), findsWidgets);
      expect(find.textContaining('Snapshot: 120 rows'), findsOneWidget);
      expect(find.textContaining('Deterministic Test Only'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets(
    'legacy history labels selected context and does not invent Fast status',
    (tester) async {
      final legacyResponse = coachLegacyResponseJson(
        provider: 'local_codex_oauth',
        providerMode: 'local_development_only',
        modelRequested: 'gpt-5.5',
        modelReported: 'gpt-5.5',
        modelSource: 'explicit',
      );
      final repository = _FakeCoachRepository(
        historyTurns: [
          {
            'request_id': coachSecondRequestId,
            'message': 'What did the older Coach inspect?',
            'response': legacyResponse,
            'created_at': '2026-07-27T10:15:01Z',
          },
        ],
      );
      await _pumpPage(tester, repository);

      final details = find.text('Data and analysis details');
      await _scrollTo(tester, details);
      await tester.tap(details);
      await tester.pumpAndSettle();

      expect(find.text('Selected context in older response'), findsOneWidget);
      expect(
        find.text('1 of 2 records selected for this older response'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Counts describe context selected for this older response, '
          'not snapshot coverage or current tool evidence.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'No per-turn tool trace was recorded for this older response.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Local Codex OAuth · Fast status not recorded'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Snapshot: not recorded for this older response'),
        findsOneWidget,
      );
      expect(find.text('Snapshot source coverage'), findsNothing);
      expect(find.textContaining('records in snapshot'), findsNothing);
      expect(find.textContaining('gpt-5.5 · Fast configured'), findsNothing);
    },
  );

  testWidgets('running analysis shows safe activity and cancel control', (
    tester,
  ) async {
    final repository = _FakeCoachRepository(block: true);
    await _pumpPage(tester, repository);
    await tester.enterText(
      find.byKey(const Key('coach-message-field')),
      'Run a longer analysis',
    );
    await _scrollTo(tester, find.byKey(const Key('coach-send-button')));
    await tester.tap(find.byKey(const Key('coach-send-button')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('coach-activity')), findsOneWidget);
    expect(find.descendant(
      of: find.byKey(const Key('coach-chat-timeline')),
      matching: find.byKey(const Key('coach-activity')),
    ), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const Key('coach-activity'))).dy,
        greaterThan(tester.getBottomLeft(find.text('Run a longer analysis')).dy));
    expect(find.text('Checking relevant history …'), findsOneWidget);
    expect(find.byKey(const Key('coach-cancel-button')), findsOneWidget);
    expect(find.textContaining('reasoning'), findsNothing);

    await tester.tap(find.byKey(const Key('coach-cancel-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repository.cancelCalls, 1);
    expect(find.byKey(const Key('coach-activity')), findsNothing);
    await _scrollTo(tester, find.byKey(const Key('coach-send-button')));
    expect(find.byKey(const Key('coach-send-button')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('coach-message-field')))
          .controller
          ?.text,
      'Run a longer analysis',
    );
  });

  testWidgets('unavailable Coach keeps history readable and input disabled', (
    tester,
  ) async {
    final repository = _FakeCoachRepository(
      capability: CoachCapabilities.localDemo(),
    );
    await _pumpPage(tester, repository);

    expect(find.text('Coach unavailable'), findsOneWidget);
    expect(find.byKey(const Key('coach-choose-provider')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('coach-message-field')))
          .enabled,
      isFalse,
    );
    await _scrollTo(
      tester,
      find.text('Your median Focus duration was 42 minutes.'),
    );
    expect(
      find.text('Your median Focus duration was 42 minutes.'),
      findsOneWidget,
    );
  });

  testWidgets('local dictation can edit draft without enabling unavailable Coach', (tester) async {
    await _pumpPage(tester, _FakeCoachRepository(
      capability: CoachCapabilities.localDemo(),
    ), allowLocalDictation: true);
    final input = find.byKey(const Key('coach-message-field'));
    expect(tester.widget<TextField>(input).enabled, isTrue);
    expect(tester.widget<IconButton>(find.byKey(
        const Key('coach-dictation-button'))).onPressed, isNotNull);
    await tester.enterText(input, 'A local dictation draft');
    await tester.pump();
    expect(tester.widget<IconButton>(find.byKey(
        const Key('coach-send-button'))).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('asynchronous Coach errors are announced as live regions', (
    tester,
  ) async {
    final repository = _FakeCoachRepository(
      capabilityError: StateError('availability failed'),
    );
    await _pumpPage(tester, repository);

    final error = find.text(
      'Coach could not complete this operation. Try again.',
    );
    expect(error, findsOneWidget);
    expect(find.byKey(const Key('coach-model-button')), findsOneWidget);
    final semantics = tester.widgetList<Semantics>(
      find.ancestor(of: error, matching: find.byType(Semantics)),
    );
    expect(
      semantics.any((widget) => widget.properties.liveRegion == true),
      isTrue,
    );
  });
}

Future<void> _pumpPage(WidgetTester tester, CoachRepository repository,
    {bool allowLocalDictation = false}) async {
  final credentials = CoachCredentialsController(
    store: PlatformCoachCredentialStore(web: true),
    api: CoachApiDataSource(ApiClient(Dio())),
    accessToken: () async => null,
  );
  await credentials.setProfile('profile-a');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachRepositoryProvider.overrideWithValue(repository),
        coachLocalDictationProvider.overrideWithValue(allowLocalDictation),
        coachActiveProfileIdProvider.overrideWithValue(
          allowLocalDictation ? 'profile-a' : null,
        ),
        coachCredentialsProvider.overrideWith((ref) => credentials),
      ],
      child: const MaterialApp(home: Scaffold(body: CoachPage())),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

class _FakeCoachRepository implements CoachRepository {
  _FakeCoachRepository({
    CoachCapabilities? capability,
    this.block = false,
    this.capabilityError,
    this.historyTurns,
  }) : capability =
            capability ?? CoachCapabilities.fromJson(coachCapabilitiesJson());

  CoachCapabilities capability;
  final bool block;
  final Object? capabilityError;
  final List<Map<String, dynamic>>? historyTurns;
  final List<String> messages = [];
  final StreamController<CoachStreamEvent> _blocking =
      StreamController<CoachStreamEvent>();
  int cancelCalls = 0;
  int capabilityCalls = 0;
  String? _latestRequestId;
  String? _latestMessage;

  @override
  Future<CoachCapabilities> getCapabilities() async {
    capabilityCalls++;
    if (capabilityError != null) throw capabilityError!;
    return capability;
  }

  @override
  Future<CoachHistory> getHistory() async {
    final requestId = _latestRequestId;
    final message = _latestMessage;
    return CoachHistory.fromJson(
      requestId == null || message == null
          ? coachHistoryJson(turns: historyTurns)
          : coachHistoryJson(
              turns: [
                ...?historyTurns,
                {
                  'request_id': requestId,
                  'message': message,
                  'response': coachResponseJson(requestId: requestId),
                  'created_at': '2026-07-28T10:15:01Z',
                },
              ],
            ),
    );
  }

  @override
  Stream<CoachStreamEvent> respond({
    required String requestId,
    required String message,
  }) async* {
    messages.add(message);
    _latestRequestId = requestId;
    _latestMessage = message;
    yield CoachStartedEvent(requestId);
    yield const CoachActivityEvent('Checking relevant history …');
    if (block) {
      yield* _blocking.stream;
      return;
    }
    yield CoachCompletedEvent(
      CoachResponse.fromJson(coachResponseJson(requestId: requestId)),
    );
  }

  @override
  Future<CoachHistoryDeleteResult> deleteHistory() async =>
      const CoachHistoryDeleteResult(true);

  @override
  void cancelActiveResponse() {
    cancelCalls++;
    if (block && !_blocking.isClosed) {
      _blocking.close();
    }
  }
}
