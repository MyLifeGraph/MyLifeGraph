import '../../domain/entities/recommendation.dart';
import '../../domain/entities/skillset_profile.dart';

class OptimizationMockDataSource {
  const OptimizationMockDataSource();

  Future<SkillsetProfile> getSkillsetProfile() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));

    return SkillsetProfile(
      userName: 'Alex',
      overallScore: 82,
      primaryArchetype: 'Focused Builder',
      updatedAt: DateTime.now().subtract(const Duration(minutes: 14)),
      scores: const [
        SkillScore(
          name: 'Deep Work',
          score: 86,
          signal: 'Strong mornings, lower late-day consistency',
        ),
        SkillScore(
          name: 'Recovery',
          score: 74,
          signal: 'Sleep debt rises after high-output days',
        ),
        SkillScore(
          name: 'Planning',
          score: 91,
          signal: 'Weekly planning cadence is stable',
        ),
        SkillScore(
          name: 'Movement',
          score: 68,
          signal: 'Activity is clustered instead of distributed',
        ),
      ],
    );
  }

  Future<List<Recommendation>> getRecommendations() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));

    return const [
      Recommendation(
        id: 'rec_focus_block',
        title: 'Protect a 90-minute focus block',
        reason: 'Your best cognitive window has been 8:30-10:30 this week.',
        actionLabel: 'Schedule block',
        category: RecommendationCategory.focus,
        confidence: 0.88,
      ),
      Recommendation(
        id: 'rec_evening_recovery',
        title: 'Lower evening stimulation',
        reason: 'Late screen-heavy sessions correlate with lower recovery.',
        actionLabel: 'Create wind-down',
        category: RecommendationCategory.recovery,
        confidence: 0.79,
      ),
      Recommendation(
        id: 'rec_micro_walk',
        title: 'Add two short movement resets',
        reason: 'Distributed movement may stabilize afternoon energy.',
        actionLabel: 'Add resets',
        category: RecommendationCategory.movement,
        confidence: 0.73,
      ),
    ];
  }
}
