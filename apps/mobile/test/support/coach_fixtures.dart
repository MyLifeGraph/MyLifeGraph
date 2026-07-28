const coachRequestId = '11111111-1111-4111-8111-111111111111';
const coachSecondRequestId = '22222222-2222-4222-8222-222222222222';
const coachMemoryId = '33333333-3333-4333-8333-333333333333';
const coachManualMemoryId = '44444444-4444-4444-8444-444444444444';
const coachFocusSessionId = '55555555-5555-4555-8555-555555555555';
const coachSecondFocusSessionId = '66666666-6666-4666-8666-666666666666';

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
  String promptVersion = 'controlled-coach-prompt-v3',
  String contextVersion = 'coach-context-v3',
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
        'prompt_version': promptVersion,
        'context_version': contextVersion,
        'generated_at': '2026-07-13T10:15:00Z',
        'provider_called': providerCalled,
      },
    };

Map<String, dynamic> coachHistoryJson({
  List<Map<String, dynamic>>? turns,
  bool includeContext = true,
}) =>
    {
      'contract_version': 'coach-history-v1',
      'turns': turns ??
          [
            {
              'request_id': coachRequestId,
              'message': 'How should I pace today?',
              if (includeContext) ...{
                'context_scope': 'today',
                'context_parameters': <String, dynamic>{},
              },
              'response': coachResponseJson(),
              'created_at': '2026-07-13T10:15:01Z',
            },
          ],
    };

Map<String, dynamic> coachFocusOptionJson({
  String focusSessionId = coachFocusSessionId,
  String status = 'completed',
  String localStartedAt = '2026-07-27T09:30:00+02:00',
  int plannedMinutes = 50,
  int actualMinutes = 47,
  bool hasReflection = true,
}) =>
    {
      'focus_session_id': focusSessionId,
      'status': status,
      'local_started_at': localStartedAt,
      'planned_minutes': plannedMinutes,
      'actual_minutes': actualMinutes,
      'has_reflection': hasReflection,
    };

Map<String, dynamic> coachContextOptionsJson({
  String timezone = 'Europe/Berlin',
  bool personalPatternAnalysisEnabled = true,
  List<Map<String, dynamic>>? focusOptions,
  String? defaultFocusSessionId = coachFocusSessionId,
  bool moreFocusOptionsAvailable = false,
}) =>
    {
      'contract_version': 'coach-context-options-v1',
      'timezone': timezone,
      'personal_pattern_analysis_enabled': personalPatternAnalysisEnabled,
      'focus_options': focusOptions ??
          [
            coachFocusOptionJson(),
            coachFocusOptionJson(
              focusSessionId: coachSecondFocusSessionId,
              status: 'abandoned',
              localStartedAt: '2026-07-25T15:15:00+02:00',
              plannedMinutes: 25,
              actualMinutes: 12,
              hasReflection: false,
            ),
          ],
      'default_focus_session_id': defaultFocusSessionId,
      'more_focus_options_available': moreFocusOptionsAvailable,
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
