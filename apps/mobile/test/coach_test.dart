import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/coach/domain/coach.dart';

import 'support/coach_fixtures.dart';

void main() {
  test('V4 request contains only identity and free question', () {
    final request = CoachRequest(
      requestId: coachRequestId,
      message: '  Compare all available Focus history.  ',
    );

    expect(request.toJson(), {
      'contract_version': 'coach-request-v4',
      'request_id': coachRequestId,
      'message': 'Compare all available Focus history.',
    });
    expect(request.toJson(), isNot(contains('context_scope')));
    expect(request.toJson(), isNot(contains('context_parameters')));
  });

  test('capabilities require the exact agent and snapshot limits', () {
    final capability = CoachCapabilities.fromJson(
      localCodexCapabilitiesJson(),
    );

    expect(capability.modelRequested, 'gpt-5.5');
    expect(capability.serviceTier, 'fast');
    expect(capability.fastMode, isTrue);
    expect(capability.limits.maxToolCalls, 12);
    expect(capability.limits.turnTimeoutSeconds, 180);
    expect(capability.limits.snapshotMaxBytes, 8 * 1024 * 1024);
  });

  test('unavailable local capability reports misconfigured model honestly', () {
    final capability = CoachCapabilities.fromJson(
      coachCapabilitiesJson(
        state: 'unavailable',
        provider: 'local_codex_oauth',
        providerMode: 'local_development_only',
        modelRequested: 'unavailable-model',
        modelSource: 'explicit',
        serviceTier: 'fast',
        fastMode: true,
        reasonCode: 'unavailable_model',
      ),
    );

    expect(capability.state, CoachCapabilityState.unavailable);
    expect(capability.modelRequested, 'unavailable-model');
    expect(capability.reasonCode, 'unavailable_model');
  });

  test('response reads backend evidence and actual tool trace', () {
    final response = CoachResponse.fromJson(coachResponseJson());

    expect(response.contractVersion, coachResponseContractVersion);
    expect(response.usesLegacySelectedContext, isFalse);
    expect(response.evidence.single.source, 'focus_sessions');
    expect(response.evidence.single.recordCount, 12);
    expect(response.evidence.single.availableRecordCount, isNull);
    expect(response.agentTrace.toolCallCount, 1);
    expect(response.agentTrace.steps.single.tool, 'query_data');
    expect(response.provenance.snapshotRowCount, 120);
  });

  test('current free Coach rejects retired prompt and snapshot pairs', () {
    final current = CoachResponse.fromJson(coachResponseJson());
    final priorV1 = coachResponseJson();
    final priorV1Provenance = priorV1['provenance'] as Map<String, dynamic>;
    priorV1Provenance['prompt_version'] = 'free-coach-agent-prompt-v1';
    priorV1Provenance['context_version'] = 'personal-snapshot-v1';
    final priorV2 = coachResponseJson();
    final priorV2Provenance = priorV2['provenance'] as Map<String, dynamic>;
    priorV2Provenance['prompt_version'] = 'free-coach-agent-prompt-v2';
    priorV2Provenance['context_version'] = 'personal-snapshot-v1';

    expect(current.provenance.promptVersion, coachAgentPromptVersion);
    expect(
      () => CoachResponse.fromJson(priorV1),
      throwsA(isA<CoachContractException>()),
    );
    expect(
      () => CoachResponse.fromJson(priorV2),
      throwsA(isA<CoachContractException>()),
    );
  });

  test('response limits count Unicode code points rather than UTF-16 units',
      () {
    final reply = List.filled(3000, '😀').join();

    final response = CoachResponse.fromJson(
      coachResponseJson(reply: reply),
    );

    expect(response.reply.runes.length, 3000);
    expect(response.reply.length, 6000);
  });

  test('legacy V1 responses remain readable without suggestion actions', () {
    final response = CoachResponse.fromJson(coachLegacyResponseJson());

    expect(response.contractVersion, 'coach-response-v1');
    expect(response.usesLegacySelectedContext, isTrue);
    expect(response.reply, contains('older response'));
    expect(response.evidence.single.source, 'tasks');
    expect(response.evidence.single.recordCount, 1);
    expect(response.evidence.single.availableRecordCount, 2);
    expect(response.agentTrace.toolCallCount, 0);
    expect(response.agentTrace.limitations.single, contains('Legacy'));
  });

  test('legacy local Codex provenance does not invent Fast configuration', () {
    final response = CoachResponse.fromJson(
      coachLegacyResponseJson(
        provider: 'local_codex_oauth',
        providerMode: 'local_development_only',
        modelRequested: 'gpt-5.5',
        modelReported: 'gpt-5.5',
        modelSource: 'explicit',
      ),
    );

    expect(response.provenance.provider, CoachProviderName.localCodexOauth);
    expect(response.provenance.serviceTier, 'not_applicable');
    expect(response.provenance.serviceTierStatus, 'not_applicable');
    expect(response.provenance.fastMode, isFalse);
  });

  test('history accepts mixed old and current response contracts', () {
    final history = CoachHistory.fromJson(
      coachHistoryJson(
        turns: [
          {
            'request_id': coachRequestId,
            'message': 'Current question',
            'response': coachResponseJson(),
            'created_at': '2026-07-28T10:15:01Z',
          },
          {
            'request_id': coachSecondRequestId,
            'message': 'Older question',
            'response': coachLegacyResponseJson(),
            'created_at': '2026-07-27T10:15:01Z',
          },
        ],
      ),
    );

    expect(history.turns, hasLength(2));
    expect(history.turns.last.response.reply, contains('older response'));
  });

  test('strict contracts reject fabricated trace fields', () {
    final response = coachResponseJson();
    (response['agent_trace'] as Map<String, dynamic>)['invented'] = true;

    expect(
      () => CoachResponse.fromJson(response),
      throwsA(isA<CoachContractException>()),
    );
  });

  test('client rejects unverified Fast, trace, snapshot, and safety claims',
      () {
    final fakeFast = coachCapabilitiesJson()
      ..['service_tier'] = 'fast'
      ..['fast_mode'] = true;
    expect(
      () => CoachCapabilities.fromJson(fakeFast),
      throwsA(isA<CoachContractException>()),
    );

    final fakeWithModel = coachCapabilitiesJson(
      modelRequested: 'invented-model',
    );
    expect(
      () => CoachCapabilities.fromJson(fakeWithModel),
      throwsA(isA<CoachContractException>()),
    );

    final invalidTrace = coachResponseJson();
    final trace = invalidTrace['agent_trace'] as Map<String, dynamic>;
    ((trace['steps'] as List).single as Map<String, dynamic>)['duration_ms'] =
        180001;
    expect(
      () => CoachResponse.fromJson(invalidTrace),
      throwsA(isA<CoachContractException>()),
    );

    final oversizedSnapshot = coachResponseJson();
    (oversizedSnapshot['provenance']
        as Map<String, dynamic>)['snapshot_row_count'] = 50001;
    expect(
      () => CoachResponse.fromJson(oversizedSnapshot),
      throwsA(isA<CoachContractException>()),
    );

    final inconsistentSafety = coachResponseJson();
    (inconsistentSafety['safety'] as Map<String, dynamic>)['classification'] =
        'safety_redirect';
    expect(
      () => CoachResponse.fromJson(inconsistentSafety),
      throwsA(isA<CoachContractException>()),
    );

    final fakeWithReportedModel = coachResponseJson();
    (fakeWithReportedModel['provenance']
        as Map<String, dynamic>)['model_reported'] = 'invented-model';
    expect(
      () => CoachResponse.fromJson(fakeWithReportedModel),
      throwsA(isA<CoachContractException>()),
    );
  });

  test('history deletion confirmation remains a strict legacy envelope', () {
    expect(
      CoachHistoryDeleteResult.fromJson(coachHistoryDeleteJson()).deleted,
      isTrue,
    );
    expect(
      () => CoachHistoryDeleteResult.fromJson({'deleted': true}),
      throwsA(isA<CoachContractException>()),
    );
  });
}
