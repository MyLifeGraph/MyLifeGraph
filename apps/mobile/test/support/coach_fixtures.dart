const coachRequestId = '11111111-1111-4111-8111-111111111111';
const coachSecondRequestId = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> coachCapabilitiesJson({
  String state = 'ready',
  String provider = 'fake',
  String providerMode = 'deterministic_test_only',
  String? modelRequested,
  String modelSource = 'not_applicable',
  String serviceTier = 'not_applicable',
  bool fastMode = false,
  String reasonCode = 'ready',
  int remainingRequests = 19,
}) =>
    {
      'contract_version': 'coach-capabilities-v2',
      'state': state,
      'provider': provider,
      'provider_mode': providerMode,
      'model_requested': modelRequested,
      'model_source': modelSource,
      'service_tier': serviceTier,
      'fast_mode': fastMode,
      'reason_code': reasonCode,
      'limits': {
        'message_codepoints': 2000,
        'reply_codepoints': 4000,
        'requests_per_local_day': 20,
        'remaining_requests': remainingRequests,
        'max_tool_calls': 12,
        'turn_timeout_seconds': 180,
        'sql_timeout_seconds': 5,
        'python_timeout_seconds': 30,
        'snapshot_max_rows': 50000,
        'snapshot_max_bytes': 8388608,
      },
    };

Map<String, dynamic> localCodexCapabilitiesJson() => coachCapabilitiesJson(
      provider: 'local_codex_oauth',
      providerMode: 'local_development_only',
      modelRequested: 'gpt-5.5',
      modelSource: 'explicit',
      serviceTier: 'fast',
      fastMode: true,
    );

Map<String, dynamic> coachResponseJson({
  String requestId = coachRequestId,
  String reply = 'Your median Focus duration was 42 minutes.',
  String uncertaintyLevel = 'low',
  String uncertaintyReason = 'This describes recorded sessions only.',
  List<Map<String, dynamic>>? evidence,
  List<Map<String, dynamic>>? steps,
}) {
  final traceSteps = steps ??
      [
        {
          'sequence': 1,
          'tool': 'query_data',
          'status': 'completed',
          'summary': 'Read-only SQL: SELECT actual_minutes FROM focus_sessions',
          'row_count': 12,
          'duration_ms': 8,
        },
      ];
  return {
    'contract_version': 'coach-response-v2',
    'request_id': requestId,
    'reply': reply,
    'uncertainty': {
      'level': uncertaintyLevel,
      'reason': uncertaintyReason,
    },
    'safety': {'classification': 'normal'},
    'evidence': evidence ??
        [
          {
            'source': 'focus_sessions',
            'record_count': 12,
            'period_start': '2026-06-01T09:00:00Z',
            'period_end': '2026-07-27T09:00:00Z',
          },
        ],
    'agent_trace': {
      'tool_call_count': traceSteps.length,
      'steps': traceSteps,
      'limitations': [
        'The snapshot contains app data only and cannot establish causality.',
      ],
    },
    'provenance': {
      'source': 'model',
      'provider': 'fake',
      'provider_mode': 'deterministic_test_only',
      'model_requested': null,
      'model_reported': null,
      'model_source': 'not_applicable',
      'prompt_version': 'free-coach-agent-prompt-v2',
      'context_version': 'personal-snapshot-v1',
      'generated_at': '2026-07-28T10:15:00Z',
      'provider_called': true,
      'service_tier': 'not_applicable',
      'service_tier_status': 'not_applicable',
      'fast_mode': false,
      'snapshot_row_count': 120,
      'snapshot_bytes': 24576,
    },
  };
}

Map<String, dynamic> coachHistoryJson({
  List<Map<String, dynamic>>? turns,
}) =>
    {
      'contract_version': 'coach-history-v2',
      'turns': turns ??
          [
            {
              'request_id': coachRequestId,
              'message': 'How long are my Focus sessions?',
              'response': coachResponseJson(),
              'created_at': '2026-07-28T10:15:01Z',
            },
          ],
    };

Map<String, dynamic> coachLegacyResponseJson({
  String provider = 'fake',
  String providerMode = 'deterministic_test_only',
  String? modelRequested,
  String? modelReported,
  String modelSource = 'not_applicable',
}) =>
    {
      'contract_version': 'coach-response-v1',
      'request_id': coachSecondRequestId,
      'reply': 'This older response remains readable.',
      'uncertainty': {
        'level': 'medium',
        'reason': 'Legacy bounded context.',
      },
      'staged_suggestion': null,
      'safety': {'classification': 'normal'},
      'used_context': [
        {
          'source': 'tasks',
          'available_count': 2,
          'included_count': 1,
          'omitted_count': 1,
          'freshness': 'current',
        },
      ],
      'provenance': {
        'source': 'model',
        'provider': provider,
        'provider_mode': providerMode,
        'model_requested': modelRequested,
        'model_reported': modelReported,
        'model_source': modelSource,
        'prompt_version': 'controlled-coach-prompt-v3',
        'context_version': 'coach-context-v3',
        'generated_at': '2026-07-27T10:15:00Z',
        'provider_called': true,
      },
    };

Map<String, dynamic> coachHistoryDeleteJson({bool deleted = true}) => {
      'contract_version': 'coach-history-v1',
      'deleted': deleted,
    };
