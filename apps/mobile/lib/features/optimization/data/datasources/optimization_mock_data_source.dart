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
}
