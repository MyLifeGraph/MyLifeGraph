import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/calendar_integration/domain/calendar_integration.dart';

import 'support/calendar_integration_fixtures.dart';

void main() {
  group('calendar-import-v1 domain', () {
    test('parses exact connection, import, timed, and all-day shapes', () {
      final feed = CalendarIntegrationFeed.fromJson(calendarFeedJson());
      final response = CalendarImportResponse.fromJson(
        calendarImportResponseJson(),
      );
      final page = CalendarEventPage.fromJson(calendarEventsPageJson());

      expect(feed.origin, CalendarIntegrationOrigin.authenticatedBackend);
      expect(feed.connection!.sourceLabel, 'Work calendar');
      expect(response.connection.lastImport!.counts.accepted, 2);
      expect(page.events, hasLength(2));
      expect(page.events.first.kind, CalendarEventKind.timed);
      expect(page.events.last.kind, CalendarEventKind.allDay);
      expect(page.events.last.displayTime, 'All day · ends before 2026-07-22');
    });

    test('rejects unknown, explicit-null, coerced, and mismatched fields', () {
      final unknown = _copy(calendarFeedJson());
      unknown['unexpected'] = true;
      expect(
        () => CalendarIntegrationFeed.fromJson(unknown),
        throwsA(isA<CalendarIntegrationContractException>()),
      );

      final explicitNull = _copy(calendarFeedJson());
      (explicitNull['connection'] as Map<String, dynamic>)['last_import'] =
          null;
      expect(
        () => CalendarIntegrationFeed.fromJson(explicitNull),
        throwsA(isA<CalendarIntegrationContractException>()),
      );

      final coerced = _copy(calendarFeedJson());
      ((coerced['connection'] as Map<String, dynamic>)['last_import']
          as Map<String, dynamic>)['counts'] = {
        'accepted': '2',
        'cancelled': 1,
        'out_of_window': 3,
        'unsupported_recurring': 1,
        'invalid': 0,
      };
      expect(
        () => CalendarIntegrationFeed.fromJson(coerced),
        throwsA(isA<CalendarIntegrationContractException>()),
      );

      final wrongContract = _copy(calendarFeedJson());
      wrongContract['contract_version'] = 'calendar-import-v2';
      expect(
        () => CalendarIntegrationFeed.fromJson(wrongContract),
        throwsA(isA<CalendarIntegrationContractException>()),
      );
    });

    test('requires a real 105-day window and rejects year zero', () {
      final shortWindow = _copy(calendarFeedJson());
      final import = ((shortWindow['connection']
          as Map<String, dynamic>)['last_import'] as Map<String, dynamic>);
      (import['window'] as Map<String, dynamic>)['ends_before'] = '2026-10-11';
      expect(
        () => CalendarIntegrationFeed.fromJson(shortWindow),
        throwsA(isA<CalendarIntegrationContractException>()),
      );

      final yearZero = _copy(calendarEventsPageJson());
      final allDay =
          (yearZero['events'] as List<dynamic>)[1] as Map<String, dynamic>;
      allDay['starts_on'] = '0000-07-20';
      expect(
        () => CalendarEventPage.fromJson(yearZero),
        throwsA(isA<CalendarIntegrationContractException>()),
      );
    });

    test('validates timestamp components instead of normalizing overflow', () {
      for (final invalid in [
        '2026-13-01T12:00:00Z',
        '2026-07-13T25:00:00Z',
        '2026-07-13T12:61:00Z',
        '2026-07-13T12:00:61Z',
        '2026-07-13T12:00:00+24:00',
      ]) {
        final json = _copy(calendarFeedJson());
        (json['connection'] as Map<String, dynamic>)['consented_at'] = invalid;
        expect(
          () => CalendarIntegrationFeed.fromJson(json),
          throwsA(isA<CalendarIntegrationContractException>()),
          reason: invalid,
        );
      }
    });

    test('last seen must not precede imported time', () {
      final json = calendarEventsPageJson(
        events: [
          calendarTimedEventJson(
            importedAt: '2026-07-13T12:00:00Z',
            lastSeenAt: '2026-07-13T11:59:59Z',
          ),
        ],
      );
      expect(
        () => CalendarEventPage.fromJson(json),
        throwsA(isA<CalendarIntegrationContractException>()),
      );
    });

    test('import response compares full summary, not only the import id', () {
      final response = calendarImportResponseJson(
        import: calendarImportSummaryJson(accepted: 1),
      );
      expect(
        () => CalendarImportResponse.fromJson(response),
        throwsA(isA<CalendarIntegrationContractException>()),
      );
    });

    test('length limits count Unicode code points', () {
      final eightyEmoji = List.filled(80, '🙂').join();
      final valid = CalendarIntegrationFeed.fromJson(
        calendarFeedJson(
          connection: calendarConnectionJson(sourceLabel: eightyEmoji),
        ),
      );
      expect(valid.connection!.sourceLabel.runes.length, 80);

      expect(
        () => CalendarIntegrationFeed.fromJson(
          calendarFeedJson(
            connection: calendarConnectionJson(
              sourceLabel: '$eightyEmoji🙂',
            ),
          ),
        ),
        throwsA(isA<CalendarIntegrationContractException>()),
      );
    });

    test('bounded event strings, pages, and cursors stay strict', () {
      final longTitle = calendarEventsPageJson(
        events: [calendarTimedEventJson(title: List.filled(201, 'x').join())],
      );
      expect(
        () => CalendarEventPage.fromJson(longTitle),
        throwsA(isA<CalendarIntegrationContractException>()),
      );

      final longLocation = calendarEventsPageJson(
        events: [
          calendarTimedEventJson(location: List.filled(301, 'x').join()),
        ],
      );
      expect(
        () => CalendarEventPage.fromJson(longLocation),
        throwsA(isA<CalendarIntegrationContractException>()),
      );

      final longCursor = calendarEventsPageJson(
        cursor: List.filled(513, 'x').join(),
      );
      expect(
        () => CalendarEventPage.fromJson(longCursor),
        throwsA(isA<CalendarIntegrationContractException>()),
      );

      final tooMany = calendarEventsPageJson(
        events: List.generate(
          51,
          (index) => calendarTimedEventJson(
            id: '${index.toRadixString(16).padLeft(8, '0')}-7777-4777-8777-777777777777',
          ),
        ),
      );
      expect(
        () => CalendarEventPage.fromJson(tooMany),
        throwsA(isA<CalendarIntegrationContractException>()),
      );
    });

    test('cross-midnight display uses backend local projections verbatim', () {
      final event = CalendarEventPage.fromJson(
        calendarEventsPageJson(events: [calendarTimedEventJson()]),
      ).events.single;

      expect(event.displayDate, '2026-07-13');
      expect(event.displayTime, '22:30–2026-07-14 01:30');
      expect(event.localStartsAt, '2026-07-13T22:30:00');
      expect(event.localEndsAt, '2026-07-14T01:30:00');
    });

    test('empty authenticated feed is explicit and valid', () {
      final feed = CalendarIntegrationFeed.fromJson(
        calendarFeedJson(noConnection: true),
      );
      expect(feed.origin, CalendarIntegrationOrigin.authenticatedBackend);
      expect(feed.connection, isNull);
    });
  });
}

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
