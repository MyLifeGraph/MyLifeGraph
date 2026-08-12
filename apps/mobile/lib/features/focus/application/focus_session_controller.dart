import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../focus_protection/domain/focus_protection.dart';
import '../domain/focus_session.dart';
import 'focus_protection_reconciler.dart';
import 'focus_recovery_store.dart';

typedef FocusClock = DateTime Function();
typedef FocusRequestIdFactory = String Function();
typedef FocusProjectionRefresh = Future<void> Function(String targetDate);
typedef FocusReflectionProjectionRefresh = Future<void> Function();
typedef FocusTerminalHandoff = Future<void> Function(
  FocusSession session,
  bool protectionConfirmed,
);

abstract interface class FocusSessionLifecyclePort {
  Future<FocusSession?> fetchActiveSession();
  Future<List<FocusSession>> fetchRecentSessions({int limit = 10});
  Future<FocusSession> fetchSessionById(String sessionId);
  Future<FocusStartContext> fetchScheduledStartContext({
    required FocusScheduleSourceKind sourceKind,
    required String blockId,
  });
  Future<Map<String, FocusReflection>> fetchReflectionsForSessions(
    Iterable<FocusSession> sessions,
  );
  Future<bool> fetchFocusReflectionPromptEnabled();
  Future<List<FocusTargetOption>> fetchAvailableTargets();
  Future<StudyFocusSettings?> fetchStudyFocusSettings();
  Future<FocusSession> startSession({
    required String sessionId,
    required FocusStartDraft draft,
  });
  Future<FocusSession> startScheduledSession({
    required String sessionId,
    required FocusScheduleSourceKind sourceKind,
    required String blockId,
    required int plannedMinutes,
  });
  Future<FocusSession> finishSession(String sessionId);
  Future<FocusSession> abandonSession(String sessionId);
  Future<FocusReflection> saveReflection({
    required FocusSession session,
    required FocusReflectionDraft draft,
    FocusReflection? existing,
  });
  Future<void> deleteReflection(FocusReflection reflection);
}

class FocusSessionLaunch {
  const FocusSessionLaunch({
    this.initialTargetKind,
    this.initialTargetId,
    this.initialPlannedMinutes,
    this.initialRecoveryMinutes,
    this.initialSourceKind,
    this.initialSourceBlockId,
    this.initialSessionId,
  });

  final FocusTargetKind? initialTargetKind;
  final String? initialTargetId;
  final int? initialPlannedMinutes;
  final int? initialRecoveryMinutes;
  final FocusScheduleSourceKind? initialSourceKind;
  final String? initialSourceBlockId;
  final String? initialSessionId;

  @override
  bool operator ==(Object other) =>
      other is FocusSessionLaunch &&
      other.initialTargetKind == initialTargetKind &&
      other.initialTargetId == initialTargetId &&
      other.initialPlannedMinutes == initialPlannedMinutes &&
      other.initialRecoveryMinutes == initialRecoveryMinutes &&
      other.initialSourceKind == initialSourceKind &&
      other.initialSourceBlockId == initialSourceBlockId &&
      other.initialSessionId == initialSessionId;

  @override
  int get hashCode => Object.hash(
        initialTargetKind,
        initialTargetId,
        initialPlannedMinutes,
        initialRecoveryMinutes,
        initialSourceKind,
        initialSourceBlockId,
        initialSessionId,
      );
}

enum StudySetupLoadStatus { configured, notConfigured, unavailable }

class FocusSessionState {
  FocusSessionState({
    required this.active,
    required List<FocusSession> recent,
    required Map<String, FocusReflection> reflections,
    required this.reflectionPromptEnabled,
    required this.reflectionDataAvailable,
    required List<FocusTargetOption> targets,
    required this.selectedTargetValue,
    required this.plannedMinutes,
    required this.recoveryMinutes,
    required this.studySettings,
    required this.studySetupStatus,
    required this.continueWithoutStudySetup,
    required this.recoveryEndsAt,
    required this.clockNow,
    required this.isLoading,
    required this.isSaving,
    required this.loadError,
    required this.scheduledContext,
    required this.startConflictMessage,
    required this.protectionStatus,
    required this.isChangingProtection,
  })  : recent = List.unmodifiable(recent),
        reflections = Map.unmodifiable(reflections),
        targets = List.unmodifiable(targets);

  factory FocusSessionState.initial({
    required FocusSessionLaunch launch,
    required DateTime now,
  }) {
    final requestedMinutes = launch.initialPlannedMinutes;
    return FocusSessionState(
      active: null,
      recent: const [],
      reflections: const {},
      reflectionPromptEnabled: false,
      reflectionDataAvailable: true,
      targets: const [],
      selectedTargetValue: null,
      plannedMinutes: requestedMinutes != null &&
              requestedMinutes >= 5 &&
              requestedMinutes <= 240
          ? requestedMinutes
          : 25,
      recoveryMinutes: 0,
      studySettings: null,
      studySetupStatus: StudySetupLoadStatus.unavailable,
      continueWithoutStudySetup: false,
      recoveryEndsAt: null,
      clockNow: now,
      isLoading: true,
      isSaving: false,
      loadError: null,
      scheduledContext: null,
      startConflictMessage: null,
      protectionStatus: null,
      isChangingProtection: false,
    );
  }

  final FocusSession? active;
  final List<FocusSession> recent;
  final Map<String, FocusReflection> reflections;
  final bool reflectionPromptEnabled;
  final bool reflectionDataAvailable;
  final List<FocusTargetOption> targets;
  final String? selectedTargetValue;
  final int plannedMinutes;
  final int recoveryMinutes;
  final StudyFocusSettings? studySettings;
  final StudySetupLoadStatus studySetupStatus;
  final bool continueWithoutStudySetup;
  final DateTime? recoveryEndsAt;
  final DateTime clockNow;
  final bool isLoading;
  final bool isSaving;
  final String? loadError;
  final FocusStartContext? scheduledContext;
  final String? startConflictMessage;
  final FocusProtectionStatus? protectionStatus;
  final bool isChangingProtection;

  bool get hasValidStartDuration =>
      plannedMinutes >= 5 &&
      plannedMinutes <= 240 &&
      (scheduledContext == null ||
          plannedMinutes <= scheduledContext!.remainingMinutes);

  bool get hasValidStartTarget {
    final selected = selectedTargetValue;
    final selectedExists =
        selected == null || targets.any((target) => target.value == selected);
    final scheduled = scheduledContext;
    if (scheduled != null) {
      return selected == scheduled.target.value && selectedExists;
    }
    return selectedExists;
  }

  bool get canStart =>
      active == null &&
      (studySetupStatus != StudySetupLoadStatus.unavailable ||
          continueWithoutStudySetup ||
          scheduledContext != null) &&
      (scheduledContext?.canStart ?? true) &&
      hasValidStartDuration &&
      hasValidStartTarget &&
      startConflictMessage == null;

  FocusTargetOption? targetFor(FocusSession session) => targets
      .where(
        (target) =>
            target.kind == session.targetKind && target.id == session.targetId,
      )
      .firstOrNull;

  FocusSessionState copyWith({
    Object? active = _unset,
    List<FocusSession>? recent,
    Map<String, FocusReflection>? reflections,
    bool? reflectionPromptEnabled,
    bool? reflectionDataAvailable,
    List<FocusTargetOption>? targets,
    Object? selectedTargetValue = _unset,
    int? plannedMinutes,
    int? recoveryMinutes,
    Object? studySettings = _unset,
    StudySetupLoadStatus? studySetupStatus,
    bool? continueWithoutStudySetup,
    Object? recoveryEndsAt = _unset,
    DateTime? clockNow,
    bool? isLoading,
    bool? isSaving,
    Object? loadError = _unset,
    Object? scheduledContext = _unset,
    Object? startConflictMessage = _unset,
    Object? protectionStatus = _unset,
    bool? isChangingProtection,
  }) {
    return FocusSessionState(
      active: identical(active, _unset) ? this.active : active as FocusSession?,
      recent: recent ?? this.recent,
      reflections: reflections ?? this.reflections,
      reflectionPromptEnabled:
          reflectionPromptEnabled ?? this.reflectionPromptEnabled,
      reflectionDataAvailable:
          reflectionDataAvailable ?? this.reflectionDataAvailable,
      targets: targets ?? this.targets,
      selectedTargetValue: identical(selectedTargetValue, _unset)
          ? this.selectedTargetValue
          : selectedTargetValue as String?,
      plannedMinutes: plannedMinutes ?? this.plannedMinutes,
      recoveryMinutes: recoveryMinutes ?? this.recoveryMinutes,
      studySettings: identical(studySettings, _unset)
          ? this.studySettings
          : studySettings as StudyFocusSettings?,
      studySetupStatus: studySetupStatus ?? this.studySetupStatus,
      continueWithoutStudySetup:
          continueWithoutStudySetup ?? this.continueWithoutStudySetup,
      recoveryEndsAt: identical(recoveryEndsAt, _unset)
          ? this.recoveryEndsAt
          : recoveryEndsAt as DateTime?,
      clockNow: clockNow ?? this.clockNow,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      loadError:
          identical(loadError, _unset) ? this.loadError : loadError as String?,
      scheduledContext: identical(scheduledContext, _unset)
          ? this.scheduledContext
          : scheduledContext as FocusStartContext?,
      startConflictMessage: identical(startConflictMessage, _unset)
          ? this.startConflictMessage
          : startConflictMessage as String?,
      protectionStatus: identical(protectionStatus, _unset)
          ? this.protectionStatus
          : protectionStatus as FocusProtectionStatus?,
      isChangingProtection: isChangingProtection ?? this.isChangingProtection,
    );
  }
}

class FocusLoadResult {
  const FocusLoadResult({this.initialReflection});

  final FocusSession? initialReflection;
}

enum FocusStartOutcome { ignored, started, anotherSessionActive, failed }

class FocusStartResult {
  const FocusStartResult._(this.outcome, {this.error});

  const FocusStartResult.ignored() : this._(FocusStartOutcome.ignored);
  const FocusStartResult.started() : this._(FocusStartOutcome.started);
  const FocusStartResult.anotherSessionActive()
      : this._(FocusStartOutcome.anotherSessionActive);
  FocusStartResult.failed(Object error)
      : this._(FocusStartOutcome.failed, error: error);

  final FocusStartOutcome outcome;
  final Object? error;
}

class FocusTerminalResult {
  const FocusTerminalResult._({
    required this.accepted,
    required this.committed,
    this.session,
    this.error,
  });

  const FocusTerminalResult.ignored()
      : this._(accepted: false, committed: false);

  FocusTerminalResult.saved(FocusSession session)
      : this._(accepted: true, committed: true, session: session);

  FocusTerminalResult.failed(Object error)
      : this._(accepted: true, committed: false, error: error);

  final bool accepted;
  final bool committed;
  final FocusSession? session;
  final Object? error;
}

class FocusEmergencyReleaseResult {
  const FocusEmergencyReleaseResult._({
    required this.accepted,
    required this.released,
  });

  const FocusEmergencyReleaseResult.ignored()
      : this._(accepted: false, released: false);
  const FocusEmergencyReleaseResult.released()
      : this._(accepted: true, released: true);
  const FocusEmergencyReleaseResult.failed()
      : this._(accepted: true, released: false);

  final bool accepted;
  final bool released;
}

class FocusSessionController extends StateNotifier<FocusSessionState> {
  FocusSessionController({
    required FocusSessionLaunch launch,
    required FocusSessionLifecyclePort? source,
    required FocusSessionLifecyclePort? studySource,
    required FocusProtectionReconciler protection,
    required FocusRecoveryStore recoveryStore,
    required FocusProjectionRefresh refreshProjection,
    FocusReflectionProjectionRefresh? refreshReflectionProjection,
    required FocusRequestIdFactory requestIdFactory,
    required bool useMockData,
    FocusClock? clock,
  })  : _launch = launch,
        _source = source,
        _studySource = studySource,
        _protection = protection,
        _recoveryStore = recoveryStore,
        _refreshProjection = refreshProjection,
        _refreshReflectionProjection =
            refreshReflectionProjection ?? _ignoreReflectionRefresh,
        _requestIdFactory = requestIdFactory,
        _useMockData = useMockData,
        _clock = clock ?? DateTime.now,
        super(
          FocusSessionState.initial(
            launch: launch,
            now: (clock ?? DateTime.now)(),
          ),
        );

  final FocusSessionLaunch _launch;
  final FocusSessionLifecyclePort? _source;
  final FocusSessionLifecyclePort? _studySource;
  final FocusProtectionReconciler _protection;
  final FocusRecoveryStore _recoveryStore;
  final FocusProjectionRefresh _refreshProjection;
  final FocusReflectionProjectionRefresh _refreshReflectionProjection;
  final FocusRequestIdFactory _requestIdFactory;
  final bool _useMockData;
  final FocusClock _clock;

  Timer? _ticker;
  int _loadGeneration = 0;
  bool _initialTargetApplied = false;
  bool _initialDurationApplied = false;
  bool _initialReflectionOpened = false;

  Future<FocusLoadResult> load() async {
    if (!mounted) return const FocusLoadResult();
    final generation = ++_loadGeneration;
    bool isCurrent() => mounted && generation == _loadGeneration;
    if (_useMockData) {
      state = state.copyWith(loadError: null, isLoading: false);
      return const FocusLoadResult();
    }
    final source = _source;
    if (source == null) {
      state = state.copyWith(
        loadError: 'Synced focus sessions are not configured.',
        isLoading: false,
      );
      return const FocusLoadResult();
    }
    state = state.copyWith(loadError: null, isLoading: true);
    try {
      final active = await source.fetchActiveSession();
      if (!isCurrent()) return const FocusLoadResult();
      final requestedSessionId = _launch.initialSessionId;
      final exactSessionFuture = requestedSessionId == null
          ? Future<FocusSession?>.value()
          : requestedSessionId == active?.id
              ? Future<FocusSession?>.value(active)
              : active == null
                  ? source.fetchSessionById(requestedSessionId)
                  : _fetchExactSessionWithoutHidingActive(
                      source,
                      requestedSessionId,
                    );
      final scheduledContextFuture = active != null ||
              _launch.initialSourceKind == null ||
              _launch.initialSourceBlockId == null
          ? Future<FocusStartContext?>.value()
          : source.fetchScheduledStartContext(
              sourceKind: _launch.initialSourceKind!,
              blockId: _launch.initialSourceBlockId!,
            );
      final results = await Future.wait<Object?>([
        source.fetchRecentSessions(),
        source.fetchAvailableTargets(),
        _fetchStudySettings(),
        exactSessionFuture,
        scheduledContextFuture,
      ]);
      final exactSession = results[3] as FocusSession?;
      final recent = <FocusSession>[
        if (exactSession != null) exactSession,
        ...(results[0] as List<FocusSession>)
            .where((session) => session.id != exactSession?.id),
      ];
      final scheduledContext = results[4] as FocusStartContext?;
      final loadedTargets = results[1] as List<FocusTargetOption>;
      final targets = <FocusTargetOption>[
        ...loadedTargets,
        if (scheduledContext != null &&
            !loadedTargets.any(
              (target) => target.value == scheduledContext.target.value,
            ))
          scheduledContext.target,
      ];
      final studyResult = results[2] as _StudySettingsResult;
      if (!isCurrent()) return const FocusLoadResult();
      final protectionStatus = await _protection.reconcile(
        canonicalSession: active,
        lastKnownStatus: state.protectionStatus,
        shouldContinue: isCurrent,
      );
      if (!isCurrent()) return const FocusLoadResult();
      Map<String, FocusReflection> reflections = const {};
      var reflectionPromptEnabled = false;
      var reflectionDataAvailable = true;
      try {
        final reflectionResults = await Future.wait<Object?>([
          source.fetchReflectionsForSessions(recent),
          source.fetchFocusReflectionPromptEnabled(),
        ]);
        reflections = reflectionResults[0] as Map<String, FocusReflection>;
        reflectionPromptEnabled = reflectionResults[1] as bool;
      } catch (_) {
        reflectionDataAvailable = false;
      }
      if (!isCurrent()) return const FocusLoadResult();
      var selected = state.selectedTargetValue;
      if (scheduledContext != null) {
        selected = scheduledContext.target.value;
        _initialTargetApplied = true;
      } else if (!_initialTargetApplied) {
        _initialTargetApplied = true;
        if (selected == null &&
            _launch.initialTargetKind != null &&
            _launch.initialTargetId != null) {
          final requested =
              '${_launch.initialTargetKind!.code}:${_launch.initialTargetId}';
          if (targets.any((target) => target.value == requested)) {
            selected = requested;
          }
        }
      }
      if (selected != null &&
          !targets.any((target) => target.value == selected)) {
        selected = null;
      }
      var plannedMinutes = state.plannedMinutes;
      if (scheduledContext != null) {
        final previous = state.scheduledContext;
        final contextChanged = previous == null ||
            previous.sourceKind != scheduledContext.sourceKind ||
            previous.blockId != scheduledContext.blockId ||
            previous.target.value != scheduledContext.target.value;
        if (!_initialDurationApplied || contextChanged) {
          plannedMinutes = scheduledContext.remainingMinutes;
        } else if (!_validPlannedMinutes(
          plannedMinutes,
          scheduledContext: scheduledContext,
        )) {
          plannedMinutes = scheduledContext.remainingMinutes;
        }
        _initialDurationApplied = true;
      } else if (!_initialDurationApplied) {
        _initialDurationApplied = true;
        if (_launch.initialPlannedMinutes == null && active == null) {
          final terminal = recent.where((session) => !session.isActive);
          if (studyResult.settings != null) {
            plannedMinutes = studyResult.settings!.focusMinutes;
          } else if (terminal.isNotEmpty) {
            plannedMinutes = terminal.first.plannedMinutes;
          }
        }
      } else if (!_validPlannedMinutes(plannedMinutes)) {
        plannedMinutes = studyResult.settings?.focusMinutes ?? 25;
      }
      final requestedRecovery = _launch.initialRecoveryMinutes;
      final recoveryMinutes = scheduledContext?.recoveryMinutes ??
          (requestedRecovery != null &&
                  (requestedRecovery == 0 ||
                      requestedRecovery >= 5 &&
                          requestedRecovery <= 60 &&
                          requestedRecovery.remainder(5) == 0)
              ? requestedRecovery
              : studyResult.settings?.recoveryMinutes ?? 0);
      final recoveryEndsAt =
          active == null ? await _restoreRecoveryCountdown(recent) : null;
      if (!isCurrent()) return const FocusLoadResult();
      state = state.copyWith(
        active: active,
        recent: recent,
        reflections: reflections,
        reflectionPromptEnabled: reflectionPromptEnabled,
        reflectionDataAvailable: reflectionDataAvailable,
        targets: targets,
        selectedTargetValue: selected,
        plannedMinutes: plannedMinutes,
        recoveryMinutes: recoveryMinutes,
        studySettings: studyResult.settings,
        studySetupStatus: studyResult.status,
        continueWithoutStudySetup: false,
        recoveryEndsAt: recoveryEndsAt,
        clockNow: _clock(),
        loadError: null,
        scheduledContext: scheduledContext,
        startConflictMessage: null,
        isLoading: false,
        protectionStatus: protectionStatus,
      );
      _syncTicker();
      if (!_initialReflectionOpened &&
          exactSession != null &&
          !exactSession.isActive) {
        _initialReflectionOpened = true;
        return FocusLoadResult(initialReflection: exactSession);
      }
      return const FocusLoadResult();
    } catch (_) {
      if (isCurrent()) {
        state = state.copyWith(
          loadError: 'Could not load focus sessions.',
          isLoading: false,
        );
      }
      return const FocusLoadResult();
    }
  }

  Future<void> retryStudySettings() async {
    if (!mounted || state.isSaving) return;
    final result = await _fetchStudySettings();
    if (!mounted) return;
    final scheduled = state.scheduledContext;
    state = state.copyWith(
      studySetupStatus: result.status,
      studySettings: result.settings,
      continueWithoutStudySetup: false,
      plannedMinutes: scheduled == null
          ? result.settings?.focusMinutes
          : state.plannedMinutes,
      recoveryMinutes: scheduled == null
          ? result.settings?.recoveryMinutes
          : scheduled.recoveryMinutes,
    );
  }

  void continueWithoutSavedStudySetup() {
    if (!mounted) return;
    if (state.scheduledContext != null) {
      state = state.copyWith(continueWithoutStudySetup: true);
      return;
    }
    final terminal = state.recent.where((session) => !session.isActive);
    state = state.copyWith(
      continueWithoutStudySetup: true,
      studySettings: null,
      plannedMinutes: terminal.isNotEmpty
          ? terminal.first.plannedMinutes
          : (state.plannedMinutes >= 5 && state.plannedMinutes <= 240
              ? state.plannedMinutes
              : 25),
      recoveryMinutes: 0,
    );
  }

  void setPlannedMinutes(int value) {
    if (!mounted ||
        !_validPlannedMinutes(
          value,
          scheduledContext: state.scheduledContext,
        )) {
      return;
    }
    state = state.copyWith(
      plannedMinutes: value,
      startConflictMessage: null,
    );
  }

  void selectTarget(String? value) {
    if (!mounted) return;
    final scheduled = state.scheduledContext;
    if (scheduled != null) {
      if (value != scheduled.target.value ||
          !state.targets.any((target) => target.value == value)) {
        return;
      }
    } else if (value != null &&
        !state.targets.any((target) => target.value == value)) {
      return;
    }
    state = state.copyWith(selectedTargetValue: value);
  }

  void setStartConflictMessage(String? message) {
    if (!mounted) return;
    state = state.copyWith(startConflictMessage: message);
  }

  Future<FocusStartResult> start() async {
    final source = _source;
    if (!mounted || source == null || state.isSaving || !state.canStart) {
      return const FocusStartResult.ignored();
    }
    final target = state.targets
        .where((candidate) => candidate.value == state.selectedTargetValue)
        .firstOrNull;
    final requestId = _requestIdFactory();
    final scheduled = state.scheduledContext;
    final plannedMinutes = state.plannedMinutes;
    final recoveryMinutes = state.recoveryMinutes;
    _loadGeneration++;
    state = state.copyWith(isSaving: true);
    try {
      final started = scheduled == null
          ? await source.startSession(
              sessionId: requestId,
              draft: FocusStartDraft(
                plannedMinutes: plannedMinutes,
                recoveryMinutes: recoveryMinutes,
                targetKind: target?.kind,
                targetId: target?.id,
                label: target?.title ?? 'Independent focus block',
              ),
            )
          : await source.startScheduledSession(
              sessionId: requestId,
              sourceKind: scheduled.sourceKind,
              blockId: scheduled.blockId,
              plannedMinutes: plannedMinutes,
            );
      await _reconcileVisibleProtection(started);
      await _afterDurableWrite(started);
      return const FocusStartResult.started();
    } catch (error) {
      if (!mounted) {
        await _reconcileUnknownStart(source, requestId);
        return FocusStartResult.failed(error);
      }
      await load();
      if (!mounted) return FocusStartResult.failed(error);
      final active = state.active;
      if (active != null) {
        await _reconcileVisibleProtection(active);
        if (active.id == requestId) {
          await _afterDurableWrite(active);
          return const FocusStartResult.started();
        }
        return const FocusStartResult.anotherSessionActive();
      }
      return FocusStartResult.failed(error);
    } finally {
      if (mounted) state = state.copyWith(isSaving: false);
    }
  }

  Future<FocusTerminalResult> finish({
    required FocusTerminalHandoff onCommitted,
  }) {
    return _runTerminal(
      finish: true,
      onCommitted: onCommitted,
    );
  }

  Future<FocusTerminalResult> abandon({
    required FocusTerminalHandoff onCommitted,
  }) {
    return _runTerminal(
      finish: false,
      onCommitted: onCommitted,
    );
  }

  Future<void> skipRecovery() async {
    await _clearStoredRecovery();
    if (!mounted) return;
    state = state.copyWith(recoveryEndsAt: null, clockNow: _clock());
    _syncTicker();
  }

  void tick([DateTime? instant]) {
    if (!mounted) return;
    final now = instant ?? _clock();
    final recoveryEndsAt = state.recoveryEndsAt;
    if (state.active == null &&
        recoveryEndsAt != null &&
        !recoveryEndsAt.isAfter(now)) {
      state = state.copyWith(clockNow: now, recoveryEndsAt: null);
      _ticker?.cancel();
      _ticker = null;
      unawaited(_clearStoredRecovery());
      return;
    }
    state = state.copyWith(clockNow: now);
  }

  Future<FocusEmergencyReleaseResult> emergencyRelease() async {
    if (!mounted || state.active == null || state.isChangingProtection) {
      return const FocusEmergencyReleaseResult.ignored();
    }
    final sessionId = state.active!.id;
    _loadGeneration++;
    state = state.copyWith(isChangingProtection: true);
    try {
      final status = await _protection.emergencyRelease(sessionId);
      if (mounted) state = state.copyWith(protectionStatus: status);
      return const FocusEmergencyReleaseResult.released();
    } catch (_) {
      return const FocusEmergencyReleaseResult.failed();
    } finally {
      if (mounted) state = state.copyWith(isChangingProtection: false);
    }
  }

  Future<FocusReflection> saveReflection({
    required FocusSession session,
    required FocusReflectionDraft draft,
    FocusReflection? existing,
  }) async {
    final source = _source;
    if (source == null) {
      throw const FocusCommandException('Focus reflection is unavailable.');
    }
    final saved = await source.saveReflection(
      session: session,
      draft: draft,
      existing: existing,
    );
    if (mounted) {
      state = state.copyWith(
        reflections: {...state.reflections, session.id: saved},
        reflectionDataAvailable: true,
      );
    }
    await _refreshReflectionProjectionSafely();
    return saved;
  }

  Future<void> deleteReflection({
    required FocusSession session,
    required FocusReflection reflection,
  }) async {
    final source = _source;
    if (source == null) {
      throw const FocusCommandException('Focus reflection is unavailable.');
    }
    await source.deleteReflection(reflection);
    if (mounted) {
      state = state.copyWith(
        reflections: {...state.reflections}..remove(session.id),
      );
    }
    await _refreshReflectionProjectionSafely();
  }

  Future<void> _refreshReflectionProjectionSafely() async {
    try {
      await _refreshReflectionProjection();
    } catch (_) {
      // A durable reflection stays successful when a dependent read cannot
      // be invalidated immediately.
    }
  }

  Future<FocusTerminalResult> _runTerminal({
    required bool finish,
    required FocusTerminalHandoff onCommitted,
  }) async {
    final source = _source;
    if (!mounted || source == null || state.active == null || state.isSaving) {
      return const FocusTerminalResult.ignored();
    }
    final active = state.active!;
    _loadGeneration++;
    state = state.copyWith(isSaving: true);
    try {
      final terminal = finish
          ? await source.finishSession(active.id)
          : await source.abandonSession(active.id);
      final deactivation = await _protection.deactivate(
        sessionId: active.id,
        lastKnownStatus: mounted ? state.protectionStatus : null,
      );
      if (mounted) {
        state = state.copyWith(
          active: null,
          selectedTargetValue: null,
          recent: [
            terminal,
            ...state.recent.where((session) => session.id != terminal.id),
          ],
          protectionStatus: deactivation.status,
        );
        _syncTicker();
      }
      if (finish) await _startRecoveryCountdown(terminal);
      unawaited(_refreshAfterTerminalWrite(terminal));
      await onCommitted(terminal, deactivation.confirmed);
      if (mounted) await load();
      return FocusTerminalResult.saved(terminal);
    } catch (error) {
      return FocusTerminalResult.failed(error);
    } finally {
      if (mounted) state = state.copyWith(isSaving: false);
    }
  }

  Future<void> _afterDurableWrite(FocusSession session) async {
    await _refreshProjection(session.snapshotEntryDate);
    if (mounted) await load();
  }

  Future<void> _reconcileUnknownStart(
    FocusSessionLifecyclePort source,
    String requestId,
  ) async {
    try {
      final active = await source.fetchActiveSession();
      if (active?.id == requestId) {
        await _protection.reconcile(canonicalSession: active);
        await _refreshProjection(active!.snapshotEntryDate);
      }
    } catch (_) {
      // The mutation remains honestly unconfirmed after navigation.
    }
  }

  Future<void> _reconcileVisibleProtection(FocusSession? session) async {
    final status = await _protection.reconcile(
      canonicalSession: session,
      lastKnownStatus: mounted ? state.protectionStatus : null,
    );
    if (mounted && status != null) {
      state = state.copyWith(protectionStatus: status);
    }
  }

  Future<void> _refreshAfterTerminalWrite(FocusSession session) async {
    try {
      await _refreshProjection(session.snapshotEntryDate);
    } catch (_) {
      // A durable terminal write is not rolled back by a stale projection.
    }
  }

  Future<_StudySettingsResult> _fetchStudySettings() async {
    final source = _studySource;
    if (source == null) {
      return const _StudySettingsResult(
        StudySetupLoadStatus.unavailable,
        null,
      );
    }
    try {
      final settings = await source.fetchStudyFocusSettings();
      return _StudySettingsResult(
        settings == null
            ? StudySetupLoadStatus.notConfigured
            : StudySetupLoadStatus.configured,
        settings,
      );
    } catch (_) {
      return const _StudySettingsResult(
        StudySetupLoadStatus.unavailable,
        null,
      );
    }
  }

  Future<FocusSession?> _fetchExactSessionWithoutHidingActive(
    FocusSessionLifecyclePort source,
    String sessionId,
  ) async {
    try {
      return await source.fetchSessionById(sessionId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _startRecoveryCountdown(FocusSession session) async {
    if (session.recoveryMinutes <= 0 ||
        session.status != FocusSessionStatus.completed) {
      return;
    }
    final endsAt = (session.endedAt ?? _clock()).add(
      Duration(minutes: session.recoveryMinutes),
    );
    try {
      await _recoveryStore.write(
        '${session.id}|${endsAt.toUtc().toIso8601String()}',
      );
    } catch (_) {
      // The visible countdown remains available for this app process.
    }
    if (mounted) {
      state = state.copyWith(clockNow: _clock(), recoveryEndsAt: endsAt);
      _syncTicker();
    }
  }

  Future<DateTime?> _restoreRecoveryCountdown(
    List<FocusSession> recent,
  ) async {
    final completedRecoveryIds = recent
        .where(
          (session) =>
              session.status == FocusSessionStatus.completed &&
              session.recoveryMinutes > 0,
        )
        .map((session) => session.id)
        .toSet();
    if (completedRecoveryIds.isEmpty) return null;
    try {
      final raw = await _recoveryStore.read();
      if (raw == null) return null;
      final separator = raw.indexOf('|');
      if (separator <= 0) {
        await _recoveryStore.clear();
        return null;
      }
      final sessionId = raw.substring(0, separator);
      final endsAt = DateTime.tryParse(raw.substring(separator + 1));
      if (!completedRecoveryIds.contains(sessionId) ||
          endsAt == null ||
          !endsAt.isAfter(_clock())) {
        await _recoveryStore.clear();
        return null;
      }
      return endsAt.toLocal();
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearStoredRecovery() async {
    try {
      await _recoveryStore.clear();
    } catch (_) {
      // Local storage availability must not block Focus.
    }
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (state.active == null &&
        state.recoveryEndsAt?.isAfter(_clock()) != true) {
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  @override
  void dispose() {
    _loadGeneration++;
    _ticker?.cancel();
    super.dispose();
  }
}

Future<void> _ignoreReflectionRefresh() async {}

bool _validPlannedMinutes(
  int value, {
  FocusStartContext? scheduledContext,
}) {
  return value >= 5 &&
      value <= 240 &&
      (scheduledContext == null || value <= scheduledContext.remainingMinutes);
}

class _StudySettingsResult {
  const _StudySettingsResult(this.status, this.settings);

  final StudySetupLoadStatus status;
  final StudyFocusSettings? settings;
}

const _unset = Object();
