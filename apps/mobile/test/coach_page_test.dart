import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/coach/domain/coach.dart';
import 'package:my_life_graph/features/coach/domain/coach_repository.dart';
import 'package:my_life_graph/features/coach/presentation/pages/coach_page.dart';
import 'package:my_life_graph/features/coach/presentation/providers/coach_providers.dart';

import 'support/coach_fixtures.dart';

void main() {
  testWidgets('free-question surface has no modes, starters, or memories',
      (tester) async {
    final repository = _FakeCoachRepository();
    await _pumpPage(tester, repository);

    expect(find.text('Coach'), findsOneWidget);
    expect(find.text('Read-only Coach ready'), findsOneWidget);
    expect(find.text('Ask anything'), findsOneWidget);
    expect(find.byKey(const Key('coach-message-field')), findsOneWidget);
    await _scrollTo(tester, find.text('Conversation history'));
    expect(find.text('Conversation history'), findsOneWidget);
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
  });

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
  });

  testWidgets('running analysis shows safe activity and cancel control',
      (tester) async {
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
    expect(find.text('Checking relevant history …'), findsOneWidget);
    expect(find.byKey(const Key('coach-cancel-button')), findsOneWidget);
    expect(find.textContaining('reasoning'), findsNothing);

    await tester.tap(find.byKey(const Key('coach-cancel-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repository.cancelCalls, 1);
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

  testWidgets('unavailable Coach keeps history readable and input disabled',
      (tester) async {
    final repository = _FakeCoachRepository(
      capability: CoachCapabilities.localDemo(),
    );
    await _pumpPage(tester, repository);

    expect(find.text('Coach unavailable'), findsOneWidget);
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

  testWidgets('asynchronous Coach errors are announced as live regions',
      (tester) async {
    final repository = _FakeCoachRepository(
      capabilityError: StateError('availability failed'),
    );
    await _pumpPage(tester, repository);

    final error = find.text(
      'Coach could not complete this operation. Try again.',
    );
    expect(error, findsOneWidget);
    final semantics = tester.widgetList<Semantics>(
      find.ancestor(of: error, matching: find.byType(Semantics)),
    );
    expect(
      semantics.any((widget) => widget.properties.liveRegion == true),
      isTrue,
    );
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  CoachRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(
        home: Scaffold(body: CoachPage()),
      ),
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

  final CoachCapabilities capability;
  final bool block;
  final Object? capabilityError;
  final List<Map<String, dynamic>>? historyTurns;
  final List<String> messages = [];
  final StreamController<CoachStreamEvent> _blocking =
      StreamController<CoachStreamEvent>();
  int cancelCalls = 0;
  String? _latestRequestId;
  String? _latestMessage;

  @override
  Future<CoachCapabilities> getCapabilities() async {
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
