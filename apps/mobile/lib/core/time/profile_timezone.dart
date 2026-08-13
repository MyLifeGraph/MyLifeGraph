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
