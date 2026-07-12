import 'package:my_life_graph/features/briefings/domain/daily_briefing.dart';

Map<String, dynamic> briefingResponseJson({
  String freshness = 'current',
  bool? needsGeneration,
  bool includeBriefing = true,
  String command = 'open_task',
  String kind = 'task',
  String? targetId = '11111111-1111-4111-8111-111111111111',
  Map<String, Object>? targetMetadata,
}) {
  final resolvedNeedsGeneration =
      needsGeneration ?? freshness != BriefingFreshness.current.code;
  return {
    'contract_version': dailyBriefingContractVersion,
    'briefing_date': '2026-07-12',
    'freshness': freshness,
    'needs_generation': resolvedNeedsGeneration,
    'stale_reasons':
        freshness == 'stale' ? ['daily_snapshot_refreshed'] : <String>[],
    'briefing': includeBriefing
        ? {
            'id': '22222222-2222-4222-8222-222222222222',
            'briefing_date': '2026-07-12',
            'mode': 'recover',
            'data_quality': 'current',
            'capacity_minutes': null,
            'capacity_note': 'Keep today\'s load small and protect recovery.',
            'summary': 'Recover mode: start with Submit the report.',
            'primary_action': briefingActionJson(
              command: command,
              kind: kind,
              targetId: targetId,
              targetMetadata: targetMetadata,
            ),
            'support_actions': <Map<String, dynamic>>[],
            'evidence_refs': [
              {
                'table': 'tasks',
                'id': '11111111-1111-4111-8111-111111111111',
                'field': 'status',
              },
            ],
            'provenance': {
              'engine': 'deterministic',
              'contract_version': dailyBriefingContractVersion,
              'daily_state_contract_version': 'explainable-daily-state-v1',
              'executable_action_contract_version': 'executable-action-v1',
              'source_snapshot_id': '33333333-3333-4333-8333-333333333333',
              'source_snapshot_generated_at': '2026-07-12T07:55:00Z',
              'baseline': 'none',
              'llm_used': false,
              'feedback_ranking': {
                'contract_version': 'feedback-ranking-v1',
                'lookback_days': 28,
                'event_count': 0,
                'applied_count': 0,
                'primary_contribution': 0,
                'reasons': <String>[],
              },
            },
            'generated_at': '2026-07-12T08:00:00Z',
            'updated_at': '2026-07-12T08:00:00Z',
          }
        : null,
  };
}

Map<String, dynamic> briefingActionJson({
  String command = 'open_task',
  String kind = 'task',
  String? targetId = '11111111-1111-4111-8111-111111111111',
  Map<String, Object>? targetMetadata,
}) {
  return {
    'target': {
      'contract_version': 'executable-action-v1',
      'id': '$command:${targetId ?? 'today'}',
      'kind': kind,
      'command': command,
      if (targetId != null) 'target_id': targetId,
      'estimated_minutes': 30,
      'metadata': targetMetadata ?? {'source': dailyBriefingContractVersion},
    },
    'title': 'Submit the report',
    'reason': 'This bounded action fits today\'s reduced load.',
    'evidence_refs': [
      {
        'table': 'tasks',
        'id': '11111111-1111-4111-8111-111111111111',
        'field': 'status',
      },
    ],
  };
}

BriefingFeed currentBriefingFeed() =>
    BriefingFeed.fromJson(briefingResponseJson());
