import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

bool _profileTimeZonesInitialized = false;

void initializeProfileTimeZones() {
  if (_profileTimeZonesInitialized) {
    return;
  }
  timezone_data.initializeTimeZones();
  _profileTimeZonesInitialized = true;
}

DateTime profileDateAt({
  required DateTime instant,
  required String timezoneName,
}) {
  initializeProfileTimeZones();
  final normalizedName = timezoneName.trim();
  if (normalizedName.isEmpty) {
    throw const ProfileTimezoneException('Profile timezone is missing.');
  }
  try {
    final location = timezone.getLocation(normalizedName);
    final local = timezone.TZDateTime.from(instant, location);
    return DateTime(local.year, local.month, local.day);
  } on timezone.LocationNotFoundException {
    throw ProfileTimezoneException(
      'Profile timezone "$normalizedName" is invalid.',
    );
  }
}

DateTime profileDateTimeAt({
  required DateTime instant,
  required String timezoneName,
}) {
  initializeProfileTimeZones();
  final normalizedName = timezoneName.trim();
  if (normalizedName.isEmpty) {
    throw const ProfileTimezoneException('Profile timezone is missing.');
  }
  try {
    final location = timezone.getLocation(normalizedName);
    return timezone.TZDateTime.from(instant, location);
  } on timezone.LocationNotFoundException {
    throw ProfileTimezoneException(
      'Profile timezone "$normalizedName" is invalid.',
    );
  }
}

DateTime profileDateTimeFromComponents({
  required int year,
  required int month,
  required int day,
  required int hour,
  required int minute,
  required String timezoneName,
}) {
  initializeProfileTimeZones();
  final normalizedName = timezoneName.trim();
  if (normalizedName.isEmpty) {
    throw const ProfileTimezoneException('Profile timezone is missing.');
  }
  try {
    final location = timezone.getLocation(normalizedName);
    final wallMilliseconds =
        DateTime.utc(year, month, day, hour, minute).millisecondsSinceEpoch;
    final offsets = location.zones.map((zone) => zone.offset).toSet();
    final candidates = <int, timezone.TZDateTime>{};
    for (final offset in offsets) {
      final candidate = timezone.TZDateTime.fromMillisecondsSinceEpoch(
        location,
        wallMilliseconds - offset,
      );
      if (candidate.year == year &&
          candidate.month == month &&
          candidate.day == day &&
          candidate.hour == hour &&
          candidate.minute == minute) {
        candidates[candidate.millisecondsSinceEpoch] = candidate;
      }
    }
    if (candidates.isEmpty) {
      throw const ProfileTimezoneException(
        'The selected profile-local time does not exist.',
      );
    }
    if (candidates.length > 1) {
      throw const ProfileTimezoneException(
        'The selected profile-local time is ambiguous.',
      );
    }
    return candidates.values.single;
  } on timezone.LocationNotFoundException {
    throw ProfileTimezoneException(
      'Profile timezone "$normalizedName" is invalid.',
    );
  }
}

String profileLocalDateKey({
  required DateTime instant,
  required String timezoneName,
}) {
  final localDate = profileDateAt(
    instant: instant,
    timezoneName: timezoneName,
  );
  final month = localDate.month.toString().padLeft(2, '0');
  final day = localDate.day.toString().padLeft(2, '0');
  return '${localDate.year}-$month-$day';
}

class ProfileTimezoneException implements Exception {
  const ProfileTimezoneException(this.message);

  final String message;

  @override
  String toString() => 'ProfileTimezoneException: $message';
}
