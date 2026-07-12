const decisionFeedbackContractVersion = 'decision-feedback-v1';

enum DecisionFeedbackType {
  done('done'),
  later('later'),
  notHelpful('not_helpful'),
  tooMuch('too_much'),
  doesNotFit('does_not_fit');

  const DecisionFeedbackType(this.code);
  final String code;

  static DecisionFeedbackType? fromCode(Object? value) {
    for (final item in values) {
      if (item.code == value) return item;
    }
    return null;
  }
}

class DecisionFeedback {
  const DecisionFeedback({
    required this.id,
    required this.requestId,
    required this.briefingId,
    required this.recommendationId,
    required this.actionId,
    required this.actionKind,
    required this.feedbackType,
    required this.contextMode,
    required this.estimatedMinutes,
    required this.ruleKey,
    required this.createdAt,
  });

  factory DecisionFeedback.fromJson(Map<String, dynamic> json) {
    const keys = {
      'id',
      'request_id',
      'briefing_id',
      'recommendation_id',
      'action_id',
      'action_kind',
      'feedback_type',
      'context_mode',
      'estimated_minutes',
      'rule_key',
      'created_at',
    };
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(json.keys.toSet()).isNotEmpty) {
      throw const DecisionFeedbackException('Feedback fields are invalid.');
    }
    final type = DecisionFeedbackType.fromCode(json['feedback_type']);
    final estimate = json['estimated_minutes'];
    final recommendationId = json['recommendation_id'];
    if (type == null ||
        estimate != null &&
            (estimate is! int || estimate < 1 || estimate > 480) ||
        recommendationId != null && recommendationId is! String) {
      throw const DecisionFeedbackException('Feedback values are invalid.');
    }
    return DecisionFeedback(
      id: _string(json['id']),
      requestId: _string(json['request_id']),
      briefingId: _string(json['briefing_id']),
      recommendationId: recommendationId as String?,
      actionId: _string(json['action_id']),
      actionKind: _string(json['action_kind']),
      feedbackType: type,
      contextMode: _string(json['context_mode']),
      estimatedMinutes: estimate as int?,
      ruleKey: _string(json['rule_key']),
      createdAt: _dateTime(json['created_at']),
    );
  }

  final String id;
  final String requestId;
  final String briefingId;
  final String? recommendationId;
  final String actionId;
  final String actionKind;
  final DecisionFeedbackType feedbackType;
  final String contextMode;
  final int? estimatedMinutes;
  final String ruleKey;
  final DateTime createdAt;
}

class DecisionFeedbackException implements Exception {
  const DecisionFeedbackException(this.message);
  final String message;
  @override
  String toString() => message;
}

String _string(Object? value) {
  if (value is! String || value.isEmpty || value != value.trim()) {
    throw const DecisionFeedbackException('Feedback string is invalid.');
  }
  return value;
}

DateTime _dateTime(Object? value) {
  if (value is! String) {
    throw const DecisionFeedbackException('Feedback timestamp is invalid.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !value.contains(RegExp(r'(Z|[+-]\d\d:\d\d)$'))) {
    throw const DecisionFeedbackException('Feedback timestamp is invalid.');
  }
  return parsed;
}
