class DashboardSnapshot {
  const DashboardSnapshot({
    required this.optimizationScore,
    required this.streakDays,
    required this.focusMinutesToday,
    required this.recoveryScore,
    required this.energyTrend,
    required this.todayPlan,
    required this.scheduleDays,
  });

  static const empty = DashboardSnapshot(
    optimizationScore: 0,
    streakDays: 0,
    focusMinutesToday: 0,
    recoveryScore: 0,
    energyTrend: [],
    todayPlan: [],
    scheduleDays: [],
  );

  final int optimizationScore;
  final int streakDays;
  final int focusMinutesToday;
  final int recoveryScore;
  final List<int> energyTrend;
  final List<PlanItem> todayPlan;
  final List<ScheduleDay> scheduleDays;
}

class PlanItem {
  const PlanItem({
    required this.id,
    required this.title,
    required this.time,
    required this.type,
    required this.isCompleted,
  });

  final String id;
  final String title;
  final String time;
  final String type;
  final bool isCompleted;
}

class ScheduleDay {
  const ScheduleDay({
    required this.label,
    required this.dateLabel,
    required this.energy,
    required this.movement,
    required this.activity,
    required this.events,
  });

  final String label;
  final String dateLabel;
  final double energy;
  final double movement;
  final int activity;
  final List<ScheduleEvent> events;
}

class ScheduleEvent {
  const ScheduleEvent({
    required this.title,
    required this.time,
  });

  final String title;
  final String time;
}
