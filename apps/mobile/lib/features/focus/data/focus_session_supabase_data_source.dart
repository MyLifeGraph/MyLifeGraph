import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/app_user_resolver.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../core/utils/client_uuid.dart';
import '../../../core/utils/local_date.dart';
import '../domain/focus_session.dart';

typedef FocusNowProvider = DateTime Function();

class FocusSessionSupabaseDataSource {
  FocusSessionSupabaseDataSource(
    this._client, {
    FocusNowProvider? nowProvider,
  }) : _nowProvider = nowProvider ?? DateTime.now;

  static const _columns =
      'id,status,started_at,ended_at,planned_minutes,actual_minutes,label,'
      'task_id,habit_id,metadata,updated_at';
  static const _reflectionColumns =
      'focus_session_id,contract_version,focus_quality,useful_progress,'
      'obstacles,created_at,updated_at';

  final SupabaseClient _client;
  final FocusNowProvider _nowProvider;

  Future<FocusSession?> fetchActiveSession() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final row = await _client
        .from(SupabaseTables.focusSessions)
        .select(_columns)
        .eq('user_id', userId)
        .eq('status', FocusSessionStatus.active.code)
        .maybeSingle();
    return row == null
        ? null
        : FocusSession.fromRow(Map<String, dynamic>.from(row));
  }

  Future<List<FocusSession>> fetchRecentSessions({int limit = 10}) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final rows = await _client
        .from(SupabaseTables.focusSessions)
        .select(_columns)
        .eq('user_id', userId)
        .order('started_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List)
        .map(FocusSession.fromRow)
        .toList();
  }

  Future<Map<String, FocusReflection>> fetchReflectionsForSessions(
    Iterable<FocusSession> sessions,
  ) async {
    final sessionIds = sessions
        .where((session) => !session.isActive)
        .map((session) => session.id)
        .toSet()
        .toList(growable: false);
    if (sessionIds.isEmpty) return const {};
    final userId = await AppUserResolver(_client).resolveUserId();
    final rows = await _client
        .from(SupabaseTables.focusSessionReflections)
        .select(_reflectionColumns)
        .eq('user_id', userId)
        .inFilter('focus_session_id', sessionIds);
    final reflections = <String, FocusReflection>{};
    for (final raw in List<Map<String, dynamic>>.from(rows as List)) {
      final reflection = FocusReflection.fromRow(raw);
      if (!sessionIds.contains(reflection.focusSessionId) ||
          reflections.containsKey(reflection.focusSessionId)) {
        throw const FocusCommandException(
          'Focus reflection response is invalid.',
        );
      }
      reflections[reflection.focusSessionId] = reflection;
    }
    return Map.unmodifiable(reflections);
  }

  Future<bool> fetchFocusReflectionPromptEnabled() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final row = await _client
        .from(SupabaseTables.learningPreferences)
        .select('contract_version,focus_reflection_prompt_enabled')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return true;
    if (row['contract_version'] != 'learning-preferences-v1' ||
        row['focus_reflection_prompt_enabled'] is! bool) {
      throw const FocusCommandException(
        'Personal learning preference response is invalid.',
      );
    }
    return row['focus_reflection_prompt_enabled'] as bool;
  }

  Future<FocusReflection> saveReflection({
    required FocusSession session,
    required FocusReflectionDraft draft,
    FocusReflection? existing,
  }) async {
    if (session.isActive ||
        existing != null && existing.focusSessionId != session.id) {
      throw const FocusCommandException(
        'Only a finished Focus session can be rated.',
      );
    }
    final userId = await AppUserResolver(_client).resolveUserId();
    final currentSession = await _requireOwnedSession(
      session.id,
      userId: userId,
    );
    if (currentSession.isActive) {
      throw const FocusCommandException(
        'Only a finished Focus session can be rated.',
      );
    }
    final payload = {
      'focus_quality': draft.focusQuality,
      'useful_progress': draft.usefulProgress,
      'obstacles': draft.obstacles.map((value) => value.code).toList(),
    };
    if (existing == null) {
      try {
        final row = await _client
            .from(SupabaseTables.focusSessionReflections)
            .insert({
              'focus_session_id': session.id,
              'user_id': userId,
              'contract_version': 'focus-reflection-v1',
              ...payload,
            })
            .select(_reflectionColumns)
            .single();
        final saved = FocusReflection.fromRow(
          Map<String, dynamic>.from(row),
        );
        if (!saved.matches(draft)) {
          throw const FocusCommandException(
            'Focus reflection save returned a mismatched result.',
          );
        }
        return saved;
      } catch (error) {
        final current = await _fetchReflection(
          session.id,
          userId: userId,
        );
        if (current?.matches(draft) == true) return current!;
        if (current != null) {
          throw const FocusReflectionConflictException(
            'This Focus reflection changed. Reload before editing it.',
          );
        }
        rethrow;
      }
    }

    try {
      final rows = await _client
          .from(SupabaseTables.focusSessionReflections)
          .update(payload)
          .eq('focus_session_id', session.id)
          .eq('user_id', userId)
          .eq('updated_at', existing.updatedAt.toUtc().toIso8601String())
          .select(_reflectionColumns);
      final typedRows = List<Map<String, dynamic>>.from(rows as List);
      if (typedRows.length == 1) {
        final saved = FocusReflection.fromRow(typedRows.single);
        if (saved.matches(draft)) return saved;
      } else if (typedRows.length > 1) {
        throw const FocusCommandException(
          'Focus reflection save returned an invalid result.',
        );
      }
    } catch (error) {
      final current = await _fetchReflection(session.id, userId: userId);
      if (current?.matches(draft) == true) return current!;
      if (current != null) {
        throw const FocusReflectionConflictException(
          'This Focus reflection changed. Reload before editing it.',
        );
      }
      rethrow;
    }
    final current = await _fetchReflection(session.id, userId: userId);
    if (current?.matches(draft) == true) return current!;
    throw const FocusReflectionConflictException(
      'This Focus reflection changed. Reload before editing it.',
    );
  }

  Future<void> deleteReflection(FocusReflection reflection) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final rows = await _client
        .from(SupabaseTables.focusSessionReflections)
        .delete()
        .eq('focus_session_id', reflection.focusSessionId)
        .eq('user_id', userId)
        .eq('updated_at', reflection.updatedAt.toUtc().toIso8601String())
        .select('focus_session_id');
    final typedRows = List<Map<String, dynamic>>.from(rows as List);
    if (typedRows.length == 1) return;
    if (typedRows.length > 1) {
      throw const FocusCommandException(
        'Focus reflection delete returned an invalid result.',
      );
    }
    final current = await _fetchReflection(
      reflection.focusSessionId,
      userId: userId,
    );
    if (current == null) return;
    throw const FocusReflectionConflictException(
      'This Focus reflection changed. Reload before deleting it.',
    );
  }

  Future<FocusReflection?> _fetchReflection(
    String sessionId, {
    required String userId,
  }) async {
    final row = await _client
        .from(SupabaseTables.focusSessionReflections)
        .select(_reflectionColumns)
        .eq('focus_session_id', sessionId)
        .eq('user_id', userId)
        .maybeSingle();
    return row == null
        ? null
        : FocusReflection.fromRow(Map<String, dynamic>.from(row));
  }

  Future<List<FocusTargetOption>> fetchAvailableTargets() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final results = await Future.wait([
      _client
          .from(SupabaseTables.tasks)
          .select('id,title,status')
          .eq('user_id', userId)
          .inFilter('status', const ['todo', 'in_progress'])
          .order('updated_at', ascending: false)
          .limit(50),
      _client
          .from(SupabaseTables.habits)
          .select('id,title,active,metadata')
          .eq('user_id', userId)
          .eq('active', true)
          .order('updated_at', ascending: false)
          .limit(50),
    ]);
    final targets = <FocusTargetOption>[
      ...List<Map<String, dynamic>>.from(results[0] as List).map(
        (row) => _targetFromRow(row, FocusTargetKind.task),
      ),
      ...List<Map<String, dynamic>>.from(results[1] as List)
          .where(_isExecutableHabit)
          .map((row) => _targetFromRow(row, FocusTargetKind.habit)),
    ];
    return targets;
  }

  Future<StudyFocusSettings?> fetchStudyFocusSettings() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final row = await _client
        .from(SupabaseTables.studySetupProfiles)
        .select(
          'focus_minutes,recovery_minutes,preparation_items,setup_revision',
        )
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null ||
        row['focus_minutes'] == null ||
        row['recovery_minutes'] == null) {
      return null;
    }
    return StudyFocusSettings.fromRow(Map<String, dynamic>.from(row));
  }

  Future<FocusSession> startSession({
    required String sessionId,
    required FocusStartDraft draft,
  }) async {
    if (!isClientUuid(sessionId)) {
      throw const FocusCommandException(
        'Focus request identity is invalid.',
      );
    }
    final userId = await AppUserResolver(_client).resolveUserId();
    final existing = await fetchActiveSession();
    if (existing != null) {
      if (existing.id == sessionId &&
          existing.plannedMinutes == draft.plannedMinutes &&
          existing.recoveryMinutes == draft.recoveryMinutes &&
          existing.targetKind == draft.targetKind &&
          existing.targetId == draft.targetId) {
        return existing;
      }
      throw const FocusCommandException(
        'Finish or abandon the active focus session first.',
      );
    }
    if (draft.targetKind != null && draft.targetId != null) {
      await _requireOwnedTarget(
        userId: userId,
        kind: draft.targetKind!,
        targetId: draft.targetId!,
      );
    }
    final nowValue = _nowProvider();
    final now = _timestamp(nowValue);
    final row = await _client
        .from(SupabaseTables.focusSessions)
        .upsert(
          {
            'id': sessionId,
            'user_id': userId,
            'status': FocusSessionStatus.active.code,
            'started_at': now,
            'planned_minutes': draft.plannedMinutes,
            'label': draft.label,
            'task_id': draft.targetKind == FocusTargetKind.task
                ? draft.targetId
                : null,
            'habit_id': draft.targetKind == FocusTargetKind.habit
                ? draft.targetId
                : null,
            'metadata': {
              'source': 'flutter-focus-v1',
              'contract_version': 'focus-session-v1',
              'entry_date': localDateKey(nowValue),
              if (draft.recoveryMinutes > 0)
                'recovery_minutes': draft.recoveryMinutes,
              'action_target': {
                'contract_version': 'executable-action-v1',
                'id': 'start_focus:$sessionId',
                'kind': 'focus',
                'command': 'start_focus',
                'target_id': draft.targetId,
                'estimated_minutes': draft.plannedMinutes,
                'metadata': {
                  'focus_minutes': draft.plannedMinutes,
                  'source': 'focus_session',
                  if (draft.targetKind != null)
                    'target_kind': draft.targetKind!.code,
                },
              },
            },
            'updated_at': now,
          },
          onConflict: 'id',
        )
        .select(_columns)
        .single();
    return FocusSession.fromRow(Map<String, dynamic>.from(row));
  }

  Future<FocusSession> finishSession(String sessionId) {
    return _endSession(
      sessionId,
      terminalStatus: FocusSessionStatus.completed,
    );
  }

  Future<FocusSession> abandonSession(String sessionId) {
    return _endSession(
      sessionId,
      terminalStatus: FocusSessionStatus.abandoned,
    );
  }

  Future<FocusSession> _endSession(
    String sessionId, {
    required FocusSessionStatus terminalStatus,
  }) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final session = await _requireOwnedSession(sessionId, userId: userId);
    if (session.status == terminalStatus) {
      return session;
    }
    if (!session.isActive) {
      throw const FocusCommandException(
        'The focus session is no longer active.',
      );
    }
    final endedAt = _nowProvider();
    final actualMinutes = measuredFocusMinutes(
      startedAt: session.startedAt,
      endedAt: endedAt,
    );
    try {
      final rows = await _client
          .from(SupabaseTables.focusSessions)
          .update({
            'status': terminalStatus.code,
            'ended_at': _timestamp(endedAt),
            'actual_minutes': actualMinutes,
            'updated_at': _timestamp(endedAt),
          })
          .eq('id', sessionId)
          .eq('user_id', userId)
          .eq('status', FocusSessionStatus.active.code)
          .select(_columns);
      final typedRows = List<Map<String, dynamic>>.from(rows as List);
      if (typedRows.length != 1) {
        throw const FocusCommandException(
          'Focus session transition did not apply.',
        );
      }
      return FocusSession.fromRow(typedRows.single);
    } catch (_) {
      try {
        final current = await _requireOwnedSession(sessionId, userId: userId);
        if (current.status == terminalStatus &&
            current.endedAt?.isAtSameMomentAs(endedAt) == true &&
            current.actualMinutes == actualMinutes) {
          return current;
        }
      } catch (_) {
        // Preserve the original ambiguous transition failure below.
      }
      rethrow;
    }
  }

  Future<FocusSession> _requireOwnedSession(
    String sessionId, {
    required String userId,
  }) async {
    final row = await _client
        .from(SupabaseTables.focusSessions)
        .select(_columns)
        .eq('id', sessionId)
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) {
      throw const FocusCommandException('Focus session is unavailable.');
    }
    return FocusSession.fromRow(Map<String, dynamic>.from(row));
  }

  Future<void> _requireOwnedTarget({
    required String userId,
    required FocusTargetKind kind,
    required String targetId,
  }) async {
    if (kind == FocusTargetKind.task) {
      final row = await _client
          .from(SupabaseTables.tasks)
          .select('id,status')
          .eq('id', targetId)
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null ||
          !const ['todo', 'in_progress'].contains(row['status'])) {
        throw const FocusCommandException('Task target is unavailable.');
      }
      return;
    }
    final row = await _client
        .from(SupabaseTables.habits)
        .select('id,active,metadata')
        .eq('id', targetId)
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null || !_isExecutableHabit(Map<String, dynamic>.from(row))) {
      throw const FocusCommandException('Habit target is unavailable.');
    }
  }

  FocusTargetOption _targetFromRow(
    Map<String, dynamic> row,
    FocusTargetKind kind,
  ) {
    final id = row['id'];
    final title = row['title'];
    if (id is! String || title is! String || title.trim().isEmpty) {
      throw const FocusCommandException('Focus target response is invalid.');
    }
    return FocusTargetOption(kind: kind, id: id, title: title.trim());
  }

  bool _isExecutableHabit(Map<String, dynamic> row) {
    if (row['active'] != true) {
      return false;
    }
    final metadata = row['metadata'];
    if (metadata is! Map) {
      return true;
    }
    final setupState = metadata['setup_state']?.toString();
    return setupState != 'candidate' && setupState != 'archived';
  }

  static String _timestamp(DateTime value) => value.toUtc().toIso8601String();
}
