import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/coach/domain/coach.dart';

import 'support/coach_fixtures.dart';

void main() {
  test('capabilities accept only the exact bounded contract', () {
    final capability = CoachCapabilities.fromJson(coachCapabilitiesJson());

    expect(capability.state, CoachCapabilityState.ready);
    expect(capability.provider, CoachProviderName.fake);
    expect(capability.modelRequested, 'fake-coach-model');
    expect(capability.limits.messageCodepoints, coachMessageCodepoints);
    expect(capability.limits.contextBytes, coachContextBytes);
    expect(capability.limits.replyCodepoints, coachReplyCodepoints);

    final extra = _copy(coachCapabilitiesJson())..['user_id'] = 'forbidden';
    expect(
      () => CoachCapabilities.fromJson(extra),
      throwsA(isA<CoachContractException>()),
    );

    final coerced = _copy(coachCapabilitiesJson());
    (coerced['limits'] as Map<String, dynamic>)['message_codepoints'] = 2000.0;
    expect(
      () => CoachCapabilities.fromJson(coerced),
      throwsA(isA<CoachContractException>()),
    );

    final explicitNull = _copy(coachCapabilitiesJson())..['reason_code'] = null;
    expect(
      () => CoachCapabilities.fromJson(explicitNull),
      throwsA(isA<CoachContractException>()),
    );
  });

  test('request trims once, uses exact keys, and counts Unicode code points',
      () {
    final request = CoachRequest(
      requestId: coachRequestId,
      message: '  What matters today?  ',
      context: const CoachContextSelection.today(),
    );

    expect(request.toJson(), {
      'contract_version': 'coach-request-v2',
      'request_id': coachRequestId,
      'message': 'What matters today?',
      'context_scope': 'today',
      'context_parameters': <String, dynamic>{},
    });
    expect(
      CoachRequest(
        requestId: coachRequestId,
        message: _repeat('🧭', 2000),
        context: const CoachContextSelection.today(),
      ).message.runes,
      hasLength(2000),
    );
    expect(
      () => CoachRequest(
        requestId: coachRequestId,
        message: _repeat('🧭', 2001),
        context: const CoachContextSelection.today(),
      ),
      throwsA(isA<CoachInputException>()),
    );
    expect(
      () => CoachRequest(
        requestId: coachRequestId,
        message: '   ',
        context: const CoachContextSelection.today(),
      ),
      throwsA(isA<CoachInputException>()),
    );
  });

  test('request emits exact context parameters for every Coach mode', () {
    Map<String, dynamic> body(CoachContextSelection context) => CoachRequest(
          requestId: coachRequestId,
          message: 'Use this context',
          context: context,
        ).toJson();

    expect(
      body(
        const CoachContextSelection.patterns(CoachPatternHorizon.days90),
      ),
      containsPair('context_parameters', {'horizon': '90_days'}),
    );
    expect(
      body(
        const CoachContextSelection.patterns(CoachPatternHorizon.year1),
      ),
      containsPair('context_parameters', {'horizon': '1_year'}),
    );
    expect(
      body(
        const CoachContextSelection.patterns(
          CoachPatternHorizon.allAvailable,
        ),
      ),
      containsPair(
        'context_parameters',
        {'horizon': 'all_available'},
      ),
    );
    expect(
      body(CoachContextSelection.focus(coachFocusSessionId)),
      containsPair(
        'context_parameters',
        {'focus_session_id': coachFocusSessionId},
      ),
    );
    expect(
      body(const CoachContextSelection.review()),
      containsPair('context_parameters', <String, dynamic>{}),
    );
    expect(
      () => CoachContextSelection.fromWire(
        scope: 'review',
        parameters: {'horizon': '90_days'},
      ),
      throwsA(isA<CoachContractException>()),
    );
  });

  test('context options parse bounded Focus choices and exact default', () {
    final options = CoachContextOptions.fromJson(coachContextOptionsJson());

    expect(options.timezone, 'Europe/Berlin');
    expect(options.personalPatternAnalysisEnabled, isTrue);
    expect(options.focusOptions, hasLength(2));
    expect(options.focusOptions.first.localStartedAt.hour, 9);
    expect(options.focusOptions.first.hasReflection, isTrue);
    expect(options.defaultFocusSessionId, coachFocusSessionId);

    final duplicate = _copy(
      coachContextOptionsJson(
        focusOptions: [
          coachFocusOptionJson(),
          coachFocusOptionJson(),
        ],
      ),
    );
    expect(
      () => CoachContextOptions.fromJson(duplicate),
      throwsA(isA<CoachContractException>()),
    );

    final missingDefault = _copy(coachContextOptionsJson())
      ..['default_focus_session_id'] = '77777777-7777-4777-8777-777777777777';
    expect(
      () => CoachContextOptions.fromJson(missingDefault),
      throwsA(isA<CoachContractException>()),
    );
  });

  test('response parses uncertainty, safety, suggestion, context, provenance',
      () {
    final response = CoachResponse.fromJson(coachResponseJson());

    expect(response.requestId, coachRequestId);
    expect(response.uncertainty.level, CoachUncertaintyLevel.medium);
    expect(response.safety.classification, CoachSafetyClassification.normal);
    expect(response.stagedSuggestion!.title, contains('smaller focus'));
    expect(response.usedContext, hasLength(2));
    expect(response.usedContext.last.omittedCount, 1);
    expect(response.provenance.source, CoachProvenanceSource.model);
    expect(response.provenance.providerCalled, isTrue);
  });

  test('response accepts the transparent V3 evidence source manifest', () {
    final sources = [
      'daily_capture',
      'focus_reflections',
      'habit_outcomes',
      'decision_feedback',
      'weekly_reviews',
      'task_lifecycle',
    ];
    final response = CoachResponse.fromJson(
      coachResponseJson(
        usedContext: [
          for (final source in sources)
            {
              'source': source,
              'available_count': 1,
              'included_count': 1,
              'omitted_count': 0,
              'freshness': 'current',
            },
        ],
      ),
    );

    expect(
      response.usedContext.map((item) => item.source.code),
      sources,
    );
  });

  test('response accepts paired V1/V2 history and rejects mixed provenance',
      () {
    final legacy = _copy(coachResponseJson());
    final legacyProvenance = legacy['provenance'] as Map<String, dynamic>;
    legacyProvenance
      ..['prompt_version'] = 'controlled-coach-prompt-v1'
      ..['context_version'] = 'coach-context-v1';
    expect(
      CoachResponse.fromJson(legacy).provenance.contextVersion,
      'coach-context-v1',
    );

    final previous = CoachResponse.fromJson(
      coachResponseJson(
        promptVersion: 'controlled-coach-prompt-v2',
        contextVersion: 'coach-context-v2',
      ),
    );
    expect(previous.provenance.contextVersion, 'coach-context-v2');

    final mixed = _copy(coachResponseJson());
    (mixed['provenance'] as Map<String, dynamic>)['context_version'] =
        'coach-context-v2';
    expect(
      () => CoachResponse.fromJson(mixed),
      throwsA(isA<CoachContractException>()),
    );
  });

  test('response rejects nested extras, coercions, count mismatches, and nulls',
      () {
    final suggestionExtra = _copy(coachResponseJson());
    (suggestionExtra['staged_suggestion'] as Map<String, dynamic>)['command'] =
        'complete_task';
    expect(
      () => CoachResponse.fromJson(suggestionExtra),
      throwsA(isA<CoachContractException>()),
    );

    final contextMismatch = _copy(coachResponseJson());
    final context = (contextMismatch['used_context'] as List).first as Map;
    context['included_count'] = 2;
    expect(
      () => CoachResponse.fromJson(contextMismatch),
      throwsA(isA<CoachContractException>()),
    );

    final coerced = _copy(coachResponseJson());
    (coerced['used_context'] as List).first['available_count'] = '1';
    expect(
      () => CoachResponse.fromJson(coerced),
      throwsA(isA<CoachContractException>()),
    );

    final explicitNull = _copy(coachResponseJson());
    (explicitNull['uncertainty'] as Map<String, dynamic>)['reason'] = null;
    expect(
      () => CoachResponse.fromJson(explicitNull),
      throwsA(isA<CoachContractException>()),
    );
  });

  test('provenance enforces provider-called truth and aware timestamps', () {
    final falseModelCall = _copy(coachResponseJson());
    (falseModelCall['provenance'] as Map<String, dynamic>)['provider_called'] =
        false;
    expect(
      () => CoachResponse.fromJson(falseModelCall),
      throwsA(isA<CoachContractException>()),
    );

    final bypassSafety = CoachResponse.fromJson(
      coachResponseJson(
        provenanceSource: 'deterministic_safety',
        providerCalled: false,
        safetyClassification: 'safety_redirect',
      ),
    );
    expect(bypassSafety.provenance.providerCalled, isFalse);

    final calledSafety = CoachResponse.fromJson(
      coachResponseJson(
        provenanceSource: 'deterministic_safety',
        providerCalled: true,
        safetyClassification: 'safety_redirect',
      ),
    );
    expect(calledSafety.provenance.providerCalled, isTrue);

    for (final inconsistent in [
      coachResponseJson(
        provenanceSource: 'model',
        providerCalled: true,
        safetyClassification: 'safety_redirect',
      ),
      coachResponseJson(
        provenanceSource: 'deterministic_safety',
        providerCalled: false,
        safetyClassification: 'normal',
      ),
    ]) {
      expect(
        () => CoachResponse.fromJson(inconsistent),
        throwsA(isA<CoachContractException>()),
      );
    }

    final naiveTime = _copy(coachResponseJson());
    (naiveTime['provenance'] as Map<String, dynamic>)['generated_at'] =
        '2026-07-13T10:15:00';
    expect(
      () => CoachResponse.fromJson(naiveTime),
      throwsA(isA<CoachContractException>()),
    );
  });

  test('history requires nested request identity and strict delete envelope',
      () {
    final history = CoachHistory.fromJson(coachHistoryJson());
    expect(history.turns.single.message, 'How should I pace today?');
    expect(history.turns.single.context.scope, CoachContextScope.today);

    final legacy = CoachHistory.fromJson(
      coachHistoryJson(includeContext: false),
    );
    expect(legacy.turns.single.context.scope, CoachContextScope.today);

    final mismatch = _copy(coachHistoryJson());
    ((mismatch['turns'] as List).single as Map<String, dynamic>)['request_id'] =
        coachSecondRequestId;
    expect(
      () => CoachHistory.fromJson(mismatch),
      throwsA(isA<CoachContractException>()),
    );

    expect(
      CoachHistoryDeleteResult.fromJson(coachHistoryDeleteJson()).deleted,
      isTrue,
    );
    final wrongDelete = _copy(coachHistoryDeleteJson())..['turns'] = [];
    expect(
      () => CoachHistoryDeleteResult.fromJson(wrongDelete),
      throwsA(isA<CoachContractException>()),
    );
  });

  test('memory selection enforces types, counts, ownership, and exact fields',
      () {
    final selection = CoachMemorySelection.fromJson(coachMemoriesJson());
    expect(selection.selectedCount, 1);
    expect(selection.memories.first.ownership, CoachMemoryOwnership.setup);
    expect(selection.memories.last.type, CoachMemoryType.pattern);

    final invalidType = _copy(coachMemoriesJson());
    ((invalidType['memories'] as List).first as Map<String, dynamic>)['type'] =
        'secret';
    expect(
      () => CoachMemorySelection.fromJson(invalidType),
      throwsA(isA<CoachContractException>()),
    );

    final badCount = _copy(coachMemoriesJson())..['available_count'] = 1;
    expect(
      () => CoachMemorySelection.fromJson(badCount),
      throwsA(isA<CoachContractException>()),
    );

    final extra = _copy(coachMemoriesJson());
    ((extra['memories'] as List).first as Map<String, dynamic>)['metadata'] =
        {};
    expect(
      () => CoachMemorySelection.fromJson(extra),
      throwsA(isA<CoachContractException>()),
    );
  });
}

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

String _repeat(String value, int count) => List.filled(count, value).join();
