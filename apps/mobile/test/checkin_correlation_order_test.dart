import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/insights/domain/services/checkin_correlations.dart';

import 'checkin_correlations_test.dart' show fixture;

void main() {
  for (final count in [7, 28]) {
    for (final focus in [false, true]) {
      test(
        '$count check-in days, Focus=$focus: source ordering cannot change evidence',
        () {
          final source = fixture(count, focus: focus);
          final expected = checkInCorrelationReport(source, windowDays: 90);
          final random = Random(20261029);
          for (var trial = 0; trial < 40; trial++) {
            source.skillsetPoints.shuffle(random);
            final actual = checkInCorrelationReport(source, windowDays: 90);
            expect(actual.results.length, expected.results.length);
            for (final original in expected.results) {
              final result = actual.resultFor(
                original.metricAId,
                original.metricBId,
              )!;
              expect(
                result.sampleSize,
                original.sampleSize,
                reason: 'trial=$trial',
              );
              expect(result.status, original.status, reason: 'trial=$trial');
              expect(
                result.coefficient,
                original.coefficient == null
                    ? isNull
                    : closeTo(original.coefficient!, 1e-12),
              );
            }
            expect(
              actual.rankedResults.map((r) => [r.metricAId, r.metricBId]),
              expected.rankedResults.map((r) => [r.metricAId, r.metricBId]),
            );
          }
        },
      );
    }
  }
}
