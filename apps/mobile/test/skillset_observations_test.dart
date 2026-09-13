import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/insights/domain/entities/correlation.dart';
import 'package:my_life_graph/features/insights/domain/entities/skillset_observations.dart';

void main() {
  test(
    'window totals, zero and missing components keep their exact meaning',
    () {
      final points = [
        for (var i = 1; i <= 3; i++)
          CorrelationDataPoint(
            date: DateTime(2026, 9, i),
            values: {
              'focus_count': 1,
              'focus_completed': i == 3 ? 0 : 1,
              'learning_count': 1,
              'learning_completed': i == 3 ? 0 : 1,
              'sport_activity': i == 1 ? 2 : 0,
              'study_motivation': 0,
            },
          ),
      ];
      final report = skillsetReport(points, DateTime(2026, 9, 3), 14);
      expect(report.points.last.values['regularity'], closeTo(50, .001));
      expect(
        report.points.last.values['learning_completion_rate'],
        closeTo(200 / 3, .001),
      );
      expect(
        skillsetReport(
          points.take(1).toList(),
          DateTime(2026, 9, 3),
          14,
        ).points.last.values,
        isEmpty,
      );
      expect(
        skillsetReport(points, DateTime(2026, 10, 1), 7).points.last.values,
        isEmpty,
      );
      expect(parseSkillsetPoints({}), isEmpty);
    },
  );
}
