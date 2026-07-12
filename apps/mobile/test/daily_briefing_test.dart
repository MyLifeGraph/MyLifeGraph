import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/actions/domain/executable_action_target.dart';
import 'package:my_life_graph/features/briefings/domain/daily_briefing.dart';

import 'support/briefing_fixtures.dart';

void main() {
  test('parses the strict persisted briefing and executable target', () {
    final feed = BriefingFeed.fromJson(briefingResponseJson());

    expect(feed.origin, BriefingOrigin.authenticatedBackend);
    expect(feed.freshness, BriefingFreshness.current);
    expect(feed.needsGeneration, isFalse);
    expect(feed.briefing?.mode, BriefingMode.recover);
    expect(feed.briefing?.capacityMinutes, isNull);
    expect(
      feed.briefing?.primaryAction.target.command,
      ExecutableActionCommand.openTask,
    );
    expect(feed.briefing?.provenance.sourceSnapshotId, isNotEmpty);
  });

  test('accepts an honest missing response without a briefing', () {
    final feed = BriefingFeed.fromJson(
      briefingResponseJson(
        freshness: 'missing',
        includeBriefing: false,
      ),
    );

    expect(feed.freshness, BriefingFreshness.missing);
    expect(feed.needsGeneration, isTrue);
    expect(feed.briefing, isNull);
  });

  test('rejects freshness and payload mismatches', () {
    expect(
      () => BriefingFeed.fromJson(
        briefingResponseJson(
          freshness: 'current',
          needsGeneration: true,
        ),
      ),
      throwsA(isA<BriefingContractException>()),
    );
    expect(
      () => BriefingFeed.fromJson(
        briefingResponseJson(
          freshness: 'stale',
          includeBriefing: false,
        ),
      ),
      throwsA(isA<BriefingContractException>()),
    );
  });

  test('rejects unknown response and nested action fields', () {
    final unknownResponse = briefingResponseJson()..['unexpected'] = true;
    expect(
      () => BriefingFeed.fromJson(unknownResponse),
      throwsA(isA<BriefingContractException>()),
    );

    final unknownAction = briefingResponseJson();
    final briefing = unknownAction['briefing'] as Map<String, dynamic>;
    final action = briefing['primary_action'] as Map<String, dynamic>;
    action['route'] = '/unsafe';
    expect(
      () => BriefingFeed.fromJson(unknownAction),
      throwsA(isA<BriefingContractException>()),
    );
  });

  test('delegates incompatible action targets to the strict action parser', () {
    expect(
      () => BriefingFeed.fromJson(
        briefingResponseJson(command: 'review_plan', kind: 'task'),
      ),
      throwsA(isA<UnsupportedActionTargetException>()),
    );
  });

  test('local demo state never fabricates a briefing', () {
    final feed = BriefingFeed.localDemo(now: DateTime(2026, 7, 12));

    expect(feed.origin, BriefingOrigin.localDemo);
    expect(feed.freshness, BriefingFreshness.missing);
    expect(feed.briefing, isNull);
  });
}
