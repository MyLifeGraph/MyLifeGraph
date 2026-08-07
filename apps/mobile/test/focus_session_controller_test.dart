import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/focus/application/focus_protection_reconciler.dart';
import 'package:my_life_graph/features/focus/application/focus_recovery_store.dart';
import 'package:my_life_graph/features/focus/application/focus_session_controller.dart';
import 'package:my_life_graph/features/focus/domain/focus_session.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/domain/focus_protection.dart';

void main() {
  test('load retry restores recovery and tick expires it explicitly', () async {
    final now = DateTime.utc(2026, 8, 2, 10);
    final terminal = _terminalSession(
      id: 'finished-focus',
      status: FocusSessionStatus.completed,
      recoveryMinutes: 10,
    );
    final source = _FocusPortFake(
      recent: [terminal],
      failActiveReads: 1,
    );
    final store = MemoryFocusRecoveryStore()
      ..value =
          '${terminal.id}|${now.add(const Duration(minutes: 8)).toIso8601String()}';
    final controller = _controller(
      source: source,
      store: store,
      now: () => now,
      launch: const FocusSessionLaunch(initialSessionId: 'finished-focus'),
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.state.loadError, 'Could not load focus sessions.');

    final result = await controller.load();
    expect(result.initialReflection, same(terminal));
    expect(controller.state.loadError, isNull);
    expect(
      controller.state.recoveryEndsAt,
      now.add(const Duration(minutes: 8)).toLocal(),
    );

    controller.tick(now.add(const Duration(minutes: 9)));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.recoveryEndsAt, isNull);
    expect(store.value, isNull);
  });

  test('ambiguous start reconciles its canonical session before refresh',
      () async {
    final events = <String>[];
    final source = _FocusPortFake(
      events: events,
      loseNextStartResponse: true,
    );
    final gateway = _FocusGatewayFake(events: events);
    final controller = _controller(
      source: source,
      gateway: gateway,
      events: events,
    );
    addTearDown(controller.dispose);
    await controller.load();
    events.clear();

    final result = await controller.start();

    expect(result.outcome, FocusStartOutcome.started);
    expect(controller.state.active?.id, _requestId);
    expect(gateway.activatedSessionIds, contains(_requestId));
    expect(events.indexOf('start'), lessThan(events.indexOf('activate')));
    expect(events.indexOf('activate'), lessThan(events.indexOf('refresh')));
  });

  test(
      'finish commits canonical state and recovery despite native cleanup failure',
      () async {
    final events = <String>[];
    final active = _activeSession(recoveryMinutes: 10);
    final source = _FocusPortFake(active: active, events: events);
    final gateway = _FocusGatewayFake(
      events: events,
      failDeactivation: true,
    );
    final store = _TrackingRecoveryStore(events);
    final controller = _controller(
      source: source,
      gateway: gateway,
      store: store,
      events: events,
    );
    addTearDown(controller.dispose);
    await controller.load();
    events.clear();

    bool? protectionConfirmed;
    final result = await controller.finish(
      onCommitted: (session, confirmed) async {
        events.add('handoff');
        protectionConfirmed = confirmed;
        expect(session.status, FocusSessionStatus.completed);
        expect(controller.state.active, isNull);
        expect(controller.state.recoveryEndsAt, isNotNull);
      },
    );

    expect(result.committed, isTrue);
    expect(source.terminal?.status, FocusSessionStatus.completed);
    expect(protectionConfirmed, isFalse);
    expect(
      events.take(5),
      orderedEquals([
        'finish',
        'deactivate',
        'recovery',
        'refresh',
        'handoff',
      ]),
    );
  });

  test('abandon deactivates after commit and never starts recovery', () async {
    final events = <String>[];
    final source = _FocusPortFake(active: _activeSession(), events: events);
    final gateway = _FocusGatewayFake(events: events);
    final store = _TrackingRecoveryStore(events);
    final controller = _controller(
      source: source,
      gateway: gateway,
      store: store,
      events: events,
    );
    addTearDown(controller.dispose);
    await controller.load();
    events.clear();

    final result = await controller.abandon(
      onCommitted: (session, confirmed) async {
        events.add('handoff');
        expect(confirmed, isTrue);
      },
    );

    expect(result.session?.status, FocusSessionStatus.abandoned);
    expect(
      events.take(4),
      orderedEquals(['abandon', 'deactivate', 'refresh', 'handoff']),
    );
    expect(events, isNot(contains('recovery')));
    expect(controller.state.recoveryEndsAt, isNull);
  });

  test('emergency release changes only the device lease', () async {
    final source = _FocusPortFake(active: _activeSession());
    final gateway = _FocusGatewayFake();
    final controller = _controller(source: source, gateway: gateway);
    addTearDown(controller.dispose);
    await controller.load();

    final result = await controller.emergencyRelease();

    expect(result.released, isTrue);
    expect(controller.state.active?.status, FocusSessionStatus.active);
    expect(
      controller.state.protectionStatus?.lease?.state,
      FocusProtectionLeaseState.emergencyReleased,
    );
    expect(source.terminal, isNull);
  });

  test('reflection save and delete update controller history', () async {
    final terminal = _terminalSession(
      id: 'reflection-focus',
      status: FocusSessionStatus.completed,
    );
    final source = _FocusPortFake(recent: [terminal]);
    var reflectionRefreshes = 0;
    final controller = _controller(
      source: source,
      refreshReflectionProjection: () async => reflectionRefreshes += 1,
    );
    addTearDown(controller.dispose);
    await controller.load();
    final draft = FocusReflectionDraft(
      focusQuality: 4,
      usefulProgress: 5,
      obstacles: const [FocusObstacle.distracted],
    );

    final saved = await controller.saveReflection(
      session: terminal,
      draft: draft,
    );
    expect(controller.state.reflections[terminal.id], same(saved));
    expect(reflectionRefreshes, 1);

    await controller.deleteReflection(
      session: terminal,
      reflection: saved,
    );
    expect(controller.state.reflections, isEmpty);
    expect(reflectionRefreshes, 2);
  });
}

const _requestId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

FocusSessionController _controller({
  required _FocusPortFake source,
  _FocusGatewayFake? gateway,
  FocusRecoveryStore? store,
  List<String>? events,
  DateTime Function()? now,
  FocusReflectionProjectionRefresh? refreshReflectionProjection,
  FocusSessionLaunch launch = const FocusSessionLaunch(),
}) {
  final eventLog = events ?? <String>[];
  return FocusSessionController(
    launch: launch,
    source: source,
    studySource: source,
    protection: FocusProtectionReconciler(
      gateway: gateway ?? _FocusGatewayFake(events: eventLog),
      platformSupported: gateway != null,
    ),
    recoveryStore: store ?? MemoryFocusRecoveryStore(),
    refreshProjection: (_) async => eventLog.add('refresh'),
    refreshReflectionProjection: refreshReflectionProjection,
    requestIdFactory: () => _requestId,
    useMockData: false,
    clock: now ?? () => DateTime.utc(2026, 8, 2, 10),
  );
}

FocusSession _activeSession({int recoveryMinutes = 0}) {
  final startedAt = DateTime.utc(2026, 8, 2, 9, 30);
  return FocusSession(
    id: 'active-focus',
    status: FocusSessionStatus.active,
    startedAt: startedAt,
    plannedMinutes: 25,
    recoveryMinutes: recoveryMinutes,
    updatedAt: startedAt,
  );
}

FocusSession _terminalSession({
  required String id,
  required FocusSessionStatus status,
  int recoveryMinutes = 0,
}) {
  final startedAt = DateTime.utc(2026, 8, 2, 9);
  final endedAt = startedAt.add(const Duration(minutes: 25));
  return FocusSession(
    id: id,
    status: status,
    startedAt: startedAt,
    endedAt: endedAt,
    plannedMinutes: 25,
    recoveryMinutes: recoveryMinutes,
    actualMinutes: 25,
    updatedAt: endedAt,
  );
}

class _FocusPortFake implements FocusSessionLifecyclePort {
  _FocusPortFake({
    this.active,
    this.recent = const [],
    this.events,
    this.failActiveReads = 0,
    this.loseNextStartResponse = false,
  });

  FocusSession? active;
  List<FocusSession> recent;
  List<String>? events;
  int failActiveReads;
  bool loseNextStartResponse;
  FocusSession? terminal;
  final reflections = <String, FocusReflection>{};

  @override
  Future<FocusSession?> fetchActiveSession() async {
    if (failActiveReads > 0) {
      failActiveReads -= 1;
      throw StateError('read failed');
    }
    return active;
  }

  @override
  Future<List<FocusSession>> fetchRecentSessions({int limit = 10}) async {
    return [if (terminal != null) terminal!, ...recent];
  }

  @override
  Future<FocusSession> fetchSessionById(String sessionId) async {
    final matches = [if (active != null) active!, ...recent]
        .where((session) => session.id == sessionId);
    if (matches.isEmpty) throw StateError('missing session');
    return matches.first;
  }

  @override
  Future<FocusStartContext> fetchScheduledStartContext({
    required FocusScheduleSourceKind sourceKind,
    required String blockId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, FocusReflection>> fetchReflectionsForSessions(
    Iterable<FocusSession> sessions,
  ) async {
    return Map.unmodifiable(reflections);
  }

  @override
  Future<bool> fetchFocusReflectionPromptEnabled() async => true;

  @override
  Future<List<FocusTargetOption>> fetchAvailableTargets() async => const [];

  @override
  Future<StudyFocusSettings?> fetchStudyFocusSettings() async => null;

  @override
  Future<FocusSession> startSession({
    required String sessionId,
    required FocusStartDraft draft,
  }) async {
    events?.add('start');
    active = FocusSession(
      id: sessionId,
      status: FocusSessionStatus.active,
      startedAt: DateTime.utc(2026, 8, 2, 10),
      plannedMinutes: draft.plannedMinutes,
      recoveryMinutes: draft.recoveryMinutes,
      updatedAt: DateTime.utc(2026, 8, 2, 10),
    );
    if (loseNextStartResponse) {
      loseNextStartResponse = false;
      throw const FocusCommandException('Response lost.');
    }
    return active!;
  }

  @override
  Future<FocusSession> startScheduledSession({
    required String sessionId,
    required FocusScheduleSourceKind sourceKind,
    required String blockId,
    required int plannedMinutes,
  }) {
    return startSession(
      sessionId: sessionId,
      draft: FocusStartDraft(plannedMinutes: plannedMinutes),
    );
  }

  @override
  Future<FocusSession> finishSession(String sessionId) async {
    events?.add('finish');
    terminal = _end(FocusSessionStatus.completed);
    return terminal!;
  }

  @override
  Future<FocusSession> abandonSession(String sessionId) async {
    events?.add('abandon');
    terminal = _end(FocusSessionStatus.abandoned);
    return terminal!;
  }

  FocusSession _end(FocusSessionStatus status) {
    final current = active!;
    final endedAt = current.startedAt.add(const Duration(minutes: 25));
    active = null;
    return FocusSession(
      id: current.id,
      status: status,
      startedAt: current.startedAt,
      endedAt: endedAt,
      plannedMinutes: current.plannedMinutes,
      recoveryMinutes: current.recoveryMinutes,
      actualMinutes: 25,
      updatedAt: endedAt,
    );
  }

  @override
  Future<FocusReflection> saveReflection({
    required FocusSession session,
    required FocusReflectionDraft draft,
    FocusReflection? existing,
  }) async {
    final now = DateTime.utc(2026, 8, 2, 11);
    final reflection = FocusReflection(
      focusSessionId: session.id,
      focusQuality: draft.focusQuality,
      usefulProgress: draft.usefulProgress,
      obstacles: draft.obstacles,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    reflections[session.id] = reflection;
    return reflection;
  }

  @override
  Future<void> deleteReflection(FocusReflection reflection) async {
    reflections.remove(reflection.focusSessionId);
  }
}

class _TrackingRecoveryStore extends MemoryFocusRecoveryStore {
  _TrackingRecoveryStore(this.events);

  final List<String> events;

  @override
  Future<void> write(String value) async {
    events.add('recovery');
    await super.write(value);
  }
}

class _FocusGatewayFake implements FocusProtectionGateway {
  _FocusGatewayFake({
    List<String>? events,
    this.failDeactivation = false,
  }) : events = events ?? <String>[];

  final List<String> events;
  final bool failDeactivation;
  final activatedSessionIds = <String>[];
  FocusProtectionLease? lease;

  FocusProtectionConfiguration get configuration =>
      FocusProtectionConfiguration(
        enabled: true,
        blockSelectedApps: true,
        silenceNotifications: true,
      );

  FocusProtectionStatus get status => FocusProtectionStatus(
        platformSupported: true,
        accessibilityEnabled: true,
        notificationPolicyGranted: true,
        configuration: configuration,
        lease: lease,
      );

  @override
  Future<FocusProtectionStatus> readStatus() async => status;

  @override
  Future<FocusProtectionStatus> activateLease({
    required String sessionId,
    required DateTime startedAt,
    required DateTime endsAt,
  }) async {
    events.add('activate');
    activatedSessionIds.add(sessionId);
    lease = FocusProtectionLease(
      sessionId: sessionId,
      startedAt: startedAt,
      endsAt: endsAt,
      state: FocusProtectionLeaseState.active,
    );
    return status;
  }

  @override
  Future<FocusProtectionStatus> deactivateLease(String sessionId) async {
    events.add('deactivate');
    if (failDeactivation) throw StateError('native cleanup failed');
    if (lease?.sessionId == sessionId) lease = null;
    return status;
  }

  @override
  Future<FocusProtectionStatus> emergencyRelease(String sessionId) async {
    final current = lease!;
    lease = FocusProtectionLease(
      sessionId: current.sessionId,
      startedAt: current.startedAt,
      endsAt: current.endsAt,
      state: FocusProtectionLeaseState.emergencyReleased,
    );
    return status;
  }

  @override
  Future<List<InstalledLaunchableApp>> listLaunchableApps() async => const [];

  @override
  Future<FocusProtectionStatus> saveConfiguration(
    FocusProtectionConfiguration configuration,
  ) async =>
      status;

  @override
  Future<void> openAccessibilitySettings() async {}

  @override
  Future<void> openNotificationPolicySettings() async {}
}
