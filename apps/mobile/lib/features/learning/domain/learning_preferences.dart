import '../../../core/contracts/strict_contract.dart';

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
    Never invalid() => throw const LearningContractException(
          'Personal learning settings response is invalid.',
        );
    requireStrictKeys(
      json,
      requiredKeys: requiredKeys,
      optionalKeys: optionalKeys,
      onFailure: invalid,
    );
    if (json['contract_version'] != learningPreferencesContractVersion) {
      invalid();
    }
    final revision = requireStrictInt(
      json['revision'],
      min: 0,
      onFailure: invalid,
    );
    final reflectionPrompt = requireStrictBool(
      json['focus_reflection_prompt_enabled'],
      onFailure: invalid,
    );
    final analysis = requireStrictBool(
      json['personal_pattern_analysis_enabled'],
      onFailure: invalid,
    );
    final learned = requireStrictBool(
      json['learned_focus_planning_enabled'],
      onFailure: invalid,
    );
    if (json.containsKey('replayed')) {
      requireStrictBool(json['replayed'], onFailure: invalid);
    }
    final updatedAt = _optionalAwareDateTime(json['updated_at']);
    if (learned && !analysis) {
      invalid();
    }
    return LearningPreferences(
      revision: revision,
      focusReflectionPromptEnabled: reflectionPrompt,
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
    Never invalid() => throw const LearningContractException(
          'Focus reflection history clear response is invalid.',
        );
    requireStrictKeys(json, requiredKeys: keys, onFailure: invalid);
    if (json['contract_version'] != focusReflectionContractVersion) invalid();
    final revision = requireStrictInt(
      json['revision'],
      min: 0,
      onFailure: invalid,
    );
    final deletedCount = requireStrictInt(
      json['deleted_count'],
      min: 0,
      onFailure: invalid,
    );
    final clearedAt = _optionalAwareDateTime(json['cleared_at']);
    if (clearedAt == null) invalid();
    final replayed = requireStrictBool(json['replayed'], onFailure: invalid);
    return FocusReflectionHistoryClearResult(
      revision: revision,
      deletedCount: deletedCount,
      clearedAt: clearedAt,
      replayed: replayed,
    );
  }

  final int revision;
  final int deletedCount;
  final DateTime clearedAt;
  final bool replayed;
}

DateTime? _optionalAwareDateTime(Object? value) {
  if (value == null) return null;
  return requireStrictAwareDateTime(
    value,
    exactSecondsFormat: false,
    onFailure: () => throw const LearningContractException(
      'Personal learning timestamp is invalid.',
    ),
  );
}

bool _isUuid(String value) => isStrictUuid(value, minVersion: 1, maxVersion: 5);

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
