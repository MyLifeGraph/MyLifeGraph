import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/features/coach/domain/coach.dart';
import 'package:my_life_graph/features/coach/domain/coach_repository.dart';
import 'package:my_life_graph/features/coach/presentation/pages/coach_page.dart';
import 'package:my_life_graph/features/coach/presentation/providers/coach_providers.dart';

import 'support/coach_fixtures.dart';

void main() {
  testWidgets('ready Coach sends deliberately and renders contract truth',
      (tester) async {
    final repository = _FakeCoachRepository();
    await _pumpPage(tester, repository);

    expect(find.text('Coach preview'), findsOneWidget);
    expect(find.text('Development Coach ready'), findsOneWidget);
    expect(find.text('Ask Coach'), findsNWidgets(2));
    expect(find.text('Conversation history'), findsOneWidget);
    expect(find.text('Selected memories'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('coach-message-field')))
          .enabled,
      isTrue,
    );

    await tester.enterText(
      find.byKey(const Key('coach-message-field')),
      'How should I pace today?',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(repository.respondMessages, ['How should I pace today?']);
    expect(repository.respondRequestIds, hasLength(1));
    expect(repository.responseTimeouts, [const Duration(seconds: 55)]);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('coach-message-field')))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      find.text('Protect one focused block, then reassess your energy.'),
      findsOneWidget,
    );
    expect(find.text('Uncertainty'), findsOneWidget);
    expect(find.text('Review-only suggestion'), findsOneWidget);
    expect(find.text('This suggestion cannot apply changes.'), findsOneWidget);
    expect(find.textContaining('Apply'), findsNothing);

    await _scrollTo(tester, find.text('Data used'));
    await tester.tap(find.text('Data used'));
    await tester.pumpAndSettle();
    expect(find.text('Today\'s check-in state'), findsOneWidget);
    expect(find.text('Selected saved notes'), findsOneWidget);

    await _scrollTo(tester, find.text('Provider and model'));
    await tester.tap(find.text('Provider and model'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Prompt version: controlled-coach-prompt-v1'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Context version: coach-context-v1'),
      findsOneWidget,
    );
    expect(find.textContaining('Provider called: yes'), findsOneWidget);
  });

  testWidgets('provider outage keeps history and memory controls available',
      (tester) async {
    final repository = _FakeCoachRepository(
      capability: CoachCapabilities.fromJson(
        coachCapabilitiesJson(
          state: 'unavailable',
          reasonCode: 'cli_not_logged_in',
        ),
      ),
      history: CoachHistory.fromJson(coachHistoryJson()),
      memories: CoachMemorySelection.fromJson(coachMemoriesJson()),
    );
    await _pumpPage(tester, repository);

    expect(find.text('Coach temporarily unavailable'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('coach-message-field')))
          .enabled,
      isFalse,
    );
    expect(repository.respondMessages, isEmpty);

    await _scrollTo(tester, find.text('Prefer one clear next step'));
    await tester.tap(find.text('Prefer one clear next step'));
    await tester.pumpAndSettle();
    expect(find.text('From Setup · selected'), findsOneWidget);
    expect(find.text('Edit in Setup'), findsOneWidget);
    await tester.tap(find.text('Remove from Coach'));
    await tester.pumpAndSettle();
    expect(repository.deselectedMemoryIds, [coachMemoryId]);

    await _scrollTo(tester, find.text('Conversation history'));
    expect(find.text('How should I pace today?'), findsOneWidget);
    await tester.tap(find.text('Delete conversation'));
    await tester.pumpAndSettle();
    expect(find.text('Delete conversation?'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Delete conversation'),
    );
    await tester.pumpAndSettle();

    expect(repository.deleteHistoryCalls, 1);
    expect(find.text('No saved Coach conversation yet.'), findsOneWidget);
  });

  testWidgets('history dialog result is ignored after Coach unmounts',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeCoachRepository(
      history: CoachHistory.fromJson(coachHistoryJson()),
    );
    final showCoach = ValueNotifier<bool>(true);
    addTearDown(showCoach.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [coachRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showCoach,
              builder: (_, visible, __) =>
                  visible ? const CoachPage() : const Text('Different page'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Conversation history'));
    await tester.tap(find.text('Delete conversation'));
    await tester.pumpAndSettle();

    showCoach.value = false;
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Delete conversation'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Different page'), findsOneWidget);
    expect(repository.deleteHistoryCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeout keeps draft and advertises exact retry', (tester) async {
    final request = RequestOptions(path: '/v1/coach/respond');
    final repository = _FakeCoachRepository(
      respondError: AppException(
        'Network request failed',
        cause: DioException(
          requestOptions: request,
          type: DioExceptionType.receiveTimeout,
        ),
      ),
    );
    await _pumpPage(tester, repository);

    await tester.enterText(
      find.byKey(const Key('coach-message-field')),
      'Keep this draft',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(
      find.text('Coach timed out. Retry the exact message.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Your message is still here. Retry it unchanged to check the same request safely.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('coach-message-field')))
          .controller!
          .text,
      'Keep this draft',
    );
  });

  testWidgets('local unavailable and rate-limited states remain distinct',
      (tester) async {
    final local = _FakeCoachRepository(
      capability: CoachCapabilities.localDemo(),
    );
    await _pumpPage(tester, local);

    expect(find.text('Coach unavailable'), findsOneWidget);
    expect(
      find.text('No Coach provider is connected.'),
      findsOneWidget,
    );
    expect(find.textContaining('I can help you break that down'), findsNothing);
    expect(local.respondMessages, isEmpty);

    final limited = _FakeCoachRepository(
      capability: CoachCapabilities.fromJson(
        coachCapabilitiesJson(remainingRequests: 0),
      ),
    );
    await _pumpPage(tester, limited);
    expect(find.text('Rate limited'), findsOneWidget);
    expect(
      find.textContaining('Existing history and memories remain available.'),
      findsOneWidget,
    );
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeCoachRepository repository,
) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [coachRepositoryProvider.overrideWithValue(repository)],
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
    CoachHistory? history,
    CoachMemorySelection? memories,
    this.respondError,
  })  : capability =
            capability ?? CoachCapabilities.fromJson(coachCapabilitiesJson()),
        history = history ?? CoachHistory.empty(),
        memories = memories ?? CoachMemorySelection.empty();

  CoachCapabilities capability;
  CoachHistory history;
  CoachMemorySelection memories;
  final Object? respondError;
  int deleteHistoryCalls = 0;
  final List<String> respondRequestIds = [];
  final List<String> respondMessages = [];
  final List<Duration> responseTimeouts = [];
  final List<String> selectedMemoryIds = [];
  final List<String> deselectedMemoryIds = [];

  @override
  Future<CoachCapabilities> getCapabilities() async => capability;

  @override
  Future<CoachHistory> getHistory() async => history;

  @override
  Future<CoachMemorySelection> getMemories() async => memories;

  @override
  Future<CoachResponse> respond({
    required String requestId,
    required String message,
    required Duration receiveTimeout,
  }) async {
    respondRequestIds.add(requestId);
    respondMessages.add(message);
    responseTimeouts.add(receiveTimeout);
    if (respondError != null) throw respondError!;
    capability = CoachCapabilities.fromJson(
      coachCapabilitiesJson(remainingRequests: 18),
    );
    return CoachResponse.fromJson(coachResponseJson(requestId: requestId));
  }

  @override
  Future<CoachHistoryDeleteResult> deleteHistory() async {
    deleteHistoryCalls += 1;
    history = CoachHistory.empty();
    return const CoachHistoryDeleteResult(deleted: true);
  }

  @override
  Future<CoachMemorySelection> selectMemory(String memoryId) async {
    selectedMemoryIds.add(memoryId);
    memories = _selection(selected: true);
    return memories;
  }

  @override
  Future<CoachMemorySelection> deselectMemory(String memoryId) async {
    deselectedMemoryIds.add(memoryId);
    memories = _selection(selected: false);
    return memories;
  }

  @override
  void cancelActiveResponse() {}
}

CoachMemorySelection _selection({required bool selected}) =>
    CoachMemorySelection.fromJson(
      coachMemoriesJson(
        memories: [
          coachMemoryJson(selected: selected),
          coachMemoryJson(
            id: coachManualMemoryId,
            type: 'pattern',
            title: 'Afternoon energy dip',
            content: 'Energy often drops later.',
            ownership: 'manual',
            selected: false,
          ),
        ],
      ),
    );
