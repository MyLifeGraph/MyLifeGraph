import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/weekly_review/domain/weekly_review.dart';

import 'support/weekly_review_fixtures.dart';

void main() {
  test('strict parser accepts the complete current contract', () {
    final feed = WeeklyReviewFeed.fromJson(weeklyReviewResponseJson());

    expect(feed.periodKey, '2026-W28');
    expect(feed.freshness, WeeklyReviewFreshness.current);
    expect(feed.review?.facts.tasks.completed, 4);
    expect(feed.review?.facts.habits.skipped, 1);
    expect(feed.review?.facts.habits.missed, 1);
    expect(feed.review?.facts.recovery.recoveryDays, 2);
    expect(feed.review?.proposals, isEmpty);
  });

  test('not-ready, missing, and stale state invariants stay distinct', () {
    final notReady = WeeklyReviewFeed.fromJson(
      weeklyReviewResponseJson(
        freshness: 'not_ready',
        includeReview: false,
      ),
    );
    final missing = WeeklyReviewFeed.fromJson(
      weeklyReviewResponseJson(
        freshness: 'missing',
        includeReview: false,
      ),
    );
    final stale = WeeklyReviewFeed.fromJson(
      weeklyReviewResponseJson(freshness: 'stale'),
    );

    expect(notReady.needsGeneration, isFalse);
    expect(missing.needsGeneration, isTrue);
    expect(stale.review, isNotNull);
    expect(stale.staleReasons, ['source_snapshot_changed']);
  });

  test('parser rejects unknown, explicit-null, and coercible fields', () {
    final unknown = _copy(weeklyReviewResponseJson())..['extra'] = true;
    final nullFacts = _copy(weeklyReviewResponseJson());
    (nullFacts['review'] as Map<String, dynamic>)['facts'] = null;
    final coerced = _copy(weeklyReviewResponseJson());
    (((coerced['review'] as Map<String, dynamic>)['facts']
            as Map<String, dynamic>)['tasks']
        as Map<String, dynamic>)['completed'] = '4';

    for (final json in [unknown, nullFacts, coerced]) {
      expect(
        () => WeeklyReviewFeed.fromJson(json),
        throwsA(isA<WeeklyReviewContractException>()),
      );
    }
  });

  test('weekly-review-v3 rejects every non-empty proposal list', () {
    final json = _copy(weeklyReviewResponseJson());
    ((json['review'] as Map<String, dynamic>)['proposals'] as List<Object?>)
        .add(
      {'legacy': true},
    );

    expect(
      () => WeeklyReviewFeed.fromJson(json),
      throwsA(isA<WeeklyReviewContractException>()),
    );
  });

  test('period, provenance, recovery, and exact fact keys are strict', () {
    final badPeriod = _copy(weeklyReviewResponseJson())
      ..['period_key'] = '2026-W29';
    final badFingerprint = _copy(weeklyReviewResponseJson());
    (((badFingerprint['review'] as Map<String, dynamic>)['provenance']
        as Map<String, dynamic>))['source_fingerprint'] = 'ABC';
    final badRecovery = _copy(weeklyReviewResponseJson());
    ((((badRecovery['review'] as Map<String, dynamic>)['facts']
            as Map<String, dynamic>)['recovery']
        as Map<String, dynamic>))['recovery_days'] = 8;
    final badFeedback = _copy(weeklyReviewResponseJson());
    ((badFeedback['review'] as Map<String, dynamic>)['facts']
        as Map<String, dynamic>)['feedback'] = {'total': 1};

    for (final json in [badPeriod, badFingerprint, badRecovery, badFeedback]) {
      expect(
        () => WeeklyReviewFeed.fromJson(json),
        throwsA(isA<WeeklyReviewContractException>()),
      );
    }
  });
}

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
