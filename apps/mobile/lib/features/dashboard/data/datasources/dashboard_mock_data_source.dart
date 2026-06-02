import '../../domain/entities/dashboard_snapshot.dart';

class DashboardMockDataSource {
  const DashboardMockDataSource();

  Future<DashboardSnapshot> getSnapshot() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));

    return const DashboardSnapshot(
      optimizationScore: 82,
      streakDays: 12,
      focusMinutesToday: 135,
      recoveryScore: 74,
      energyTrend: [63, 71, 68, 76, 82, 79, 84],
      todayPlan: [
        PlanItem(
          id: 'mock_deep_work',
          title: 'Deep work block',
          time: '08:30',
          type: 'Focus',
          isCompleted: true,
        ),
        PlanItem(
          id: 'mock_lunch',
          title: 'Protein-forward lunch',
          time: '12:30',
          type: 'Nutrition',
          isCompleted: false,
        ),
        PlanItem(
          id: 'mock_walk',
          title: 'Walk reset',
          time: '15:15',
          type: 'Movement',
          isCompleted: false,
        ),
      ],
    );
  }
}
