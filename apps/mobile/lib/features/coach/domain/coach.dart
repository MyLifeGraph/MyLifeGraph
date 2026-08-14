import '../../../core/contracts/strict_contract.dart';

const coachRequestContractVersion = 'coach-request-v3';
const coachResponseContractVersion = 'coach-response-v2';
const _legacyCoachResponseContractVersion = 'coach-response-v1';
const coachCapabilitiesContractVersion = 'coach-capabilities-v2';
const coachHistoryContractVersion = 'coach-history-v2';
const coachAgentPromptVersion = 'free-coach-agent-prompt-v4';
const _acceptedCoachAgentPromptVersions = {coachAgentPromptVersion};
const coachAgentContextVersion = 'personal-snapshot-v3';
const coachMessageCodepoints = 2000;
const coachReplyCodepoints = 4000;

enum CoachCapabilityState {
  disabled('disabled'),
  unavailable('unavailable'),
  ready('ready');

  const CoachCapabilityState(this.code);
  final String code;

  static CoachCapabilityState? fromCode(Object? value) => switch (value) {
        'disabled' => disabled,
        'unavailable' => unavailable,
        'ready' => ready,
        _ => null,
      };
}

enum CoachProviderName {
  disabled('disabled'),
  localCodexOauth('local_codex_oauth'),
  fake('fake');

  const CoachProviderName(this.code);
  final String code;

  static CoachProviderName? fromCode(Object? value) => switch (value) {
        'disabled' => disabled,
        'local_codex_oauth' => localCodexOauth,
        'fake' => fake,
        _ => null,
      };
}

class CoachAgentLimits {
  const CoachAgentLimits({
    required this.messageCodepoints,
    required this.replyCodepoints,
    required this.requestsPerLocalDay,
    required this.remainingRequests,
    required this.maxToolCalls,
    required this.turnTimeoutSeconds,
    required this.sqlTimeoutSeconds,
    required this.pythonTimeoutSeconds,
    required this.snapshotMaxRows,
    required this.snapshotMaxBytes,
  });

  factory CoachAgentLimits.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'message_codepoints',
        'reply_codepoints',
        'requests_per_local_day',
        'remaining_requests',
        'max_tool_calls',
        'turn_timeout_seconds',
        'sql_timeout_seconds',
        'python_timeout_seconds',
        'snapshot_max_rows',
        'snapshot_max_bytes',
      },
      'Coach limits',
    );
    final value = CoachAgentLimits(
      messageCodepoints: _int(json['message_codepoints']),
      replyCodepoints: _int(json['reply_codepoints']),
      requestsPerLocalDay: _int(json['requests_per_local_day']),
      remainingRequests: _int(json['remaining_requests']),
      maxToolCalls: _int(json['max_tool_calls']),
      turnTimeoutSeconds: _int(json['turn_timeout_seconds']),
      sqlTimeoutSeconds: _int(json['sql_timeout_seconds']),
      pythonTimeoutSeconds: _int(json['python_timeout_seconds']),
      snapshotMaxRows: _int(json['snapshot_max_rows']),
      snapshotMaxBytes: _int(json['snapshot_max_bytes']),
    );
    if (value.messageCodepoints != 2000 ||
        value.replyCodepoints != 4000 ||
        value.requestsPerLocalDay != 20 ||
        value.remainingRequests < 0 ||
        value.remainingRequests > value.requestsPerLocalDay ||
        value.maxToolCalls != 12 ||
        value.turnTimeoutSeconds != 180 ||
        value.sqlTimeoutSeconds != 5 ||
        value.pythonTimeoutSeconds != 30 ||
        value.snapshotMaxRows != 50000 ||
        value.snapshotMaxBytes != 8388608) {
      throw const CoachContractException('Coach limits are invalid.');
    }
    return value;
  }

  final int messageCodepoints;
  final int replyCodepoints;
  final int requestsPerLocalDay;
  final int remainingRequests;
  final int maxToolCalls;
  final int turnTimeoutSeconds;
  final int sqlTimeoutSeconds;
  final int pythonTimeoutSeconds;
  final int snapshotMaxRows;
  final int snapshotMaxBytes;
}

class CoachCapabilities {
  const CoachCapabilities({
    required this.state,
    required this.provider,
    required this.providerMode,
    required this.modelRequested,
    required this.modelSource,
    required this.serviceTier,
    required this.fastMode,
    required this.reasonCode,
    required this.limits,
  });

  factory CoachCapabilities.localDemo() => const CoachCapabilities(
        state: CoachCapabilityState.disabled,
        provider: CoachProviderName.disabled,
        providerMode: 'disabled',
        modelRequested: null,
        modelSource: 'not_applicable',
        serviceTier: 'not_applicable',
        fastMode: false,
        reasonCode: 'local_demo',
        limits: CoachAgentLimits(
          messageCodepoints: 2000,
          replyCodepoints: 4000,
          requestsPerLocalDay: 20,
          remainingRequests: 0,
          maxToolCalls: 12,
          turnTimeoutSeconds: 180,
          sqlTimeoutSeconds: 5,
          pythonTimeoutSeconds: 30,
          snapshotMaxRows: 50000,
          snapshotMaxBytes: 8388608,
        ),
      );

  factory CoachCapabilities.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'contract_version',
        'state',
        'provider',
        'provider_mode',
        'model_requested',
        'model_source',
        'service_tier',
        'fast_mode',
        'reason_code',
        'limits',
      },
      'Coach capabilities',
    );
    if (json['contract_version'] != coachCapabilitiesContractVersion) {
      throw const CoachContractException(
        'Coach capabilities contract is unsupported.',
      );
    }
    final state = CoachCapabilityState.fromCode(json['state']);
    final provider = CoachProviderName.fromCode(json['provider']);
    final fastMode = json['fast_mode'];
    if (state == null || provider == null || fastMode is! bool) {
      throw const CoachContractException('Coach capabilities are invalid.');
    }
    final result = CoachCapabilities(
      state: state,
      provider: provider,
      providerMode: _text(json['provider_mode'], 64),
      modelRequested: _optionalText(json['model_requested'], 100),
      modelSource: _text(json['model_source'], 64),
      serviceTier: _text(json['service_tier'], 32),
      fastMode: fastMode,
      reasonCode: _text(json['reason_code'], 64),
      limits: CoachAgentLimits.fromJson(_map(json['limits'], 'limits')),
    );
    switch (provider) {
      case CoachProviderName.localCodexOauth:
        if (result.providerMode != 'local_development_only' ||
            result.modelSource != 'explicit' ||
            result.serviceTier != 'fast' ||
            !result.fastMode ||
            state == CoachCapabilityState.ready &&
                result.modelRequested != 'gpt-5.5') {
          throw const CoachContractException(
            'Local Coach Fast provenance is invalid.',
          );
        }
      case CoachProviderName.fake:
        if (result.providerMode != 'deterministic_test_only' ||
            result.modelRequested != null ||
            result.modelSource != 'not_applicable' ||
            result.serviceTier != 'not_applicable' ||
            result.fastMode) {
          throw const CoachContractException(
            'Fake Coach capabilities are invalid.',
          );
        }
      case CoachProviderName.disabled:
        if (result.providerMode != 'disabled' ||
            result.modelRequested != null ||
            result.modelSource != 'not_applicable' ||
            result.serviceTier != 'not_applicable' ||
            result.fastMode) {
          throw const CoachContractException(
            'Disabled Coach capabilities are invalid.',
          );
        }
    }
    if (state == CoachCapabilityState.ready &&
            provider == CoachProviderName.disabled ||
        state == CoachCapabilityState.disabled &&
            provider != CoachProviderName.disabled) {
      throw const CoachContractException(
        'Coach capability state and provider are inconsistent.',
      );
    }
    return result;
  }

  final CoachCapabilityState state;
  final CoachProviderName provider;
  final String providerMode;
  final String? modelRequested;
  final String modelSource;
  final String serviceTier;
  final bool fastMode;
  final String reasonCode;
  final CoachAgentLimits limits;

  bool get canRespond =>
      state == CoachCapabilityState.ready && limits.remainingRequests > 0;
}

class CoachRequest {
  CoachRequest({required this.requestId, required String message})
      : message = message.trim() {
    if (!isStrictUuid(
      requestId,
      lowercaseOnly: false,
      requireRfcVariant: false,
    )) {
      throw const CoachInputException('Coach request id is invalid.');
    }
    if (this.message.isEmpty ||
        this.message.runes.length > coachMessageCodepoints) {
      throw const CoachInputException(
        'Coach message must contain 1 to 2,000 Unicode code points.',
      );
    }
  }

  final String requestId;
  final String message;

  Map<String, dynamic> toJson() => {
        'contract_version': coachRequestContractVersion,
        'request_id': requestId,
        'message': message,
      };
}

class CoachUncertainty {
  const CoachUncertainty({required this.level, required this.reason});

  factory CoachUncertainty.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, const {'level', 'reason'}, 'Coach uncertainty');
    final level = _text(json['level'], 20);
    if (!const {'low', 'medium', 'high'}.contains(level)) {
      throw const CoachContractException('Coach uncertainty is invalid.');
    }
    return CoachUncertainty(
      level: level,
      reason: _text(json['reason'], 300),
    );
  }

  final String level;
  final String reason;
}

class CoachSafety {
  const CoachSafety(this.classification);

  factory CoachSafety.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, const {'classification'}, 'Coach safety');
    final value = _text(json['classification'], 30);
    if (!const {'normal', 'sensitive', 'safety_redirect'}.contains(value)) {
      throw const CoachContractException('Coach safety is invalid.');
    }
    return CoachSafety(value);
  }

  final String classification;
}

class CoachEvidence {
  const CoachEvidence({
    required this.source,
    required this.recordCount,
    required this.periodStart,
    required this.periodEnd,
    this.availableRecordCount,
  });

  factory CoachEvidence.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'source', 'record_count', 'period_start', 'period_end'},
      'Coach evidence',
    );
    final count = _int(json['record_count']);
    final periodStart = _optionalText(json['period_start'], 40);
    final periodEnd = _optionalText(json['period_end'], 40);
    if (count < 0 || (periodStart == null) != (periodEnd == null)) {
      throw const CoachContractException('Coach evidence count is invalid.');
    }
    return CoachEvidence(
      source: _text(json['source'], 80),
      recordCount: count,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
  }

  final String source;
  final int recordCount;
  final String? periodStart;
  final String? periodEnd;
  final int? availableRecordCount;
}

class CoachTraceStep {
  const CoachTraceStep({
    required this.sequence,
    required this.tool,
    required this.status,
    required this.summary,
    required this.rowCount,
    required this.durationMs,
  });

  factory CoachTraceStep.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'sequence',
        'tool',
        'status',
        'summary',
        'row_count',
        'duration_ms',
      },
      'Coach trace step',
    );
    final tool = _text(json['tool'], 30);
    final status = _text(json['status'], 20);
    final rowCount = json['row_count'] == null ? null : _int(json['row_count']);
    if (!const {'inspect_data', 'query_data', 'run_python'}.contains(tool) ||
        !const {'completed', 'failed'}.contains(status) ||
        rowCount != null && rowCount < 0) {
      throw const CoachContractException('Coach trace step is invalid.');
    }
    final sequence = _int(json['sequence']);
    final durationMs = _int(json['duration_ms']);
    if (sequence < 1 ||
        sequence > 12 ||
        durationMs < 0 ||
        durationMs > 180000) {
      throw const CoachContractException('Coach trace step is invalid.');
    }
    return CoachTraceStep(
      sequence: sequence,
      tool: tool,
      status: status,
      summary: _text(json['summary'], 500),
      rowCount: rowCount,
      durationMs: durationMs,
    );
  }

  final int sequence;
  final String tool;
  final String status;
  final String summary;
  final int? rowCount;
  final int durationMs;
}

class CoachAgentTrace {
  const CoachAgentTrace({
    required this.toolCallCount,
    required this.steps,
    required this.limitations,
  });

  factory CoachAgentTrace.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'tool_call_count', 'steps', 'limitations'},
      'Coach agent trace',
    );
    final rawSteps = json['steps'];
    final rawLimitations = json['limitations'];
    if (rawSteps is! List ||
        rawSteps.length > 12 ||
        rawLimitations is! List ||
        rawLimitations.length > 20) {
      throw const CoachContractException('Coach agent trace is invalid.');
    }
    final steps = rawSteps
        .map((value) => CoachTraceStep.fromJson(_map(value, 'trace step')))
        .toList(growable: false);
    final count = _int(json['tool_call_count']);
    if (count != steps.length ||
        steps.asMap().entries.any(
              (entry) => entry.value.sequence != entry.key + 1,
            )) {
      throw const CoachContractException('Coach trace order is invalid.');
    }
    return CoachAgentTrace(
      toolCallCount: count,
      steps: steps,
      limitations: rawLimitations
          .map((value) => _text(value, 500))
          .toList(growable: false),
    );
  }

  final int toolCallCount;
  final List<CoachTraceStep> steps;
  final List<String> limitations;
}

class CoachProvenance {
  const CoachProvenance({
    required this.source,
    required this.provider,
    required this.providerMode,
    required this.modelRequested,
    required this.modelReported,
    required this.modelSource,
    required this.promptVersion,
    required this.contextVersion,
    required this.generatedAt,
    required this.providerCalled,
    required this.serviceTier,
    required this.serviceTierStatus,
    required this.fastMode,
    required this.snapshotRowCount,
    required this.snapshotBytes,
  });

  factory CoachProvenance.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'source',
        'provider',
        'provider_mode',
        'model_requested',
        'model_reported',
        'model_source',
        'prompt_version',
        'context_version',
        'generated_at',
        'provider_called',
        'service_tier',
        'service_tier_status',
        'fast_mode',
        'snapshot_row_count',
        'snapshot_bytes',
      },
      'Coach provenance',
    );
    final provider = CoachProviderName.fromCode(json['provider']);
    final providerCalled = json['provider_called'];
    final fastMode = json['fast_mode'];
    if (provider == null || providerCalled is! bool || fastMode is! bool) {
      throw const CoachContractException('Coach provenance is invalid.');
    }
    final result = CoachProvenance(
      source: _text(json['source'], 30),
      provider: provider,
      providerMode: _text(json['provider_mode'], 64),
      modelRequested: _optionalText(json['model_requested'], 100),
      modelReported: _optionalText(json['model_reported'], 100),
      modelSource: _text(json['model_source'], 64),
      promptVersion: _text(json['prompt_version'], 100),
      contextVersion: _text(json['context_version'], 100),
      generatedAt: _dateTime(json['generated_at']),
      providerCalled: providerCalled,
      serviceTier: _text(json['service_tier'], 32),
      serviceTierStatus: _text(json['service_tier_status'], 32),
      fastMode: fastMode,
      snapshotRowCount: _int(json['snapshot_row_count']),
      snapshotBytes: _int(json['snapshot_bytes']),
    );
    if (!const {'model', 'deterministic_safety'}.contains(result.source) ||
        !_acceptedCoachAgentPromptVersions.contains(result.promptVersion) ||
        !_validAgentContractPair(
          result.promptVersion,
          result.contextVersion,
        ) ||
        result.snapshotRowCount < 0 ||
        result.snapshotRowCount > 50000 ||
        result.snapshotBytes < 0 ||
        result.snapshotBytes > 8388608 ||
        result.source == 'model' && !result.providerCalled) {
      throw const CoachContractException('Coach provenance is invalid.');
    }
    switch (provider) {
      case CoachProviderName.localCodexOauth:
        if (result.providerMode != 'local_development_only' ||
            result.modelRequested != 'gpt-5.5' ||
            result.modelReported != null && result.modelReported != 'gpt-5.5' ||
            result.modelSource != 'explicit' ||
            result.serviceTier != 'fast' ||
            result.serviceTierStatus != 'configured' ||
            !result.fastMode) {
          throw const CoachContractException(
            'Coach Fast provenance is invalid.',
          );
        }
      case CoachProviderName.fake:
        if (result.providerMode != 'deterministic_test_only' ||
            result.modelRequested != null ||
            result.modelReported != null ||
            result.modelSource != 'not_applicable' ||
            result.serviceTier != 'not_applicable' ||
            result.serviceTierStatus != 'not_applicable' ||
            result.fastMode) {
          throw const CoachContractException(
            'Fake Coach provenance is invalid.',
          );
        }
      case CoachProviderName.disabled:
        if (result.providerMode != 'disabled' ||
            result.modelRequested != null ||
            result.modelReported != null ||
            result.modelSource != 'not_applicable' ||
            result.serviceTier != 'not_applicable' ||
            result.serviceTierStatus != 'not_applicable' ||
            result.fastMode ||
            result.providerCalled ||
            result.source != 'deterministic_safety') {
          throw const CoachContractException(
            'Disabled Coach provenance is invalid.',
          );
        }
    }
    return result;
  }

  factory CoachProvenance.fromLegacy(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'source',
        'provider',
        'provider_mode',
        'model_requested',
        'model_reported',
        'model_source',
        'prompt_version',
        'context_version',
        'generated_at',
        'provider_called',
      },
      'Legacy Coach provenance',
    );
    final provider = CoachProviderName.fromCode(json['provider']);
    if (provider == null || json['provider_called'] is! bool) {
      throw const CoachContractException(
        'Legacy Coach provenance is invalid.',
      );
    }
    return CoachProvenance(
      source: _text(json['source'], 30),
      provider: provider,
      providerMode: _text(json['provider_mode'], 64),
      modelRequested: _optionalText(json['model_requested'], 100),
      modelReported: _optionalText(json['model_reported'], 100),
      modelSource: _text(json['model_source'], 64),
      promptVersion: _text(json['prompt_version'], 100),
      contextVersion: _text(json['context_version'], 100),
      generatedAt: _dateTime(json['generated_at']),
      providerCalled: json['provider_called'] as bool,
      serviceTier: 'not_applicable',
      serviceTierStatus: 'not_applicable',
      fastMode: false,
      snapshotRowCount: 0,
      snapshotBytes: 0,
    );
  }

  final String source;
  final CoachProviderName provider;
  final String providerMode;
  final String? modelRequested;
  final String? modelReported;
  final String modelSource;
  final String promptVersion;
  final String contextVersion;
  final DateTime generatedAt;
  final bool providerCalled;
  final String serviceTier;
  final String serviceTierStatus;
  final bool fastMode;
  final int snapshotRowCount;
  final int snapshotBytes;
}

class CoachResponse {
  const CoachResponse({
    required this.contractVersion,
    required this.requestId,
    required this.reply,
    required this.uncertainty,
    required this.safety,
    required this.evidence,
    required this.agentTrace,
    required this.provenance,
  });

  factory CoachResponse.fromJson(Map<String, dynamic> json) {
    if (json['contract_version'] == _legacyCoachResponseContractVersion) {
      return CoachResponse._fromLegacy(json);
    }
    _expectExactKeys(
      json,
      const {
        'contract_version',
        'request_id',
        'reply',
        'uncertainty',
        'safety',
        'evidence',
        'agent_trace',
        'provenance',
      },
      'Coach response',
    );
    if (json['contract_version'] != coachResponseContractVersion ||
        json['evidence'] is! List ||
        (json['evidence'] as List).length > 100) {
      throw const CoachContractException(
        'Coach response contract is unsupported.',
      );
    }
    final result = CoachResponse(
      contractVersion: coachResponseContractVersion,
      requestId: _uuidText(json['request_id']),
      reply: _text(json['reply'], coachReplyCodepoints),
      uncertainty: CoachUncertainty.fromJson(
        _map(json['uncertainty'], 'uncertainty'),
      ),
      safety: CoachSafety.fromJson(_map(json['safety'], 'safety')),
      evidence: (json['evidence'] as List)
          .map((value) => CoachEvidence.fromJson(_map(value, 'evidence')))
          .toList(growable: false),
      agentTrace: CoachAgentTrace.fromJson(
        _map(json['agent_trace'], 'agent trace'),
      ),
      provenance: CoachProvenance.fromJson(
        _map(json['provenance'], 'provenance'),
      ),
    );
    _validateSafetyProvenance(result);
    return result;
  }

  factory CoachResponse._fromLegacy(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'contract_version',
        'request_id',
        'reply',
        'uncertainty',
        'staged_suggestion',
        'safety',
        'used_context',
        'provenance',
      },
      'Legacy Coach response',
    );
    final used = json['used_context'];
    if (used is! List) {
      throw const CoachContractException('Legacy Coach response is invalid.');
    }
    _validateLegacySuggestion(json['staged_suggestion']);
    final result = CoachResponse(
      contractVersion: _legacyCoachResponseContractVersion,
      requestId: _uuidText(json['request_id']),
      reply: _text(json['reply'], coachReplyCodepoints),
      uncertainty: CoachUncertainty.fromJson(
        _map(json['uncertainty'], 'uncertainty'),
      ),
      safety: CoachSafety.fromJson(_map(json['safety'], 'safety')),
      evidence: used.map((value) {
        final item = _map(value, 'legacy context');
        _expectExactKeys(
          item,
          const {
            'source',
            'available_count',
            'included_count',
            'omitted_count',
            'freshness',
          },
          'Legacy Coach context',
        );
        final available = _int(item['available_count']);
        final included = _int(item['included_count']);
        final omitted = _int(item['omitted_count']);
        if (available < 0 ||
            included < 0 ||
            omitted < 0 ||
            included + omitted != available) {
          throw const CoachContractException(
            'Legacy Coach context counts are invalid.',
          );
        }
        return CoachEvidence(
          source: _text(item['source'], 80),
          recordCount: included,
          periodStart: null,
          periodEnd: null,
          availableRecordCount: available,
        );
      }).toList(growable: false),
      agentTrace: const CoachAgentTrace(
        toolCallCount: 0,
        steps: [],
        limitations: ['Legacy response: no tool trace was recorded.'],
      ),
      provenance: CoachProvenance.fromLegacy(
        _map(json['provenance'], 'provenance'),
      ),
    );
    _validateSafetyProvenance(result);
    return result;
  }

  final String contractVersion;
  final String requestId;
  final String reply;
  final CoachUncertainty uncertainty;
  final CoachSafety safety;
  final List<CoachEvidence> evidence;
  final CoachAgentTrace agentTrace;
  final CoachProvenance provenance;

  bool get usesLegacySelectedContext =>
      contractVersion == _legacyCoachResponseContractVersion;
}

class CoachHistoryTurn {
  const CoachHistoryTurn({
    required this.requestId,
    required this.message,
    required this.response,
    required this.createdAt,
  });

  factory CoachHistoryTurn.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'request_id', 'message', 'response', 'created_at'},
      'Coach history turn',
    );
    final response = CoachResponse.fromJson(_map(json['response'], 'response'));
    final requestId = _uuidText(json['request_id']);
    if (requestId != response.requestId) {
      throw const CoachContractException(
        'Coach history identity is inconsistent.',
      );
    }
    return CoachHistoryTurn(
      requestId: requestId,
      message: _text(json['message'], coachMessageCodepoints),
      response: response,
      createdAt: _dateTime(json['created_at']),
    );
  }

  final String requestId;
  final String message;
  final CoachResponse response;
  final DateTime createdAt;
}

class CoachHistory {
  const CoachHistory(this.turns);

  factory CoachHistory.empty() => const CoachHistory([]);

  factory CoachHistory.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'contract_version', 'turns'},
      'Coach history',
    );
    if (json['contract_version'] != coachHistoryContractVersion ||
        json['turns'] is! List) {
      throw const CoachContractException('Coach history is invalid.');
    }
    return CoachHistory(
      (json['turns'] as List)
          .map((value) => CoachHistoryTurn.fromJson(_map(value, 'turn')))
          .toList(growable: false),
    );
  }

  final List<CoachHistoryTurn> turns;
}

class CoachHistoryDeleteResult {
  const CoachHistoryDeleteResult(this.deleted);

  factory CoachHistoryDeleteResult.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'contract_version', 'deleted'},
      'Coach deletion result',
    );
    if (json['contract_version'] != 'coach-history-v1' ||
        json['deleted'] is! bool) {
      throw const CoachContractException('Coach deletion result is invalid.');
    }
    return CoachHistoryDeleteResult(json['deleted'] as bool);
  }

  final bool deleted;
}

void _validateSafetyProvenance(CoachResponse response) {
  final deterministic = response.provenance.source == 'deterministic_safety';
  final redirected = response.safety.classification == 'safety_redirect';
  if (deterministic != redirected) {
    throw const CoachContractException(
      'Coach safety and provenance are inconsistent.',
    );
  }
}

void _validateLegacySuggestion(Object? value) {
  if (value == null) return;
  final suggestion = _map(value, 'legacy suggestion');
  _expectExactKeys(
    suggestion,
    const {'title', 'rationale'},
    'Legacy Coach suggestion',
  );
  _text(suggestion['title'], 120);
  _text(suggestion['rationale'], 500);
}

sealed class CoachStreamEvent {
  const CoachStreamEvent();
}

class CoachStartedEvent extends CoachStreamEvent {
  const CoachStartedEvent(this.requestId);
  final String requestId;
}

class CoachActivityEvent extends CoachStreamEvent {
  const CoachActivityEvent(this.message);
  final String message;
}

class CoachCompletedEvent extends CoachStreamEvent {
  const CoachCompletedEvent(this.response);
  final CoachResponse response;
}

class CoachFailedEvent extends CoachStreamEvent {
  const CoachFailedEvent(this.error);
  final CoachErrorDetail error;
}

class CoachErrorDetail {
  const CoachErrorDetail({
    required this.code,
    required this.message,
    required this.retryable,
  });

  factory CoachErrorDetail.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'code', 'message', 'retryable'},
      'Coach error',
    );
    if (json['retryable'] is! bool) {
      throw const CoachContractException('Coach error is invalid.');
    }
    return CoachErrorDetail(
      code: _text(json['code'], 64),
      message: _text(json['message'], 300),
      retryable: json['retryable'] as bool,
    );
  }

  final String code;
  final String message;
  final bool retryable;
}

class CoachInputException implements Exception {
  const CoachInputException(this.message);
  final String message;
}

class CoachContractException implements Exception {
  const CoachContractException(this.message);
  final String message;
}

bool _validAgentContractPair(String promptVersion, String contextVersion) =>
    promptVersion == coachAgentPromptVersion &&
    contextVersion == coachAgentContextVersion;

Map<String, dynamic> _map(Object? value, String name) {
  return requireStrictMap(
    value,
    onFailure: () => throw CoachContractException('Coach $name is invalid.'),
  );
}

String _text(Object? value, int max) {
  return requireStrictString(
    value,
    maxLength: max,
    whitespace: StrictStringWhitespace.trim,
    length: StrictStringLength.runes,
    measureBeforeWhitespace: true,
    onFailure: () => throw const CoachContractException(
      'Coach text is invalid.',
    ),
  );
}

String? _optionalText(Object? value, int max) =>
    value == null ? null : _text(value, max);

int _int(Object? value) {
  return requireStrictInt(
    value,
    onFailure: () => throw const CoachContractException(
      'Coach number is invalid.',
    ),
  );
}

DateTime _dateTime(Object? value) {
  return requireStrictAwareDateTime(
    value,
    exactSecondsFormat: false,
    onFailure: () => throw const CoachContractException(
      'Coach date is invalid.',
    ),
  );
}

String _uuidText(Object? value) {
  return requireStrictUuid(
    value,
    lowercaseOnly: false,
    requireRfcVariant: false,
    onFailure: () => throw const CoachContractException(
      'Coach request id is invalid.',
    ),
  ).toLowerCase();
}

void _expectExactKeys(
  Map<String, dynamic> json,
  Set<String> keys,
  String name,
) {
  requireStrictKeys(
    json,
    requiredKeys: keys,
    onFailure: () => throw CoachContractException(
      '$name has unexpected or missing fields.',
    ),
  );
}
