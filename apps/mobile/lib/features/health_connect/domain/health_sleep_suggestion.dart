import '../../../core/time/profile_timezone.dart';

class HealthSleepSuggestion {
  const HealthSleepSuggestion(this.startedAt, this.wokeAt);
  final DateTime startedAt;
  final DateTime wokeAt;

  static HealthSleepSuggestion? parse(
    Map<String, dynamic> data,
    String day,
    String zone,
    DateTime now,
  ) {
    if (data['started_at'] is! String || data['woke_at'] is! String) {
      return null;
    }
    final start = DateTime.tryParse(data['started_at'] as String);
    final end = DateTime.tryParse(data['woke_at'] as String);
    if (start == null ||
        end == null ||
        !start.isUtc ||
        !end.isUtc ||
        end.isAfter(now) ||
        end.difference(start).inMinutes < 60 ||
        end.difference(start).inMinutes > 960) {
      return null;
    }
    final localStart = profileDateTimeAt(instant: start, timezoneName: zone);
    final localEnd = profileDateTimeAt(instant: end, timezoneName: zone);
    final target = DateTime.tryParse(day);
    if (target == null ||
        target.year != localEnd.year ||
        target.month != localEnd.month ||
        target.day != localEnd.day) {
      return null;
    }
    return HealthSleepSuggestion(localStart, localEnd);
  }
}
