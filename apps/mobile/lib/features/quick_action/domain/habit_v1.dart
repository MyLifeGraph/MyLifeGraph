enum HabitCadenceKind {
  daily('daily'),
  weekdays('weekdays'),
  weeklyTarget('weekly_target');

  const HabitCadenceKind(this.code);

  final String code;

  static HabitCadenceKind? fromCode(Object? value) {
    for (final kind in values) {
      if (kind.code == value) {
        return kind;
      }
    }
    return null;
  }
}

enum HabitOutcome {
  completed('completed'),
  skipped('skipped');

  const HabitOutcome(this.code);

  final String code;

  static HabitOutcome? fromCode(Object? value) {
    for (final outcome in values) {
      if (outcome.code == value) {
        return outcome;
      }
    }
    return null;
  }
}

enum HabitLifecycle {
  active('active'),
  paused('paused'),
  archived('archived');

  const HabitLifecycle(this.code);

  final String code;
}

class HabitCadence {
  HabitCadence._({
    required this.kind,
    required this.weeklyTarget,
    required Set<int> scheduledWeekdays,
  }) : scheduledWeekdays = Set.unmodifiable(scheduledWeekdays) {
    _validate();
  }

  factory HabitCadence.daily() => HabitCadence._(
        kind: HabitCadenceKind.daily,
        weeklyTarget: 1,
        scheduledWeekdays: const {},
      );

  factory HabitCadence.weekdays(Iterable<int> weekdays) => HabitCadence._(
        kind: HabitCadenceKind.weekdays,
        weeklyTarget: 1,
        scheduledWeekdays: weekdays.toSet(),
      );

  factory HabitCadence.weeklyTarget(int target) => HabitCadence._(
        kind: HabitCadenceKind.weeklyTarget,
        weeklyTarget: target,
        scheduledWeekdays: const {},
      );

  factory HabitCadence.fromPersistence({
    required Object? frequency,
    required Object? target,
    required Object? metadata,
  }) {
    final map = _stringMap(metadata);
    if (map?['cadence'] != null && map?['contract_version'] != 'habit-v1') {
      throw const HabitContractException(
        'Habit cadence contract version is unsupported.',
      );
    }
    final contractKind = HabitCadenceKind.fromCode(map?['cadence']);
    if (contractKind == HabitCadenceKind.weekdays) {
      final rawWeekdays = map?['scheduled_weekdays'];
      if (rawWeekdays is! List) {
        throw const HabitContractException(
          'Scheduled-weekday cadence is malformed.',
        );
      }
      return HabitCadence.weekdays(
        rawWeekdays.map(_requiredInt),
      );
    }
    if (contractKind == HabitCadenceKind.weeklyTarget) {
      return HabitCadence.weeklyTarget(_positiveTarget(target));
    }
    if (contractKind == HabitCadenceKind.daily) {
      return HabitCadence.daily();
    }
    if (frequency == 'weekly') {
      return HabitCadence.weeklyTarget(_positiveTarget(target));
    }
    return HabitCadence.daily();
  }

  final HabitCadenceKind kind;
  final int weeklyTarget;
  final Set<int> scheduledWeekdays;

  String get compatibilityFrequency =>
      kind == HabitCadenceKind.weeklyTarget ? 'weekly' : 'daily';

  int get compatibilityTarget =>
      kind == HabitCadenceKind.weeklyTarget ? weeklyTarget : 1;

  Map<String, Object> get metadataProjection => {
        'contract_version': 'habit-v1',
        'cadence': kind.code,
        if (kind == HabitCadenceKind.weekdays)
          'scheduled_weekdays': scheduledWeekdays.toList()..sort(),
      };

  bool isScheduledOn(DateTime date) {
    return switch (kind) {
      HabitCadenceKind.daily => true,
      HabitCadenceKind.weekdays => scheduledWeekdays.contains(date.weekday),
      HabitCadenceKind.weeklyTarget => true,
    };
  }

  String get label {
    return switch (kind) {
      HabitCadenceKind.daily => 'Daily',
      HabitCadenceKind.weekdays =>
        'On ${(_sortedWeekdays().map(_weekdayLabel)).join(', ')}',
      HabitCadenceKind.weeklyTarget => '$weeklyTarget times per week',
    };
  }

  void _validate() {
    switch (kind) {
      case HabitCadenceKind.daily:
        if (weeklyTarget != 1 || scheduledWeekdays.isNotEmpty) {
          throw const HabitContractException('Daily cadence is invalid.');
        }
      case HabitCadenceKind.weekdays:
        if (weeklyTarget != 1 ||
            scheduledWeekdays.isEmpty ||
            scheduledWeekdays.length > 7 ||
            scheduledWeekdays.any((day) => day < 1 || day > 7)) {
          throw const HabitContractException(
            'Choose one to seven valid weekdays.',
          );
        }
      case HabitCadenceKind.weeklyTarget:
        if (weeklyTarget < 1 ||
            weeklyTarget > 7 ||
            scheduledWeekdays.isNotEmpty) {
          throw const HabitContractException(
            'Weekly target must be between one and seven.',
          );
        }
    }
  }

  List<int> _sortedWeekdays() => scheduledWeekdays.toList()..sort();

  static String _weekdayLabel(int weekday) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[weekday - 1];
  }

  static int _positiveTarget(Object? value) {
    final target = _requiredInt(value);
    if (target < 1 || target > 7) {
      throw const HabitContractException(
        'Weekly target must be between one and seven.',
      );
    }
    return target;
  }

  static int _requiredInt(Object? value) {
    if (value is num && value == value.toInt()) {
      return value.toInt();
    }
    throw const HabitContractException('Habit number is invalid.');
  }

  static Map<String, dynamic>? _stringMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(value);
  }
}

class HabitLogEntry {
  const HabitLogEntry({
    required this.entryDate,
    required this.outcome,
  });

  final DateTime entryDate;
  final HabitOutcome outcome;

  String get dateKey => habitDateKey(entryDate);
}

class HabitProgress {
  const HabitProgress({
    required this.completed,
    required this.target,
    required this.skipped,
    required this.missed,
    required this.open,
    required this.streak,
  });

  final int completed;
  final int target;
  final int skipped;
  final int missed;
  final int open;
  final int streak;

  double get ratio => target == 0 ? 0 : (completed / target).clamp(0, 1);

  String get label => '$completed/$target';
}

class HabitV1 {
  HabitV1({
    required this.id,
    required String title,
    required this.cadence,
    required this.lifecycle,
    required this.createdAt,
    required this.updatedAt,
    required this.isSetupManaged,
    required Map<String, dynamic> metadata,
    this.description,
    Iterable<HabitLogEntry> logs = const [],
  })  : title = title.trim(),
        metadata = Map.unmodifiable(metadata),
        logs = List.unmodifiable(logs) {
    if (id.trim().isEmpty || this.title.isEmpty) {
      throw const HabitContractException('Habit identity is invalid.');
    }
  }

  final String id;
  final String title;
  final String? description;
  final HabitCadence cadence;
  final HabitLifecycle lifecycle;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSetupManaged;
  final Map<String, dynamic> metadata;
  final List<HabitLogEntry> logs;

  bool get isActive => lifecycle == HabitLifecycle.active;

  HabitOutcome? outcomeOn(DateTime date) {
    final key = habitDateKey(date);
    for (final log in logs.reversed) {
      if (log.dateKey == key) {
        return log.outcome;
      }
    }
    return null;
  }

  bool isRelevantOn(DateTime date) {
    if (!isActive) {
      return false;
    }
    return cadence.kind == HabitCadenceKind.weeklyTarget ||
        cadence.isScheduledOn(date);
  }

  HabitProgress progressAt(DateTime today) {
    final localToday = habitDateOnly(today);
    final weekStart = habitAddCalendarDays(
      localToday,
      -(localToday.weekday - DateTime.monday),
    );
    final createdDate = _effectiveCreatedDate();
    final outcomes = {
      for (final log in logs) log.dateKey: log.outcome,
    };

    if (cadence.kind == HabitCadenceKind.weeklyTarget) {
      final currentOutcomes = <String, HabitOutcome>{};
      for (final log in logs) {
        final date = habitDateOnly(log.entryDate);
        if (!date.isBefore(weekStart) &&
            !date.isBefore(createdDate) &&
            !date.isAfter(localToday)) {
          currentOutcomes[habitDateKey(date)] = log.outcome;
        }
      }
      final completed = currentOutcomes.values
          .where((outcome) => outcome == HabitOutcome.completed)
          .length;
      final skipped = currentOutcomes.values
          .where((outcome) => outcome == HabitOutcome.skipped)
          .length;
      return HabitProgress(
        completed: completed,
        target: cadence.weeklyTarget,
        skipped: skipped,
        missed: 0,
        open: (cadence.weeklyTarget - completed).clamp(0, 7),
        streak: _weeklyStreak(
          today: localToday,
          createdDate: createdDate,
          logs: logs,
          weeklyTarget: cadence.weeklyTarget,
        ),
      );
    }

    final first = createdDate.isAfter(weekStart) ? createdDate : weekStart;
    final opportunities = <DateTime>[];
    for (var date = first;
        !date.isAfter(localToday);
        date = habitAddCalendarDays(date, 1)) {
      if (cadence.isScheduledOn(date)) {
        opportunities.add(date);
      }
    }
    var completed = 0;
    var skipped = 0;
    var missed = 0;
    var open = 0;
    for (final date in opportunities) {
      final outcome = outcomes[habitDateKey(date)];
      if (outcome == HabitOutcome.completed) {
        completed++;
      } else if (outcome == HabitOutcome.skipped) {
        skipped++;
      } else if (date == localToday) {
        open++;
      } else {
        missed++;
      }
    }
    return HabitProgress(
      completed: completed,
      target: opportunities.length,
      skipped: skipped,
      missed: missed,
      open: open,
      streak: _scheduledStreak(
        today: localToday,
        createdDate: createdDate,
        cadence: cadence,
        outcomes: outcomes,
      ),
    );
  }

  static int _scheduledStreak({
    required DateTime today,
    required DateTime createdDate,
    required HabitCadence cadence,
    required Map<String, HabitOutcome> outcomes,
  }) {
    var streak = 0;
    for (var date = today, scannedDays = 0;
        !date.isBefore(createdDate) && scannedDays <= 366;
        date = habitAddCalendarDays(date, -1), scannedDays++) {
      if (!cadence.isScheduledOn(date)) {
        continue;
      }
      final outcome = outcomes[habitDateKey(date)];
      if (date == today && outcome == null) {
        continue;
      }
      if (outcome != HabitOutcome.completed) {
        break;
      }
      streak++;
    }
    return streak;
  }

  DateTime _effectiveCreatedDate() {
    final startedOn = metadata['started_on'];
    if (startedOn is String &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(startedOn)) {
      final parsed = DateTime.tryParse(startedOn);
      if (parsed != null && habitDateKey(parsed) == startedOn) {
        return habitDateOnly(parsed);
      }
    }
    return habitDateOnly(createdAt.toLocal());
  }

  static int _weeklyStreak({
    required DateTime today,
    required DateTime createdDate,
    required List<HabitLogEntry> logs,
    required int weeklyTarget,
  }) {
    var weekStart = habitAddCalendarDays(
      today,
      -(today.weekday - DateTime.monday),
    );
    var streak = 0;
    for (var offset = 0; offset < 53; offset++) {
      final weekEnd = habitAddCalendarDays(weekStart, 6);
      if (weekEnd.isBefore(createdDate)) {
        break;
      }
      final isCurrentWeek = offset == 0;
      final completedDates = <String>{};
      for (final log in logs) {
        final date = habitDateOnly(log.entryDate);
        if (!date.isBefore(weekStart) &&
            !date.isAfter(weekEnd) &&
            !date.isBefore(createdDate) &&
            !date.isAfter(today) &&
            log.outcome == HabitOutcome.completed) {
          completedDates.add(habitDateKey(date));
        }
      }
      if (completedDates.length >= weeklyTarget) {
        streak++;
      } else if (!isCurrentWeek || today.weekday == DateTime.sunday) {
        break;
      }
      weekStart = habitAddCalendarDays(weekStart, -7);
    }
    return streak;
  }
}

HabitLifecycle habitLifecycleFromPersistence({
  required bool active,
  required Object? metadata,
}) {
  final map = metadata is Map ? Map<String, dynamic>.from(metadata) : null;
  final setupState = map?['setup_state']?.toString();
  final lifecycle = map?['lifecycle']?.toString();
  if (setupState == 'archived' || lifecycle == HabitLifecycle.archived.code) {
    return HabitLifecycle.archived;
  }
  if (!active ||
      setupState == 'candidate' ||
      setupState == 'paused' ||
      lifecycle == HabitLifecycle.paused.code) {
    return HabitLifecycle.paused;
  }
  return HabitLifecycle.active;
}

DateTime habitDateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime habitAddCalendarDays(DateTime value, int days) {
  final date = habitDateOnly(value);
  return DateTime(date.year, date.month, date.day + days);
}

int habitCalendarDayDifference(DateTime later, DateTime earlier) {
  final laterDay = DateTime.utc(later.year, later.month, later.day);
  final earlierDay = DateTime.utc(earlier.year, earlier.month, earlier.day);
  return laterDay.difference(earlierDay).inDays;
}

String habitDateKey(DateTime value) {
  final date = habitDateOnly(value);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

class HabitContractException implements Exception {
  const HabitContractException(this.message);

  final String message;

  @override
  String toString() => message;
}
