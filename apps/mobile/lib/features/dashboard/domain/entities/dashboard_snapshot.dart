class DashboardSnapshot {
  const DashboardSnapshot({
    required this.optimizationScore,
    required this.streakDays,
    required this.focusMinutesToday,
    required this.recoveryScore,
    required this.energyTrend,
    required this.todayPlan,
  });

  final int optimizationScore;
  final int streakDays;
  final int focusMinutesToday;
  final int recoveryScore;
  final List<int> energyTrend;
  final List<PlanItem> todayPlan;
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
