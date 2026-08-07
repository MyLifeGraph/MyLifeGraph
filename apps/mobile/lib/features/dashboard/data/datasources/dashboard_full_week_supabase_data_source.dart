import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/app_user_resolver.dart';
import '../../../../core/supabase/supabase_tables.dart';
import '../../domain/entities/dashboard_full_week.dart';

const maxDashboardFullWeekCommitments = 200;
const maxDashboardFullWeekBlocks = 240;
const maxDashboardFullWeekFocusAssociations = 500;
const _dashboardFullWeekBatchSize = 100;

abstract interface class DashboardFullWeekDataSource {
  Future<List<DashboardSetupCommitmentFact>> getSetupCommitments();

  Future<Map<String, List<DashboardBlockFocusFact>>> getBlockFocusFacts(
    Iterable<String> requestedBlockIds,
  );
}

class DashboardFullWeekSupabaseDataSource
    implements DashboardFullWeekDataSource {
  const DashboardFullWeekSupabaseDataSource(
    this._client, {
    Future<String> Function()? resolveUserId,
  }) : _resolveUserId = resolveUserId;

  final SupabaseClient _client;
  final Future<String> Function()? _resolveUserId;

  @override
  Future<List<DashboardSetupCommitmentFact>> getSetupCommitments() async {
    final userId = await _userId();
    final response = await _client
        .from(SupabaseTables.scheduleItems)
        .select('id,title,weekday,starts_at,ends_at,location,metadata')
        .eq('user_id', userId)
        .eq('metadata->>managed_by', 'setup')
        .order('weekday', ascending: true)
        .order('starts_at', ascending: true)
        .order('id', ascending: true)
        .limit(maxDashboardFullWeekCommitments + 1);
    final rows = _rows(response, 'Setup commitments');
    if (rows.length > maxDashboardFullWeekCommitments) {
      throw const DashboardFullWeekDataException(
        'Setup commitment result exceeded its bounded size.',
      );
    }
    return rows.map(_commitmentFromRow).toList(growable: false);
  }

  @override
  Future<Map<String, List<DashboardBlockFocusFact>>> getBlockFocusFacts(
    Iterable<String> requestedBlockIds,
  ) async {
    final blockIds = requestedBlockIds.toSet().toList(growable: false)..sort();
    if (blockIds.isEmpty) return const {};
    if (blockIds.length > maxDashboardFullWeekBlocks ||
        blockIds.any((id) => id.trim().isEmpty)) {
      throw const DashboardFullWeekDataException(
        'Preparation block request exceeded its bounded size.',
      );
    }
    final userId = await _userId();
    final sourceRows = await _loadAssociationBatches(
      blockIds: blockIds,
      userId: userId,
    );
    if (sourceRows.isEmpty) {
      return Map<String, List<DashboardBlockFocusFact>>.unmodifiable({
        for (final id in blockIds) id: const <DashboardBlockFocusFact>[],
      });
    }

    final blockIdSet = blockIds.toSet();
    final blockBySession = <String, String>{};
    for (final row in sourceRows) {
      final sessionId = _requiredText(row['focus_session_id']);
      final blockId = _requiredText(row['deadline_plan_block_id']);
      if (row['source_kind'] != 'deadline_plan_block' ||
          !blockIdSet.contains(blockId) ||
          blockBySession.containsKey(sessionId)) {
        throw const DashboardFullWeekDataException(
          'Focus association result is invalid.',
        );
      }
      blockBySession[sessionId] = blockId;
    }

    final sessionIds = blockBySession.keys.toList(growable: false)..sort();
    final sessionRows = await _loadBatches(
      table: SupabaseTables.focusSessions,
      columns: 'id,status',
      userId: userId,
      identityColumn: 'id',
      identities: sessionIds,
      label: 'Focus sessions',
    );
    final statusBySession = <String, String>{};
    for (final row in sessionRows) {
      final id = _requiredText(row['id']);
      final status = _requiredText(row['status']);
      if (!blockBySession.containsKey(id) ||
          !const {'active', 'completed', 'abandoned'}.contains(status) ||
          statusBySession.putIfAbsent(id, () => status) != status) {
        throw const DashboardFullWeekDataException(
          'Focus session result is invalid.',
        );
      }
    }
    if (statusBySession.length != sessionIds.length) {
      throw const DashboardFullWeekDataException(
        'Focus session result is incomplete.',
      );
    }

    final reflectionRows = await _loadBatches(
      table: SupabaseTables.focusSessionReflections,
      columns:
          'focus_session_id,contract_version,focus_quality,useful_progress',
      userId: userId,
      identityColumn: 'focus_session_id',
      identities: sessionIds,
      label: 'Focus reflections',
    );
    final validReflectionSessions = <String>{};
    final seenReflectionSessions = <String>{};
    for (final row in reflectionRows) {
      final sessionId = _requiredText(row['focus_session_id']);
      if (!blockBySession.containsKey(sessionId) ||
          !seenReflectionSessions.add(sessionId)) {
        throw const DashboardFullWeekDataException(
          'Focus reflection result is invalid.',
        );
      }
      if (_isValidReflection(row)) validReflectionSessions.add(sessionId);
    }

    final result = <String, List<DashboardBlockFocusFact>>{
      for (final id in blockIds) id: <DashboardBlockFocusFact>[],
    };
    for (final sessionId in sessionIds) {
      result[blockBySession[sessionId]]!.add(
        DashboardBlockFocusFact(
          sessionId: sessionId,
          terminal: statusBySession[sessionId] != 'active',
          hasValidReflection: validReflectionSessions.contains(sessionId),
        ),
      );
    }
    return Map<String, List<DashboardBlockFocusFact>>.unmodifiable({
      for (final entry in result.entries)
        entry.key: List<DashboardBlockFocusFact>.unmodifiable(entry.value),
    });
  }

  Future<List<Map<String, dynamic>>> _loadAssociationBatches({
    required List<String> blockIds,
    required String userId,
  }) async {
    final result = <Map<String, dynamic>>[];
    var remaining = maxDashboardFullWeekFocusAssociations;
    for (var offset = 0;
        offset < blockIds.length;
        offset += _dashboardFullWeekBatchSize) {
      final candidateEnd = offset + _dashboardFullWeekBatchSize;
      final end =
          candidateEnd < blockIds.length ? candidateEnd : blockIds.length;
      final batch = blockIds.sublist(offset, end);
      final response = await _client
          .from(SupabaseTables.focusSessionScheduleSources)
          .select('focus_session_id,source_kind,deadline_plan_block_id')
          .eq('user_id', userId)
          .eq('source_kind', 'deadline_plan_block')
          .inFilter('deadline_plan_block_id', batch)
          .order('created_at', ascending: true)
          .order('focus_session_id', ascending: true)
          .limit(remaining + 1);
      final rows = _rows(response, 'Focus schedule sources');
      if (rows.length > remaining) {
        throw const DashboardFullWeekDataException(
          'Focus association result exceeded its bounded size.',
        );
      }
      result.addAll(rows);
      remaining -= rows.length;
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> _loadBatches({
    required String table,
    required String columns,
    required String userId,
    required String identityColumn,
    required List<String> identities,
    required String label,
  }) async {
    final result = <Map<String, dynamic>>[];
    for (var offset = 0;
        offset < identities.length;
        offset += _dashboardFullWeekBatchSize) {
      final candidateEnd = offset + _dashboardFullWeekBatchSize;
      final end =
          candidateEnd < identities.length ? candidateEnd : identities.length;
      final batch = identities.sublist(offset, end);
      final response = await _client
          .from(table)
          .select(columns)
          .eq('user_id', userId)
          .inFilter(identityColumn, batch)
          .order(identityColumn, ascending: true)
          .limit(batch.length + 1);
      final rows = _rows(response, label);
      if (rows.length > batch.length) {
        throw DashboardFullWeekDataException(
          '$label exceeded its bounded size.',
        );
      }
      result.addAll(rows);
    }
    return result;
  }

  Future<String> _userId() async {
    final resolver = _resolveUserId;
    return resolver == null
        ? AppUserResolver(_client).resolveUserId()
        : resolver();
  }

  DashboardSetupCommitmentFact _commitmentFromRow(
    Map<String, dynamic> row,
  ) {
    final id = _requiredText(row['id']);
    final title = _requiredText(row['title']);
    final weekday = (row['weekday'] as num?)?.toInt();
    final startsAt = _requiredText(row['starts_at']);
    final endsAt = _requiredText(row['ends_at']);
    final metadataValue = row['metadata'];
    if (metadataValue is! Map) {
      throw const DashboardFullWeekDataException(
        'Setup commitment result is invalid.',
      );
    }
    final metadata = Map<String, dynamic>.from(metadataValue);
    if (metadata['managed_by'] != 'setup') {
      throw const DashboardFullWeekDataException(
        'Setup commitment result is invalid.',
      );
    }
    final validFrom = _optionalDate(metadata['valid_from']);
    final validUntil = _optionalDate(metadata['valid_until']);
    final sortMinutes = _timeMinutes(startsAt);
    if (weekday == null ||
        weekday < DateTime.monday ||
        weekday > DateTime.sunday ||
        sortMinutes == null ||
        _timeMinutes(endsAt) == null ||
        (validFrom != null &&
            validUntil != null &&
            validUntil.isBefore(validFrom))) {
      throw const DashboardFullWeekDataException(
        'Setup commitment result is invalid.',
      );
    }
    return DashboardSetupCommitmentFact(
      id: id,
      title: title,
      weekday: weekday,
      startsAt: startsAt.substring(0, 5),
      endsAt: endsAt.substring(0, 5),
      sortMinutes: sortMinutes,
      location: _optionalText(row['location']),
      validFrom: validFrom,
      validUntil: validUntil,
    );
  }

  bool _isValidReflection(Map<String, dynamic> row) {
    final quality = row['focus_quality'];
    final progress = row['useful_progress'];
    return row['contract_version'] == 'focus-reflection-v1' &&
        quality is int &&
        quality >= 1 &&
        quality <= 5 &&
        progress is int &&
        progress >= 1 &&
        progress <= 5;
  }

  List<Map<String, dynamic>> _rows(Object? value, String label) {
    if (value is! List) {
      throw DashboardFullWeekDataException('$label are invalid.');
    }
    try {
      return value
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);
    } catch (_) {
      throw DashboardFullWeekDataException('$label are invalid.');
    }
  }
}

class DashboardFullWeekDataException implements Exception {
  const DashboardFullWeekDataException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _requiredText(Object? value) {
  if (value is! String || value.trim().isEmpty || value.trim() != value) {
    throw const DashboardFullWeekDataException(
      'Full-week text value is invalid.',
    );
  }
  return value;
}

String? _optionalText(Object? value) {
  if (value == null) return null;
  return _requiredText(value);
}

int? _timeMinutes(String value) {
  final match = RegExp(r'^(\d{2}):(\d{2})').firstMatch(value);
  final hour = int.tryParse(match?.group(1) ?? '');
  final minute = int.tryParse(match?.group(2) ?? '');
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

DateTime? _optionalDate(Object? value) {
  if (value == null) return null;
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const DashboardFullWeekDataException(
      'Setup commitment validity is invalid.',
    );
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || _dateKey(parsed) != value) {
    throw const DashboardFullWeekDataException(
      'Setup commitment validity is invalid.',
    );
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
