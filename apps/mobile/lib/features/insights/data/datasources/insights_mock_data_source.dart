import '../../domain/entities/correlation.dart';
import '../../domain/entities/insight.dart';

class InsightsMockDataSource {
  const InsightsMockDataSource();

  Future<List<Insight>> getInsights() async {
    await Future<void>.delayed(const Duration(milliseconds: 220));

    return const [
      Insight(
        id: 'activity_mood_primary',
        title: 'Activity lifts mood',
        summary:
            'Mood tends to be better on days with 8k+ steps or higher activity levels.',
        confidence: 0.72,
        tags: ['Activity', 'Mood'],
      ),
      Insight(
        id: 'activity_mood_secondary',
        title: 'Activity lifts mood',
        summary:
            'Mood tends to be better on days with 8k+ steps or higher activity levels.',
        confidence: 0.72,
        tags: ['Activity', 'Mood'],
      ),
      Insight(
        id: 'screen_focus_primary',
        title: 'Screen time competes with focus',
        summary: 'High screen-time days often have lower deep-work minutes.',
        confidence: 0.68,
        tags: ['Screen time', 'Focus'],
      ),
      Insight(
        id: 'screen_focus_secondary',
        title: 'Screen time competes with focus',
        summary: 'High screen-time days often have lower deep-work minutes.',
        confidence: 0.68,
        tags: ['Screen time', 'Focus'],
      ),
    ];
  }

  Future<List<CorrelationDataPoint>> getCorrelationDataPoints({
    required int windowDays,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 160));

    final today = DateTime.now();
    final count = normalizeInsightsWindowDays(windowDays);
    return List.generate(count, (index) {
      final offset = index - count + 1;
      final date = DateTime(today.year, today.month, today.day).add(
        Duration(days: offset),
      );
      final wave = _wave(index);
      final sleep = (7.1 + wave * 0.55 - (index % 8 == 0 ? 0.7 : 0))
          .clamp(5.3, 8.8)
          .toDouble();
      final screen = (4.4 - wave * 0.35 + (index % 6 == 0 ? 1.1 : 0))
          .clamp(2.0, 7.6)
          .toDouble();
      final stress = (5.4 - wave * 1.2 + (screen > 5.5 ? 1.2 : 0))
          .clamp(2.0, 9.0)
          .toDouble();
      final focus =
          (92 + sleep * 10 - stress * 6 + wave * 18).clamp(25, 190).toDouble();
      final activity = (5.4 + wave * 1.6).clamp(1.0, 9.0).toDouble();
      final energy = (4.2 + sleep * 0.45 + activity * 0.22 - stress * 0.18)
          .clamp(2.0, 10.0)
          .toDouble();
      final mood = (4.0 + energy * 0.35 + activity * 0.18 - stress * 0.12)
          .clamp(2.0, 10.0)
          .toDouble();
      final habitRate =
          (62 + wave * 22 + (sleep > 7.2 ? 12 : -8)).clamp(0, 100).toDouble();
      final plannedMinutes = (120 + stress * 18 + (index % 5 == 0 ? 90 : 0))
          .clamp(30, 480)
          .toDouble();

      return CorrelationDataPoint(
        date: date,
        values: {
          'sleep_hours': sleep,
          'focus_minutes': focus,
          'planned_minutes': plannedMinutes,
          'stress_level': stress,
          'energy_level': energy,
          'mood_score': mood,
          'screen_time_hours': screen,
          'activity_level': activity,
          'steps': (5400 + activity * 620).roundToDouble(),
          'habit_completion_rate': habitRate,
        },
      );
    });
  }

  double _wave(int index) {
    const values = [-0.9, -0.2, 0.5, 1.0, 0.3, -0.4, 0.8];
    return values[index % values.length];
  }
}
