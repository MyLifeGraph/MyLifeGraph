import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/projection_refresh_providers.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/features/focus/data/focus_session_supabase_data_source.dart';
import 'package:my_life_graph/features/focus/domain/focus_session.dart';
import 'package:my_life_graph/features/focus/presentation/pages/focus_session_page.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/domain/focus_protection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('confirmed start activates protection before projection refresh',
      (tester) async {
    final events = <String>[];
    final source = _LifecycleFocusSource(events: events);
    final gateway = _LifecycleGateway(events: events);

    await _pumpFocus(tester, source: source, gateway: gateway, events: events);
    await tester.tap(find.text('Start focus session'));
    await tester.pumpAndSettle();

    expect(find.text('Focus active'), findsOneWidget);
    expect(gateway.activatedSessionIds, isNotEmpty);
    expect(gateway.activatedSessionIds.toSet(), {source.active!.id});
    expect(events.indexOf('activate'), lessThan(events.indexOf('projection')));
    expect(find.text('Device protection active'), findsOneWidget);

    await tester.tap(find.text('Finish focus session'));
    await tester.pumpAndSettle();
    expect(gateway.deactivatedSessionIds, [source.lastTerminal!.id]);
    expect(events.indexOf('finish'), lessThan(events.indexOf('deactivate')));
  });

  testWidgets('ambiguous committed start replay reconciles the same lease',
      (tester) async {
    final events = <String>[];
    final source = _LifecycleFocusSource(
      events: events,
      loseFirstStartResponse: true,
    );
    final gateway = _LifecycleGateway(events: events);

    await _pumpFocus(tester, source: source, gateway: gateway, events: events);
    await tester.tap(find.text('Start focus session'));
    await tester.pumpAndSettle();

    expect(find.text('Focus active'), findsOneWidget);
    expect(gateway.activatedSessionIds, isNotEmpty);
    expect(gateway.activatedSessionIds.toSet(), {source.active!.id});
  });

  testWidgets('native activation failure never rolls back synced Focus start',
      (tester) async {
    final events = <String>[];
    final source = _LifecycleFocusSource(events: events);
    final gateway = _LifecycleGateway(
      events: events,
      failActivation: true,
    );

    await _pumpFocus(tester, source: source, gateway: gateway, events: events);
    await tester.tap(find.text('Start focus session'));
    await tester.pumpAndSettle();

    expect(source.active, isNotNull);
    expect(find.text('Focus active'), findsOneWidget);
    expect(
      find.textContaining('Android protection status could not be confirmed'),
      findsOneWidget,
    );
  });

  testWidgets('native cleanup failure never rolls back synced Focus finish',
      (tester) async {
    final events = <String>[];
    final source = _LifecycleFocusSource(events: events, initiallyActive: true);
    final gateway = _LifecycleGateway(
      events: events,
      failDeactivation: true,
    );

    await _pumpFocus(tester, source: source, gateway: gateway, events: events);
    await tester.tap(find.text('Finish focus session'));
    await tester.pumpAndSettle();

    expect(source.active, isNull);
    expect(source.lastTerminal?.status, FocusSessionStatus.completed);
    expect(gateway.deactivatedSessionIds, isNotEmpty);
    expect(gateway.deactivatedSessionIds.toSet(), {'existing-session'});
    expect(find.text('Focus active'), findsNothing);
    expect(
      find.textContaining('Android cleanup could not be confirmed'),
      findsOneWidget,
    );
  });

  testWidgets('confirmed abandon deactivates only after durable mutation',
      (tester) async {
    final events = <String>[];
    final source = _LifecycleFocusSource(events: events, initiallyActive: true);
    final gateway = _LifecycleGateway(events: events);

    await _pumpFocus(tester, source: source, gateway: gateway, events: events);
    await tester.tap(find.text('Abandon'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Abandon session'));
    await tester.pumpAndSettle();

    expect(source.active, isNull);
    expect(source.lastTerminal?.status, FocusSessionStatus.abandoned);
    expect(gateway.deactivatedSessionIds, ['existing-session']);
    expect(events.indexOf('abandon'), lessThan(events.indexOf('deactivate')));
  });

  testWidgets('resume refetches canonical state and clears a terminal lease',
      (tester) async {
    final events = <String>[];
    final source = _LifecycleFocusSource(events: events, initiallyActive: true);
    final gateway = _LifecycleGateway(events: events);

    await _pumpFocus(tester, source: source, gateway: gateway, events: events);
    expect(gateway.lease?.sessionId, 'existing-session');
    source.active = null;

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpAndSettle();

    expect(gateway.deactivatedSessionIds, contains('existing-session'));
    expect(gateway.lease, isNull);
    expect(find.text('Focus active'), findsNothing);
  });

  testWidgets('older overlapping resume response cannot reactivate stale lease',
      (tester) async {
    final events = <String>[];
    final source = _LifecycleFocusSource(events: events, initiallyActive: true);
    final gateway = _LifecycleGateway(events: events);

    await _pumpFocus(tester, source: source, gateway: gateway, events: events);
    final oldSession = source.active!;
    final delayedFetch = Completer<FocusSession?>();
    source.delayNextActiveFetch(delayedFetch);
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pump();

    source.active = null;
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpAndSettle();
    final activationCount = gateway.activatedSessionIds.length;

    delayedFetch.complete(oldSession);
    await tester.pumpAndSettle();

    expect(gateway.lease, isNull);
    expect(gateway.activatedSessionIds, hasLength(activationCount));
    expect(find.text('Focus active'), findsNothing);
  });

  testWidgets('unknown native configuration is not presented as switched off',
      (tester) async {
    final events = <String>[];
    final source = _LifecycleFocusSource(events: events, initiallyActive: true);
    final gateway = _LifecycleGateway(events: events, failRead: true);

    await _pumpFocus(tester, source: source, gateway: gateway, events: events);

    expect(find.text('Device protection status unavailable'), findsOneWidget);
    expect(find.text('Device protection is off'), findsNothing);
  });

  testWidgets('an active lease with no confirmed mechanism is shown as partial',
      (tester) async {
    final events = <String>[];
    final source = _LifecycleFocusSource(events: events, initiallyActive: true);
    final gateway = _LifecycleGateway(
      events: events,
      reportActiveMechanisms: false,
    );

    await _pumpFocus(tester, source: source, gateway: gateway, events: events);

    expect(
      find.text('Focus continues with partial protection'),
      findsOneWidget,
    );
    expect(find.text('Device protection active'), findsNothing);
    expect(
      find.byKey(const ValueKey('focus-protection-emergency-release')),
      findsOneWidget,
    );
  });

  testWidgets('emergency release waits five seconds and keeps session active',
      (tester) async {
    final events = <String>[];
    final source = _LifecycleFocusSource(events: events, initiallyActive: true);
    final gateway = _LifecycleGateway(events: events);

    await _pumpFocus(tester, source: source, gateway: gateway, events: events);
    await tester.tap(
      find.byKey(const ValueKey('focus-protection-emergency-release')),
    );
    await tester.pump();
    final confirm = find.byKey(
      const ValueKey('confirm-focus-protection-emergency-release'),
    );
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(source.active, isNotNull);
    expect(gateway.emergencySessionIds, [source.active!.id]);
    expect(find.text('Device protection released'), findsOneWidget);
  });
}

Future<void> _pumpFocus(
  WidgetTester tester, {
  required _LifecycleFocusSource source,
  required _LifecycleGateway gateway,
  required List<String> events,
}) async {
  final projection = ProjectionRefreshCoordinator(
    refreshDailySnapshot: (_) async => events.add('projection'),
    invalidateProjection: (_) {},
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(_realConfig),
        focusSessionPageDataSourceProvider.overrideWithValue(source),
        focusStudySettingsDataSourceProvider.overrideWithValue(source),
        focusProtectionPlatformSupportedProvider.overrideWithValue(true),
        focusProtectionGatewayProvider.overrideWithValue(gateway),
        projectionRefreshCoordinatorProvider.overrideWithValue(projection),
      ],
      child: const MaterialApp(
        home: Scaffold(body: FocusSessionPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _realConfig = AppConfig(
  environment: 'test',
  supabaseUrl: 'http://localhost:54321',
  supabaseAnonKey: 'test-anon-key',
  aiServiceBaseUrl: 'http://localhost:8000',
  useMockData: false,
);

class _LifecycleFocusSource extends FocusSessionSupabaseDataSource {
  _LifecycleFocusSource({
    required this.events,
    this.loseFirstStartResponse = false,
    bool initiallyActive = false,
  })  : active = initiallyActive ? _newSession('existing-session') : null,
        super(
          SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final List<String> events;
  final bool loseFirstStartResponse;
  bool _lostResponse = false;
  Completer<FocusSession?>? _delayedActiveFetch;
  FocusSession? active;
  FocusSession? lastTerminal;

  @override
  Future<FocusSession?> fetchActiveSession() async {
    final delayed = _delayedActiveFetch;
    if (delayed != null) {
      _delayedActiveFetch = null;
      return delayed.future;
    }
    return active;
  }

  void delayNextActiveFetch(Completer<FocusSession?> completer) {
    _delayedActiveFetch = completer;
  }

  @override
  Future<List<FocusSession>> fetchRecentSessions({int limit = 10}) async =>
      lastTerminal == null ? const [] : [lastTerminal!];

  @override
  Future<List<FocusTargetOption>> fetchAvailableTargets() async => const [];

  @override
  Future<StudyFocusSettings?> fetchStudyFocusSettings() async => null;

  @override
  Future<Map<String, FocusReflection>> fetchReflectionsForSessions(
    Iterable<FocusSession> sessions,
  ) async =>
      const {};

  @override
  Future<bool> fetchFocusReflectionPromptEnabled() async => false;

  @override
  Future<FocusSession> startSession({
    required String sessionId,
    required FocusStartDraft draft,
  }) async {
    active = _newSession(sessionId, plannedMinutes: draft.plannedMinutes);
    events.add('start');
    if (loseFirstStartResponse && !_lostResponse) {
      _lostResponse = true;
      throw const FocusCommandException('Response lost.');
    }
    return active!;
  }

  @override
  Future<FocusSession> finishSession(String sessionId) async {
    events.add('finish');
    final current = active!;
    final endedAt = current.startedAt.add(const Duration(minutes: 1));
    lastTerminal = FocusSession(
      id: current.id,
      status: FocusSessionStatus.completed,
      startedAt: current.startedAt,
      endedAt: endedAt,
      plannedMinutes: current.plannedMinutes,
      actualMinutes: 1,
      updatedAt: endedAt,
    );
    active = null;
    return lastTerminal!;
  }

  @override
  Future<FocusSession> abandonSession(String sessionId) async {
    events.add('abandon');
    final current = active!;
    final endedAt = current.startedAt.add(const Duration(minutes: 1));
    lastTerminal = FocusSession(
      id: current.id,
      status: FocusSessionStatus.abandoned,
      startedAt: current.startedAt,
      endedAt: endedAt,
      plannedMinutes: current.plannedMinutes,
      actualMinutes: 1,
      updatedAt: endedAt,
    );
    active = null;
    return lastTerminal!;
  }

  static FocusSession _newSession(
    String id, {
    int plannedMinutes = 25,
  }) {
    final now = DateTime.now().subtract(const Duration(seconds: 5));
    return FocusSession(
      id: id,
      status: FocusSessionStatus.active,
      startedAt: now,
      plannedMinutes: plannedMinutes,
      updatedAt: now,
    );
  }
}

class _LifecycleGateway implements FocusProtectionGateway {
  _LifecycleGateway({
    required this.events,
    this.failActivation = false,
    this.failDeactivation = false,
    this.failRead = false,
    this.reportActiveMechanisms = true,
  });

  final List<String> events;
  final bool failActivation;
  final bool failDeactivation;
  final bool failRead;
  final bool reportActiveMechanisms;
  final activatedSessionIds = <String>[];
  final deactivatedSessionIds = <String>[];
  final emergencySessionIds = <String>[];
  FocusProtectionLease? lease;

  FocusProtectionConfiguration get configuration =>
      FocusProtectionConfiguration(
        enabled: true,
        blockSelectedApps: true,
        silenceNotifications: true,
        selectedPackages: const ['video.app'],
      );

  FocusProtectionStatus get status => FocusProtectionStatus(
        platformSupported: true,
        accessibilityEnabled: true,
        notificationPolicyGranted: true,
        configuration: configuration,
        lease: lease,
        activeMechanisms: reportActiveMechanisms && lease?.isActive == true
            ? const ['app_blocking', 'silence_notifications']
            : const [],
      );

  @override
  Future<FocusProtectionStatus> readStatus() async {
    if (failRead) throw StateError('native read failure');
    return status;
  }

  @override
  Future<FocusProtectionStatus> activateLease({
    required String sessionId,
    required DateTime startedAt,
    required DateTime endsAt,
  }) async {
    events.add('activate');
    activatedSessionIds.add(sessionId);
    if (failActivation) throw StateError('native failure');
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
    deactivatedSessionIds.add(sessionId);
    if (failDeactivation) throw StateError('native cleanup failure');
    if (lease?.sessionId == sessionId) lease = null;
    return status;
  }

  @override
  Future<FocusProtectionStatus> emergencyRelease(String sessionId) async {
    emergencySessionIds.add(sessionId);
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
