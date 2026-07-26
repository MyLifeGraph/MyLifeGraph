const learningPreferencesContractVersion = 'learning-preferences-v1';
const focusReflectionContractVersion = 'focus-reflection-v1';

class LearningPreferences {
  const LearningPreferences({
    required this.revision,
    required this.focusReflectionPromptEnabled,
    required this.personalPatternAnalysisEnabled,
    required this.learnedFocusPlanningEnabled,
    required this.updatedAt,
  });

  factory LearningPreferences.fromJson(Map<String, dynamic> json) {
    const requiredKeys = {
      'contract_version',
      'revision',
      'focus_reflection_prompt_enabled',
      'personal_pattern_analysis_enabled',
      'learned_focus_planning_enabled',
      'updated_at',
    };
    const optionalKeys = {'replayed'};
    final keys = json.keys.toSet();
    if (requiredKeys.difference(keys).isNotEmpty ||
        keys.difference({...requiredKeys, ...optionalKeys}).isNotEmpty ||
        json['contract_version'] != learningPreferencesContractVersion ||
        json['revision'] is! int ||
        (json['revision'] as int) < 0 ||
        json['focus_reflection_prompt_enabled'] is! bool ||
        json['personal_pattern_analysis_enabled'] is! bool ||
        json['learned_focus_planning_enabled'] is! bool ||
        json.containsKey('replayed') && json['replayed'] is! bool) {
      throw const LearningContractException(
        'Personal learning settings response is invalid.',
      );
    }
    final updatedAt = _optionalAwareDateTime(json['updated_at']);
    final analysis = json['personal_pattern_analysis_enabled'] as bool;
    final learned = json['learned_focus_planning_enabled'] as bool;
    if (learned && !analysis) {
      throw const LearningContractException(
        'Personal learning settings response is invalid.',
      );
    }
    return LearningPreferences(
      revision: json['revision'] as int,
      focusReflectionPromptEnabled:
          json['focus_reflection_prompt_enabled'] as bool,
      personalPatternAnalysisEnabled: analysis,
      learnedFocusPlanningEnabled: learned,
      updatedAt: updatedAt,
    );
  }

  final int revision;
  final bool focusReflectionPromptEnabled;
  final bool personalPatternAnalysisEnabled;
  final bool learnedFocusPlanningEnabled;
  final DateTime? updatedAt;
}

class LearningPreferencesUpdate {
  LearningPreferencesUpdate({
    required this.requestId,
    required this.expectedRevision,
    required this.focusReflectionPromptEnabled,
    required this.personalPatternAnalysisEnabled,
    required this.learnedFocusPlanningEnabled,
  }) {
    if (!_isUuid(requestId) ||
        expectedRevision < 0 ||
        learnedFocusPlanningEnabled && !personalPatternAnalysisEnabled) {
      throw const LearningContractException(
        'Personal learning settings update is invalid.',
      );
    }
  }

  final String requestId;
  final int expectedRevision;
  final bool focusReflectionPromptEnabled;
  final bool personalPatternAnalysisEnabled;
  final bool learnedFocusPlanningEnabled;

  Map<String, dynamic> toJson() => {
        'request_id': requestId,
        'expected_revision': expectedRevision,
        'focus_reflection_prompt_enabled': focusReflectionPromptEnabled,
        'personal_pattern_analysis_enabled': personalPatternAnalysisEnabled,
        'learned_focus_planning_enabled': learnedFocusPlanningEnabled,
      };
}

class FocusReflectionHistoryClearRequest {
  FocusReflectionHistoryClearRequest({
    required this.requestId,
    required this.expectedRevision,
  }) {
    if (!_isUuid(requestId) || expectedRevision < 0) {
      throw const LearningContractException(
        'Focus reflection history clear request is invalid.',
      );
    }
  }

  final String requestId;
  final int expectedRevision;

  Map<String, dynamic> toJson() => {
        'request_id': requestId,
        'expected_revision': expectedRevision,
        'confirmation': 'CLEAR',
      };
}

class FocusReflectionHistoryClearResult {
  const FocusReflectionHistoryClearResult({
    required this.revision,
    required this.deletedCount,
    required this.clearedAt,
    required this.replayed,
  });

  factory FocusReflectionHistoryClearResult.fromJson(
    Map<String, dynamic> json,
  ) {
    const keys = {
      'contract_version',
      'revision',
      'deleted_count',
      'cleared_at',
      'replayed',
    };
    final clearedAt = _optionalAwareDateTime(json['cleared_at']);
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(json.keys.toSet()).isNotEmpty ||
        json['contract_version'] != focusReflectionContractVersion ||
        json['revision'] is! int ||
        (json['revision'] as int) < 0 ||
        json['deleted_count'] is! int ||
        (json['deleted_count'] as int) < 0 ||
        clearedAt == null ||
        json['replayed'] is! bool) {
      throw const LearningContractException(
        'Focus reflection history clear response is invalid.',
      );
    }
    return FocusReflectionHistoryClearResult(
      revision: json['revision'] as int,
      deletedCount: json['deleted_count'] as int,
      clearedAt: clearedAt,
      replayed: json['replayed'] as bool,
    );
  }

  final int revision;
  final int deletedCount;
  final DateTime clearedAt;
  final bool replayed;
}

DateTime? _optionalAwareDateTime(Object? value) {
  if (value == null) return null;
  if (value is! String ||
      !RegExp(r'(Z|[+-][0-9]{2}:[0-9]{2})$').hasMatch(value)) {
    throw const LearningContractException(
      'Personal learning timestamp is invalid.',
    );
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const LearningContractException(
      'Personal learning timestamp is invalid.',
    );
  }
  return parsed;
}

bool _isUuid(String value) => RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-'
      r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(value);

class LearningException implements Exception {
  const LearningException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LearningContractException extends LearningException {
  const LearningContractException(super.message);
}

class LearningAccessException extends LearningException {
  const LearningAccessException(super.message);
}

class LearningConflictException extends LearningException {
  const LearningConflictException(super.message);
}

class LearningOutcomeUnknownException extends LearningException {
  const LearningOutcomeUnknownException(super.message);
}
