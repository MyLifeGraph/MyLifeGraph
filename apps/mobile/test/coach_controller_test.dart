import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/features/coach/application/coach_controller.dart';
import 'package:my_life_graph/features/coach/domain/coach.dart';
import 'package:my_life_graph/features/coach/domain/coach_repository.dart';

import 'support/coach_fixtures.dart';

void main() {
  test(
      'initial load reads capability, history, and memories without responding',
      () async {
    final repository = _FakeCoachRepository(
      capability: _capability(state: 'unavailable'),
      history: _history(),
      memories: _memories(),
    );
    final controller = CoachController(repository: repository);
    addTearDown(controller.dispose);

    await pumpEventQueue();

    expect(controller.state.isLoading, isFalse);
    expect(
      controller.state.capabilities!.state,
      CoachCapabilityState.unavailable,
    );
    expect(controller.state.history.turns, hasLength(1));
    expect(controller.state.memories.memories, hasLength(2));
    expect(repository.capabilityCalls, 1);
    expect(repository.historyCalls, 1);
    expect(repository.memoryCalls, 1);
    expect(repository.respondRequestIds, isEmpty);
  });

  test('send prevents duplicates, uses capability timeout, clears on success',
      () async {
    final responseCompleter = Completer<CoachResponse>();
    final repository = _FakeCoachRepository(
      responseCompleter: responseCompleter,
    );
    final controller = CoachController(repository: repository);
    addTearDown(controller.dispose);
    await pumpEventQueue();
    controller.updateDraft('  Help me pace today.  ');
    final firstRequestId = controller.state.requestId;

    final first = controller.send();
    final duplicate = await controller.send();
    expect(duplicate, isFalse);
    expect(repository.respondRequestIds, [firstRequestId]);
    expect(repository.respondMessages, ['Help me pace today.']);
    expect(repository.responseTimeouts, [const Duration(seconds: 55)]);

    responseCompleter.complete(_response(requestId: firstRequestId));
    expect(await first, isTrue);
    expect(controller.state.draft, isEmpty);
    expect(controller.state.requestId, isNot(firstRequestId));
    expect(controller.state.latestResponse!.requestId, firstRequestId);
    expect(controller.state.latestMessage, 'Help me pace today.');
  });

  test('ambiguous timeout retains exact request identity for retry', () async {
    final request = RequestOptions(path: '/v1/coach/respond');
    final repository = _FakeCoachRepository(
      responseErrors: [
        AppException(
          'Network request failed',
          cause: DioException(
            requestOptions: request,
            type: DioExceptionType.receiveTimeout,
          ),
        ),
      ],
    );
    final controller = CoachController(repository: repository);
    addTearDown(controller.dispose);
    await pumpEventQueue();
    controller.updateDraft('Keep this exact');
    final requestId = controller.state.requestId;

    expect(await controller.send(), isFalse);
    expect(controller.state.requestId, requestId);
    expect(controller.state.exactRetryMessage, 'Keep this exact');
    expect(
      coachErrorMessage(controller.state.sendError),
      contains('timed out'),
    );

    expect(await controller.send(), isTrue);
    expect(repository.respondRequestIds, [requestId, requestId]);
    expect(repository.respondMessages, ['Keep this exact', 'Keep this exact']);
  });

  test('editing after ambiguous failure releases the exact retry identity',
      () async {
    final repository = _FakeCoachRepository(
      responseErrors: [const CoachContractException('invalid success')],
    );
    final controller = CoachController(repository: repository);
    addTearDown(controller.dispose);
    await pumpEventQueue();
    controller.updateDraft('Original payload');
    final requestId = controller.state.requestId;

    expect(await controller.send(), isFalse);
    expect(controller.state.requestId, requestId);
    controller.updateDraft('Changed payload');

    expect(controller.state.requestId, isNot(requestId));
    expect(controller.state.exactRetryMessage, isNull);
    expect(controller.state.sendError, isNull);
  });

  test('known failures rotate id except retryable in-progress conflict',
      () async {
    final knownRepository = _FakeCoachRepository(
      responseErrors: [
        const CoachRemoteException(
          code: 'invalid_output',
          message: 'Invalid provider output.',
          retryable: false,
          statusCode: 422,
        ),
      ],
    );
    final known = CoachController(repository: knownRepository);
    addTearDown(known.dispose);
    await pumpEventQueue();
    known.updateDraft('Known failure');
    final knownId = known.state.requestId;
    expect(await known.send(), isFalse);
    expect(known.state.requestId, isNot(knownId));
    expect(known.state.exactRetryMessage, isNull);

    final activeRepository = _FakeCoachRepository(
      responseErrors: [
        const CoachRemoteException(
          code: 'in_progress',
          message: 'Still in progress.',
          retryable: true,
          statusCode: 409,
        ),
      ],
    );
    final active = CoachController(repository: activeRepository);
    addTearDown(active.dispose);
    await pumpEventQueue();
    active.updateDraft('Active request');
    final activeId = active.state.requestId;
    expect(await active.send(), isFalse);
    expect(active.state.requestId, activeId);
    expect(active.state.exactRetryMessage, 'Active request');
  });

  test('rate limit is distinct and capability refresh can recover', () async {
    final repository = _FakeCoachRepository(
      responseErrors: [
        const CoachRemoteException(
          code: 'rate_limited',
          message: 'Local account limit reached.',
          retryable: true,
          statusCode: 429,
        ),
      ],
    );
    final controller = CoachController(repository: repository);
    addTearDown(controller.dispose);
    await pumpEventQueue();
    controller.updateDraft('Keep the draft');

    expect(await controller.send(), isFalse);
    expect(controller.state.isRateLimited, isTrue);
    expect(controller.state.canSend, isFalse);
    expect(controller.state.draft, 'Keep the draft');

    await controller.load();
    expect(controller.state.isRateLimited, isFalse);
    expect(controller.state.canSend, isTrue);
    expect(controller.state.draft, 'Keep the draft');
  });

  test('history and memories remain mutable when provider is unavailable',
      () async {
    final repository = _FakeCoachRepository(
      capability: _capability(state: 'unavailable'),
      history: _history(),
      memories: _memories(),
    );
    final controller = CoachController(repository: repository);
    addTearDown(controller.dispose);
    await pumpEventQueue();

    await controller.setMemorySelected(
      controller.state.memories.memories.first,
      false,
    );
    await controller.deleteHistory();

    expect(repository.deselectedMemoryIds, [coachMemoryId]);
    expect(controller.state.memories.selectedCount, 0);
    expect(repository.deleteHistoryCalls, 1);
    expect(controller.state.history.turns, isEmpty);
  });

  test('disposing an active response cancels it without publishing error',
      () async {
    final completer = Completer<CoachResponse>();
    final repository = _FakeCoachRepository(responseCompleter: completer);
    final controller = CoachController(repository: repository);
    await pumpEventQueue();
    controller.updateDraft('Long response');

    final send = controller.send();
    controller.dispose();
    expect(repository.cancelCalls, 1);
    expect(await send, isFalse);
  });
}

CoachCapabilities _capability({String state = 'ready'}) =>
    CoachCapabilities.fromJson(
      coachCapabilitiesJson(
        state: state,
        reasonCode: state == 'ready' ? 'ready' : 'provider_unavailable',
      ),
    );

CoachHistory _history() => CoachHistory.fromJson(coachHistoryJson());

CoachMemorySelection _memories({bool selected = true}) =>
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

CoachResponse _response({required String requestId}) =>
    CoachResponse.fromJson(coachResponseJson(requestId: requestId));

class _FakeCoachRepository implements CoachRepository {
  _FakeCoachRepository({
    CoachCapabilities? capability,
    CoachHistory? history,
    CoachMemorySelection? memories,
    List<Object>? responseErrors,
    this.responseCompleter,
  })  : capability = capability ?? _capability(),
        history = history ?? CoachHistory.empty(),
        memories = memories ?? CoachMemorySelection.empty(),
        responseErrors = responseErrors ?? [];

  CoachCapabilities capability;
  CoachHistory history;
  CoachMemorySelection memories;
  final List<Object> responseErrors;
  final Completer<CoachResponse>? responseCompleter;
  int capabilityCalls = 0;
  int historyCalls = 0;
  int memoryCalls = 0;
  int deleteHistoryCalls = 0;
  int cancelCalls = 0;
  final List<String> respondRequestIds = [];
  final List<String> respondMessages = [];
  final List<Duration> responseTimeouts = [];
  final List<String> selectedMemoryIds = [];
  final List<String> deselectedMemoryIds = [];

  @override
  Future<CoachCapabilities> getCapabilities() async {
    capabilityCalls += 1;
    return capability;
  }

  @override
  Future<CoachHistory> getHistory() async {
    historyCalls += 1;
    return history;
  }

  @override
  Future<CoachMemorySelection> getMemories() async {
    memoryCalls += 1;
    return memories;
  }

  @override
  Future<CoachResponse> respond({
    required String requestId,
    required String message,
    required Duration receiveTimeout,
  }) async {
    respondRequestIds.add(requestId);
    respondMessages.add(message);
    responseTimeouts.add(receiveTimeout);
    if (responseErrors.isNotEmpty) throw responseErrors.removeAt(0);
    if (responseCompleter != null && !responseCompleter!.isCompleted) {
      return responseCompleter!.future;
    }
    return _response(requestId: requestId);
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
    memories = _memories(selected: true);
    return memories;
  }

  @override
  Future<CoachMemorySelection> deselectMemory(String memoryId) async {
    deselectedMemoryIds.add(memoryId);
    memories = _memories(selected: false);
    return memories;
  }

  @override
  void cancelActiveResponse() {
    cancelCalls += 1;
    final completer = responseCompleter;
    if (completer != null && !completer.isCompleted) {
      final request = RequestOptions(path: '/v1/coach/respond');
      completer.completeError(
        AppException(
          'Network request failed',
          cause: DioException(
            requestOptions: request,
            type: DioExceptionType.cancel,
          ),
        ),
      );
    }
  }
}
