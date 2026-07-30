import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/coach/application/coach_controller.dart';
import 'package:my_life_graph/features/coach/application/coach_turn_notice.dart';
import 'package:my_life_graph/features/coach/domain/coach.dart';
import 'package:my_life_graph/features/coach/domain/coach_repository.dart';
import 'package:my_life_graph/features/coach/presentation/providers/coach_providers.dart';

import 'support/coach_fixtures.dart';

void main() {
  test('load reads only capabilities and conversation history', () async {
    final repository = _FakeCoachRepository();
    final controller = CoachController(repository: repository);
    await _settle();

    expect(controller.state.isLoading, isFalse);
    expect(controller.state.capabilities?.canRespond, isTrue);
    expect(controller.state.history.turns, hasLength(1));
    expect(repository.capabilityCalls, 1);
    expect(repository.historyCalls, 1);
    controller.dispose();
  });

  test('send accepts a free question and surfaces safe activity', () async {
    final repository = _FakeCoachRepository(
      remainingRequests: const [19, 18],
    );
    final controller = CoachController(repository: repository);
    await _settle();
    controller.updateDraft('  Compare my full Focus history.  ');

    final sent = await controller.send();

    expect(sent, isTrue);
    expect(repository.messages.single, 'Compare my full Focus history.');
    expect(controller.state.latestResponse?.agentTrace.toolCallCount, 1);
    expect(controller.state.latestMessage, 'Compare my full Focus history.');
    expect(controller.state.draft, isEmpty);
    expect(controller.state.capabilities?.limits.remainingRequests, 18);
    expect(repository.capabilityCalls, 2);
    expect(repository.historyCalls, 2);
    controller.dispose();
  });

  test('completed turn publishes a profile-bound local notice', () async {
    final repository = _FakeCoachRepository();
    final notice = CoachTurnNoticeController(profileId: 'profile-1');
    final controller = CoachController(
      repository: repository,
      profileId: 'profile-1',
      turnNoticeController: notice,
    );
    await _settle();
    controller.updateDraft('Compare my Focus history');
    final requestId = controller.state.requestId;

    expect(await controller.send(), isTrue);

    expect(
      notice.state,
      isA<CoachTurnNotice>()
          .having((value) => value.profileId, 'profileId', 'profile-1')
          .having((value) => value.requestId, 'requestId', requestId)
          .having(
            (value) => value.status,
            'status',
            CoachTurnNoticeStatus.completed,
          ),
    );
    controller.dispose();
    notice.dispose();
  });

  test('completed response replaces cancellation before projections refresh',
      () async {
    final refreshGate = Completer<void>();
    final repository = _FakeCoachRepository(
      refreshGate: refreshGate,
      remainingRequests: const [19, 18],
    );
    final controller = CoachController(repository: repository);
    await _settle();
    controller.updateDraft('Compare the full history');

    final pending = controller.send();
    await _waitUntil(() => controller.state.latestResponse != null);

    expect(controller.state.isSending, isFalse);
    expect(controller.state.isCancelling, isFalse);
    expect(controller.state.isLoading, isTrue);
    expect(controller.state.latestMessage, 'Compare the full history');
    controller.cancelAnalysis();
    expect(repository.cancelCalls, 0);

    await controller.deleteHistory();
    await controller.load();
    expect(await controller.send(), isFalse);
    expect(repository.deleteCalls, 0);
    expect(repository.capabilityCalls, 2);
    expect(repository.messages, hasLength(1));

    refreshGate.complete();
    expect(await pending, isTrue);
    expect(controller.state.isLoading, isFalse);
    expect(controller.state.capabilities?.limits.remainingRequests, 18);
    controller.dispose();
  });

  test('projection failures are independent and retain a completed response',
      () async {
    final repository = _FakeCoachRepository(
      capabilityErrorAfterInitial: StateError('capability refresh failed'),
      historyAfterInitial: CoachHistory.empty(),
    );
    final controller = CoachController(repository: repository);
    await _settle();
    controller.updateDraft('Keep the answer if status refresh fails');

    expect(await controller.send(), isTrue);

    expect(controller.state.latestResponse, isNotNull);
    expect(
      controller.state.latestMessage,
      'Keep the answer if status refresh fails',
    );
    expect(controller.state.capabilityError, isA<StateError>());
    expect(controller.state.history.turns, isEmpty);
    expect(controller.state.historyError, isNull);
    controller.dispose();
  });

  test('failed turn refreshes capabilities even when history refresh fails',
      () async {
    final repository = _FakeCoachRepository(
      error: const CoachRemoteException(
        code: 'provider_timeout',
        message: 'Timed out.',
        retryable: true,
        statusCode: 503,
      ),
      historyErrorAfterInitial: StateError('history refresh failed'),
      remainingRequests: const [20, 19],
    );
    final controller = CoachController(repository: repository);
    await _settle();
    controller.updateDraft('Long data question');

    expect(await controller.send(), isFalse);

    expect(controller.state.capabilities?.limits.remainingRequests, 19);
    expect(controller.state.capabilityError, isNull);
    expect(controller.state.historyError, isA<StateError>());
    expect(controller.state.sendError, isA<CoachRemoteException>());
    controller.dispose();
  });

  test('failed turn publishes a notice and a new retry consumes it', () async {
    final repository = _FakeCoachRepository(
      error: const CoachRemoteException(
        code: 'provider_timeout',
        message: 'Timed out.',
        retryable: true,
        statusCode: 503,
      ),
    );
    final notice = CoachTurnNoticeController(profileId: 'profile-1');
    final controller = CoachController(
      repository: repository,
      profileId: 'profile-1',
      turnNoticeController: notice,
    );
    await _settle();
    controller.updateDraft('Retry this unchanged question');
    final requestId = controller.state.requestId;

    expect(await controller.send(), isFalse);
    expect(
      notice.state,
      isA<CoachTurnNotice>()
          .having((value) => value.requestId, 'requestId', requestId)
          .having(
            (value) => value.status,
            'status',
            CoachTurnNoticeStatus.failed,
          ),
    );

    repository.responseGate = Completer<void>();
    expect(controller.state.requestId, isNot(requestId));
    final retry = controller.send();
    await _settle();
    expect(notice.state, isNull);
    repository.responseGate!.complete();
    expect(await retry, isFalse);
    expect(notice.state?.status, CoachTurnNoticeStatus.failed);
    controller.dispose();
    notice.dispose();
  });

  test('editing an uncertain retry creates a fresh request identity', () async {
    final repository = _FakeCoachRepository(
      error: const CoachRemoteException(
        code: 'network_error',
        message: 'Connection lost.',
        retryable: true,
        statusCode: 503,
      ),
    );
    final controller = CoachController(repository: repository);
    await _settle();
    controller.updateDraft('First question');
    await controller.send();
    final retained = controller.state.requestId;

    expect(controller.state.exactRetryMessage, 'First question');
    controller.updateDraft('Different question');

    expect(controller.state.exactRetryMessage, isNull);
    expect(controller.state.requestId, isNot(retained));
    controller.dispose();
  });

  test('contract failure preserves the exact request identity for retry',
      () async {
    final repository = _FakeCoachRepository(
      error: const CoachContractException('Malformed stream encoding.'),
    );
    final controller = CoachController(repository: repository);
    await _settle();
    controller.updateDraft('Retry this exact question');
    final requestId = controller.state.requestId;

    expect(await controller.send(), isFalse);

    expect(controller.state.requestId, requestId);
    expect(controller.state.exactRetryMessage, 'Retry this exact question');
    expect(controller.state.sendError, isA<CoachContractException>());
    controller.dispose();
  });

  test('cancel keeps the draft and clears the running status', () async {
    final repository = _FakeCoachRepository(
      block: true,
      remainingRequests: const [20, 19],
    );
    final notice = CoachTurnNoticeController(profileId: 'profile-1');
    final controller = CoachController(
      repository: repository,
      profileId: 'profile-1',
      turnNoticeController: notice,
    );
    await _settle();
    controller.updateDraft('Long analysis');
    final pending = controller.send();
    await _settle();

    expect(controller.state.isSending, isTrue);
    controller.cancelAnalysis();
    await pending;

    expect(repository.cancelCalls, 1);
    expect(controller.state.isSending, isFalse);
    expect(controller.state.draft, 'Long analysis');
    expect(controller.state.sendError, isNull);
    expect(controller.state.capabilities?.limits.remainingRequests, 19);
    expect(repository.capabilityCalls, 2);
    expect(repository.historyCalls, 2);
    expect(notice.state, isNull);
    controller.dispose();
    notice.dispose();
  });

  test('history deletion is blocked while analysis is running', () async {
    final repository = _FakeCoachRepository(block: true);
    final controller = CoachController(repository: repository);
    await _settle();
    controller.updateDraft('Long analysis');
    final pending = controller.send();
    await _settle();

    await controller.deleteHistory();
    expect(repository.deleteCalls, 0);

    controller.cancelAnalysis();
    await pending;
    await controller.deleteHistory();
    expect(repository.deleteCalls, 1);
    expect(controller.state.history.turns, isEmpty);
    controller.dispose();
  });

  test('profile switch clears draft and notice and disposes the old turn',
      () async {
    final activeProfile = StateProvider<String?>((ref) => 'profile-1');
    final repository = _FakeCoachRepository();
    final container = ProviderContainer(
      overrides: [
        coachActiveProfileIdProvider.overrideWith(
          (ref) => ref.watch(activeProfile),
        ),
        coachRepositoryProvider.overrideWithValue(repository),
      ],
    );
    final subscription = container.listen(
      coachControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    await _settle();
    container
        .read(coachControllerProvider.notifier)
        .updateDraft('Profile one private draft');
    final requestId = container.read(coachControllerProvider).requestId;
    container.read(coachTurnNoticeProvider.notifier).publish(
          profileId: 'profile-1',
          requestId: requestId,
          status: CoachTurnNoticeStatus.completed,
        );

    container.read(activeProfile.notifier).state = 'profile-2';
    await _settle();

    expect(container.read(coachControllerProvider).draft, isEmpty);
    expect(container.read(coachControllerProvider).requestId, isNot(requestId));
    expect(container.read(coachTurnNoticeProvider), isNull);
    expect(repository.cancelCalls, 1);

    subscription.close();
    container.dispose();
    expect(repository.cancelCalls, 2);
  });
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (predicate()) return;
    await _settle();
  }
  fail('Timed out waiting for Coach controller state.');
}

class _FakeCoachRepository implements CoachRepository {
  _FakeCoachRepository({
    this.error,
    this.block = false,
    this.refreshGate,
    this.capabilityErrorAfterInitial,
    this.historyErrorAfterInitial,
    this.historyAfterInitial,
    this.remainingRequests = const [19],
  }) : assert(remainingRequests.isNotEmpty);

  final Object? error;
  final bool block;
  final Completer<void>? refreshGate;
  final Object? capabilityErrorAfterInitial;
  final Object? historyErrorAfterInitial;
  final CoachHistory? historyAfterInitial;
  final List<int> remainingRequests;
  Completer<void>? responseGate;
  final List<String> messages = [];
  final StreamController<CoachStreamEvent> _blocking =
      StreamController<CoachStreamEvent>();
  int capabilityCalls = 0;
  int historyCalls = 0;
  int deleteCalls = 0;
  int cancelCalls = 0;

  @override
  Future<CoachCapabilities> getCapabilities() async {
    capabilityCalls++;
    if (capabilityCalls > 1) {
      await refreshGate?.future;
      if (capabilityErrorAfterInitial != null) {
        throw capabilityErrorAfterInitial!;
      }
    }
    final index = capabilityCalls <= remainingRequests.length
        ? capabilityCalls - 1
        : remainingRequests.length - 1;
    return CoachCapabilities.fromJson(
      coachCapabilitiesJson(remainingRequests: remainingRequests[index]),
    );
  }

  @override
  Future<CoachHistory> getHistory() async {
    historyCalls++;
    if (historyCalls > 1) {
      await refreshGate?.future;
      if (historyErrorAfterInitial != null) {
        throw historyErrorAfterInitial!;
      }
      if (historyAfterInitial != null) return historyAfterInitial!;
    }
    return CoachHistory.fromJson(coachHistoryJson());
  }

  @override
  Stream<CoachStreamEvent> respond({
    required String requestId,
    required String message,
  }) async* {
    messages.add(message);
    yield CoachStartedEvent(requestId);
    yield const CoachActivityEvent('Checking relevant history …');
    await responseGate?.future;
    if (block) {
      yield* _blocking.stream;
      return;
    }
    if (error != null) throw error!;
    yield CoachCompletedEvent(
      CoachResponse.fromJson(coachResponseJson(requestId: requestId)),
    );
  }

  @override
  Future<CoachHistoryDeleteResult> deleteHistory() async {
    deleteCalls++;
    return const CoachHistoryDeleteResult(true);
  }

  @override
  void cancelActiveResponse() {
    cancelCalls++;
    if (block && !_blocking.isClosed) {
      _blocking
        ..addError(const CoachAccessException('Cancelled.'))
        ..close();
    }
  }
}
