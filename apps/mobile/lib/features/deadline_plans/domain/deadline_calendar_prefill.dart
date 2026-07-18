enum DeadlineCalendarPrefillStatus { current, stale, unavailable }

enum DeadlineCalendarEventKind { timed, allDay }

class DeadlineCalendarPrefill {
  DeadlineCalendarPrefill._({
    required this.eventId,
    required this.status,
    required this.title,
    required this.sourceFingerprint,
    required this.kind,
    required this.startsAt,
    required this.startsOn,
  }) {
    if (!_uuidPattern.hasMatch(eventId) ||
        status == DeadlineCalendarPrefillStatus.unavailable &&
            (title != null ||
                sourceFingerprint != null ||
                kind != null ||
                startsAt != null ||
                startsOn != null) ||
        status != DeadlineCalendarPrefillStatus.unavailable &&
            (title == null ||
                title!.trim() != title ||
                title!.isEmpty ||
                title!.runes.length > 200 ||
                sourceFingerprint == null ||
                !_fingerprintPattern.hasMatch(sourceFingerprint!) ||
                kind == null) ||
        kind == DeadlineCalendarEventKind.timed &&
            (startsAt == null || startsOn != null) ||
        kind == DeadlineCalendarEventKind.allDay &&
            (startsOn == null || startsAt != null)) {
      throw const DeadlineCalendarPrefillException(
        'Calendar preparation prefill is invalid.',
      );
    }
  }

  factory DeadlineCalendarPrefill.current({
    required String eventId,
    required String title,
    required String sourceFingerprint,
    required DeadlineCalendarEventKind kind,
    required DateTime? startsAt,
    required String? startsOn,
  }) =>
      DeadlineCalendarPrefill._(
        eventId: eventId,
        status: DeadlineCalendarPrefillStatus.current,
        title: title,
        sourceFingerprint: sourceFingerprint,
        kind: kind,
        startsAt: startsAt,
        startsOn: startsOn,
      );

  factory DeadlineCalendarPrefill.stale({
    required String eventId,
    required String title,
    required String sourceFingerprint,
    required DeadlineCalendarEventKind kind,
    required DateTime? startsAt,
    required String? startsOn,
  }) =>
      DeadlineCalendarPrefill._(
        eventId: eventId,
        status: DeadlineCalendarPrefillStatus.stale,
        title: title,
        sourceFingerprint: sourceFingerprint,
        kind: kind,
        startsAt: startsAt,
        startsOn: startsOn,
      );

  factory DeadlineCalendarPrefill.unavailable(String eventId) =>
      DeadlineCalendarPrefill._(
        eventId: eventId,
        status: DeadlineCalendarPrefillStatus.unavailable,
        title: null,
        sourceFingerprint: null,
        kind: null,
        startsAt: null,
        startsOn: null,
      );

  final String eventId;
  final DeadlineCalendarPrefillStatus status;
  final String? title;
  final String? sourceFingerprint;
  final DeadlineCalendarEventKind? kind;
  final DateTime? startsAt;
  final String? startsOn;

  bool get canPrefill => status != DeadlineCalendarPrefillStatus.unavailable;

  bool hasFutureDeadline(DateTime now) {
    if (!canPrefill) return false;
    if (kind == DeadlineCalendarEventKind.timed) {
      return startsAt!.isAfter(now);
    }
    final date = DateTime.parse(startsOn!);
    return !DateTime(date.year, date.month, date.day).isBefore(
      DateTime(now.year, now.month, now.day),
    );
  }
}

class DeadlineCalendarPrefillException implements Exception {
  const DeadlineCalendarPrefillException(this.message);

  final String message;

  @override
  String toString() => message;
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _fingerprintPattern = RegExp(r'^[0-9a-f]{64}$');
