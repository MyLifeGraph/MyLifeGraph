class SkillsetProfile {
  const SkillsetProfile({
    required this.userName,
    required this.overallScore,
    required this.primaryArchetype,
    required this.scores,
    required this.updatedAt,
  });

  final String userName;
  final int overallScore;
  final String primaryArchetype;
  final List<SkillScore> scores;
  final DateTime updatedAt;
}

class SkillScore {
  const SkillScore({
    required this.name,
    required this.score,
    required this.signal,
  });

  final String name;
  final int score;
  final String signal;
}
