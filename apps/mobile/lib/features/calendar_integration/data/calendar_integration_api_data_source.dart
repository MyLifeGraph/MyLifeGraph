import '../../../core/network/api_client.dart';
import '../domain/calendar_integration.dart';

class CalendarIntegrationApiDataSource {
  const CalendarIntegrationApiDataSource(this._client);

  final ApiClient _client;

  Future<CalendarIntegrationFeed> getIntegration({
    required String accessToken,
  }) async {
    final json = await _client.getJson(
      '/v1/calendar-integrations',
      headers: _headers(accessToken),
    );
    return CalendarIntegrationFeed.fromJson(json);
  }

  Future<CalendarIntegrationFeed> createConnection({
    required String accessToken,
    required String requestId,
    required String sourceLabel,
  }) async {
    final json = await _client.postJson(
      '/v1/calendar-integrations/connections',
      headers: _headers(accessToken),
      body: {
        'request_id': requestId,
        'source_kind': 'ical_file',
        'source_label': sourceLabel,
        'consent': const CalendarConsent().toJson(),
      },
    );
    final feed = CalendarIntegrationFeed.fromJson(json);
    _requireMutationConnection(feed, 'create');
    return feed;
  }

  Future<CalendarImportResponse> importCalendar({
    required String accessToken,
    required String connectionId,
    required String requestId,
    required String calendarText,
  }) async {
    final json = await _client.postJson(
      '/v1/calendar-integrations/connections/$connectionId/imports',
      headers: _headers(accessToken),
      body: {'request_id': requestId, 'calendar_text': calendarText},
    );
    return CalendarImportResponse.fromJson(json);
  }

  Future<CalendarEventPage> getEvents({
    required String accessToken,
    required String connectionId,
    String? cursor,
  }) async {
    final suffix =
        cursor == null ? '' : '?cursor=${Uri.encodeQueryComponent(cursor)}';
    final json = await _client.getJson(
      '/v1/calendar-integrations/connections/$connectionId/events$suffix',
      headers: _headers(accessToken),
    );
    return CalendarEventPage.fromJson(json);
  }

  Future<CalendarIntegrationFeed> disconnect({
    required String accessToken,
    required String connectionId,
    required String requestId,
  }) async {
    final json = await _client.postJson(
      '/v1/calendar-integrations/connections/$connectionId/disconnect',
      headers: _headers(accessToken),
      body: {'request_id': requestId},
    );
    final feed = CalendarIntegrationFeed.fromJson(json);
    _requireMutationConnection(feed, 'disconnect');
    return feed;
  }

  Future<CalendarIntegrationFeed> deleteImportedData({
    required String accessToken,
    required String connectionId,
    required String requestId,
  }) async {
    final query = Uri(queryParameters: {'request_id': requestId}).query;
    final json = await _client.deleteJson(
      '/v1/calendar-integrations/connections/$connectionId/imported-data?$query',
      headers: _headers(accessToken),
    );
    final feed = CalendarIntegrationFeed.fromJson(json);
    _requireMutationConnection(feed, 'delete');
    return feed;
  }

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
      };

  void _requireMutationConnection(
    CalendarIntegrationFeed feed,
    String operation,
  ) {
    if (feed.connection == null) {
      throw CalendarIntegrationContractException(
        'Calendar $operation response is missing its connection.',
      );
    }
  }
}
