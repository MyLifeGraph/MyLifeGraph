import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_life_graph/features/deadline_plans/data/deadline_calendar_prefill_data_source.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_calendar_prefill.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('loads current owner-RLS event and current connection projection',
      () async {
    final requests = <http.Request>[];
    final client = _client((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/calendar_events')) {
        return _json([_eventRow()], request);
      }
      if (request.url.path.endsWith('/calendar_connections')) {
        return _json([_connectionRow()], request);
      }
      throw StateError('Unexpected request ${request.url}');
    });
    addTearDown(client.dispose);
    final source = DeadlineCalendarPrefillSupabaseDataSource(
      client,
      verifyAuthenticatedOwner: () async {},
    );

    final prefill = await source.getEvent(eventId);

    expect(prefill.status, DeadlineCalendarPrefillStatus.current);
    expect(prefill.title, 'Private algorithms exam');
    expect(prefill.startsAt, DateTime.parse('2026-07-25T15:00:00Z'));
    expect(requests, hasLength(2));
    expect(requests.first.url.queryParameters['id'], 'eq.$eventId');
    expect(requests.first.url.queryParameters, isNot(contains('user_id')));
    expect(
      requests.last.url.queryParameters['id'],
      'eq.$connectionId',
    );
  });

  test('missing event is unavailable without querying a connection', () async {
    var calls = 0;
    final client = _client((request) async {
      calls++;
      return _json([], request);
    });
    addTearDown(client.dispose);
    final source = DeadlineCalendarPrefillSupabaseDataSource(
      client,
      verifyAuthenticatedOwner: () async {},
    );

    final prefill = await source.getEvent(eventId);

    expect(prefill.status, DeadlineCalendarPrefillStatus.unavailable);
    expect(calls, 1);
  });

  test('disconnected or superseded import is reported as stale', () async {
    final client = _client((request) async {
      if (request.url.path.endsWith('/calendar_events')) {
        return _json([_eventRow()], request);
      }
      return _json(
        [
          _connectionRow()
            ..['status'] = 'disconnected'
            ..['last_import_id'] = '99999999-9999-4999-8999-999999999999',
        ],
        request,
      );
    });
    addTearDown(client.dispose);
    final source = DeadlineCalendarPrefillSupabaseDataSource(
      client,
      verifyAuthenticatedOwner: () async {},
    );

    final prefill = await source.getEvent(eventId);

    expect(prefill.status, DeadlineCalendarPrefillStatus.stale);
    expect(prefill.title, 'Private algorithms exam');
  });
}

const eventId = '88888888-8888-4888-8888-888888888888';
const connectionId = '66666666-6666-4666-8666-666666666666';
const importId = '77777777-7777-4777-8777-777777777777';
const fingerprint =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> _eventRow() => {
      'id': eventId,
      'connection_id': connectionId,
      'import_id': importId,
      'contract_version': 'calendar-import-v1',
      'origin': 'authenticated_backend',
      'source_kind': 'ical_file',
      'source_fingerprint': fingerprint,
      'title': 'Private algorithms exam',
      'event_kind': 'timed',
      'starts_at': '2026-07-25T15:00:00Z',
      'starts_on': null,
    };

Map<String, dynamic> _connectionRow() => {
      'id': connectionId,
      'contract_version': 'calendar-import-v1',
      'origin': 'authenticated_backend',
      'source_kind': 'ical_file',
      'status': 'connected',
      'last_import_id': importId,
      'imported_data_deleted_at': null,
    };

SupabaseClient _client(
  Future<http.Response> Function(http.Request request) handler,
) =>
    SupabaseClient(
      'http://localhost:54321',
      'test-anon-key',
      httpClient: MockClient(handler),
      accessToken: () async => 'test-access-token',
    );

http.Response _json(Object value, http.Request request) => http.Response(
      jsonEncode(value),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
