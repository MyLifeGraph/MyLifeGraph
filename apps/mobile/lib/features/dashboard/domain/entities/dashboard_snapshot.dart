enum DashboardOrigin { localDemo, account }

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.origin,
    required this.loadedAt,
    required this.latestCheckIn,
    required this.checkInStreakDays,
    required this.todayPlan,
    required this.scheduleDays,
    this.preparationScheduleError,
    this.localDate,
    this.timezone,
    this.checkIns,
    this.progress,
    this.todayTasks = const [],
    this.timeline = const [],
    this.todayHabits = const [],
    this.sourceStates,
    this.isTodayOverview = false,
  });

  factory DashboardSnapshot.empty({
    required DashboardOrigin origin,
    required DateTime loadedAt,
  }) {
    return DashboardSnapshot(
      origin: origin,
      loadedAt: loadedAt,
      latestCheckIn: null,
      checkInStreakDays: 0,
      todayPlan: const [],
      scheduleDays: const [],
    );
  }

  final DashboardOrigin origin;
  final DateTime loadedAt;
  final DashboardCheckIn? latestCheckIn;
  final int checkInStreakDays;
  final List<PlanItem> todayPlan;
  final List<ScheduleDay> scheduleDays;
  final String? preparationScheduleError;
  final DateTime? localDate;
  final String? timezone;
  final TodayCheckIns? checkIns;
  final TodayProgress? progress;
  final List<PlanItem> todayTasks;
  final List<TodayTimelineItem> timeline;
  final List<TodayHabit> todayHabits;
  final TodaySourceStates? sourceStates;
  final bool isTodayOverview;

  List<PlanItem> get allTasks => todayPlan;
}

class TodayCheckIns {
  const TodayCheckIns({
    required this.morningSaved,
    required this.eveningSaved,
    required this.completedDaysStreak,
  });

  final bool morningSaved;
  final bool eveningSaved;
  final int completedDaysStreak;
}

class TodayProgress {
  const TodayProgress({required this.completed, required this.total});

  final int completed;
  final int total;

  double get ratio => total == 0 ? 0 : (completed / total).clamp(0, 1);
}

enum TodayTimelineKind {
  setupCommitment,
  preparation,
  calendarEvent,
  focusSession,
  taskBlock,
  habitSlot,
  manualCommitment,
}

class TodayTimelineItem {
  const TodayTimelineItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.allDay,
    this.location,
    this.startsAt,
    this.endsAt,
    this.startsOn,
    this.endsOn,
    this.sourceLabel,
    this.planId,
    this.blockId,
    this.managedTaskId,
    this.state,
    this.plannedMinutes,
    this.creditedTrackedMinutes,
    this.actualMinutes,
    this.taskId,
    this.habitId,
    this.commitmentId,
  });

  final TodayTimelineKind kind;
  final String id;
  final String title;
  final String? location;
  final bool allDay;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final String? sourceLabel;
  final String? planId;
  final String? blockId;
  final String? managedTaskId;
  final String? state;
  final int? plannedMinutes;
  final int? creditedTrackedMinutes;
  final int? actualMinutes;
  final String? taskId;
  final String? habitId;
  final String? commitmentId;
}

class TodayHabit {
  const TodayHabit({
    required this.id,
    required this.title,
    required this.cadence,
    required this.cadenceLabel,
    required this.weeklyCompleted,
    required this.weeklyTarget,
    required this.setupManaged,
    this.scheduledToday = false,
    this.description,
    this.outcome,
  });

  final String id;
  final String title;
  final String? description;
  final String cadence;
  final String cadenceLabel;
  final String? outcome;
  final int weeklyCompleted;
  final int weeklyTarget;
  final bool setupManaged;
  final bool scheduledToday;
}

enum TodaySourceStatus { current, unavailable }

class TodaySourceState {
  const TodaySourceState({required this.status, this.message});

  final TodaySourceStatus status;
  final String? message;
}

class TodaySourceStates {
  const TodaySourceStates({
    required this.checkIns,
    required this.tasks,
    required this.habits,
    required this.setupCommitments,
    required this.preparation,
    required this.calendarEvents,
    required this.focusSessions,
    this.planner,
  });

  final TodaySourceState checkIns;
  final TodaySourceState tasks;
  final TodaySourceState habits;
  final TodaySourceState setupCommitments;
  final TodaySourceState preparation;
  final TodaySourceState calendarEvents;
  final TodaySourceState focusSessions;
  final TodaySourceState? planner;

  Iterable<TodaySourceState> get timelineStates => [
        setupCommitments,
        preparation,
        calendarEvents,
        focusSessions,
        if (planner case final planner?) planner,
      ];
}

class DashboardCheckIn {
  const DashboardCheckIn({
    required this.entryDate,
    this.mood,
    this.energy,
    this.sleepHours,
    this.stress,
    this.focusMinutes,
    this.steps,
    this.activityLevel,
    this.screenTimeHours,
    this.hasEveningCapture = false,
    this.hasMorningCapture = false,
    this.focusBand,
    this.stressSource,
    this.stressControllability,
    this.dayShape,
  });

  final DateTime entryDate;
  final int? mood;
  final int? energy;
  final double? sleepHours;
  final int? stress;
  final int? focusMinutes;
  final int? steps;
  final int? activityLevel;
  final double? screenTimeHours;
  final bool hasEveningCapture;
  final bool hasMorningCapture;
  final String? focusBand;
  final String? stressSource;
  final String? stressControllability;
  final String? dayShape;

  bool get hasAnySignal =>
      mood != null ||
      energy != null ||
      sleepHours != null ||
      stress != null ||
      focusMinutes != null ||
      steps != null ||
      activityLevel != null ||
      screenTimeHours != null ||
      focusBand != null ||
      dayShape != null;
}

class PlanItem {
  const PlanItem({
    required this.id,
    required this.title,
    required this.priority,
    required this.isCompleted,
    required this.status,
    this.deadline,
    this.description,
    this.estimatedMinutes,
    this.source,
    this.deadlinePlanId,
    this.completedAt,
    this.todayReason,
    this.scheduledToday = false,
  });

  final String id;
  final String title;
  final String priority;
  final bool isCompleted;
  final String status;
  final DateTime? deadline;
  final String? description;
  final int? estimatedMinutes;
  final String? source;
  final String? deadlinePlanId;
  final DateTime? completedAt;
  final String? todayReason;
  final bool scheduledToday;

  bool get isDeadlinePlanManaged =>
      source == 'deadline-plan-v1' && deadlinePlanId == id;
}

class ScheduleDay {
  const ScheduleDay({
    required this.label,
    required this.dateLabel,
    required this.events,
    this.date,
  });

  final String label;
  final String dateLabel;
  final List<ScheduleEvent> events;
  final DateTime? date;
}

enum ScheduleEventOrigin { commitment, deadlinePreparation }

class ScheduleEvent {
  const ScheduleEvent({
    required this.title,
    required this.time,
    this.origin = ScheduleEventOrigin.commitment,
    this.provenanceLabel,
    this.deadlinePlanId,
    this.deadlinePlanBlockId,
    this.state,
    this.sortMinutes,
    this.endSortMinutes,
  });

  final String title;
  final String time;
  final ScheduleEventOrigin origin;
  final String? provenanceLabel;
  final String? deadlinePlanId;
  final String? deadlinePlanBlockId;
  final String? state;
  final int? sortMinutes;
  final int? endSortMinutes;

  bool get isDeadlinePreparation =>
      origin == ScheduleEventOrigin.deadlinePreparation;
}

class DashboardUnavailableException implements Exception {
  const DashboardUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
