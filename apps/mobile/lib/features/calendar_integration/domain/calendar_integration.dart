const calendarImportContractVersion = 'calendar-import-v1';
const calendarImportConsentVersion = 'calendar-import-consent-v1';
const calendarImportMaxFileBytes = 512 * 1024;

enum CalendarIntegrationOrigin {
  localDemo,
  authenticatedBackend;

  static CalendarIntegrationOrigin? fromCode(Object? value) => switch (value) {
        'authenticated_backend' => authenticatedBackend,
        _ => null,
      };
}

enum CalendarConnectionStatus {
  connected('connected'),
  disconnected('disconnected');

  const CalendarConnectionStatus(this.code);
  final String code;

  static CalendarConnectionStatus? fromCode(Object? value) => switch (value) {
        'connected' => connected,
        'disconnected' => disconnected,
        _ => null,
      };
}

class CalendarIntegrationFeed {
  CalendarIntegrationFeed._({required this.origin, required this.connection});

  factory CalendarIntegrationFeed.localDemo() => CalendarIntegrationFeed._(
        origin: CalendarIntegrationOrigin.localDemo,
        connection: null,
      );

  factory CalendarIntegrationFeed.authenticated(
    CalendarConnection? connection,
  ) =>
      CalendarIntegrationFeed._(
        origin: CalendarIntegrationOrigin.authenticatedBackend,
        connection: connection,
      );

  factory CalendarIntegrationFeed.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'contract_version', 'origin', 'connection'},
      'calendar integration response',
    );
    _requireContract(json['contract_version']);
    final origin = CalendarIntegrationOrigin.fromCode(json['origin']);
    final rawConnection = json['connection'];
    if (origin != CalendarIntegrationOrigin.authenticatedBackend ||
        rawConnection != null && rawConnection is! Map) {
      throw const CalendarIntegrationContractException(
        'Calendar integration response fields are invalid.',
      );
    }
    return CalendarIntegrationFeed._(
      origin: origin!,
      connection: rawConnection == null
          ? null
          : CalendarConnection.fromJson(
              Map<String, dynamic>.from(rawConnection),
            ),
    );
  }

  final CalendarIntegrationOrigin origin;
  final CalendarConnection? connection;
}

class CalendarImportResponse {
  CalendarImportResponse({required this.connection, required this.import});

  factory CalendarImportResponse.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'contract_version', 'origin', 'connection', 'import'},
      'calendar import response',
    );
    _requireContract(json['contract_version']);
    if (CalendarIntegrationOrigin.fromCode(json['origin']) !=
            CalendarIntegrationOrigin.authenticatedBackend ||
        json['connection'] is! Map ||
        json['import'] is! Map) {
      throw const CalendarIntegrationContractException(
        'Calendar import response fields are invalid.',
      );
    }
    final connection = CalendarConnection.fromJson(
      Map<String, dynamic>.from(json['connection'] as Map),
    );
    final imported = CalendarImportSummary.fromJson(
      Map<String, dynamic>.from(json['import'] as Map),
    );
    if (connection.lastImport == null ||
        !connection.lastImport!.hasSameContent(imported)) {
      throw const CalendarIntegrationContractException(
        'Calendar import response does not match the connection projection.',
      );
    }
    return CalendarImportResponse(connection: connection, import: imported);
  }

  final CalendarConnection connection;
  final CalendarImportSummary import;
}

class CalendarConsent {
  const CalendarConsent();

  factory CalendarConsent.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'consent_version',
        'read_calendar_events',
        'store_event_basics',
        'provider_writes',
        'llm_processing',
      },
      'calendar consent',
    );
    if (json['consent_version'] != calendarImportConsentVersion ||
        json['read_calendar_events'] != true ||
        json['store_event_basics'] != true ||
        json['provider_writes'] != false ||
        json['llm_processing'] != false) {
      throw const CalendarIntegrationContractException(
        'Calendar consent is invalid.',
      );
    }
    return const CalendarConsent();
  }

  Map<String, dynamic> toJson() => const {
        'consent_version': calendarImportConsentVersion,
        'read_calendar_events': true,
        'store_event_basics': true,
        'provider_writes': false,
        'llm_processing': false,
      };
}

class CalendarConnection {
  CalendarConnection({
    required this.id,
    required this.sourceLabel,
    required this.status,
    required this.consent,
    required this.consentedAt,
    required this.connectedAt,
    required this.disconnectedAt,
    required this.importedDataDeletedAt,
    required this.lastImport,
  });

  factory CalendarConnection.fromJson(Map<String, dynamic> json) {
    _expectRequiredAndOptionalKeys(
      json,
      required: const {
        'id',
        'contract_version',
        'origin',
        'source_kind',
        'source_label',
        'status',
        'consent',
        'consented_at',
        'connected_at',
        'provider_writes',
        'llm_processed',
      },
      optional: const {
        'disconnected_at',
        'imported_data_deleted_at',
        'last_import',
      },
      model: 'calendar connection',
    );
    _requireContract(json['contract_version']);
    final status = CalendarConnectionStatus.fromCode(json['status']);
    if (CalendarIntegrationOrigin.fromCode(json['origin']) !=
            CalendarIntegrationOrigin.authenticatedBackend ||
        json['source_kind'] != 'ical_file' ||
        status == null ||
        json['consent'] is! Map ||
        json['provider_writes'] != false ||
        json['llm_processed'] != false) {
      throw const CalendarIntegrationContractException(
        'Calendar connection fields are invalid.',
      );
    }
    final disconnectedAt = _optionalAwareDateTime(
      json,
      'disconnected_at',
    );
    final deletedAt = _optionalAwareDateTime(
      json,
      'imported_data_deleted_at',
    );
    final rawLastImport = json['last_import'];
    if (status == CalendarConnectionStatus.connected &&
            disconnectedAt != null ||
        status == CalendarConnectionStatus.disconnected &&
            disconnectedAt == null ||
        deletedAt != null && status != CalendarConnectionStatus.disconnected ||
        rawLastImport != null && rawLastImport is! Map ||
        deletedAt != null && rawLastImport != null) {
      throw const CalendarIntegrationContractException(
        'Calendar connection lifecycle is invalid.',
      );
    }
    return CalendarConnection(
      id: _requiredUuid(json['id'], 'connection.id'),
      sourceLabel: _requiredString(
        json['source_label'],
        'connection.source_label',
        maxLength: 80,
      ),
      status: status,
      consent: CalendarConsent.fromJson(
        Map<String, dynamic>.from(json['consent'] as Map),
      ),
      consentedAt: _requiredAwareDateTime(
        json['consented_at'],
        'connection.consented_at',
      ),
      connectedAt: _requiredAwareDateTime(
        json['connected_at'],
        'connection.connected_at',
      ),
      disconnectedAt: disconnectedAt,
      importedDataDeletedAt: deletedAt,
      lastImport: rawLastImport == null
          ? null
          : CalendarImportSummary.fromJson(
              Map<String, dynamic>.from(rawLastImport as Map),
            ),
    );
  }

  final String id;
  final String sourceLabel;
  final CalendarConnectionStatus status;
  final CalendarConsent consent;
  final DateTime consentedAt;
  final DateTime connectedAt;
  final DateTime? disconnectedAt;
  final DateTime? importedDataDeletedAt;
  final CalendarImportSummary? lastImport;

  bool get isConnected => status == CalendarConnectionStatus.connected;
  bool get hasRetainedImportedData => lastImport != null;
  bool get importedDataDeleted => importedDataDeletedAt != null;
}

class CalendarImportSummary {
  CalendarImportSummary({
    required this.id,
    required this.importedAt,
    required this.window,
    required this.counts,
    required this.sourceFingerprint,
  });

  factory CalendarImportSummary.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'id', 'imported_at', 'window', 'counts', 'source_fingerprint'},
      'calendar import summary',
    );
    if (json['window'] is! Map || json['counts'] is! Map) {
      throw const CalendarIntegrationContractException(
        'Calendar import summary fields are invalid.',
      );
    }
    return CalendarImportSummary(
      id: _requiredUuid(json['id'], 'import.id'),
      importedAt: _requiredAwareDateTime(
        json['imported_at'],
        'import.imported_at',
      ),
      window: CalendarImportWindow.fromJson(
        Map<String, dynamic>.from(json['window'] as Map),
      ),
      counts: CalendarImportCounts.fromJson(
        Map<String, dynamic>.from(json['counts'] as Map),
      ),
      sourceFingerprint: _requiredFingerprint(
        json['source_fingerprint'],
        'import.source_fingerprint',
      ),
    );
  }

  final String id;
  final DateTime importedAt;
  final CalendarImportWindow window;
  final CalendarImportCounts counts;
  final String sourceFingerprint;

  bool hasSameContent(CalendarImportSummary other) =>
      id == other.id &&
      importedAt == other.importedAt &&
      window.hasSameContent(other.window) &&
      counts.hasSameContent(other.counts) &&
      sourceFingerprint == other.sourceFingerprint;
}

class CalendarImportWindow {
  CalendarImportWindow({
    required this.startsOn,
    required this.endsBefore,
    required this.timezone,
  }) {
    if (_dateValue(endsBefore).difference(_dateValue(startsOn)).inDays != 105) {
      throw const CalendarIntegrationContractException(
        'Calendar import window must span exactly 105 dates.',
      );
    }
  }

  factory CalendarImportWindow.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'starts_on', 'ends_before', 'timezone'},
      'calendar import window',
    );
    return CalendarImportWindow(
      startsOn: _requiredDate(json['starts_on'], 'window.starts_on'),
      endsBefore: _requiredDate(json['ends_before'], 'window.ends_before'),
      timezone: _requiredString(
        json['timezone'],
        'window.timezone',
        maxLength: 100,
      ),
    );
  }

  final String startsOn;
  final String endsBefore;
  final String timezone;

  bool hasSameContent(CalendarImportWindow other) =>
      startsOn == other.startsOn &&
      endsBefore == other.endsBefore &&
      timezone == other.timezone;
}

class CalendarImportCounts {
  CalendarImportCounts({
    required this.accepted,
    required this.cancelled,
    required this.outOfWindow,
    required this.unsupportedRecurring,
    required this.invalid,
  }) {
    if (accepted > 500 ||
        accepted + cancelled + outOfWindow + unsupportedRecurring + invalid >
            2000) {
      throw const CalendarIntegrationContractException(
        'Calendar import counts exceed the V1 bounds.',
      );
    }
  }

  factory CalendarImportCounts.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'accepted',
        'cancelled',
        'out_of_window',
        'unsupported_recurring',
        'invalid',
      },
      'calendar import counts',
    );
    return CalendarImportCounts(
      accepted: _requiredBoundedInt(json['accepted'], 'counts.accepted'),
      cancelled: _requiredBoundedInt(json['cancelled'], 'counts.cancelled'),
      outOfWindow:
          _requiredBoundedInt(json['out_of_window'], 'counts.out_of_window'),
      unsupportedRecurring: _requiredBoundedInt(
        json['unsupported_recurring'],
        'counts.unsupported_recurring',
      ),
      invalid: _requiredBoundedInt(json['invalid'], 'counts.invalid'),
    );
  }

  final int accepted;
  final int cancelled;
  final int outOfWindow;
  final int unsupportedRecurring;
  final int invalid;

  bool hasSameContent(CalendarImportCounts other) =>
      accepted == other.accepted &&
      cancelled == other.cancelled &&
      outOfWindow == other.outOfWindow &&
      unsupportedRecurring == other.unsupportedRecurring &&
      invalid == other.invalid;
}

enum CalendarEventKind { timed, allDay }

class CalendarEventPage {
  CalendarEventPage({
    required this.connectionId,
    required this.importId,
    required List<CalendarImportedEvent> events,
    required this.nextCursor,
  }) : events = List.unmodifiable(events) {
    if (events.length > 50 ||
        events.map((event) => event.id).toSet().length != events.length ||
        events.isNotEmpty && importId == null ||
        nextCursor != null && importId == null) {
      throw const CalendarIntegrationContractException(
        'Calendar event page is invalid.',
      );
    }
  }

  factory CalendarEventPage.fromJson(Map<String, dynamic> json) {
    _expectRequiredAndOptionalKeys(
      json,
      required: const {
        'contract_version',
        'origin',
        'connection_id',
        'events',
      },
      optional: const {'import_id', 'next_cursor'},
      model: 'calendar event response',
    );
    _requireContract(json['contract_version']);
    if (CalendarIntegrationOrigin.fromCode(json['origin']) !=
            CalendarIntegrationOrigin.authenticatedBackend ||
        json['events'] is! List) {
      throw const CalendarIntegrationContractException(
        'Calendar event response fields are invalid.',
      );
    }
    final events = (json['events'] as List).map((value) {
      if (value is! Map) {
        throw const CalendarIntegrationContractException(
          'Calendar event item is invalid.',
        );
      }
      return CalendarImportedEvent.fromJson(
        Map<String, dynamic>.from(value),
      );
    }).toList(growable: false);
    return CalendarEventPage(
      connectionId: _requiredUuid(
        json['connection_id'],
        'events.connection_id',
      ),
      importId: _optionalUuid(json, 'import_id'),
      events: events,
      nextCursor: _optionalString(
        json,
        'next_cursor',
        maxLength: 512,
      ),
    );
  }

  final String connectionId;
  final String? importId;
  final List<CalendarImportedEvent> events;
  final String? nextCursor;
}

class CalendarImportedEvent {
  CalendarImportedEvent._({
    required this.id,
    required this.title,
    required this.location,
    required this.kind,
    required this.busyStatus,
    required this.eventStatus,
    required this.eventTimezone,
    required this.timezoneSource,
    required this.importedAt,
    required this.lastSeenAt,
    required this.sourceFingerprint,
    required this.provenance,
    required this.startsAt,
    required this.endsAt,
    required this.localStartsAt,
    required this.localEndsAt,
    required this.startsOn,
    required this.endsOn,
  });

  factory CalendarImportedEvent.fromJson(Map<String, dynamic> json) {
    final kind = switch (json['event_kind']) {
      'timed' => CalendarEventKind.timed,
      'all_day' => CalendarEventKind.allDay,
      _ => null,
    };
    final variantKeys = kind == CalendarEventKind.timed
        ? const {'starts_at', 'ends_at', 'local_starts_at', 'local_ends_at'}
        : const {'starts_on', 'ends_on'};
    _expectRequiredAndOptionalKeys(
      json,
      required: {
        'id',
        'title',
        'event_kind',
        'busy_status',
        'event_status',
        'event_timezone',
        'timezone_source',
        'imported_at',
        'last_seen_at',
        'source_fingerprint',
        'provenance',
        ...variantKeys,
      },
      optional: const {'location'},
      model: 'calendar event',
    );
    if (kind == null ||
        !const {'busy', 'free'}.contains(json['busy_status']) ||
        !const {'confirmed', 'tentative'}.contains(json['event_status']) ||
        !const {'utc', 'event', 'profile'}.contains(json['timezone_source']) ||
        json['provenance'] is! Map) {
      throw const CalendarIntegrationContractException(
        'Calendar event fields are invalid.',
      );
    }

    final startsAt = kind == CalendarEventKind.timed
        ? _requiredAwareDateTimeText(json['starts_at'], 'event.starts_at')
        : null;
    final endsAt = kind == CalendarEventKind.timed
        ? _requiredAwareDateTimeText(json['ends_at'], 'event.ends_at')
        : null;
    final localStartsAt = kind == CalendarEventKind.timed
        ? _requiredLocalDateTime(
            json['local_starts_at'],
            'event.local_starts_at',
          )
        : null;
    final localEndsAt = kind == CalendarEventKind.timed
        ? _requiredLocalDateTime(
            json['local_ends_at'],
            'event.local_ends_at',
          )
        : null;
    final startsOn = kind == CalendarEventKind.allDay
        ? _requiredDate(json['starts_on'], 'event.starts_on')
        : null;
    final endsOn = kind == CalendarEventKind.allDay
        ? _requiredDate(json['ends_on'], 'event.ends_on')
        : null;
    if (kind == CalendarEventKind.timed &&
            !DateTime.parse(endsAt!).isAfter(DateTime.parse(startsAt!)) ||
        kind == CalendarEventKind.allDay &&
            _dateValue(endsOn!).compareTo(_dateValue(startsOn!)) <= 0) {
      throw const CalendarIntegrationContractException(
        'Calendar event interval is invalid.',
      );
    }
    final provenance = CalendarEventProvenance.fromJson(
      Map<String, dynamic>.from(json['provenance'] as Map),
    );
    final importedAt = _requiredAwareDateTime(
      json['imported_at'],
      'event.imported_at',
    );
    final lastSeenAt = _requiredAwareDateTime(
      json['last_seen_at'],
      'event.last_seen_at',
    );
    if (lastSeenAt.isBefore(importedAt)) {
      throw const CalendarIntegrationContractException(
        'Calendar event last seen time is invalid.',
      );
    }
    return CalendarImportedEvent._(
      id: _requiredUuid(json['id'], 'event.id'),
      title: _requiredString(json['title'], 'event.title', maxLength: 200),
      location: _optionalString(json, 'location', maxLength: 300),
      kind: kind,
      busyStatus: json['busy_status'] as String,
      eventStatus: json['event_status'] as String,
      eventTimezone: _requiredString(
        json['event_timezone'],
        'event.event_timezone',
        maxLength: 100,
      ),
      timezoneSource: json['timezone_source'] as String,
      importedAt: importedAt,
      lastSeenAt: lastSeenAt,
      sourceFingerprint: _requiredFingerprint(
        json['source_fingerprint'],
        'event.source_fingerprint',
      ),
      provenance: provenance,
      startsAt: startsAt,
      endsAt: endsAt,
      localStartsAt: localStartsAt,
      localEndsAt: localEndsAt,
      startsOn: startsOn,
      endsOn: endsOn,
    );
  }

  final String id;
  final String title;
  final String? location;
  final CalendarEventKind kind;
  final String busyStatus;
  final String eventStatus;
  final String eventTimezone;
  final String timezoneSource;
  final DateTime importedAt;
  final DateTime lastSeenAt;
  final String sourceFingerprint;
  final CalendarEventProvenance provenance;
  final String? startsAt;
  final String? endsAt;
  final String? localStartsAt;
  final String? localEndsAt;
  final String? startsOn;
  final String? endsOn;

  String get displayDate => kind == CalendarEventKind.allDay
      ? startsOn!
      : localStartsAt!.substring(0, 10);

  String get displayTime {
    if (kind == CalendarEventKind.allDay) {
      return 'All day · ends before $endsOn';
    }
    final start = localStartsAt!;
    final end = localEndsAt!;
    final endLabel = start.substring(0, 10) == end.substring(0, 10)
        ? end.substring(11, 16)
        : '${end.substring(0, 10)} ${end.substring(11, 16)}';
    return '${start.substring(11, 16)}–$endLabel';
  }
}

class CalendarEventProvenance {
  CalendarEventProvenance({required this.sourceLabel});

  factory CalendarEventProvenance.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'kind',
        'contract_version',
        'source_kind',
        'source_label',
        'provider_writes',
        'llm_processed',
      },
      'calendar event provenance',
    );
    if (json['kind'] != 'integration' ||
        json['contract_version'] != calendarImportContractVersion ||
        json['source_kind'] != 'ical_file' ||
        json['provider_writes'] != false ||
        json['llm_processed'] != false) {
      throw const CalendarIntegrationContractException(
        'Calendar event provenance is invalid.',
      );
    }
    return CalendarEventProvenance(
      sourceLabel: _requiredString(
        json['source_label'],
        'event.provenance.source_label',
        maxLength: 80,
      ),
    );
  }

  final String sourceLabel;
}

class CalendarIntegrationContractException implements Exception {
  const CalendarIntegrationContractException(this.message);
  final String message;

  @override
  String toString() => 'CalendarIntegrationContractException: $message';
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _fingerprintPattern = RegExp(r'^[0-9a-f]{64}$');
final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _localDateTimePattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?$',
);
final _awareDateTimePattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$',
);

bool isCalendarUuid(String value) => _uuidPattern.hasMatch(value);

void _requireContract(Object? value) {
  if (value != calendarImportContractVersion) {
    throw const CalendarIntegrationContractException(
      'Unsupported calendar integration contract.',
    );
  }
}

void _expectExactKeys(
  Map<String, dynamic> json,
  Set<String> keys,
  String model,
) {
  if (json.length != keys.length ||
      json.keys.toSet().difference(keys).isNotEmpty ||
      keys.difference(json.keys.toSet()).isNotEmpty) {
    throw CalendarIntegrationContractException(
      '$model fields do not match the contract.',
    );
  }
}

void _expectRequiredAndOptionalKeys(
  Map<String, dynamic> json, {
  required Set<String> required,
  required Set<String> optional,
  required String model,
}) {
  final keys = json.keys.toSet();
  if (required.difference(keys).isNotEmpty ||
      keys.difference({...required, ...optional}).isNotEmpty ||
      optional.any((key) => json.containsKey(key) && json[key] == null)) {
    throw CalendarIntegrationContractException(
      '$model fields do not match the contract.',
    );
  }
}

String _requiredString(Object? value, String field, {required int maxLength}) {
  if (value is! String ||
      value.isEmpty ||
      value.trim() != value ||
      value.runes.length > maxLength) {
    throw CalendarIntegrationContractException('$field is invalid.');
  }
  return value;
}

String? _optionalString(
  Map<String, dynamic> json,
  String key, {
  required int maxLength,
}) {
  if (!json.containsKey(key)) return null;
  return _requiredString(json[key], key, maxLength: maxLength);
}

String _requiredUuid(Object? value, String field) {
  final result = _requiredString(value, field, maxLength: 36);
  if (!_uuidPattern.hasMatch(result)) {
    throw CalendarIntegrationContractException('$field is invalid.');
  }
  return result;
}

String? _optionalUuid(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) return null;
  return _requiredUuid(json[key], key);
}

String _requiredFingerprint(Object? value, String field) {
  final result = _requiredString(value, field, maxLength: 64);
  if (!_fingerprintPattern.hasMatch(result)) {
    throw CalendarIntegrationContractException('$field is invalid.');
  }
  return result;
}

int _requiredBoundedInt(Object? value, String field) {
  if (value is! int || value < 0 || value > 2000) {
    throw CalendarIntegrationContractException('$field is invalid.');
  }
  return value;
}

String _requiredDate(Object? value, String field) {
  final result = _requiredString(value, field, maxLength: 10);
  if (!_datePattern.hasMatch(result) || result.startsWith('0000-')) {
    throw CalendarIntegrationContractException('$field is invalid.');
  }
  final parsed = DateTime.tryParse('${result}T00:00:00Z');
  if (parsed == null ||
      '${parsed.year.toString().padLeft(4, '0')}-'
              '${parsed.month.toString().padLeft(2, '0')}-'
              '${parsed.day.toString().padLeft(2, '0')}' !=
          result) {
    throw CalendarIntegrationContractException('$field is invalid.');
  }
  return result;
}

DateTime _dateValue(String value) => DateTime.parse('${value}T00:00:00Z');

String _requiredAwareDateTimeText(Object? value, String field) {
  final result = _requiredString(value, field, maxLength: 40);
  final match = _awareDateTimePattern.firstMatch(result);
  if (match == null) {
    throw CalendarIntegrationContractException('$field is invalid.');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final offset = match.group(7)!;
  final date = DateTime.utc(year, month, day);
  final validDate =
      year >= 1 && date.year == year && date.month == month && date.day == day;
  var validOffset = true;
  if (offset != 'Z') {
    final offsetHour = int.parse(offset.substring(1, 3));
    final offsetMinute = int.parse(offset.substring(4, 6));
    validOffset = offsetHour <= 23 && offsetMinute <= 59;
  }
  if (!validDate ||
      hour > 23 ||
      minute > 59 ||
      second > 59 ||
      !validOffset ||
      DateTime.tryParse(result) == null) {
    throw CalendarIntegrationContractException('$field is invalid.');
  }
  return result;
}

DateTime _requiredAwareDateTime(Object? value, String field) =>
    DateTime.parse(_requiredAwareDateTimeText(value, field));

DateTime? _optionalAwareDateTime(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) return null;
  return _requiredAwareDateTime(json[key], key);
}

String _requiredLocalDateTime(Object? value, String field) {
  final result = _requiredString(value, field, maxLength: 32);
  if (!_localDateTimePattern.hasMatch(result)) {
    throw CalendarIntegrationContractException('$field is invalid.');
  }
  final date = _requiredDate(result.substring(0, 10), '$field date');
  final time = result.substring(11);
  final parts = time.split(RegExp(r'[:.]'));
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  final second = int.tryParse(parts[2]);
  if (date.isEmpty ||
      hour == null ||
      minute == null ||
      second == null ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    throw CalendarIntegrationContractException('$field is invalid.');
  }
  return result;
}
