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
        impact: '72%',
        tags: ['Activity', 'Mood'],
      ),
      Insight(
        id: 'activity_mood_secondary',
        title: 'Activity lifts mood',
        summary:
            'Mood tends to be better on days with 8k+ steps or higher activity levels.',
        impact: '72%',
        tags: ['Activity', 'Mood'],
      ),
      Insight(
        id: 'screen_focus_primary',
        title: 'Screen time competes with focus',
        summary:
            'High screen-time days often have lower deep-work minutes.',
        impact: '68%',
        tags: ['Screen time', 'Focus'],
      ),
      Insight(
        id: 'screen_focus_secondary',
        title: 'Screen time competes with focus',
        summary:
            'High screen-time days often have lower deep-work minutes.',
        impact: '68%',
        tags: ['Screen time', 'Focus'],
      ),
    ];
  }
}
