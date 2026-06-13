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
      scheduleDays: [
        ScheduleDay(
          label: 'Mon',
          dateLabel: 'May 25',
          energy: 0.71,
          movement: 0.74,
          activity: 71,
          events: [
            ScheduleEvent(title: 'Math', time: '08:15-09:45'),
          ],
        ),
        ScheduleDay(
          label: 'Tue',
          dateLabel: 'May 26',
          energy: 0.68,
          movement: 0.64,
          activity: 68,
          events: [
            ScheduleEvent(title: 'Empty 1', time: '--:--'),
            ScheduleEvent(title: 'Empty 2', time: '--:--'),
          ],
        ),
        ScheduleDay(
          label: 'Wed',
          dateLabel: 'May 27',
          energy: 0.76,
          movement: 0.70,
          activity: 76,
          events: [
            ScheduleEvent(title: 'Empty 1', time: '--:--'),
            ScheduleEvent(title: 'Empty 2', time: '--:--'),
          ],
        ),
        ScheduleDay(
          label: 'Thu',
          dateLabel: 'May 28',
          energy: 0.82,
          movement: 0.76,
          activity: 82,
          events: [
            ScheduleEvent(title: 'Empty 1', time: '--:--'),
            ScheduleEvent(title: 'Empty 2', time: '--:--'),
          ],
        ),
        ScheduleDay(
          label: 'Fri',
          dateLabel: 'May 29',
          energy: 0.79,
          movement: 0.72,
          activity: 79,
          events: [
            ScheduleEvent(title: 'Empty 1', time: '--:--'),
            ScheduleEvent(title: 'Empty 2', time: '--:--'),
          ],
        ),
        ScheduleDay(
          label: 'Sat',
          dateLabel: 'May 30',
          energy: 0.84,
          movement: 0.78,
          activity: 84,
          events: [
            ScheduleEvent(title: 'Empty 1', time: '--:--'),
            ScheduleEvent(title: 'Empty 2', time: '--:--'),
          ],
        ),
        ScheduleDay(
          label: 'Sun',
          dateLabel: 'May 31',
          energy: 0.63,
          movement: 0.60,
          activity: 63,
          events: [
            ScheduleEvent(title: 'Empty 1', time: '--:--'),
            ScheduleEvent(title: 'Empty 2', time: '--:--'),
          ],
        ),
      ],
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
