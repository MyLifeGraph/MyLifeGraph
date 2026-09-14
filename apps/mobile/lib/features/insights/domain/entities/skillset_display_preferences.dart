enum SkillsetChartView { radar, bars }

const defaultSkillsetDimensions = {
  'sleep',
  'sport',
  'energy',
  'social',
  'learning',
  'concentration',
};

const supportedSkillsetDimensions = {
  ...defaultSkillsetDimensions,
  'stress',
  'mood',
  'productivity',
  'motivation',
  'discipline',
};

class SkillsetDisplayPreferences {
  SkillsetDisplayPreferences({
    Set<String> dimensions = defaultSkillsetDimensions,
    this.chart = SkillsetChartView.radar,
  }) : dimensions = Set.unmodifiable(dimensions);

  final Set<String> dimensions;
  final SkillsetChartView chart;
}
