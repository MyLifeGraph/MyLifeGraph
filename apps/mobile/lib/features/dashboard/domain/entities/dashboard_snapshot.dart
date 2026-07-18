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
  });

  final String title;
  final String time;
  final ScheduleEventOrigin origin;
  final String? provenanceLabel;
  final String? deadlinePlanId;
  final String? deadlinePlanBlockId;
  final String? state;
  final int? sortMinutes;

  bool get isDeadlinePreparation =>
      origin == ScheduleEventOrigin.deadlinePreparation;
}

class DashboardUnavailableException implements Exception {
  const DashboardUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
