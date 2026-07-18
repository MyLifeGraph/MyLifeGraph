import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/navigation/app_routes.dart';
import 'package:my_life_graph/features/calendar_integration/domain/calendar_integration.dart';
import 'package:my_life_graph/features/calendar_integration/presentation/pages/calendar_integration_page.dart';

import 'support/calendar_integration_fixtures.dart';

void main() {
  test('all-day source URL carries only its opaque event identity', () {
    final event = CalendarImportedEvent.fromJson(calendarAllDayEventJson());

    final location = calendarPreparationPlanLocation(
      event,
      now: DateTime(2026, 7, 18, 12),
    );

    expect(location!.path, AppRoutes.preparationPlans);
    expect(location.queryParameters, {'calendar_event_id': event.id});
    expect(location.toString(), isNot(contains(event.title)));
    expect(location.toString(), isNot(contains(event.sourceFingerprint)));
    expect(location.toString(), isNot(contains('2026-07-20')));
  });

  test('timed source URL carries no title, fingerprint, or deadline', () {
    final event = CalendarImportedEvent.fromJson(calendarTimedEventJson());

    final location = calendarPreparationPlanLocation(
      event,
      now: DateTime.utc(2026, 7, 13, 12),
    );

    expect(location!.queryParameters, {'calendar_event_id': event.id});
    expect(location.toString(), isNot(contains(event.title)));
    expect(location.toString(), isNot(contains(event.sourceFingerprint)));
    expect(location.toString(), isNot(contains('deadline')));
  });
}
