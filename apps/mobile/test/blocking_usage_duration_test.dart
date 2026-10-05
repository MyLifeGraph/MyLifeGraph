import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/focus_protection/domain/blocking_usage_duration.dart';

void main() {
  test(
    'measured usage retains seconds and promotes minutes, hours and days',
    () {
      for (final (milliseconds, label) in [
        (-1, '0m'),
        (0, '0m'),
        (1, '<1s'),
        (999, '<1s'),
        (1000, '1s'),
        (59999, '59s'),
        (60000, '1m'),
        (61000, '1m 1s'),
        (3599999, '59m 59s'),
        (3600000, '1h'),
        (3661000, '1h 1m 1s'),
        (2000 * 60000, '1d 9h 20m'),
        (86400000, '1d'),
        (86401000, '1d 1s'),
        (90061000, '1d 1h 1m'),
        (30 * 86400000, '30d'),
      ]) {
        expect(formatBlockingUsageDuration(milliseconds), label);
      }
    },
  );
}
