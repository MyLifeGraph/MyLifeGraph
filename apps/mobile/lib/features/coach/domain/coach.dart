const coachRequestContractVersion = 'coach-request-v2';
const coachResponseContractVersion = 'coach-response-v1';
const coachCapabilitiesContractVersion = 'coach-capabilities-v1';
const coachHistoryContractVersion = 'coach-history-v1';
const coachMemorySelectionContractVersion = 'coach-memory-selection-v1';
const coachContextOptionsContractVersion = 'coach-context-options-v1';
const coachPromptVersion = 'controlled-coach-prompt-v3';
const coachContextVersion = 'coach-context-v3';
const _previousCoachPromptVersion = 'controlled-coach-prompt-v2';
const _previousCoachContextVersion = 'coach-context-v2';
const _legacyCoachPromptVersion = 'controlled-coach-prompt-v1';
const _legacyCoachContextVersion = 'coach-context-v1';

const coachMessageCodepoints = 2000;
const coachContextBytes = 32768;
const coachReplyCodepoints = 4000;
const coachMaxSelectedMemories = 8;
const coachMaxFocusOptions = 10;

enum CoachContextScope {
  today('today'),
  patterns('patterns'),
  focus('focus'),
  review('review');

  const CoachContextScope(this.code);
  final String code;

  static CoachContextScope? fromCode(Object? value) => switch (value) {
        'today' => today,
        'patterns' => patterns,
        'focus' => focus,
        'review' => review,
        _ => null,
      };
}

enum CoachPatternHorizon {
  days90('90_days'),
  year1('1_year'),
  allAvailable('all_available');

  const CoachPatternHorizon(this.code);
  final String code;

  static CoachPatternHorizon? fromCode(Object? value) => switch (value) {
        '90_days' => days90,
        '1_year' => year1,
        'all_available' => allAvailable,
        _ => null,
      };
}

class CoachContextSelection {
  const CoachContextSelection._({
    required this.scope,
    this.patternHorizon,
    this.focusSessionId,
  });

  const CoachContextSelection.today() : this._(scope: CoachContextScope.today);

  const CoachContextSelection.patterns(CoachPatternHorizon horizon)
      : this._(
          scope: CoachContextScope.patterns,
          patternHorizon: horizon,
        );

  factory CoachContextSelection.focus(String focusSessionId) {
    final normalized = focusSessionId.trim().toLowerCase();
    if (!_uuidPattern.hasMatch(normalized)) {
      throw const CoachInputException('Coach Focus session id is invalid.');
    }
    return CoachContextSelection._(
      scope: CoachContextScope.focus,
      focusSessionId: normalized,
    );
  }

  const CoachContextSelection.review()
      : this._(scope: CoachContextScope.review);

  factory CoachContextSelection.fromWire({
    required Object? scope,
    required Object? parameters,
  }) {
    final parsedScope = CoachContextScope.fromCode(scope);
    if (parsedScope == null || parameters is! Map) {
      throw const CoachContractException(
        'Coach context selection is invalid.',
      );
    }
    final values = _requiredMap(parameters, 'context parameters');
    return switch (parsedScope) {
      CoachContextScope.today => _emptySelection(
          values,
          const CoachContextSelection.today(),
        ),
      CoachContextScope.patterns => _patternsSelection(values),
      CoachContextScope.focus => _focusSelection(values),
      CoachContextScope.review => _emptySelection(
          values,
          const CoachContextSelection.review(),
        ),
    };
  }

  final CoachContextScope scope;
  final CoachPatternHorizon? patternHorizon;
  final String? focusSessionId;

  Map<String, dynamic> get parameters => switch (scope) {
        CoachContextScope.today ||
        CoachContextScope.review =>
          const <String, dynamic>{},
        CoachContextScope.patterns => {
            'horizon': patternHorizon!.code,
          },
        CoachContextScope.focus => {
            'focus_session_id': focusSessionId!,
          },
      };

  static CoachContextSelection _emptySelection(
    Map<String, dynamic> values,
    CoachContextSelection selection,
  ) {
    if (values.isNotEmpty) {
      throw const CoachContractException(
        'Coach context parameters are invalid.',
      );
    }
    return selection;
  }

  static CoachContextSelection _patternsSelection(
    Map<String, dynamic> values,
  ) {
    _expectExactKeys(values, const {'horizon'}, 'Coach pattern context');
    final horizon = CoachPatternHorizon.fromCode(values['horizon']);
    if (horizon == null) {
      throw const CoachContractException(
        'Coach pattern horizon is invalid.',
      );
    }
    return CoachContextSelection.patterns(horizon);
  }

  static CoachContextSelection _focusSelection(Map<String, dynamic> values) {
    _expectExactKeys(
      values,
      const {'focus_session_id'},
      'Coach Focus context',
    );
    final rawId = values['focus_session_id'];
    if (rawId is! String || !_uuidPattern.hasMatch(rawId)) {
      throw const CoachContractException(
        'Coach Focus context is invalid.',
      );
    }
    return CoachContextSelection.focus(rawId);
  }

  @override
  bool operator ==(Object other) =>
      other is CoachContextSelection &&
      other.scope == scope &&
      other.patternHorizon == patternHorizon &&
      other.focusSessionId == focusSessionId;

  @override
  int get hashCode => Object.hash(scope, patternHorizon, focusSessionId);
}

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

enum CoachProviderMode {
  disabled('disabled'),
  localDevelopmentOnly('local_development_only'),
  deterministicTestOnly('deterministic_test_only');

  const CoachProviderMode(this.code);
  final String code;

  static CoachProviderMode? fromCode(Object? value) => switch (value) {
        'disabled' => disabled,
        'local_development_only' => localDevelopmentOnly,
        'deterministic_test_only' => deterministicTestOnly,
        _ => null,
      };
}

enum CoachModelSource {
  explicit('explicit'),
  cliDefault('cli_default'),
  notApplicable('not_applicable');

  const CoachModelSource(this.code);
  final String code;

  static CoachModelSource? fromCode(Object? value) => switch (value) {
        'explicit' => explicit,
        'cli_default' => cliDefault,
        'not_applicable' => notApplicable,
        _ => null,
      };
}

class CoachLimits {
  const CoachLimits({
    required this.messageCodepoints,
    required this.contextBytes,
    required this.replyCodepoints,
    required this.timeoutSeconds,
    required this.requestsPerLocalDay,
    required this.remainingRequests,
  });

  factory CoachLimits.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'message_codepoints',
        'context_bytes',
        'reply_codepoints',
        'timeout_seconds',
        'requests_per_local_day',
        'remaining_requests',
      },
      'Coach limits',
    );
    final messageCodepoints = _requiredInt(json['message_codepoints']);
    final contextBytes = _requiredInt(json['context_bytes']);
    final replyCodepoints = _requiredInt(json['reply_codepoints']);
    final timeoutSeconds = _requiredInt(json['timeout_seconds']);
    final requestsPerLocalDay = _requiredInt(json['requests_per_local_day']);
    final remainingRequests = _requiredInt(json['remaining_requests']);
    if (messageCodepoints != coachMessageCodepoints ||
        contextBytes != coachContextBytes ||
        replyCodepoints != coachReplyCodepoints ||
        timeoutSeconds < 5 ||
        timeoutSeconds > 120 ||
        requestsPerLocalDay < 1 ||
        requestsPerLocalDay > 100 ||
        remainingRequests < 0 ||
        remainingRequests > 100) {
      throw const CoachContractException('Coach limits are invalid.');
    }
    return CoachLimits(
      messageCodepoints: messageCodepoints,
      contextBytes: contextBytes,
      replyCodepoints: replyCodepoints,
      timeoutSeconds: timeoutSeconds,
      requestsPerLocalDay: requestsPerLocalDay,
      remainingRequests: remainingRequests,
    );
  }

  final int messageCodepoints;
  final int contextBytes;
  final int replyCodepoints;
  final int timeoutSeconds;
  final int requestsPerLocalDay;
  final int remainingRequests;
}

class CoachCapabilities {
  const CoachCapabilities({
    required this.state,
    required this.provider,
    required this.providerMode,
    required this.modelRequested,
    required this.modelSource,
    required this.reasonCode,
    required this.limits,
  });

  factory CoachCapabilities.localDemo() => const CoachCapabilities(
        state: CoachCapabilityState.disabled,
        provider: CoachProviderName.disabled,
        providerMode: CoachProviderMode.disabled,
        modelRequested: null,
        modelSource: CoachModelSource.notApplicable,
        reasonCode: 'local_demo',
        limits: CoachLimits(
          messageCodepoints: coachMessageCodepoints,
          contextBytes: coachContextBytes,
          replyCodepoints: coachReplyCodepoints,
          timeoutSeconds: 45,
          requestsPerLocalDay: 20,
          remainingRequests: 0,
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
    final providerMode = CoachProviderMode.fromCode(json['provider_mode']);
    final modelSource = CoachModelSource.fromCode(json['model_source']);
    final reasonCode = _boundedText(json['reason_code'], 64);
    final modelRequested = _optionalBoundedText(json['model_requested'], 100);
    if (state == null ||
        provider == null ||
        providerMode == null ||
        modelSource == null ||
        !_reasonCodePattern.hasMatch(reasonCode)) {
      throw const CoachContractException(
        'Coach capabilities fields are invalid.',
      );
    }
    return CoachCapabilities(
      state: state,
      provider: provider,
      providerMode: providerMode,
      modelRequested: modelRequested,
      modelSource: modelSource,
      reasonCode: reasonCode,
      limits: CoachLimits.fromJson(_requiredMap(json['limits'], 'limits')),
    );
  }

  final CoachCapabilityState state;
  final CoachProviderName provider;
  final CoachProviderMode providerMode;
  final String? modelRequested;
  final CoachModelSource modelSource;
  final String reasonCode;
  final CoachLimits limits;

  bool get canRespond =>
      state == CoachCapabilityState.ready && limits.remainingRequests > 0;
}

enum CoachFocusStatus {
  completed('completed'),
  abandoned('abandoned');

  const CoachFocusStatus(this.code);
  final String code;

  static CoachFocusStatus? fromCode(Object? value) => switch (value) {
        'completed' => completed,
        'abandoned' => abandoned,
        _ => null,
      };
}

class CoachFocusOption {
  const CoachFocusOption({
    required this.focusSessionId,
    required this.status,
    required this.localStartedAt,
    required this.plannedMinutes,
    required this.actualMinutes,
    required this.hasReflection,
  });

  factory CoachFocusOption.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'focus_session_id',
        'status',
        'local_started_at',
        'planned_minutes',
        'actual_minutes',
        'has_reflection',
      },
      'Coach Focus option',
    );
    final status = CoachFocusStatus.fromCode(json['status']);
    final plannedMinutes = _requiredInt(json['planned_minutes']);
    final actualMinutes = _requiredInt(json['actual_minutes']);
    final hasReflection = json['has_reflection'];
    final rawLocalStartedAt = json['local_started_at'];
    if (status == null ||
        plannedMinutes < 5 ||
        plannedMinutes > 240 ||
        actualMinutes < 0 ||
        actualMinutes > 90 * 24 * 60 ||
        hasReflection is! bool ||
        rawLocalStartedAt is! String) {
      throw const CoachContractException(
        'Coach Focus option fields are invalid.',
      );
    }
    _requiredAwareDateTime(rawLocalStartedAt);
    return CoachFocusOption(
      focusSessionId: _requiredUuid(json['focus_session_id']),
      status: status,
      localStartedAt: _profileLocalWallClock(rawLocalStartedAt),
      plannedMinutes: plannedMinutes,
      actualMinutes: actualMinutes,
      hasReflection: hasReflection,
    );
  }

  final String focusSessionId;
  final CoachFocusStatus status;
  final DateTime localStartedAt;
  final int plannedMinutes;
  final int actualMinutes;
  final bool hasReflection;
}

class CoachContextOptions {
  const CoachContextOptions({
    required this.timezone,
    required this.personalPatternAnalysisEnabled,
    required this.focusOptions,
    required this.defaultFocusSessionId,
    required this.moreFocusOptionsAvailable,
  });

  factory CoachContextOptions.localDemo() => const CoachContextOptions(
        timezone: 'UTC',
        personalPatternAnalysisEnabled: false,
        focusOptions: [],
        defaultFocusSessionId: null,
        moreFocusOptionsAvailable: false,
      );

  factory CoachContextOptions.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'contract_version',
        'timezone',
        'personal_pattern_analysis_enabled',
        'focus_options',
        'default_focus_session_id',
        'more_focus_options_available',
      },
      'Coach context options',
    );
    final analysisEnabled = json['personal_pattern_analysis_enabled'];
    final rawOptions = json['focus_options'];
    final moreOptions = json['more_focus_options_available'];
    final timezone = _boundedText(json['timezone'], 100);
    if (json['contract_version'] != coachContextOptionsContractVersion ||
        analysisEnabled is! bool ||
        rawOptions is! List ||
        rawOptions.length > coachMaxFocusOptions ||
        moreOptions is! bool) {
      throw const CoachContractException(
        'Coach context options response is invalid.',
      );
    }
    final options = List<CoachFocusOption>.unmodifiable(
      rawOptions.map(
        (value) => CoachFocusOption.fromJson(
          _requiredMap(value, 'Focus option'),
        ),
      ),
    );
    if (options.map((option) => option.focusSessionId).toSet().length !=
        options.length) {
      throw const CoachContractException(
        'Coach Focus options contain duplicate sessions.',
      );
    }
    final rawDefault = json['default_focus_session_id'];
    final defaultId = rawDefault == null ? null : _requiredUuid(rawDefault);
    if (defaultId != null &&
        !options.any((option) => option.focusSessionId == defaultId)) {
      throw const CoachContractException(
        'Coach default Focus option is unavailable.',
      );
    }
    return CoachContextOptions(
      timezone: timezone,
      personalPatternAnalysisEnabled: analysisEnabled,
      focusOptions: options,
      defaultFocusSessionId: defaultId,
      moreFocusOptionsAvailable: moreOptions,
    );
  }

  final String timezone;
  final bool personalPatternAnalysisEnabled;
  final List<CoachFocusOption> focusOptions;
  final String? defaultFocusSessionId;
  final bool moreFocusOptionsAvailable;
}

class CoachRequest {
  CoachRequest._({
    required this.requestId,
    required this.message,
    required this.context,
  });

  factory CoachRequest({
    required String requestId,
    required String message,
    required CoachContextSelection context,
  }) {
    if (!_clientUuidPattern.hasMatch(requestId)) {
      throw const CoachInputException('Coach request id is invalid.');
    }
    final normalized = message.trim();
    if (normalized.isEmpty ||
        normalized.runes.length > coachMessageCodepoints) {
      throw const CoachInputException(
        'Coach message must contain 1 to 2,000 Unicode code points.',
      );
    }
    return CoachRequest._(
      requestId: requestId,
      message: normalized,
      context: context,
    );
  }

  final String requestId;
  final String message;
  final CoachContextSelection context;

  Map<String, dynamic> toJson() => {
        'contract_version': coachRequestContractVersion,
        'request_id': requestId,
        'message': message,
        'context_scope': context.scope.code,
        'context_parameters': context.parameters,
      };
}

enum CoachUncertaintyLevel {
  low('low'),
  medium('medium'),
  high('high');

  const CoachUncertaintyLevel(this.code);
  final String code;

  static CoachUncertaintyLevel? fromCode(Object? value) => switch (value) {
        'low' => low,
        'medium' => medium,
        'high' => high,
        _ => null,
      };
}

class CoachUncertainty {
  const CoachUncertainty({required this.level, required this.reason});

  factory CoachUncertainty.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, const {'level', 'reason'}, 'Coach uncertainty');
    final level = CoachUncertaintyLevel.fromCode(json['level']);
    if (level == null) {
      throw const CoachContractException('Coach uncertainty is invalid.');
    }
    return CoachUncertainty(
      level: level,
      reason: _boundedText(json['reason'], 300),
    );
  }

  final CoachUncertaintyLevel level;
  final String reason;
}

class CoachStagedSuggestion {
  const CoachStagedSuggestion({required this.title, required this.rationale});

  factory CoachStagedSuggestion.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'title', 'rationale'},
      'Coach staged suggestion',
    );
    return CoachStagedSuggestion(
      title: _boundedText(json['title'], 120),
      rationale: _boundedText(json['rationale'], 500),
    );
  }

  final String title;
  final String rationale;
}

enum CoachSafetyClassification {
  normal('normal'),
  sensitive('sensitive'),
  safetyRedirect('safety_redirect');

  const CoachSafetyClassification(this.code);
  final String code;

  static CoachSafetyClassification? fromCode(Object? value) => switch (value) {
        'normal' => normal,
        'sensitive' => sensitive,
        'safety_redirect' => safetyRedirect,
        _ => null,
      };
}

class CoachSafety {
  const CoachSafety({required this.classification});

  factory CoachSafety.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, const {'classification'}, 'Coach safety');
    final classification =
        CoachSafetyClassification.fromCode(json['classification']);
    if (classification == null) {
      throw const CoachContractException('Coach safety is invalid.');
    }
    return CoachSafety(classification: classification);
  }

  final CoachSafetyClassification classification;
}

enum CoachContextSource {
  profile('profile'),
  dailySnapshot('daily_snapshot'),
  dailyBriefing('daily_briefing'),
  goals('goals'),
  tasks('tasks'),
  habits('habits'),
  focusSessions('focus_sessions'),
  weeklyReview('weekly_review'),
  memories('memories'),
  coachHistory('coach_history'),
  dailyCapture('daily_capture'),
  focusReflections('focus_reflections'),
  habitOutcomes('habit_outcomes'),
  decisionFeedback('decision_feedback'),
  weeklyReviews('weekly_reviews'),
  taskLifecycle('task_lifecycle');

  const CoachContextSource(this.code);
  final String code;

  static CoachContextSource? fromCode(Object? value) => switch (value) {
        'profile' => profile,
        'daily_snapshot' => dailySnapshot,
        'daily_briefing' => dailyBriefing,
        'goals' => goals,
        'tasks' => tasks,
        'habits' => habits,
        'focus_sessions' => focusSessions,
        'weekly_review' => weeklyReview,
        'memories' => memories,
        'coach_history' => coachHistory,
        'daily_capture' => dailyCapture,
        'focus_reflections' => focusReflections,
        'habit_outcomes' => habitOutcomes,
        'decision_feedback' => decisionFeedback,
        'weekly_reviews' => weeklyReviews,
        'task_lifecycle' => taskLifecycle,
        _ => null,
      };
}

enum CoachContextFreshness {
  current('current'),
  stale('stale'),
  missing('missing'),
  notApplicable('not_applicable');

  const CoachContextFreshness(this.code);
  final String code;

  static CoachContextFreshness? fromCode(Object? value) => switch (value) {
        'current' => current,
        'stale' => stale,
        'missing' => missing,
        'not_applicable' => notApplicable,
        _ => null,
      };
}

class CoachUsedContext {
  const CoachUsedContext({
    required this.source,
    required this.availableCount,
    required this.includedCount,
    required this.omittedCount,
    required this.freshness,
  });

  factory CoachUsedContext.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'source',
        'available_count',
        'included_count',
        'omitted_count',
        'freshness',
      },
      'Coach used context',
    );
    final source = CoachContextSource.fromCode(json['source']);
    final freshness = CoachContextFreshness.fromCode(json['freshness']);
    final availableCount = _requiredInt(json['available_count']);
    final includedCount = _requiredInt(json['included_count']);
    final omittedCount = _requiredInt(json['omitted_count']);
    if (source == null ||
        freshness == null ||
        availableCount < 0 ||
        includedCount < 0 ||
        omittedCount < 0 ||
        includedCount + omittedCount != availableCount) {
      throw const CoachContractException(
        'Coach used-context counts are invalid.',
      );
    }
    return CoachUsedContext(
      source: source,
      availableCount: availableCount,
      includedCount: includedCount,
      omittedCount: omittedCount,
      freshness: freshness,
    );
  }

  final CoachContextSource source;
  final int availableCount;
  final int includedCount;
  final int omittedCount;
  final CoachContextFreshness freshness;
}

enum CoachProvenanceSource {
  model('model'),
  deterministicSafety('deterministic_safety');

  const CoachProvenanceSource(this.code);
  final String code;

  static CoachProvenanceSource? fromCode(Object? value) => switch (value) {
        'model' => model,
        'deterministic_safety' => deterministicSafety,
        _ => null,
      };
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
      },
      'Coach provenance',
    );
    final source = CoachProvenanceSource.fromCode(json['source']);
    final provider = CoachProviderName.fromCode(json['provider']);
    final providerMode = CoachProviderMode.fromCode(json['provider_mode']);
    final modelSource = CoachModelSource.fromCode(json['model_source']);
    final providerCalled = json['provider_called'];
    final promptVersion = json['prompt_version'];
    final contextVersion = json['context_version'];
    final versionsMatch = (promptVersion == coachPromptVersion &&
            contextVersion == coachContextVersion) ||
        (promptVersion == _previousCoachPromptVersion &&
            contextVersion == _previousCoachContextVersion) ||
        (promptVersion == _legacyCoachPromptVersion &&
            contextVersion == _legacyCoachContextVersion);
    if (source == null ||
        provider == null ||
        providerMode == null ||
        modelSource == null ||
        providerCalled is! bool ||
        source == CoachProvenanceSource.model && !providerCalled ||
        providerCalled && provider == CoachProviderName.disabled ||
        !versionsMatch) {
      throw const CoachContractException('Coach provenance is invalid.');
    }
    return CoachProvenance(
      source: source,
      provider: provider,
      providerMode: providerMode,
      modelRequested: _optionalBoundedText(json['model_requested'], 100),
      modelReported: _optionalBoundedText(json['model_reported'], 100),
      modelSource: modelSource,
      promptVersion: promptVersion as String,
      contextVersion: contextVersion as String,
      generatedAt: _requiredAwareDateTime(json['generated_at']),
      providerCalled: providerCalled,
    );
  }

  final CoachProvenanceSource source;
  final CoachProviderName provider;
  final CoachProviderMode providerMode;
  final String? modelRequested;
  final String? modelReported;
  final CoachModelSource modelSource;
  final String promptVersion;
  final String contextVersion;
  final DateTime generatedAt;
  final bool providerCalled;
}

class CoachResponse {
  const CoachResponse({
    required this.requestId,
    required this.reply,
    required this.uncertainty,
    required this.stagedSuggestion,
    required this.safety,
    required this.usedContext,
    required this.provenance,
  });

  factory CoachResponse.fromJson(Map<String, dynamic> json) {
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
      'Coach response',
    );
    if (json['contract_version'] != coachResponseContractVersion) {
      throw const CoachContractException(
        'Coach response contract is unsupported.',
      );
    }
    final rawSuggestion = json['staged_suggestion'];
    final rawUsedContext = json['used_context'];
    if (rawSuggestion != null && rawSuggestion is! Map ||
        rawUsedContext is! List ||
        rawUsedContext.length > 10) {
      throw const CoachContractException('Coach response fields are invalid.');
    }
    final safety = CoachSafety.fromJson(_requiredMap(json['safety'], 'safety'));
    final provenance = CoachProvenance.fromJson(
      _requiredMap(json['provenance'], 'provenance'),
    );
    final hasDeterministicSafety =
        provenance.source == CoachProvenanceSource.deterministicSafety;
    final hasSafetyRedirect =
        safety.classification == CoachSafetyClassification.safetyRedirect;
    if (hasDeterministicSafety != hasSafetyRedirect) {
      throw const CoachContractException(
        'Coach safety provenance is inconsistent.',
      );
    }
    return CoachResponse(
      requestId: _requiredUuid(json['request_id']),
      reply: _boundedText(json['reply'], coachReplyCodepoints),
      uncertainty: CoachUncertainty.fromJson(
        _requiredMap(json['uncertainty'], 'uncertainty'),
      ),
      stagedSuggestion: rawSuggestion == null
          ? null
          : CoachStagedSuggestion.fromJson(
              _requiredMap(rawSuggestion, 'staged_suggestion'),
            ),
      safety: safety,
      usedContext: List<CoachUsedContext>.unmodifiable(
        rawUsedContext.map(
          (value) => CoachUsedContext.fromJson(
            _requiredMap(value, 'used_context item'),
          ),
        ),
      ),
      provenance: provenance,
    );
  }

  final String requestId;
  final String reply;
  final CoachUncertainty uncertainty;
  final CoachStagedSuggestion? stagedSuggestion;
  final CoachSafety safety;
  final List<CoachUsedContext> usedContext;
  final CoachProvenance provenance;
}

class CoachHistoryTurn {
  const CoachHistoryTurn({
    required this.requestId,
    required this.message,
    required this.context,
    required this.response,
    required this.createdAt,
  });

  factory CoachHistoryTurn.fromJson(Map<String, dynamic> json) {
    const legacyKeys = {'request_id', 'message', 'response', 'created_at'};
    const currentKeys = {
      'request_id',
      'message',
      'context_scope',
      'context_parameters',
      'response',
      'created_at',
    };
    final keys = json.keys.toSet();
    final isLegacy =
        keys.length == legacyKeys.length && keys.every(legacyKeys.contains);
    final isCurrent =
        keys.length == currentKeys.length && keys.every(currentKeys.contains);
    if (!isLegacy && !isCurrent) {
      throw const CoachContractException(
        'Coach history turn has unexpected or missing fields.',
      );
    }
    final requestId = _requiredUuid(json['request_id']);
    final response = CoachResponse.fromJson(
      _requiredMap(json['response'], 'response'),
    );
    if (response.requestId != requestId) {
      throw const CoachContractException(
        'Coach history request identity is inconsistent.',
      );
    }
    return CoachHistoryTurn(
      requestId: requestId,
      message: _boundedText(json['message'], coachMessageCodepoints),
      context: isLegacy
          ? const CoachContextSelection.today()
          : CoachContextSelection.fromWire(
              scope: json['context_scope'],
              parameters: json['context_parameters'],
            ),
      response: response,
      createdAt: _requiredAwareDateTime(json['created_at']),
    );
  }

  final String requestId;
  final String message;
  final CoachContextSelection context;
  final CoachResponse response;
  final DateTime createdAt;
}

class CoachHistory {
  const CoachHistory({required this.turns});

  factory CoachHistory.empty() => const CoachHistory(turns: []);

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
      turns: List<CoachHistoryTurn>.unmodifiable(
        (json['turns'] as List).map(
          (value) => CoachHistoryTurn.fromJson(
            _requiredMap(value, 'history turn'),
          ),
        ),
      ),
    );
  }

  final List<CoachHistoryTurn> turns;
}

class CoachHistoryDeleteResult {
  const CoachHistoryDeleteResult({required this.deleted});

  factory CoachHistoryDeleteResult.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'contract_version', 'deleted'},
      'Coach history deletion',
    );
    if (json['contract_version'] != coachHistoryContractVersion ||
        json['deleted'] is! bool) {
      throw const CoachContractException(
        'Coach history deletion response is invalid.',
      );
    }
    return CoachHistoryDeleteResult(deleted: json['deleted'] as bool);
  }

  final bool deleted;
}

enum CoachMemoryType {
  pattern('pattern'),
  preference('preference'),
  goal('goal'),
  habit('habit'),
  recurringProblem('recurring_problem'),
  recommendation('recommendation');

  const CoachMemoryType(this.code);
  final String code;

  static CoachMemoryType? fromCode(Object? value) => switch (value) {
        'pattern' => pattern,
        'preference' => preference,
        'goal' => goal,
        'habit' => habit,
        'recurring_problem' => recurringProblem,
        'recommendation' => recommendation,
        _ => null,
      };
}

enum CoachMemoryOwnership {
  setup('setup'),
  manual('manual');

  const CoachMemoryOwnership(this.code);
  final String code;

  static CoachMemoryOwnership? fromCode(Object? value) => switch (value) {
        'setup' => setup,
        'manual' => manual,
        _ => null,
      };
}

class CoachMemory {
  const CoachMemory({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    required this.contentTruncated,
    required this.ownership,
    required this.selected,
    required this.updatedAt,
  });

  factory CoachMemory.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'id',
        'type',
        'title',
        'content',
        'content_truncated',
        'ownership',
        'selected',
        'updated_at',
      },
      'Coach memory',
    );
    final type = CoachMemoryType.fromCode(json['type']);
    final ownership = CoachMemoryOwnership.fromCode(json['ownership']);
    if (type == null ||
        ownership == null ||
        json['content_truncated'] is! bool ||
        json['selected'] is! bool) {
      throw const CoachContractException('Coach memory fields are invalid.');
    }
    return CoachMemory(
      id: _requiredUuid(json['id']),
      type: type,
      title: _boundedText(json['title'], 160),
      content: _boundedText(json['content'], 1000),
      contentTruncated: json['content_truncated'] as bool,
      ownership: ownership,
      selected: json['selected'] as bool,
      updatedAt: _requiredAwareDateTime(json['updated_at']),
    );
  }

  final String id;
  final CoachMemoryType type;
  final String title;
  final String content;
  final bool contentTruncated;
  final CoachMemoryOwnership ownership;
  final bool selected;
  final DateTime updatedAt;
}

class CoachMemorySelection {
  const CoachMemorySelection({
    required this.maxSelected,
    required this.availableCount,
    required this.memories,
  });

  factory CoachMemorySelection.empty() => const CoachMemorySelection(
        maxSelected: coachMaxSelectedMemories,
        availableCount: 0,
        memories: [],
      );

  factory CoachMemorySelection.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'contract_version',
        'max_selected',
        'available_count',
        'memories',
      },
      'Coach memory selection',
    );
    final maxSelected = _requiredInt(json['max_selected']);
    final availableCount = _requiredInt(json['available_count']);
    final rawMemories = json['memories'];
    if (json['contract_version'] != coachMemorySelectionContractVersion ||
        maxSelected != coachMaxSelectedMemories ||
        availableCount < 0 ||
        rawMemories is! List) {
      throw const CoachContractException(
        'Coach memory selection response is invalid.',
      );
    }
    final memories = List<CoachMemory>.unmodifiable(
      rawMemories.map(
        (value) => CoachMemory.fromJson(_requiredMap(value, 'memory')),
      ),
    );
    if (availableCount < memories.length ||
        memories.where((memory) => memory.selected).length > maxSelected) {
      throw const CoachContractException(
        'Coach memory selection counts are invalid.',
      );
    }
    return CoachMemorySelection(
      maxSelected: maxSelected,
      availableCount: availableCount,
      memories: memories,
    );
  }

  final int maxSelected;
  final int availableCount;
  final List<CoachMemory> memories;

  int get selectedCount => memories.where((memory) => memory.selected).length;
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
      'Coach error detail',
    );
    final code = _boundedText(json['code'], 64);
    if (!_reasonCodePattern.hasMatch(code) || json['retryable'] is! bool) {
      throw const CoachContractException('Coach error detail is invalid.');
    }
    return CoachErrorDetail(
      code: code,
      message: _boundedText(json['message'], 300),
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

  @override
  String toString() => 'CoachInputException: $message';
}

class CoachContractException implements Exception {
  const CoachContractException(this.message);
  final String message;

  @override
  String toString() => 'CoachContractException: $message';
}

final _clientUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final _reasonCodePattern = RegExp(r'^[a-z0-9][a-z0-9_:-]*$');
final _awareDateTimePattern = RegExp(r'(Z|[+-]\d{2}:\d{2})$');
final _localDateTimePartsPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})',
);

void _expectExactKeys(
  Map<String, dynamic> json,
  Set<String> expected,
  String label,
) {
  if (json.length != expected.length ||
      json.keys.any((key) => !expected.contains(key))) {
    throw CoachContractException('$label has unexpected or missing fields.');
  }
}

Map<String, dynamic> _requiredMap(Object? value, String field) {
  if (value is! Map) {
    throw CoachContractException('Coach $field must be an object.');
  }
  try {
    return Map<String, dynamic>.from(value);
  } catch (_) {
    throw CoachContractException('Coach $field must use string keys.');
  }
}

int _requiredInt(Object? value) {
  if (value is! int) {
    throw const CoachContractException('Coach integer field is invalid.');
  }
  return value;
}

String _boundedText(Object? value, int maxLength) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.runes.length > maxLength) {
    throw const CoachContractException('Coach text field is invalid.');
  }
  return value;
}

String? _optionalBoundedText(Object? value, int maxLength) {
  if (value == null) return null;
  return _boundedText(value, maxLength);
}

String _requiredUuid(Object? value) {
  if (value is! String || !_uuidPattern.hasMatch(value)) {
    throw const CoachContractException('Coach UUID field is invalid.');
  }
  return value.toLowerCase();
}

DateTime _requiredAwareDateTime(Object? value) {
  if (value is! String || !_awareDateTimePattern.hasMatch(value)) {
    throw const CoachContractException('Coach timestamp is invalid.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const CoachContractException('Coach timestamp is invalid.');
  }
  return parsed;
}

DateTime _profileLocalWallClock(String value) {
  final match = _localDateTimePartsPattern.firstMatch(value);
  if (match == null) {
    throw const CoachContractException('Coach local timestamp is invalid.');
  }
  final parts = [
    for (var index = 1; index <= 6; index++) int.parse(match.group(index)!),
  ];
  final result = DateTime(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  if (result.year != parts[0] ||
      result.month != parts[1] ||
      result.day != parts[2] ||
      result.hour != parts[3] ||
      result.minute != parts[4] ||
      result.second != parts[5]) {
    throw const CoachContractException('Coach local timestamp is invalid.');
  }
  return result;
}
