import 'calendar_integration.dart';

abstract interface class CalendarIntegrationRepository {
  Future<CalendarIntegrationFeed> getIntegration();

  Future<CalendarIntegrationFeed> createConnection({
    required String requestId,
    required String sourceLabel,
  });

  Future<CalendarImportResponse> importCalendar({
    required String connectionId,
    required String requestId,
    required String calendarText,
  });

  Future<CalendarEventPage> getEvents({
    required String connectionId,
    String? cursor,
  });

  Future<CalendarIntegrationFeed> disconnect({
    required String connectionId,
    required String requestId,
  });

  Future<CalendarIntegrationFeed> deleteImportedData({
    required String connectionId,
    required String requestId,
  });
}
