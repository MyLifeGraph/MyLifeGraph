import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_full_week.dart';

void main() {
  group('DashboardFullWeekProjector', () {
    test('uses the displayed profile-local Monday-to-Sunday week', () {
      final projection = const DashboardFullWeekProjector().project(
        displayedLocalDate: DateTime(2026, 8, 5),
        commitments: const [
          DashboardSetupCommitmentFact(
            id: 'setup-late',
            title: 'Late seminar',
            weekday: DateTime.monday,
            startsAt: '15:00',
            endsAt: '16:00',
            sortMinutes: 900,
          ),
          DashboardSetupCommitmentFact(
            id: 'setup-early',
            title: 'Early seminar',
            weekday: DateTime.monday,
            startsAt: '09:00',
            endsAt: '10:00',
            sortMinutes: 540,
          ),
        ],
        preparationBlocks: const [
          DashboardPreparationBlockFact(
            id: 'block-open',
            planId: 'plan-1',
            planTitle: 'Algorithms',
            localDate: '2026-08-09',
            localStartTime: '11:00',
            localEndTime: '11:45',
            sortMinutes: 660,
            state: 'upcoming',
            recoveryMinutes: 15,
            reservedLocalEndTime: '12:00',
          ),
        ],
      );

      expect(projection.weekStartsOn, DateTime(2026, 8, 3));
      expect(projection.days, hasLength(7));
      expect(
        projection.days.map((day) => day.localDate),
        [for (var day = 3; day <= 9; day += 1) DateTime(2026, 8, day)],
      );
      expect(
        projection.days.first.items.map((item) => item.title),
        ['Early seminar', 'Late seminar'],
      );
      expect(projection.days[1].items, isEmpty);
      expect(projection.days.last.items.single.id, 'block-open');
      expect(
        projection.days.last.items.single.status,
        DashboardAppointmentStatus.open,
      );
      expect(
        projection.days.last.items.single.timeLabel,
        '11:00–11:45 focus + 15 min recovery · reserved until 12:00',
      );
    });

    test('honors inclusive profile-local Setup validity dates', () {
      final projection = const DashboardFullWeekProjector().project(
        displayedLocalDate: DateTime(2026, 7, 22),
        commitments: [
          DashboardSetupCommitmentFact(
            id: 'active-on-boundary',
            title: 'Active lecture',
            weekday: DateTime.wednesday,
            startsAt: '09:00',
            endsAt: '10:00',
            sortMinutes: 540,
            validFrom: DateTime(2026, 7, 22),
            validUntil: DateTime(2026, 7, 22),
          ),
          DashboardSetupCommitmentFact(
            id: 'expired',
            title: 'Expired lecture',
            weekday: DateTime.thursday,
            startsAt: '09:00',
            endsAt: '10:00',
            sortMinutes: 540,
            validUntil: DateTime(2026, 7, 22),
          ),
          DashboardSetupCommitmentFact(
            id: 'future',
            title: 'Future lecture',
            weekday: DateTime.tuesday,
            startsAt: '09:00',
            endsAt: '10:00',
            sortMinutes: 540,
            validFrom: DateTime(2026, 7, 29),
          ),
        ],
      );

      expect(
        projection.days.expand((day) => day.items).map((item) => item.id),
        ['active-on-boundary'],
      );
    });

    test('requires every exact associated terminal session to be rated', () {
      final projection = const DashboardFullWeekProjector().project(
        displayedLocalDate: DateTime(2026, 8, 5),
        preparationBlocks: const [
          DashboardPreparationBlockFact(
            id: 'fully-rated',
            planId: 'plan-1',
            planTitle: 'Algorithms',
            localDate: '2026-08-05',
            localStartTime: '09:00',
            localEndTime: '10:00',
            sortMinutes: 540,
            state: 'completed',
            recoveryMinutes: 0,
            reservedLocalEndTime: '10:00',
          ),
          DashboardPreparationBlockFact(
            id: 'missing-reflection',
            planId: 'plan-1',
            planTitle: 'Algorithms follow-up',
            localDate: '2026-08-05',
            localStartTime: '11:00',
            localEndTime: '12:00',
            sortMinutes: 660,
            state: 'completed',
            recoveryMinutes: 0,
            reservedLocalEndTime: '12:00',
          ),
          DashboardPreparationBlockFact(
            id: 'unrelated',
            planId: 'plan-2',
            planTitle: 'Unrelated block',
            localDate: '2026-08-05',
            localStartTime: '13:00',
            localEndTime: '14:00',
            sortMinutes: 780,
            state: 'completed',
            recoveryMinutes: 0,
            reservedLocalEndTime: '14:00',
          ),
        ],
        focusByBlock: const {
          'fully-rated': [
            DashboardBlockFocusFact(
              sessionId: 'session-1',
              terminal: true,
              hasValidReflection: true,
            ),
            DashboardBlockFocusFact(
              sessionId: 'session-2',
              terminal: true,
              hasValidReflection: true,
            ),
          ],
          'missing-reflection': [
            DashboardBlockFocusFact(
              sessionId: 'session-3',
              terminal: true,
              hasValidReflection: true,
            ),
            DashboardBlockFocusFact(
              sessionId: 'session-4',
              terminal: true,
              hasValidReflection: false,
            ),
          ],
          'different-block-id': [
            DashboardBlockFocusFact(
              sessionId: 'session-5',
              terminal: true,
              hasValidReflection: true,
            ),
          ],
        },
      );

      final statusById = {
        for (final item in projection.days[2].items) item.id: item.status,
      };
      expect(
        statusById['fully-rated'],
        DashboardAppointmentStatus.fullyRated,
      );
      expect(
        statusById['missing-reflection'],
        DashboardAppointmentStatus.completed,
      );
      expect(
        statusById['unrelated'],
        DashboardAppointmentStatus.completed,
      );
    });

    test('an active associated session prevents fully-rated status', () {
      final projection = const DashboardFullWeekProjector().project(
        displayedLocalDate: DateTime(2026, 8, 5),
        preparationBlocks: const [_completedBlock],
        focusByBlock: const {
          'block-completed': [
            DashboardBlockFocusFact(
              sessionId: 'terminal',
              terminal: true,
              hasValidReflection: true,
            ),
            DashboardBlockFocusFact(
              sessionId: 'active',
              terminal: false,
              hasValidReflection: false,
            ),
          ],
        },
      );

      expect(
        projection.days[2].items.single.status,
        DashboardAppointmentStatus.completed,
      );
    });

    test('rating failure retains official completion and reports local error',
        () {
      final projection = const DashboardFullWeekProjector().project(
        displayedLocalDate: DateTime(2026, 8, 5),
        preparationBlocks: const [_completedBlock],
        focusByBlock: const {
          'block-completed': [
            DashboardBlockFocusFact(
              sessionId: 'terminal',
              terminal: true,
              hasValidReflection: true,
            ),
          ],
        },
        ratingLoadError: 'Rating status unavailable.',
      );

      expect(projection.ratingStatusUnavailable, isTrue);
      expect(
        projection.days[2].items.single.status,
        DashboardAppointmentStatus.completed,
      );
    });

    test('date-only arithmetic stays consecutive across a DST week', () {
      final projection = DashboardFullWeekProjection.empty(
        DateTime(2026, 10, 25),
      );

      expect(projection.weekStartsOn, DateTime(2026, 10, 19));
      expect(projection.days.last.localDate, DateTime(2026, 10, 25));
      for (var index = 1; index < projection.days.length; index += 1) {
        final previous = projection.days[index - 1].localDate;
        final current = projection.days[index].localDate;
        expect(
          DateTime.utc(current.year, current.month, current.day)
              .difference(
                DateTime.utc(previous.year, previous.month, previous.day),
              )
              .inDays,
          1,
        );
      }
    });

    test('one-row sentinels reject oversized projections', () {
      expect(
        () => const DashboardFullWeekProjector().project(
          displayedLocalDate: DateTime(2026, 8, 5),
          commitments: List.filled(
            201,
            const DashboardSetupCommitmentFact(
              id: 'duplicate',
              title: 'Setup',
              weekday: DateTime.monday,
              startsAt: '09:00',
              endsAt: '10:00',
              sortMinutes: 540,
            ),
          ),
        ),
        throwsA(isA<DashboardFullWeekException>()),
      );
    });
  });
}

const _completedBlock = DashboardPreparationBlockFact(
  id: 'block-completed',
  planId: 'plan-1',
  planTitle: 'Algorithms',
  localDate: '2026-08-05',
  localStartTime: '09:00',
  localEndTime: '10:00',
  sortMinutes: 540,
  state: 'completed',
  recoveryMinutes: 0,
  reservedLocalEndTime: '10:00',
);
