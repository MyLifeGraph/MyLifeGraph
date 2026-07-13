const calendarConnectionId = '11111111-1111-4111-8111-111111111111';
const calendarImportId = '22222222-2222-4222-8222-222222222222';
const calendarCreateRequestId = '33333333-3333-4333-8333-333333333333';
const calendarImportRequestId = '44444444-4444-4444-8444-444444444444';
const calendarDisconnectRequestId = '55555555-5555-4555-8555-555555555555';
const calendarDeleteRequestId = '66666666-6666-4666-8666-666666666666';
const calendarTimedEventId = '77777777-7777-4777-8777-777777777777';
const calendarAllDayEventId = '88888888-8888-4888-8888-888888888888';
const calendarFingerprint =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> calendarConsentJson() => {
      'consent_version': 'calendar-import-consent-v1',
      'read_calendar_events': true,
      'store_event_basics': true,
      'provider_writes': false,
      'llm_processing': false,
    };

Map<String, dynamic> calendarImportSummaryJson({int accepted = 2}) => {
      'id': calendarImportId,
      'imported_at': '2026-07-13T12:00:00Z',
      'window': {
        'starts_on': '2026-06-29',
        'ends_before': '2026-10-12',
        'timezone': 'Europe/Berlin',
      },
      'counts': {
        'accepted': accepted,
        'cancelled': 1,
        'out_of_window': 3,
        'unsupported_recurring': 1,
        'invalid': 0,
      },
      'source_fingerprint': calendarFingerprint,
    };

Map<String, dynamic> calendarConnectionJson({
  String status = 'connected',
  String sourceLabel = 'Work calendar',
  bool includeImport = true,
  bool deleted = false,
}) {
  final result = <String, dynamic>{
    'id': calendarConnectionId,
    'contract_version': 'calendar-import-v1',
    'origin': 'authenticated_backend',
    'source_kind': 'ical_file',
    'source_label': sourceLabel,
    'status': status,
    'consent': calendarConsentJson(),
    'consented_at': '2026-07-13T11:00:00Z',
    'connected_at': '2026-07-13T11:00:00Z',
    'provider_writes': false,
    'llm_processed': false,
  };
  if (status == 'disconnected') {
    result['disconnected_at'] = '2026-07-13T14:00:00Z';
  }
  if (deleted) {
    result['imported_data_deleted_at'] = '2026-07-13T15:00:00Z';
  } else if (includeImport) {
    result['last_import'] = calendarImportSummaryJson();
  }
  return result;
}

Map<String, dynamic> calendarFeedJson({
  Map<String, dynamic>? connection,
  bool noConnection = false,
}) =>
    {
      'contract_version': 'calendar-import-v1',
      'origin': 'authenticated_backend',
      'connection':
          noConnection ? null : connection ?? calendarConnectionJson(),
    };

Map<String, dynamic> calendarImportResponseJson({
  Map<String, dynamic>? connection,
  Map<String, dynamic>? import,
}) =>
    {
      'contract_version': 'calendar-import-v1',
      'origin': 'authenticated_backend',
      'connection': connection ?? calendarConnectionJson(),
      'import': import ?? calendarImportSummaryJson(),
    };

Map<String, dynamic> calendarTimedEventJson({
  String id = calendarTimedEventId,
  String title = 'Late planning session',
  String? location = 'Room 2',
  String importedAt = '2026-07-13T12:00:00Z',
  String lastSeenAt = '2026-07-13T12:00:00Z',
}) {
  final result = <String, dynamic>{
    'id': id,
    'title': title,
    'event_kind': 'timed',
    'busy_status': 'busy',
    'event_status': 'confirmed',
    'event_timezone': 'Europe/Berlin',
    'timezone_source': 'event',
    'starts_at': '2026-07-13T20:30:00Z',
    'ends_at': '2026-07-13T23:30:00Z',
    'local_starts_at': '2026-07-13T22:30:00',
    'local_ends_at': '2026-07-14T01:30:00',
    'imported_at': importedAt,
    'last_seen_at': lastSeenAt,
    'source_fingerprint': calendarFingerprint,
    'provenance': {
      'kind': 'integration',
      'contract_version': 'calendar-import-v1',
      'source_kind': 'ical_file',
      'source_label': 'Work calendar',
      'provider_writes': false,
      'llm_processed': false,
    },
  };
  if (location != null) result['location'] = location;
  return result;
}

Map<String, dynamic> calendarAllDayEventJson() => {
      'id': calendarAllDayEventId,
      'title': 'Company holiday',
      'event_kind': 'all_day',
      'busy_status': 'free',
      'event_status': 'tentative',
      'event_timezone': 'Europe/Berlin',
      'timezone_source': 'profile',
      'starts_on': '2026-07-20',
      'ends_on': '2026-07-22',
      'imported_at': '2026-07-13T12:00:00Z',
      'last_seen_at': '2026-07-13T12:00:00Z',
      'source_fingerprint': calendarFingerprint,
      'provenance': {
        'kind': 'integration',
        'contract_version': 'calendar-import-v1',
        'source_kind': 'ical_file',
        'source_label': 'Work calendar',
        'provider_writes': false,
        'llm_processed': false,
      },
    };

Map<String, dynamic> calendarEventsPageJson({
  List<Map<String, dynamic>>? events,
  String? cursor,
  bool includeImportId = true,
}) {
  final result = <String, dynamic>{
    'contract_version': 'calendar-import-v1',
    'origin': 'authenticated_backend',
    'connection_id': calendarConnectionId,
    'events': events ?? [calendarTimedEventJson(), calendarAllDayEventJson()],
  };
  if (includeImportId) result['import_id'] = calendarImportId;
  if (cursor != null) result['next_cursor'] = cursor;
  return result;
}
