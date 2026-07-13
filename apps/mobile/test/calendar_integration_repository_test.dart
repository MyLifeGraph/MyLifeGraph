import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/calendar_integration/data/calendar_integration_api_data_source.dart';
import 'package:my_life_graph/features/calendar_integration/data/calendar_integration_repository_impl.dart';
import 'package:my_life_graph/features/calendar_integration/domain/calendar_integration.dart';

import 'support/calendar_integration_fixtures.dart';

void main() {
  const config = AppConfig(
    environment: 'test',
    supabaseUrl: 'http://127.0.0.1:54321',
    supabaseAnonKey: 'anon-key',
    aiServiceBaseUrl: 'http://127.0.0.1:8000',
    useMockData: false,
  );

  test('read is GET-only and create sends exact consent and bearer', () async {
    final client = _TrackingApiClient(
      getResponses: {
        '/v1/calendar-integrations': calendarFeedJson(noConnection: true),
      },
      postResponses: {
        '/v1/calendar-integrations/connections': calendarFeedJson(
          connection: calendarConnectionJson(includeImport: false),
        ),
      },
    );
    final repository = _repository(client, config: config);

    final empty = await repository.getIntegration();
    final created = await repository.createConnection(
      requestId: calendarCreateRequestId,
      sourceLabel: 'Work calendar',
    );

    expect(empty.connection, isNull);
    expect(created.connection!.isConnected, isTrue);
    expect(client.getCalls, ['/v1/calendar-integrations']);
    expect(client.postCalls, ['/v1/calendar-integrations/connections']);
    expect(client.headersByPath['/v1/calendar-integrations'], {
      'Authorization': 'Bearer account-token',
    });
    expect(client.bodyByPath['/v1/calendar-integrations/connections'], {
      'request_id': calendarCreateRequestId,
      'source_kind': 'ical_file',
      'source_label': 'Work calendar',
      'consent': {
        'consent_version': 'calendar-import-consent-v1',
        'read_calendar_events': true,
        'store_event_basics': true,
        'provider_writes': false,
        'llm_processing': false,
      },
    });
  });

  test('import and event pagination use only their exact endpoints', () async {
    const cursor = 'opaque/cursor with space';
    final eventPath =
        '/v1/calendar-integrations/connections/$calendarConnectionId/events'
        '?cursor=${Uri.encodeQueryComponent(cursor)}';
    final client = _TrackingApiClient(
      postResponses: {
        '/v1/calendar-integrations/connections/$calendarConnectionId/imports':
            calendarImportResponseJson(),
      },
      getResponses: {eventPath: calendarEventsPageJson()},
    );
    final repository = _repository(client, config: config);

    final imported = await repository.importCalendar(
      connectionId: calendarConnectionId,
      requestId: calendarImportRequestId,
      calendarText: 'BEGIN:VCALENDAR\nEND:VCALENDAR',
    );
    final page = await repository.getEvents(
      connectionId: calendarConnectionId,
      cursor: cursor,
    );

    expect(imported.import.id, calendarImportId);
    expect(page.events, hasLength(2));
    expect(client.postCalls.single, contains('/imports'));
    expect(client.getCalls, [eventPath]);
    expect(client.bodyByPath[client.postCalls.single], {
      'request_id': calendarImportRequestId,
      'calendar_text': 'BEGIN:VCALENDAR\nEND:VCALENDAR',
    });
  });

  test('disconnect and deletion retain stable ids in exact requests', () async {
    final disconnectPath =
        '/v1/calendar-integrations/connections/$calendarConnectionId/disconnect';
    final deletePath =
        '/v1/calendar-integrations/connections/$calendarConnectionId/'
        'imported-data?request_id=$calendarDeleteRequestId';
    final client = _TrackingApiClient(
      postResponses: {
        disconnectPath: calendarFeedJson(
          connection: calendarConnectionJson(status: 'disconnected'),
        ),
      },
      deleteResponses: {
        deletePath: calendarFeedJson(
          connection: calendarConnectionJson(
            status: 'disconnected',
            includeImport: false,
            deleted: true,
          ),
        ),
      },
    );
    final repository = _repository(client, config: config);

    final disconnected = await repository.disconnect(
      connectionId: calendarConnectionId,
      requestId: calendarDisconnectRequestId,
    );
    final deleted = await repository.deleteImportedData(
      connectionId: calendarConnectionId,
      requestId: calendarDeleteRequestId,
    );

    expect(disconnected.connection!.hasRetainedImportedData, isTrue);
    expect(deleted.connection!.importedDataDeleted, isTrue);
    expect(client.bodyByPath[disconnectPath], {
      'request_id': calendarDisconnectRequestId,
    });
    expect(client.deleteCalls, [deletePath]);
  });

  test('guest and mock source stays zero-call for every operation', () async {
    final client = _TrackingApiClient(throwOnRequest: true);
    final repository = _repository(
      client,
      config: config,
      isLocalDemo: true,
      token: null,
    );

    final feed = await repository.getIntegration();
    expect(feed.origin, CalendarIntegrationOrigin.localDemo);
    await expectLater(
      repository.createConnection(
        requestId: calendarCreateRequestId,
        sourceLabel: 'Work calendar',
      ),
      throwsA(isA<CalendarIntegrationAccessException>()),
    );
    await expectLater(
      repository.importCalendar(
        connectionId: calendarConnectionId,
        requestId: calendarImportRequestId,
        calendarText: 'BEGIN:VCALENDAR',
      ),
      throwsA(isA<CalendarIntegrationAccessException>()),
    );
    await expectLater(
      repository.getEvents(connectionId: calendarConnectionId),
      throwsA(isA<CalendarIntegrationAccessException>()),
    );
    await expectLater(
      repository.disconnect(
        connectionId: calendarConnectionId,
        requestId: calendarDisconnectRequestId,
      ),
      throwsA(isA<CalendarIntegrationAccessException>()),
    );
    await expectLater(
      repository.deleteImportedData(
        connectionId: calendarConnectionId,
        requestId: calendarDeleteRequestId,
      ),
      throwsA(isA<CalendarIntegrationAccessException>()),
    );
    expect(client.totalCalls, 0);
  });

  test('missing config or token fails before any request', () async {
    final client = _TrackingApiClient(throwOnRequest: true);
    final noConfig = _repository(
      client,
      config: const AppConfig(
        environment: 'test',
        supabaseUrl: '',
        supabaseAnonKey: '',
        aiServiceBaseUrl: 'http://127.0.0.1:8000',
        useMockData: false,
      ),
    );
    final noToken = _repository(client, config: config, token: ' ');

    await expectLater(
      noConfig.getIntegration(),
      throwsA(isA<CalendarIntegrationAccessException>()),
    );
    await expectLater(
      noToken.getIntegration(),
      throwsA(isA<CalendarIntegrationAccessException>()),
    );
    expect(client.totalCalls, 0);
  });

  test('non-synced capability fails honestly without becoming demo', () async {
    final client = _TrackingApiClient(throwOnRequest: true);
    final repository = _repository(
      client,
      config: config,
      canUseSyncedIntegration: false,
    );

    await expectLater(
      repository.getIntegration(),
      throwsA(
        isA<CalendarIntegrationAccessException>().having(
          (error) => error.message,
          'message',
          contains('authenticated synced account'),
        ),
      ),
    );
    expect(client.totalCalls, 0);
  });

  test('mutation responses may never omit their connection', () async {
    final client = _TrackingApiClient(
      postResponses: {
        '/v1/calendar-integrations/connections':
            calendarFeedJson(noConnection: true),
      },
    );
    final repository = _repository(client, config: config);

    await expectLater(
      repository.createConnection(
        requestId: calendarCreateRequestId,
        sourceLabel: 'Work calendar',
      ),
      throwsA(isA<CalendarIntegrationContractException>()),
    );
  });
}

CalendarIntegrationRepositoryImpl _repository(
  _TrackingApiClient client, {
  required AppConfig config,
  bool isLocalDemo = false,
  bool canUseSyncedIntegration = true,
  String? token = ' account-token ',
}) =>
    CalendarIntegrationRepositoryImpl(
      config: config,
      apiDataSource: CalendarIntegrationApiDataSource(client),
      accessTokenProvider: () => token,
      isLocalDemo: isLocalDemo,
      canUseSyncedIntegration: isLocalDemo ? false : canUseSyncedIntegration,
    );

class _TrackingApiClient extends ApiClient {
  _TrackingApiClient({
    this.getResponses = const {},
    this.postResponses = const {},
    this.deleteResponses = const {},
    this.throwOnRequest = false,
  }) : super(Dio());

  final Map<String, Map<String, dynamic>> getResponses;
  final Map<String, Map<String, dynamic>> postResponses;
  final Map<String, Map<String, dynamic>> deleteResponses;
  final bool throwOnRequest;
  final List<String> getCalls = [];
  final List<String> postCalls = [];
  final List<String> deleteCalls = [];
  final Map<String, Map<String, dynamic>?> bodyByPath = {};
  final Map<String, Map<String, String>?> headersByPath = {};

  int get totalCalls => getCalls.length + postCalls.length + deleteCalls.length;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    if (throwOnRequest) throw StateError('Network must not be used.');
    getCalls.add(path);
    headersByPath[path] = headers;
    return getResponses[path] ?? (throw StateError('Missing GET $path'));
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    if (throwOnRequest) throw StateError('Network must not be used.');
    postCalls.add(path);
    bodyByPath[path] = body;
    headersByPath[path] = headers;
    return postResponses[path] ?? (throw StateError('Missing POST $path'));
  }

  @override
  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    if (throwOnRequest) throw StateError('Network must not be used.');
    deleteCalls.add(path);
    headersByPath[path] = headers;
    return deleteResponses[path] ?? (throw StateError('Missing DELETE $path'));
  }
}
