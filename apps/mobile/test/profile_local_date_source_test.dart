import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/time/profile_timezone.dart';
import 'package:my_life_graph/features/auth/application/profile_local_date_source.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';

void main() {
  group('profile local date', () {
    test('resolves one instant to each authenticated profile calendar', () {
      final instant = DateTime.utc(2026, 7, 10, 23, 30);

      expect(
        profileDateAt(
          instant: instant,
          timezoneName: 'Europe/Berlin',
        ),
        DateTime(2026, 7, 11),
      );
      expect(
        profileDateAt(
          instant: instant,
          timezoneName: 'America/Los_Angeles',
        ),
        DateTime(2026, 7, 10),
      );
    });

    test('keeps date conversion correct across both DST transitions', () {
      expect(
        profileDateAt(
          instant: DateTime.utc(2026, 3, 29, 22, 30),
          timezoneName: 'Europe/Berlin',
        ),
        DateTime(2026, 3, 30),
      );
      expect(
        profileDateAt(
          instant: DateTime.utc(2026, 10, 25, 23, 30),
          timezoneName: 'Europe/Berlin',
        ),
        DateTime(2026, 10, 26),
      );
    });

    test('builds profile-local instants and rejects DST gaps and folds', () {
      final value = profileDateTimeFromComponents(
        year: 2026,
        month: 7,
        day: 20,
        hour: 9,
        minute: 15,
        timezoneName: 'Europe/Berlin',
      );
      expect(value.toUtc(), DateTime.utc(2026, 7, 20, 7, 15));

      expect(
        () => profileDateTimeFromComponents(
          year: 2026,
          month: 3,
          day: 29,
          hour: 2,
          minute: 30,
          timezoneName: 'Europe/Berlin',
        ),
        throwsA(isA<ProfileTimezoneException>()),
      );
      expect(
        () => profileDateTimeFromComponents(
          year: 2026,
          month: 10,
          day: 25,
          hour: 2,
          minute: 30,
          timezoneName: 'Europe/Berlin',
        ),
        throwsA(
          isA<ProfileTimezoneException>().having(
            (error) => error.message,
            'message',
            contains('ambiguous'),
          ),
        ),
      );
    });

    test('authenticated invalid timezone fails instead of using device date',
        () {
      final source = SessionProfileLocalDateSource(
        session: AppSession.authenticated(
          _profile(timezone: 'Not/A_Timezone'),
        ),
        currentInstant: () => DateTime.utc(2026, 7, 10, 23, 30),
      );

      expect(source.today, throwsA(isA<ProfileTimezoneException>()));
    });

    test('exposes only the authenticated profile timezone', () {
      final authenticated = SessionProfileLocalDateSource(
        session: AppSession.authenticated(
          _profile(timezone: 'Europe/Berlin'),
        ),
      );
      final guest = SessionProfileLocalDateSource(
        session: AppSession.guest(_profile(timezone: 'device-local')),
      );

      expect(authenticated.timezoneName, 'Europe/Berlin');
      expect(guest.timezoneName, isNull);
      expect(
        const SessionProfileLocalDateSource(session: null).timezoneName,
        isNull,
      );
    });

    test('guest explicitly keeps the device-local calendar behavior', () {
      final instant = DateTime.utc(2026, 7, 10, 23, 30);
      final source = SessionProfileLocalDateSource(
        session: AppSession.guest(_profile(timezone: 'device-local')),
        currentInstant: () => instant,
      );
      final local = instant.toLocal();

      expect(source.today(), DateTime(local.year, local.month, local.day));
    });

    test('today captures the current instant only once', () {
      var clockCalls = 0;
      final source = SessionProfileLocalDateSource(
        session: AppSession.authenticated(
          _profile(timezone: 'Europe/Berlin'),
        ),
        currentInstant: () {
          clockCalls += 1;
          return DateTime.utc(2026, 7, 10, 23, 30);
        },
      );

      expect(source.todayKey(), '2026-07-11');
      expect(clockCalls, 1);
    });
  });
}

AppProfile _profile({required String timezone}) => AppProfile(
      id: '10000000-0000-4000-8000-000000000001',
      email: 'student@example.com',
      name: 'Student',
      timezone: timezone,
      role: AppRole.user,
      onboardingDone: true,
      authProvider: 'email',
    );
