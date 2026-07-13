const coachRequestId = '11111111-1111-4111-8111-111111111111';
const coachSecondRequestId = '22222222-2222-4222-8222-222222222222';
const coachMemoryId = '33333333-3333-4333-8333-333333333333';
const coachManualMemoryId = '44444444-4444-4444-8444-444444444444';

Map<String, dynamic> coachCapabilitiesJson({
  String state = 'ready',
  String provider = 'fake',
  String providerMode = 'deterministic_test_only',
  String? modelRequested = 'fake-coach-model',
  String modelSource = 'explicit',
  String reasonCode = 'ready',
  int remainingRequests = 19,
  int timeoutSeconds = 45,
}) =>
    {
      'contract_version': 'coach-capabilities-v1',
      'state': state,
      'provider': provider,
      'provider_mode': providerMode,
      'model_requested': modelRequested,
      'model_source': modelSource,
      'reason_code': reasonCode,
      'limits': {
        'message_codepoints': 2000,
        'context_bytes': 32768,
        'reply_codepoints': 4000,
        'timeout_seconds': timeoutSeconds,
        'requests_per_local_day': 20,
        'remaining_requests': remainingRequests,
      },
    };

Map<String, dynamic> coachResponseJson({
  String requestId = coachRequestId,
  String reply = 'Protect one focused block, then reassess your energy.',
  String uncertaintyLevel = 'medium',
  String uncertaintyReason = 'The latest daily state is partial.',
  bool includeSuggestion = true,
  String safetyClassification = 'normal',
  String provenanceSource = 'model',
  bool providerCalled = true,
  List<Map<String, dynamic>>? usedContext,
}) =>
    {
      'contract_version': 'coach-response-v1',
      'request_id': requestId,
      'reply': reply,
      'uncertainty': {
        'level': uncertaintyLevel,
        'reason': uncertaintyReason,
      },
      'staged_suggestion': includeSuggestion
          ? {
              'title': 'Review a smaller focus block',
              'rationale': 'A shorter block may fit the partial daily state.',
            }
          : null,
      'safety': {'classification': safetyClassification},
      'used_context': usedContext ??
          [
            {
              'source': 'daily_snapshot',
              'available_count': 1,
              'included_count': 1,
              'omitted_count': 0,
              'freshness': 'current',
            },
            {
              'source': 'memories',
              'available_count': 2,
              'included_count': 1,
              'omitted_count': 1,
              'freshness': 'current',
            },
          ],
      'provenance': {
        'source': provenanceSource,
        'provider': 'fake',
        'provider_mode': 'deterministic_test_only',
        'model_requested': 'fake-coach-model',
        'model_reported': providerCalled ? 'fake-coach-model-v1' : null,
        'model_source': 'explicit',
        'prompt_version': 'controlled-coach-prompt-v1',
        'context_version': 'coach-context-v1',
        'generated_at': '2026-07-13T10:15:00Z',
        'provider_called': providerCalled,
      },
    };

Map<String, dynamic> coachHistoryJson({
  List<Map<String, dynamic>>? turns,
}) =>
    {
      'contract_version': 'coach-history-v1',
      'turns': turns ??
          [
            {
              'request_id': coachRequestId,
              'message': 'How should I pace today?',
              'response': coachResponseJson(),
              'created_at': '2026-07-13T10:15:01Z',
            },
          ],
    };

Map<String, dynamic> coachHistoryDeleteJson({bool deleted = true}) => {
      'contract_version': 'coach-history-v1',
      'deleted': deleted,
    };

Map<String, dynamic> coachMemoryJson({
  String id = coachMemoryId,
  String type = 'preference',
  String title = 'Prefer one clear next step',
  String content = 'Keep guidance concrete and recovery-aware.',
  bool contentTruncated = false,
  String ownership = 'setup',
  bool selected = true,
}) =>
    {
      'id': id,
      'type': type,
      'title': title,
      'content': content,
      'content_truncated': contentTruncated,
      'ownership': ownership,
      'selected': selected,
      'updated_at': '2026-07-12T09:00:00+00:00',
    };

Map<String, dynamic> coachMemoriesJson({
  List<Map<String, dynamic>>? memories,
  int? availableCount,
}) {
  final rows = memories ??
      [
        coachMemoryJson(),
        coachMemoryJson(
          id: coachManualMemoryId,
          type: 'pattern',
          title: 'Afternoon energy dip',
          content: 'Energy often drops after a meeting-heavy morning.',
          ownership: 'manual',
          selected: false,
        ),
      ];
  return {
    'contract_version': 'coach-memory-selection-v1',
    'max_selected': 8,
    'available_count': availableCount ?? rows.length,
    'memories': rows,
  };
}
