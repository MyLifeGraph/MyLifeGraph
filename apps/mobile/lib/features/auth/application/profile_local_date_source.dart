import '../../../core/time/profile_timezone.dart';
import '../domain/app_session.dart';

typedef CurrentInstantProvider = DateTime Function();
typedef ProfileDateResolver = DateTime Function({
  required DateTime instant,
  required String timezoneName,
});

abstract interface class ProfileLocalDateSource {
  DateTime dateAt(DateTime instant);

  String dateKeyAt(DateTime instant);

  DateTime today();

  String todayKey();
}

class SessionProfileLocalDateSource implements ProfileLocalDateSource {
  const SessionProfileLocalDateSource({
    required AppSession? session,
    CurrentInstantProvider currentInstant = DateTime.now,
    ProfileDateResolver profileDateResolver = profileDateAt,
  })  : _session = session,
        _currentInstant = currentInstant,
        _profileDateResolver = profileDateResolver;

  final AppSession? _session;
  final CurrentInstantProvider _currentInstant;
  final ProfileDateResolver _profileDateResolver;

  @override
  DateTime dateAt(DateTime instant) {
    final session = _session;
    if (session == null || session.isGuestSession) {
      final local = instant.toLocal();
      return DateTime(local.year, local.month, local.day);
    }
    return _profileDateResolver(
      instant: instant,
      timezoneName: session.profile.timezone,
    );
  }

  @override
  String dateKeyAt(DateTime instant) => _dateKey(dateAt(instant));

  @override
  DateTime today() => dateAt(_currentInstant());

  @override
  String todayKey() => _dateKey(today());

  String _dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
