enum SkillsetChartView { radar, bars }

const supportedSkillsetDimensions = {
  'sleep',
  'sport',
  'energy',
  'social',
  'learning',
  'concentration',
  'stress',
  'mood',
  'productivity',
  'motivation',
  'discipline',
};

const defaultSkillsetDimensions = supportedSkillsetDimensions;

class SkillsetDisplayPreferences {
  SkillsetDisplayPreferences({
    Set<String> dimensions = defaultSkillsetDimensions,
    this.chart = SkillsetChartView.radar,
  }) : dimensions = Set.unmodifiable(dimensions);

  final Set<String> dimensions;
  final SkillsetChartView chart;
}
