import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/quick_action/domain/habit_v1.dart';

void main() {
  group('Habit V1 enums', () {
    test('cadence and outcome parsers accept only exact known codes', () {
      for (final kind in HabitCadenceKind.values) {
        expect(HabitCadenceKind.fromCode(kind.code), kind);
      }
      for (final outcome in HabitOutcome.values) {
        expect(HabitOutcome.fromCode(outcome.code), outcome);
      }

      expect(HabitCadenceKind.fromCode('DAILY'), isNull);
      expect(HabitCadenceKind.fromCode('monthly'), isNull);
      expect(HabitCadenceKind.fromCode(null), isNull);
      expect(HabitOutcome.fromCode('COMPLETED'), isNull);
      expect(HabitOutcome.fromCode('open'), isNull);
      expect(HabitOutcome.fromCode(null), isNull);
    });
  });

  group('HabitCadence validation and projection', () {
    test('daily has a stable compatibility projection and schedule', () {
      final cadence = HabitCadence.daily();

      expect(cadence.kind, HabitCadenceKind.daily);
      expect(cadence.weeklyTarget, 1);
      expect(cadence.scheduledWeekdays, isEmpty);
      expect(cadence.compatibilityFrequency, 'daily');
      expect(cadence.compatibilityTarget, 1);
      expect(cadence.metadataProjection, {
        'contract_version': 'habit-v1',
        'cadence': 'daily',
      });
      expect(cadence.label, 'Daily');
      for (var day = 6; day <= 12; day++) {
        expect(cadence.isScheduledOn(DateTime(2026, 7, day)), isTrue);
      }
    });

    test('weekdays deduplicate, sort, label, and schedule selected days', () {
      final input = <int>[7, 1, 3, 1];
      final cadence = HabitCadence.weekdays(input);

      input
        ..clear()
        ..add(2);

      expect(cadence.kind, HabitCadenceKind.weekdays);
      expect(cadence.weeklyTarget, 1);
      expect(cadence.scheduledWeekdays, {1, 3, 7});
      expect(cadence.compatibilityFrequency, 'daily');
      expect(cadence.compatibilityTarget, 1);
      expect(cadence.metadataProjection, {
        'contract_version': 'habit-v1',
        'cadence': 'weekdays',
        'scheduled_weekdays': [1, 3, 7],
      });
      expect(cadence.label, 'On Mon, Wed, Sun');
      expect(cadence.isScheduledOn(DateTime(2026, 7, 6)), isTrue);
      expect(cadence.isScheduledOn(DateTime(2026, 7, 7)), isFalse);
      expect(cadence.isScheduledOn(DateTime(2026, 7, 8)), isTrue);
      expect(cadence.isScheduledOn(DateTime(2026, 7, 12)), isTrue);
    });

    test('weekdays accept one through seven unique ISO weekdays', () {
      for (var count = 1; count <= 7; count++) {
        final weekdays = [for (var day = 1; day <= count; day++) day];
        expect(() => HabitCadence.weekdays(weekdays), returnsNormally);
      }
    });

    test('weekdays reject empty and out-of-range selections', () {
      for (final weekdays in <List<int>>[
        [],
        [0],
        [8],
        [-1, 1],
        [1, 7, 9],
      ]) {
        expect(
          () => HabitCadence.weekdays(weekdays),
          throwsA(isA<HabitContractException>()),
          reason: '$weekdays is not an ISO-weekday selection',
        );
      }
    });

    test('weekly targets one through seven have stable projections', () {
      for (var target = 1; target <= 7; target++) {
        final cadence = HabitCadence.weeklyTarget(target);

        expect(cadence.kind, HabitCadenceKind.weeklyTarget);
        expect(cadence.weeklyTarget, target);
        expect(cadence.scheduledWeekdays, isEmpty);
        expect(cadence.compatibilityFrequency, 'weekly');
        expect(cadence.compatibilityTarget, target);
        expect(cadence.metadataProjection, {
          'contract_version': 'habit-v1',
          'cadence': 'weekly_target',
        });
        expect(cadence.label, '$target times per week');
        expect(cadence.isScheduledOn(DateTime(2026, 7, 6)), isTrue);
      }
    });

    test('weekly targets reject values outside one through seven', () {
      for (final target in [-1, 0, 8, 100]) {
        expect(
          () => HabitCadence.weeklyTarget(target),
          throwsA(isA<HabitContractException>()),
        );
      }
    });

    test('scheduled weekdays are immutable', () {
      final cadence = HabitCadence.weekdays([1, 3, 5]);

      expect(
        () => cadence.scheduledWeekdays.add(2),
        throwsUnsupportedError,
      );
    });
  });

  group('HabitCadence persistence', () {
    test('round-trips every typed cadence through persistence fields', () {
      final cadences = [
        HabitCadence.daily(),
        HabitCadence.weekdays([5, 1, 3]),
        HabitCadence.weeklyTarget(4),
      ];

      for (final original in cadences) {
        final parsed = HabitCadence.fromPersistence(
          frequency: original.compatibilityFrequency,
          target: original.compatibilityTarget,
          metadata: original.metadataProjection,
        );

        expect(parsed.kind, original.kind);
        expect(parsed.weeklyTarget, original.weeklyTarget);
        expect(parsed.scheduledWeekdays, original.scheduledWeekdays);
        expect(parsed.metadataProjection, original.metadataProjection);
      }
    });

    test('reads legacy daily and weekly compatibility fields', () {
      final daily = HabitCadence.fromPersistence(
        frequency: 'daily',
        target: 1,
        metadata: null,
      );
      final missingFrequency = HabitCadence.fromPersistence(
        frequency: null,
        target: null,
        metadata: null,
      );
      final weekly = HabitCadence.fromPersistence(
        frequency: 'weekly',
        target: 3,
        metadata: const {},
      );

      expect(daily.kind, HabitCadenceKind.daily);
      expect(missingFrequency.kind, HabitCadenceKind.daily);
      expect(weekly.kind, HabitCadenceKind.weeklyTarget);
      expect(weekly.weeklyTarget, 3);
    });

    test('typed cadence takes precedence over legacy compatibility fields', () {
      final daily = HabitCadence.fromPersistence(
        frequency: 'weekly',
        target: 7,
        metadata: const {
          'contract_version': 'habit-v1',
          'cadence': 'daily',
        },
      );
      final weekdays = HabitCadence.fromPersistence(
        frequency: 'weekly',
        target: 7,
        metadata: const {
          'contract_version': 'habit-v1',
          'cadence': 'weekdays',
          'scheduled_weekdays': [5, 1, 3],
        },
      );

      expect(daily.kind, HabitCadenceKind.daily);
      expect(weekdays.kind, HabitCadenceKind.weekdays);
      expect(weekdays.scheduledWeekdays, {1, 3, 5});
    });

    test('rejects malformed typed weekday persistence', () {
      for (final weekdays in <Object?>[
        null,
        '1,3,5',
        <Object>[],
        <Object>[0],
        <Object>[8],
        <Object>[1.5],
        <Object>['1'],
        <Object>[true],
      ]) {
        expect(
          () => HabitCadence.fromPersistence(
            frequency: 'daily',
            target: 1,
            metadata: {
              'contract_version': 'habit-v1',
              'cadence': 'weekdays',
              'scheduled_weekdays': weekdays,
            },
          ),
          throwsA(isA<HabitContractException>()),
          reason: '$weekdays must not become a weekday cadence',
        );
      }
    });

    test('rejects malformed weekly targets from typed and legacy rows', () {
      for (final target in <Object?>[
        null,
        0,
        8,
        2.5,
        '3',
        true,
      ]) {
        for (final metadata in <Object?>[
          const {
            'contract_version': 'habit-v1',
            'cadence': 'weekly_target',
          },
          null,
        ]) {
          expect(
            () => HabitCadence.fromPersistence(
              frequency: 'weekly',
              target: target,
              metadata: metadata,
            ),
            throwsA(isA<HabitContractException>()),
            reason: '$target must not become a weekly target',
          );
        }
      }
    });

    test('rejects typed cadence metadata with an unsupported contract', () {
      expect(
        () => HabitCadence.fromPersistence(
          frequency: 'daily',
          target: 1,
          metadata: const {
            'contract_version': 'habit-v2',
            'cadence': 'weekdays',
            'scheduled_weekdays': [1, 3, 5],
          },
        ),
        throwsA(isA<HabitContractException>()),
      );
    });
  });

  group('HabitV1 daily and weekday progress', () {
    test('daily distinguishes complete, skip, miss, and current open', () {
      final habit = _habit(
        createdAt: DateTime(2026, 6, 1),
        logs: [
          _log(2026, 7, 6, HabitOutcome.completed),
          _log(2026, 7, 7, HabitOutcome.skipped),
          _log(2026, 7, 9, HabitOutcome.completed),
        ],
      );

      final progress = habit.progressAt(DateTime(2026, 7, 11, 23, 30));

      expect(progress.completed, 2);
      expect(progress.target, 6);
      expect(progress.skipped, 1);
      expect(progress.missed, 2);
      expect(progress.open, 1);
      expect(progress.streak, 0);
      expect(progress.ratio, closeTo(1 / 3, 0.000001));
      expect(progress.label, '2/6');
    });

    test('weekday progress counts only elapsed selected opportunities', () {
      final habit = _habit(
        cadence: HabitCadence.weekdays([1, 3, 5]),
        createdAt: DateTime(2026, 6, 1),
        logs: [
          _log(2026, 7, 6, HabitOutcome.completed),
          _log(2026, 7, 8, HabitOutcome.skipped),
          _log(2026, 7, 9, HabitOutcome.completed),
        ],
      );

      final progress = habit.progressAt(DateTime(2026, 7, 11));

      expect(progress.completed, 1);
      expect(progress.target, 3);
      expect(progress.skipped, 1);
      expect(progress.missed, 1);
      expect(progress.open, 0);
      expect(progress.label, '1/3');
    });

    test('creation date excludes earlier opportunities and outcomes', () {
      final habit = _habit(
        createdAt: DateTime(2026, 7, 8, 18),
        logs: [
          _log(2026, 7, 6, HabitOutcome.completed),
          _log(2026, 7, 7, HabitOutcome.skipped),
          _log(2026, 7, 8, HabitOutcome.completed),
          _log(2026, 7, 10, HabitOutcome.skipped),
        ],
      );

      final progress = habit.progressAt(DateTime(2026, 7, 11));

      expect(progress.completed, 1);
      expect(progress.target, 4);
      expect(progress.skipped, 1);
      expect(progress.missed, 1);
      expect(progress.open, 1);
    });

    test('a future creation date has no elapsed opportunities', () {
      final progress = _habit(
        createdAt: DateTime(2026, 7, 12),
      ).progressAt(DateTime(2026, 7, 11));

      expect(progress.completed, 0);
      expect(progress.target, 0);
      expect(progress.skipped, 0);
      expect(progress.missed, 0);
      expect(progress.open, 0);
      expect(progress.streak, 0);
      expect(progress.ratio, 0);
    });

    test('progress resets at the ISO-week boundary', () {
      final habit = _habit(
        createdAt: DateTime(2026, 6, 1),
        logs: [
          _log(2026, 7, 4, HabitOutcome.completed),
          _log(2026, 7, 5, HabitOutcome.completed),
        ],
      );

      final progress = habit.progressAt(DateTime(2026, 7, 6));

      expect(progress.completed, 0);
      expect(progress.target, 1);
      expect(progress.skipped, 0);
      expect(progress.missed, 0);
      expect(progress.open, 1);
      expect(progress.streak, 2);
    });
  });

  group('HabitV1 weekly-target progress', () {
    test('counts completed dates, skips, and remaining target this ISO week',
        () {
      final habit = _habit(
        cadence: HabitCadence.weeklyTarget(3),
        createdAt: DateTime(2026, 6, 1),
        logs: [
          _log(2026, 7, 6, HabitOutcome.completed),
          _log(2026, 7, 7, HabitOutcome.skipped),
          _log(2026, 7, 8, HabitOutcome.completed),
        ],
      );

      final progress = habit.progressAt(DateTime(2026, 7, 9));

      expect(progress.completed, 2);
      expect(progress.target, 3);
      expect(progress.skipped, 1);
      expect(progress.missed, 0);
      expect(progress.open, 1);
      expect(progress.streak, 0);
      expect(progress.label, '2/3');
    });

    test('creation date excludes earlier weekly outcomes', () {
      final habit = _habit(
        cadence: HabitCadence.weeklyTarget(3),
        createdAt: DateTime(2026, 7, 8, 18),
        logs: [
          _log(2026, 7, 6, HabitOutcome.completed),
          _log(2026, 7, 7, HabitOutcome.completed),
          _log(2026, 7, 8, HabitOutcome.completed),
          _log(2026, 7, 9, HabitOutcome.skipped),
        ],
      );

      final progress = habit.progressAt(DateTime(2026, 7, 9));

      expect(progress.completed, 1);
      expect(progress.target, 3);
      expect(progress.skipped, 1);
      expect(progress.missed, 0);
      expect(progress.open, 2);
      expect(progress.streak, 0);
    });

    test('counts distinct completion dates instead of duplicate log objects',
        () {
      final habit = _habit(
        cadence: HabitCadence.weeklyTarget(2),
        createdAt: DateTime(2026, 6, 1),
        logs: [
          _log(2026, 7, 6, HabitOutcome.completed),
          _log(2026, 7, 6, HabitOutcome.completed),
        ],
      );

      final progress = habit.progressAt(DateTime(2026, 7, 8));

      expect(progress.completed, 1);
      expect(progress.open, 1);
      expect(progress.streak, 0);
    });

    test('resets current progress on Monday and preserves prior streak', () {
      final habit = _habit(
        cadence: HabitCadence.weeklyTarget(2),
        createdAt: DateTime(2026, 6, 1),
        logs: [
          _log(2026, 7, 1, HabitOutcome.completed),
          _log(2026, 7, 3, HabitOutcome.completed),
        ],
      );

      final progress = habit.progressAt(DateTime(2026, 7, 6));

      expect(progress.completed, 0);
      expect(progress.target, 2);
      expect(progress.open, 2);
      expect(progress.streak, 1);
    });
  });

  group('HabitV1 streaks', () {
    test('current scheduled open preserves the historical daily streak', () {
      final habit = _habit(
        createdAt: DateTime(2026, 6, 1),
        logs: [
          _log(2026, 7, 9, HabitOutcome.skipped),
          _log(2026, 7, 10, HabitOutcome.completed),
          _log(2026, 7, 11, HabitOutcome.completed),
        ],
      );

      expect(habit.progressAt(DateTime(2026, 7, 12)).streak, 2);
    });

    test('current completion advances and current skip breaks a streak', () {
      final completedToday = _habit(
        createdAt: DateTime(2026, 6, 1),
        logs: [
          _log(2026, 7, 10, HabitOutcome.completed),
          _log(2026, 7, 11, HabitOutcome.completed),
          _log(2026, 7, 12, HabitOutcome.completed),
        ],
      );
      final skippedToday = _habit(
        createdAt: DateTime(2026, 6, 1),
        logs: [
          _log(2026, 7, 10, HabitOutcome.completed),
          _log(2026, 7, 11, HabitOutcome.completed),
          _log(2026, 7, 12, HabitOutcome.skipped),
        ],
      );

      expect(completedToday.progressAt(DateTime(2026, 7, 12)).streak, 3);
      expect(skippedToday.progressAt(DateTime(2026, 7, 12)).streak, 0);
    });

    test('a historical open or missed opportunity breaks the streak', () {
      final habit = _habit(
        createdAt: DateTime(2026, 6, 1),
        logs: [
          _log(2026, 7, 9, HabitOutcome.completed),
          _log(2026, 7, 11, HabitOutcome.completed),
        ],
      );

      expect(habit.progressAt(DateTime(2026, 7, 12)).streak, 1);
    });

    test('unscheduled current days preserve selected-weekday streaks', () {
      final habit = _habit(
        cadence: HabitCadence.weekdays([1, 3, 5]),
        createdAt: DateTime(2026, 6, 1),
        logs: [
          _log(2026, 7, 6, HabitOutcome.completed),
          _log(2026, 7, 8, HabitOutcome.completed),
          _log(2026, 7, 10, HabitOutcome.completed),
        ],
      );

      expect(habit.progressAt(DateTime(2026, 7, 11)).streak, 3);
    });

    test('an open current weekly target preserves completed prior weeks', () {
      final habit = _habit(
        cadence: HabitCadence.weeklyTarget(2),
        createdAt: DateTime(2026, 6, 1),
        logs: [
          _log(2026, 6, 23, HabitOutcome.completed),
          _log(2026, 6, 25, HabitOutcome.completed),
          _log(2026, 7, 1, HabitOutcome.completed),
          _log(2026, 7, 3, HabitOutcome.completed),
          _log(2026, 7, 6, HabitOutcome.completed),
        ],
      );

      expect(habit.progressAt(DateTime(2026, 7, 8)).streak, 2);
    });

    test('an unmet weekly target becomes historical at Sunday close', () {
      final habit = _habit(
        cadence: HabitCadence.weeklyTarget(2),
        createdAt: DateTime(2026, 6, 1),
        logs: [
          _log(2026, 7, 1, HabitOutcome.completed),
          _log(2026, 7, 3, HabitOutcome.completed),
          _log(2026, 7, 6, HabitOutcome.completed),
        ],
      );

      expect(habit.progressAt(DateTime(2026, 7, 12)).streak, 0);
    });

    test('future outcomes cannot satisfy the current weekly streak', () {
      final habit = _habit(
        cadence: HabitCadence.weeklyTarget(2),
        createdAt: DateTime(2026, 6, 1),
        logs: [
          _log(2026, 7, 6, HabitOutcome.completed),
          _log(2026, 7, 12, HabitOutcome.completed),
        ],
      );

      expect(habit.progressAt(DateTime(2026, 7, 8)).streak, 0);
    });
  });

  group('Habit calendar dates across Europe/Berlin DST boundaries', () {
    test('spring-forward keeps consecutive local calendar dates', () {
      final transitionDay = habitDateOnly(DateTime(2026, 3, 29, 12));
      final nextDay = habitAddCalendarDays(transitionDay, 1);

      expect(habitDateKey(transitionDay), '2026-03-29');
      expect(habitDateKey(nextDay), '2026-03-30');
      expect(habitCalendarDayDifference(nextDay, transitionDay), 1);
      expect(habitAddCalendarDays(nextDay, -1), transitionDay);

      if (transitionDay.timeZoneOffset == const Duration(hours: 1) &&
          nextDay.timeZoneOffset == const Duration(hours: 2)) {
        expect(nextDay.difference(transitionDay), const Duration(hours: 23));
      }
    });

    test('fall-back keeps consecutive local calendar dates', () {
      final transitionDay = habitDateOnly(DateTime(2026, 10, 25, 12));
      final nextDay = habitAddCalendarDays(transitionDay, 1);

      expect(habitDateKey(transitionDay), '2026-10-25');
      expect(habitDateKey(nextDay), '2026-10-26');
      expect(habitCalendarDayDifference(nextDay, transitionDay), 1);
      expect(habitAddCalendarDays(nextDay, -1), transitionDay);

      if (transitionDay.timeZoneOffset == const Duration(hours: 2) &&
          nextDay.timeZoneOffset == const Duration(hours: 1)) {
        expect(nextDay.difference(transitionDay), const Duration(hours: 25));
      }
    });

    test('scheduled opportunities count dates on both transition weekends', () {
      final cases = [
        (
          startedOn: '2026-03-27',
          today: DateTime(2026, 3, 29, 23, 30),
          dates: [(2026, 3, 27), (2026, 3, 28), (2026, 3, 29)],
        ),
        (
          startedOn: '2026-10-23',
          today: DateTime(2026, 10, 25, 23, 30),
          dates: [(2026, 10, 23), (2026, 10, 24), (2026, 10, 25)],
        ),
      ];

      for (final entry in cases) {
        final habit = _habit(
          cadence: HabitCadence.weekdays([
            DateTime.friday,
            DateTime.saturday,
            DateTime.sunday,
          ]),
          createdAt: entry.today,
          metadata: {'started_on': entry.startedOn},
          logs: [
            for (final date in entry.dates)
              _log(date.$1, date.$2, date.$3, HabitOutcome.completed),
          ],
        );

        final progress = habit.progressAt(entry.today);

        expect(progress.completed, 3, reason: entry.startedOn);
        expect(progress.target, 3, reason: entry.startedOn);
        expect(progress.skipped, 0, reason: entry.startedOn);
        expect(progress.missed, 0, reason: entry.startedOn);
        expect(progress.open, 0, reason: entry.startedOn);
        expect(progress.streak, 3, reason: entry.startedOn);
      }
    });
  });

  group('HabitV1 outcome, lifecycle, and immutability', () {
    test('outcome lookup uses the local date and latest durable outcome', () {
      final habit = _habit(
        logs: [
          _log(2026, 7, 11, HabitOutcome.completed),
          HabitLogEntry(
            entryDate: DateTime(2026, 7, 11, 23, 59),
            outcome: HabitOutcome.skipped,
          ),
        ],
      );

      expect(
        habit.outcomeOn(DateTime(2026, 7, 11, 8)),
        HabitOutcome.skipped,
      );
      expect(habit.outcomeOn(DateTime(2026, 7, 12)), isNull);
    });

    test('relevance requires active lifecycle and a scheduled date', () {
      final monday = DateTime(2026, 7, 6);
      final tuesday = DateTime(2026, 7, 7);
      final cadence = HabitCadence.weekdays([1]);

      expect(_habit(cadence: cadence).isRelevantOn(monday), isTrue);
      expect(_habit(cadence: cadence).isRelevantOn(tuesday), isFalse);
      expect(
        _habit(
          cadence: cadence,
          lifecycle: HabitLifecycle.paused,
        ).isRelevantOn(monday),
        isFalse,
      );
      expect(
        _habit(
          cadence: cadence,
          lifecycle: HabitLifecycle.archived,
        ).isRelevantOn(monday),
        isFalse,
      );
      expect(
        _habit(cadence: HabitCadence.weeklyTarget(3)).isRelevantOn(tuesday),
        isTrue,
      );
    });

    test('maps active, paused, and archived persistence states', () {
      expect(
        habitLifecycleFromPersistence(active: true, metadata: null),
        HabitLifecycle.active,
      );
      expect(
        habitLifecycleFromPersistence(active: false, metadata: null),
        HabitLifecycle.paused,
      );
      expect(
        habitLifecycleFromPersistence(
          active: true,
          metadata: const {'lifecycle': 'paused'},
        ),
        HabitLifecycle.paused,
      );
      expect(
        habitLifecycleFromPersistence(
          active: false,
          metadata: const {'lifecycle': 'active'},
        ),
        HabitLifecycle.paused,
      );
      expect(
        habitLifecycleFromPersistence(
          active: true,
          metadata: const {'setup_state': 'archived'},
        ),
        HabitLifecycle.archived,
      );
      expect(
        habitLifecycleFromPersistence(
          active: true,
          metadata: const {'lifecycle': 'archived'},
        ),
        HabitLifecycle.archived,
      );
    });

    test('setup candidate and paused states are never active', () {
      for (final setupState in ['candidate', 'paused']) {
        for (final active in [false, true]) {
          expect(
            habitLifecycleFromPersistence(
              active: active,
              metadata: {'setup_state': setupState},
            ),
            HabitLifecycle.paused,
            reason: '$setupState must not become executable',
          );
        }
      }
    });

    test('trims title and rejects blank identity', () {
      final habit = _habit(title: '  Read  ');

      expect(habit.title, 'Read');
      expect(
        () => _habit(id: '   '),
        throwsA(isA<HabitContractException>()),
      );
      expect(
        () => _habit(title: '   '),
        throwsA(isA<HabitContractException>()),
      );
    });

    test('metadata and logs are defensive immutable copies', () {
      final metadata = <String, dynamic>{'source': 'manual'};
      final logs = <HabitLogEntry>[
        _log(2026, 7, 11, HabitOutcome.completed),
      ];
      final habit = _habit(metadata: metadata, logs: logs);

      metadata['source'] = 'mutated';
      logs.clear();

      expect(habit.metadata, {'source': 'manual'});
      expect(habit.logs, hasLength(1));
      expect(
        () => habit.metadata['source'] = 'mutated',
        throwsUnsupportedError,
      );
      expect(
        () => habit.logs.add(_log(2026, 7, 12, HabitOutcome.skipped)),
        throwsUnsupportedError,
      );
    });

    test('date helpers preserve local calendar identity', () {
      final value = DateTime(2026, 7, 3, 23, 59, 58);

      expect(habitDateOnly(value), DateTime(2026, 7, 3));
      expect(habitDateKey(value), '2026-07-03');
    });

    test('zero-target progress ratio is stable and completion is capped', () {
      const empty = HabitProgress(
        completed: 0,
        target: 0,
        skipped: 0,
        missed: 0,
        open: 0,
        streak: 0,
      );
      const overTarget = HabitProgress(
        completed: 4,
        target: 3,
        skipped: 0,
        missed: 0,
        open: 0,
        streak: 1,
      );

      expect(empty.ratio, 0);
      expect(empty.label, '0/0');
      expect(overTarget.ratio, 1);
    });
  });
}

HabitV1 _habit({
  String id = 'habit-123',
  String title = 'Read',
  HabitCadence? cadence,
  HabitLifecycle lifecycle = HabitLifecycle.active,
  DateTime? createdAt,
  DateTime? updatedAt,
  bool isSetupManaged = false,
  Map<String, dynamic>? metadata,
  Iterable<HabitLogEntry> logs = const [],
}) =>
    HabitV1(
      id: id,
      title: title,
      cadence: cadence ?? HabitCadence.daily(),
      lifecycle: lifecycle,
      createdAt: createdAt ?? DateTime(2026, 6, 1),
      updatedAt: updatedAt ?? DateTime(2026, 7, 11),
      isSetupManaged: isSetupManaged,
      metadata: metadata ?? const {},
      logs: logs,
    );

HabitLogEntry _log(
  int year,
  int month,
  int day,
  HabitOutcome outcome,
) =>
    HabitLogEntry(
      entryDate: DateTime(year, month, day),
      outcome: outcome,
    );
