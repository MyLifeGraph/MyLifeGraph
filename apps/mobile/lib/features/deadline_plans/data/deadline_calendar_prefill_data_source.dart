import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/app_user_resolver.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../domain/deadline_calendar_prefill.dart';
import '../domain/deadline_plan.dart';

abstract interface class DeadlineCalendarPrefillDataSource {
  Future<DeadlineCalendarPrefill> getEvent(String eventId);
}

class DeadlineCalendarPrefillSupabaseDataSource
    implements DeadlineCalendarPrefillDataSource {
  const DeadlineCalendarPrefillSupabaseDataSource(
    this._client, {
    Future<void> Function()? verifyAuthenticatedOwner,
  }) : _verifyAuthenticatedOwner = verifyAuthenticatedOwner;

  final SupabaseClient _client;
  final Future<void> Function()? _verifyAuthenticatedOwner;

  @override
  Future<DeadlineCalendarPrefill> getEvent(String eventId) async {
    if (!isDeadlinePlanUuid(eventId)) {
      throw const DeadlineCalendarPrefillException(
        'Calendar event identity is invalid.',
      );
    }
    final verifyOwner = _verifyAuthenticatedOwner;
    if (verifyOwner == null) {
      await AppUserResolver(_client).resolveUserId();
    } else {
      await verifyOwner();
    }
    final eventResponse = await _client
        .from(SupabaseTables.calendarEvents)
        .select(
          'id,connection_id,import_id,contract_version,origin,source_kind,'
          'source_fingerprint,title,event_kind,starts_at,starts_on',
        )
        .eq('id', eventId)
        .limit(2);
    final eventRows = _rows(eventResponse, 'calendar event');
    if (eventRows.isEmpty) return DeadlineCalendarPrefill.unavailable(eventId);
    if (eventRows.length != 1) {
      throw const DeadlineCalendarPrefillException(
        'Calendar event result is not unique.',
      );
    }
    final event = _parseEvent(eventRows.single, expectedId: eventId);

    final connectionResponse = await _client
        .from(SupabaseTables.calendarConnections)
        .select(
          'id,contract_version,origin,source_kind,status,last_import_id,'
          'imported_data_deleted_at',
        )
        .eq('id', event.connectionId)
        .limit(2);
    final connectionRows = _rows(connectionResponse, 'calendar connection');
    if (connectionRows.length > 1) {
      throw const DeadlineCalendarPrefillException(
        'Calendar connection result is not unique.',
      );
    }
    final isCurrent = connectionRows.length == 1 &&
        _connectionIsCurrent(
          connectionRows.single,
          expectedId: event.connectionId,
          expectedImportId: event.importId,
        );
    return isCurrent
        ? DeadlineCalendarPrefill.current(
            eventId: eventId,
            title: event.title,
            sourceFingerprint: event.sourceFingerprint,
            kind: event.kind,
            startsAt: event.startsAt,
            startsOn: event.startsOn,
          )
        : DeadlineCalendarPrefill.stale(
            eventId: eventId,
            title: event.title,
            sourceFingerprint: event.sourceFingerprint,
            kind: event.kind,
            startsAt: event.startsAt,
            startsOn: event.startsOn,
          );
  }

  List<Map<String, dynamic>> _rows(Object? value, String label) {
    if (value is! List) {
      throw DeadlineCalendarPrefillException('$label result is invalid.');
    }
    try {
      return value
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);
    } catch (_) {
      throw DeadlineCalendarPrefillException('$label result is invalid.');
    }
  }

  _CalendarEventProjection _parseEvent(
    Map<String, dynamic> row, {
    required String expectedId,
  }) {
    const expectedKeys = {
      'id',
      'connection_id',
      'import_id',
      'contract_version',
      'origin',
      'source_kind',
      'source_fingerprint',
      'title',
      'event_kind',
      'starts_at',
      'starts_on',
    };
    if (row.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(row.keys.toSet()).isNotEmpty ||
        row['id'] != expectedId ||
        row['contract_version'] != 'calendar-import-v1' ||
        row['origin'] != 'authenticated_backend' ||
        row['source_kind'] != 'ical_file') {
      throw const DeadlineCalendarPrefillException(
        'Calendar event projection is invalid.',
      );
    }
    final connectionId = _uuid(row['connection_id']);
    final importId = _uuid(row['import_id']);
    final title = row['title'];
    final fingerprint = row['source_fingerprint'];
    final kind = switch (row['event_kind']) {
      'timed' => DeadlineCalendarEventKind.timed,
      'all_day' => DeadlineCalendarEventKind.allDay,
      _ => null,
    };
    if (title is! String ||
        title.trim() != title ||
        title.isEmpty ||
        title.runes.length > 200 ||
        fingerprint is! String ||
        !_fingerprintPattern.hasMatch(fingerprint) ||
        kind == null) {
      throw const DeadlineCalendarPrefillException(
        'Calendar event basics are invalid.',
      );
    }
    DateTime? startsAt;
    String? startsOn;
    if (kind == DeadlineCalendarEventKind.timed) {
      startsAt = _awareDateTime(row['starts_at']);
      if (row['starts_on'] != null) {
        throw const DeadlineCalendarPrefillException(
          'Timed calendar event projection is invalid.',
        );
      }
    } else {
      startsOn = _date(row['starts_on']);
      if (row['starts_at'] != null) {
        throw const DeadlineCalendarPrefillException(
          'All-day calendar event projection is invalid.',
        );
      }
    }
    return _CalendarEventProjection(
      connectionId: connectionId,
      importId: importId,
      title: title,
      sourceFingerprint: fingerprint,
      kind: kind,
      startsAt: startsAt,
      startsOn: startsOn,
    );
  }

  bool _connectionIsCurrent(
    Map<String, dynamic> row, {
    required String expectedId,
    required String expectedImportId,
  }) {
    const expectedKeys = {
      'id',
      'contract_version',
      'origin',
      'source_kind',
      'status',
      'last_import_id',
      'imported_data_deleted_at',
    };
    if (row.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(row.keys.toSet()).isNotEmpty ||
        row['id'] != expectedId ||
        row['contract_version'] != 'calendar-import-v1' ||
        row['origin'] != 'authenticated_backend' ||
        row['source_kind'] != 'ical_file') {
      throw const DeadlineCalendarPrefillException(
        'Calendar connection projection is invalid.',
      );
    }
    final status = row['status'];
    if (status != 'connected' && status != 'disconnected') {
      throw const DeadlineCalendarPrefillException(
        'Calendar connection status is invalid.',
      );
    }
    final lastImportId = row['last_import_id'];
    if (lastImportId != null) _uuid(lastImportId);
    final deletedAt = row['imported_data_deleted_at'];
    if (deletedAt != null) _awareDateTime(deletedAt);
    return status == 'connected' &&
        deletedAt == null &&
        lastImportId == expectedImportId;
  }
}

class _CalendarEventProjection {
  const _CalendarEventProjection({
    required this.connectionId,
    required this.importId,
    required this.title,
    required this.sourceFingerprint,
    required this.kind,
    required this.startsAt,
    required this.startsOn,
  });

  final String connectionId;
  final String importId;
  final String title;
  final String sourceFingerprint;
  final DeadlineCalendarEventKind kind;
  final DateTime? startsAt;
  final String? startsOn;
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _fingerprintPattern = RegExp(r'^[0-9a-f]{64}$');
final _awarePattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$',
);
final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String _uuid(Object? value) {
  if (value is! String || !_uuidPattern.hasMatch(value)) {
    throw const DeadlineCalendarPrefillException(
      'Calendar projection identity is invalid.',
    );
  }
  return value;
}

DateTime _awareDateTime(Object? value) {
  if (value is! String || !_awarePattern.hasMatch(value)) {
    throw const DeadlineCalendarPrefillException(
      'Calendar projection instant is invalid.',
    );
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const DeadlineCalendarPrefillException(
      'Calendar projection instant is invalid.',
    );
  }
  return parsed;
}

String _date(Object? value) {
  if (value is! String || !_datePattern.hasMatch(value)) {
    throw const DeadlineCalendarPrefillException(
      'Calendar projection date is invalid.',
    );
  }
  final parsed = DateTime.tryParse(value);
  final normalized = parsed == null
      ? null
      : '${parsed.year.toString().padLeft(4, '0')}-'
          '${parsed.month.toString().padLeft(2, '0')}-'
          '${parsed.day.toString().padLeft(2, '0')}';
  if (normalized != value) {
    throw const DeadlineCalendarPrefillException(
      'Calendar projection date is invalid.',
    );
  }
  return value;
}
