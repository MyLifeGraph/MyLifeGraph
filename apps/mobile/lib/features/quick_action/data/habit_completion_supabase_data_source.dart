import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/app_user_resolver.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../core/utils/client_uuid.dart';
import '../domain/habit_v1.dart';

typedef HabitNowProvider = DateTime Function();

class HabitCompletionSupabaseDataSource {
  HabitCompletionSupabaseDataSource(
    this._client, {
    HabitNowProvider? nowProvider,
  }) : _nowProvider = nowProvider ?? DateTime.now;

  final SupabaseClient _client;
  final HabitNowProvider _nowProvider;

  Future<List<HabitV1>> fetchActiveHabits() async {
    final today = habitDateOnly(_nowProvider());
    final habits = await fetchHabits(activeOnly: true);
    return habits.where((habit) => habit.isRelevantOn(today)).toList();
  }

  Future<HabitV1> fetchOwnedHabit(String habitId) =>
      _requireOwnedHabit(habitId);

  Future<List<HabitV1>> fetchHabits({
    bool activeOnly = false,
    bool excludeSetupManaged = false,
  }) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final today = habitDateOnly(_nowProvider());
    final historyStart = habitAddCalendarDays(today, -370);
    final habitRows = await _fetchHabitRows(
      userId: userId,
      activeOnly: activeOnly,
    );
    final logRows = await _fetchHabitLogRows(
      userId: userId,
      historyStart: historyStart,
      today: today,
    );

    final logsByHabit = <String, List<HabitLogEntry>>{};
    for (final row in logRows) {
      final habitId = row['habit_id']?.toString();
      final entryDate = DateTime.tryParse(row['entry_date']?.toString() ?? '');
      final explicitOutcome = HabitOutcome.fromCode(row['status']);
      final legacyValue = row['value'];
      final outcome = explicitOutcome ??
          (legacyValue is num && legacyValue > 0
              ? HabitOutcome.completed
              : null);
      if (habitId == null || entryDate == null || outcome == null) {
        continue;
      }
      logsByHabit.putIfAbsent(habitId, () => []).add(
            HabitLogEntry(entryDate: entryDate, outcome: outcome),
          );
    }

    return habitRows.where((row) {
      return isHabitVisibleForFetch(
        row['metadata'],
        excludeSetupManaged: excludeSetupManaged,
      );
    }).map((row) {
      final id = row['id']?.toString() ?? '';
      return _habitFromRow(row, logs: logsByHabit[id] ?? const []);
    }).where((habit) {
      return !activeOnly || habit.lifecycle == HabitLifecycle.active;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchHabitRows({
    required String userId,
    required bool activeOnly,
  }) async {
    const pageSize = 500;
    final result = <Map<String, dynamic>>[];
    for (var offset = 0;; offset += pageSize) {
      var query = _client
          .from(SupabaseTables.habits)
          .select(
            'id,title,description,frequency,target,active,metadata,created_at,'
            'updated_at',
          )
          .eq('user_id', userId);
      if (activeOnly) {
        query = query.eq('active', true);
      }
      final rows = await query
          .order('updated_at', ascending: false)
          .order('id', ascending: true)
          .range(offset, offset + pageSize - 1);
      final page = List<Map<String, dynamic>>.from(rows as List);
      result.addAll(page);
      if (page.length < pageSize) {
        return result;
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchHabitLogRows({
    required String userId,
    required DateTime historyStart,
    required DateTime today,
  }) async {
    const pageSize = 1000;
    final result = <Map<String, dynamic>>[];
    for (var offset = 0;; offset += pageSize) {
      final rows = await _client
          .from(SupabaseTables.habitLogs)
          .select('habit_id,entry_date,value,status')
          .eq('user_id', userId)
          .gte('entry_date', habitDateKey(historyStart))
          .lte('entry_date', habitDateKey(today))
          .order('entry_date', ascending: false)
          .order('habit_id', ascending: true)
          .range(offset, offset + pageSize - 1);
      final page = List<Map<String, dynamic>>.from(rows as List);
      result.addAll(page);
      if (page.length < pageSize) {
        return result;
      }
    }
  }

  Future<HabitV1> createHabit({
    required String habitId,
    required String title,
    String? description,
    required HabitCadence cadence,
  }) async {
    if (!isClientUuid(habitId)) {
      throw const HabitCommandException('Habit request identity is invalid.');
    }
    final normalizedTitle = _validateTitle(title);
    final normalizedDescription = _validateDescription(description);
    final userId = await AppUserResolver(_client).resolveUserId();
    final nowValue = _nowProvider();
    final now = _timestamp(nowValue);
    final metadata = <String, Object>{
      'source': 'flutter-habit-management-v1',
      ...cadence.metadataProjection,
      'lifecycle': HabitLifecycle.active.code,
      'started_on': habitDateKey(nowValue),
    };
    final row = await _client
        .from(SupabaseTables.habits)
        .upsert(
          {
            'id': habitId,
            'user_id': userId,
            'title': normalizedTitle,
            'description': normalizedDescription,
            'frequency': cadence.compatibilityFrequency,
            'target': cadence.compatibilityTarget,
            'active': true,
            'metadata': metadata,
            'updated_at': now,
          },
          onConflict: 'id',
        )
        .select()
        .single();
    return _habitFromRow(Map<String, dynamic>.from(row));
  }

  Future<HabitV1> updateHabit({
    required HabitV1 habit,
    required String title,
    String? description,
    required HabitCadence cadence,
  }) async {
    if (habit.isSetupManaged) {
      throw const HabitCommandException(
        'Setup-owned habits are edited in Settings Setup.',
      );
    }
    final metadata = <String, dynamic>{
      ...habit.metadata,
      ...cadence.metadataProjection,
      'source': habit.metadata['source'] ?? 'flutter-habit-management-v1',
      'lifecycle': habit.lifecycle.code,
    };
    return _updateOwnedHabit(
      habit.id,
      {
        'title': _validateTitle(title),
        'description': _validateDescription(description),
        'frequency': cadence.compatibilityFrequency,
        'target': cadence.compatibilityTarget,
        'metadata': metadata,
      },
      expectedUpdatedAt: habit.updatedAt,
    );
  }

  Future<HabitV1> setHabitLifecycle({
    required HabitV1 habit,
    required HabitLifecycle lifecycle,
  }) async {
    if (habit.isSetupManaged) {
      throw const HabitCommandException(
        'Setup-owned habits are managed in Settings Setup.',
      );
    }
    final metadata = <String, dynamic>{
      ...habit.metadata,
      'lifecycle': lifecycle.code,
    };
    return _updateOwnedHabit(
      habit.id,
      {
        'active': lifecycle == HabitLifecycle.active,
        'metadata': metadata,
      },
      expectedUpdatedAt: habit.updatedAt,
    );
  }

  Future<void> setTodayOutcome({
    required String habitId,
    required HabitOutcome outcome,
    required DateTime targetDate,
    String? notes,
  }) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final habit = await _requireOwnedHabit(habitId);
    final now = _nowProvider();
    final entryDate = habitDateOnly(targetDate);
    if (!habit.isActive || !habit.isRelevantOn(entryDate)) {
      throw const HabitCommandException(
        'This habit is not available for that date.',
      );
    }
    final normalizedNotes = _validateNotes(notes);
    final entryDateKey = habitDateKey(entryDate);
    final value = outcome == HabitOutcome.completed ? 1 : 0;
    try {
      await _client.from(SupabaseTables.habitLogs).upsert(
        {
          'user_id': userId,
          'habit_id': habitId,
          'entry_date': entryDateKey,
          'status': outcome.code,
          'value': value,
          'notes': normalizedNotes,
          'updated_at': _timestamp(now),
        },
        onConflict: 'habit_id,entry_date',
      );
    } catch (_) {
      final committed = await _habitOutcomeMatches(
        userId: userId,
        habitId: habitId,
        entryDate: entryDateKey,
        outcome: outcome,
        value: value,
        notes: normalizedNotes,
      );
      if (!committed) {
        rethrow;
      }
    }
  }

  Future<void> undoTodayOutcome({
    required String habitId,
    required DateTime targetDate,
  }) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final habit = await _requireOwnedHabit(habitId);
    if (!habit.isActive) {
      throw const HabitCommandException('This habit is not active.');
    }
    final entryDate = habitDateKey(habitDateOnly(targetDate));
    try {
      await _client
          .from(SupabaseTables.habitLogs)
          .delete()
          .eq('habit_id', habitId)
          .eq('user_id', userId)
          .eq('entry_date', entryDate);
    } catch (_) {
      if (await _habitOutcomeExists(
        userId: userId,
        habitId: habitId,
        entryDate: entryDate,
      )) {
        rethrow;
      }
    }
  }

  Future<HabitV1> _requireOwnedHabit(String habitId) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final row = await _client
        .from(SupabaseTables.habits)
        .select(
          'id,title,description,frequency,target,active,metadata,created_at,'
          'updated_at',
        )
        .eq('id', habitId)
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) {
      throw const HabitCommandException('Habit is unavailable.');
    }
    final habit = _habitFromRow(Map<String, dynamic>.from(row));
    if (!isHabitVisibleForFetch(
      habit.metadata,
      excludeSetupManaged: false,
    )) {
      throw const HabitCommandException('Habit is unavailable.');
    }
    return habit;
  }

  Future<HabitV1> _updateOwnedHabit(
    String habitId,
    Map<String, dynamic> values, {
    required DateTime expectedUpdatedAt,
  }) async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final now = _nowProvider();
    final nextUpdatedAt = now.isAfter(expectedUpdatedAt)
        ? now
        : expectedUpdatedAt.add(const Duration(microseconds: 1));
    List<Map<String, dynamic>> typedRows;
    try {
      final rows = await _client
          .from(SupabaseTables.habits)
          .update({
            ...values,
            'updated_at': _timestamp(nextUpdatedAt),
          })
          .eq('id', habitId)
          .eq('user_id', userId)
          .eq('updated_at', _timestamp(expectedUpdatedAt))
          .select();
      typedRows = List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      final reconciled = await _readMatchingHabitMutation(
        userId: userId,
        habitId: habitId,
        values: values,
        mutationAt: nextUpdatedAt,
      );
      if (reconciled == null) {
        rethrow;
      }
      return _habitFromRow(reconciled);
    }
    if (typedRows.length != 1) {
      final reconciled = await _readMatchingHabitMutation(
        userId: userId,
        habitId: habitId,
        values: values,
        mutationAt: nextUpdatedAt,
      );
      if (reconciled != null) {
        return _habitFromRow(reconciled);
      }
      throw const HabitCommandException(
        'Habit changed elsewhere. Reload before retrying.',
      );
    }
    return _habitFromRow(typedRows.single);
  }

  Future<Map<String, dynamic>?> _readMatchingHabitMutation({
    required String userId,
    required String habitId,
    required Map<String, dynamic> values,
    required DateTime mutationAt,
  }) async {
    try {
      final row = await _client
          .from(SupabaseTables.habits)
          .select()
          .eq('id', habitId)
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) {
        return null;
      }
      final typedRow = Map<String, dynamic>.from(row);
      final updatedAt = DateTime.tryParse(
        typedRow['updated_at']?.toString() ?? '',
      );
      if (updatedAt == null || !updatedAt.isAtSameMomentAs(mutationAt)) {
        return null;
      }
      for (final entry in values.entries) {
        if (!_deepEquals(typedRow[entry.key], entry.value)) {
          return null;
        }
      }
      return typedRow;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _habitOutcomeMatches({
    required String userId,
    required String habitId,
    required String entryDate,
    required HabitOutcome outcome,
    required int value,
    required String? notes,
  }) async {
    try {
      final row = await _client
          .from(SupabaseTables.habitLogs)
          .select('status,value,notes')
          .eq('user_id', userId)
          .eq('habit_id', habitId)
          .eq('entry_date', entryDate)
          .maybeSingle();
      return row != null &&
          row['status'] == outcome.code &&
          row['value'] == value &&
          _optionalString(row['notes']) == notes;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _habitOutcomeExists({
    required String userId,
    required String habitId,
    required String entryDate,
  }) async {
    try {
      final row = await _client
          .from(SupabaseTables.habitLogs)
          .select('id')
          .eq('user_id', userId)
          .eq('habit_id', habitId)
          .eq('entry_date', entryDate)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return true;
    }
  }

  HabitV1 _habitFromRow(
    Map<String, dynamic> row, {
    List<HabitLogEntry> logs = const [],
  }) {
    final metadata = row['metadata'] is Map
        ? Map<String, dynamic>.from(row['metadata'] as Map)
        : <String, dynamic>{};
    final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(row['updated_at']?.toString() ?? '');
    if (createdAt == null || updatedAt == null) {
      throw const HabitContractException('Habit timestamps are invalid.');
    }
    final active = row['active'] as bool? ?? true;
    return HabitV1(
      id: row['id']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
      description: _optionalString(row['description']),
      cadence: HabitCadence.fromPersistence(
        frequency: row['frequency'],
        target: row['target'],
        metadata: metadata,
      ),
      lifecycle: habitLifecycleFromPersistence(
        active: active,
        metadata: metadata,
      ),
      createdAt: createdAt,
      updatedAt: updatedAt,
      isSetupManaged: metadata['managed_by']?.toString() == 'setup',
      metadata: metadata,
      logs: logs,
    );
  }

  String _validateTitle(String value) {
    final title = value.trim();
    if (title.isEmpty || title.length > 160) {
      throw const HabitCommandException(
        'Habit title must contain 1 to 160 characters.',
      );
    }
    return title;
  }

  String? _validateDescription(String? value) {
    final description = _optionalString(value);
    if (description != null && description.length > 2000) {
      throw const HabitCommandException(
        'Habit description must be at most 2000 characters.',
      );
    }
    return description;
  }

  String? _validateNotes(String? value) {
    final notes = _optionalString(value);
    if (notes != null && notes.length > 500) {
      throw const HabitCommandException(
        'Habit outcome note must be at most 500 characters.',
      );
    }
    return notes;
  }

  String? _optionalString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String _timestamp(DateTime value) => value.toUtc().toIso8601String();

  static bool _deepEquals(Object? left, Object? right) {
    if (left is Map && right is Map) {
      if (left.length != right.length) {
        return false;
      }
      for (final entry in right.entries) {
        if (!left.containsKey(entry.key) ||
            !_deepEquals(left[entry.key], entry.value)) {
          return false;
        }
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) {
        return false;
      }
      for (var index = 0; index < left.length; index += 1) {
        if (!_deepEquals(left[index], right[index])) {
          return false;
        }
      }
      return true;
    }
    return left == right;
  }
}

bool isHabitVisibleForFetch(
  Object? metadata, {
  required bool excludeSetupManaged,
}) {
  if (metadata is! Map) {
    return true;
  }
  final setupState =
      metadata['setup_state']?.toString() ?? metadata['status']?.toString();
  if (setupState == 'candidate' || setupState == 'archived') {
    return false;
  }
  return !excludeSetupManaged || metadata['managed_by']?.toString() != 'setup';
}

class HabitCommandException implements Exception {
  const HabitCommandException(this.message);

  final String message;

  @override
  String toString() => message;
}
